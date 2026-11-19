import Darwin
import Foundation

enum AppleWidgetCommand: Equatable, Sendable {
    case start
    case stop
    case toggle
}

enum AppleWidgetCommandOutcome: Equatable, Sendable {
    case completed
    case inProgress
    case needsForeground
}

/// Interactive Widget actions are available from iOS 17. Execution uses the
/// background APIs provided by each OS; iOS 16 retains navigation-only links.
enum AppleWidgetExecutionPolicy {
    static var usesBackgroundActions: Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) { return true }
        #endif
        return false
    }
}

enum AppleWidgetStatus: String, Codable, Sendable {
    case unknown
    case disconnected
    case connecting
    case connected
    case disconnecting
}

enum AppleWidgetControlStatus: String, Sendable {
    case unknown, disconnected, connecting, connected, disconnecting, failed
}

enum AppleWidgetControlFailure: String, Codable, Sendable {
    case vpnService, xray
}

typealias AppleWidgetControlAttempt = UUID

private struct AppleWidgetControlObservation: Codable {
    struct Failure: Codable {
        let kind: AppleWidgetControlFailure
        let observedAt: Date
    }

    let attempt: AppleWidgetControlAttempt
    var didStart = false
    var failure: Failure?
}

/// A display snapshot, never an input for starting or configuring a tunnel.
struct AppleWidgetSnapshot: Codable, Equatable, Sendable {
    static let maximumAge: TimeInterval = 15 * 60
    let version: Int
    let status: AppleWidgetStatus
    let observedAt: Date

    init(status: AppleWidgetStatus, observedAt: Date = Date()) {
        version = 1
        self.status = status
        self.observedAt = observedAt
    }

    func isCurrent(at date: Date) -> Bool {
        let age = date.timeIntervalSince(observedAt)
        return version == 1 && age >= -60 && age < Self.maximumAge
    }

    func displayedStatus(at date: Date) -> AppleWidgetStatus {
        isCurrent(at: date) ? status : .unknown
    }
}

enum AppleWidgetLanguage {
    static func normalized(_ code: String) -> String {
        switch code.replacingOccurrences(of: "_", with: "-").lowercased() {
        case "zh", "zh-hans": return "zh-Hans"
        case "zh-hant": return "zh-Hant"
        case "ru": return "ru"
        case "fa": return "fa"
        default: return "en"
        }
    }
}

enum AppleWidgetLocalization {
    static func text(_ key: String, languageCode: String? = nil) -> String {
        let language = languageCode ?? AppleWidgetStore.shared?.languageCode() ?? "en"
        let path = Bundle.main.path(forResource: AppleWidgetLanguage.normalized(language), ofType: "lproj")
        let bundle = path.flatMap(Bundle.init(path:)) ?? Bundle.main
        return bundle.localizedString(forKey: key, value: key, table: "Widget")
    }
}

/// Separate files let the app change language without overwriting a tunnel event.
struct AppleWidgetStore: Sendable {
    static let appGroup = "group.net.yuandev.onexray"
    static let kind = "net.yuandev.onexray.connection"
    static let controlKind = "net.yuandev.onexray.vpn"
    let directory: URL

    static var shared: AppleWidgetStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .map { AppleWidgetStore(directory: $0.appendingPathComponent("widget", isDirectory: true)) }
    }

    func snapshot() -> AppleWidgetSnapshot? {
        guard let data = read("status.json"),
              let value = try? JSONDecoder().decode(AppleWidgetSnapshot.self, from: data),
              value.version == 1 else { return nil }
        return value
    }

    func displayedControlStatus(at date: Date = Date()) -> AppleWidgetControlStatus {
        if let failure = controlObservation()?.failure {
            let age = date.timeIntervalSince(failure.observedAt)
            if age >= -60 && age < AppleWidgetSnapshot.maximumAge { return .failed }
        }
        let status = snapshot()?.displayedStatus(at: date) ?? .unknown
        return AppleWidgetControlStatus(rawValue: status.rawValue) ?? .unknown
    }

    /// Record mutations from Runner and the Packet Tunnel in the same attempt order.
    /// A late callback must neither revive a cleared warning nor replace a newer one.
    func beginControlAttempt(_ attempt: AppleWidgetControlAttempt) throws -> Bool {
        try withControlLock {
            let clearedWarning = controlObservation()?.failure != nil
            try writeControlObservation(AppleWidgetControlObservation(attempt: attempt))
            return clearedWarning
        }
    }

    func completeControlStart(_ attempt: AppleWidgetControlAttempt) throws -> Bool {
        try withControlLock {
            guard var current = controlObservation(), current.attempt == attempt,
                  !current.didStart else { return false }
            let clearedWarning = current.failure != nil
            current.didStart = true
            current.failure = nil
            try writeControlObservation(current)
            return clearedWarning
        }
    }

    func writeControlFailure(
        _ failure: AppleWidgetControlFailure, for attempt: AppleWidgetControlAttempt,
        afterStart: Bool = false, at date: Date = Date()
    ) throws -> Bool {
        try withControlLock {
            guard var current = controlObservation(), current.attempt == attempt,
                  afterStart || !current.didStart else { return false }
            if let previous = current.failure, previous.kind == failure || previous.kind == .xray {
                return false
            }
            current.failure = .init(kind: failure, observedAt: date)
            try writeControlObservation(current)
            return true
        }
    }

    func endControlAttempt(_ attempt: AppleWidgetControlAttempt? = nil) throws -> Bool {
        try withControlLock {
            guard let current = controlObservation(), attempt == nil || current.attempt == attempt else {
                return false
            }
            try FileManager.default.removeItem(at: directory.appendingPathComponent("control-status.json"))
            return current.failure != nil
        }
    }

    private func controlObservation() -> AppleWidgetControlObservation? {
        guard let data = read("control-status.json") else { return nil }
        return try? JSONDecoder().decode(AppleWidgetControlObservation.self, from: data)
    }

    private func writeControlObservation(_ observation: AppleWidgetControlObservation) throws {
        try write(JSONEncoder().encode(observation), name: "control-status.json")
    }

    private func withControlLock(_ change: () throws -> Bool) throws -> Bool {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("control-status.lock").path
        let fd = open(path, O_WRONLY | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return try change()
    }

    func languageCode() -> String {
        guard let data = read("language.json"),
              let code = try? JSONDecoder().decode(String.self, from: data) else { return "en" }
        return AppleWidgetLanguage.normalized(code)
    }

    /// Repeated native reads do not spend a widget reload on an unchanged state.
    @discardableResult
    func writeStatus(_ status: AppleWidgetStatus, at date: Date = Date()) throws -> Bool {
        if let previous = snapshot(), previous.status == status,
           previous.isCurrent(at: date), date.timeIntervalSince(previous.observedAt) < 60 {
            return false
        }
        try write(JSONEncoder().encode(AppleWidgetSnapshot(status: status, observedAt: date)), name: "status.json")
        return true
    }

    @discardableResult
    func writeLanguage(_ code: String) throws -> Bool {
        let normalized = AppleWidgetLanguage.normalized(code)
        if read("language.json") != nil, languageCode() == normalized { return false }
        try write(JSONEncoder().encode(normalized), name: "language.json")
        return true
    }

    private func read(_ name: String) -> Data? {
        let url = directory.appendingPathComponent(name)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 4096 else { return nil }
        return try? Data(contentsOf: url)
    }

    private func write(_ data: Data, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
