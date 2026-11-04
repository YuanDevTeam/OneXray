import Foundation
import Darwin

/// Retires starts synchronously, while Core work and Stop wait on a background queue.
final class XrayRuntimeLifecycle: @unchecked Sendable {
    private let stateLock = NSLock()
    private let coreQueue = DispatchQueue(label: "net.yuandev.onexray.core.lifecycle", qos: .userInitiated)
    private var generation: UInt64 = 0

    func beginStart() -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        generation &+= 1
        return generation
    }

    func isCurrent(_ token: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return token == generation
    }

    func check(_ token: UInt64) throws {
        guard isCurrent(token) else { throw CancellationError() }
    }

    func start(
        generation token: UInt64,
        operation: @escaping @Sendable () throws -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        coreQueue.async {
            do {
                try self.check(token)
                try operation()
                try self.check(token)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    @discardableResult
    func stop(
        operation: @escaping @Sendable () -> Void,
        completion: @escaping @Sendable (UInt64) -> Void
    ) -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        generation &+= 1
        let token = generation
        // Enqueue before admitting a newer generation, so this Stop cannot close it.
        coreQueue.async {
            operation()
            completion(token)
        }
        return token
    }
}

enum XrayRuntimeLogError: LocalizedError {
    case invalidDirectory(String)
    case invalidFile(String)

    var errorDescription: String? {
        switch self {
        case let .invalidDirectory(path): return "Invalid runtime log directory: \(path)"
        case let .invalidFile(path): return "Invalid runtime log file: \(path)"
        }
    }
}

/// Clear only the two managed logs after the previous Core has stopped.
func clearXrayRuntimeLogs(in directory: URL, fileManager: FileManager = .default) throws {
    guard let directoryType = try xrayRuntimeLogFileType(directory) else { return }
    guard directoryType == S_IFDIR else {
        throw XrayRuntimeLogError.invalidDirectory(directory.path)
    }
    var files: [URL] = []
    for name in ["access.log", "error.log"] {
        let file = directory.appendingPathComponent(name)
        guard let type = try xrayRuntimeLogFileType(file) else { continue }
        guard type == S_IFREG else { throw XrayRuntimeLogError.invalidFile(file.path) }
        files.append(file)
    }
    // Validate both before removing either; do not follow links or enumerate run/.
    for file in files { try fileManager.removeItem(at: file) }
}

private func xrayRuntimeLogFileType(_ url: URL) throws -> mode_t? {
    var info = stat()
    if lstat(url.path, &info) == 0 { return info.st_mode & S_IFMT }
    if errno == ENOENT { return nil }
    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
}

/// Preserve Core-owned environment entries while installing the platform FD.
/// Resource paths for the System Extension are applied by its caller afterwards.
func xrayRuntimeEnvWithTunFd(_ object: Any?, fd: Int32) throws -> [String: Any] {
    var env: [String: Any]
    if let object, !(object is NSNull) {
        guard let existing = object as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        env = existing
    } else {
        env = [:]
    }
    env["xray.tun.fd"] = "\(fd)"
    return env
}
