import Foundation

enum AppleWidgetStatus: String, Codable, Sendable {
    case unknown
    case disconnected
    case connecting
    case connected
    case disconnecting
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

/// Separate files let the app change language without overwriting a tunnel event.
struct AppleWidgetStore: Sendable {
    static let appGroup = "group.net.yuandev.onexray"
    static let kind = "net.yuandev.onexray.connection"
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
