import Foundation
import Darwin

/// Stop retires old starts and drains profile writes, not native status waits.
@MainActor
final class AppleVpnStartAdmission {
    enum Failure: LocalizedError {
        case startBlocked

        var errorDescription: String? {
            "VPN start is temporarily unavailable while app data is being updated."
        }
    }

    private(set) var generation: UInt64 = 0
    private var preparing: Set<UInt64> = []
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []
    private var dartPreparations: [String: UInt64] = [:]
    private let startBlockedURL: URL?

    init(startBlockedURL: URL? = nil) {
        self.startBlockedURL = startBlockedURL
    }

    func requireStartAllowed() throws {
        if try markerType() != nil { throw Failure.startBlocked }
    }

    func setStartBlocked(_ blocked: Bool) throws {
        guard let startBlockedURL else { throw CocoaError(.fileNoSuchFile) }
        if let type = try markerType(), type != S_IFREG {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: startBlockedURL.path])
        }
        if blocked {
            try Data([1]).write(to: startBlockedURL, options: .atomic)
        } else if try markerType() != nil {
            try FileManager.default.removeItem(at: startBlockedURL)
        }
    }

    private func markerType() throws -> mode_t? {
        guard let startBlockedURL else { return nil }
        var info = stat()
        if lstat(startBlockedURL.path, &info) == 0 { return info.st_mode & S_IFMT }
        if errno == ENOENT { return nil }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: startBlockedURL.path])
    }

    func beginDartPreparation() throws -> String {
        try requireStartAllowed()
        let token = UUID().uuidString
        dartPreparations[token] = generation
        return token
    }

    func finishDartPreparation(token: String) {
        dartPreparations.removeValue(forKey: token)
    }

    func isCurrent(_ token: String) -> Bool {
        dartPreparations[token] == generation
    }

    var hasCurrentDartPreparation: Bool {
        dartPreparations.values.contains(generation)
    }

    func consumeDartPreparation(token: String) -> Bool {
        dartPreparations.removeValue(forKey: token) == generation
    }

    func begin() -> UInt64 {
        generation &+= 1
        preparing.insert(generation)
        return generation
    }

    func isCurrent(_ token: UInt64) -> Bool { token == generation }

    func check(_ token: UInt64) throws {
        guard isCurrent(token) else { throw CancellationError() }
    }

    func finishPreparation(_ token: UInt64) {
        preparing.remove(token)
        guard preparing.isEmpty else { return }
        let waiters = drainWaiters
        drainWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    @discardableResult
    func invalidate() -> [String] {
        generation &+= 1
        let invalidated = dartPreparations.keys.sorted()
        dartPreparations.removeAll()
        return invalidated
    }

    func waitForPreparation() async {
        guard !preparing.isEmpty else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }
}
