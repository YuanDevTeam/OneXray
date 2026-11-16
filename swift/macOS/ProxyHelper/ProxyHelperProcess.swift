import Darwin
import Foundation

/// Owns only the child it created. Never adopts or stops processes by name.
final class DesktopProxyProcess: @unchecked Sendable {
    private let process = Process()
    private let queue = DispatchQueue(label: "net.yuandev.onexray.proxy.ipc", qos: .userInitiated)
    private let parentSocket: FileHandle
    private let childSocket: FileHandle
    private var nextCommandID: UInt64 = 0
    private var launched = false
    private var closed = false

    init(executable: URL, onExit: @escaping @Sendable () -> Void) throws {
        var sockets: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
            throw ProxyHelperFailure.system(errno)
        }
        do {
            try ProxyHelperWire.prepareSocket(sockets[0])
            try ProxyHelperWire.prepareSocket(sockets[1])
        } catch {
            Darwin.close(sockets[0])
            Darwin.close(sockets[1])
            throw error
        }
        parentSocket = FileHandle(fileDescriptor: sockets[0], closeOnDealloc: true)
        childSocket = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
        process.executableURL = executable
        process.standardInput = childSocket
        // Core console output must not be interpreted as control messages.
        // Configured Xray file logs remain owned by Core.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in onExit() }
    }

    var isRunning: Bool { process.isRunning }

    func start(invokeText: String, port: Int) async throws {
        try await perform {
            do {
                try self.process.run()
                self.launched = true
                // Only the child now owns its socket end; parent death/close
                // therefore delivers EOF to the helper.
                try self.childSocket.close()
                let result = try self.exchange(method: "start", invokeText: invokeText, port: port)
                guard result.running else { throw ProxyHelperFailure.closed }
            } catch {
                self.terminateOwnedProcess()
                self.closeChannel()
                throw error
            }
        }
    }

    func readStatus() async throws -> Bool {
        try await perform {
            guard self.process.isRunning else { return false }
            return try self.exchange(method: "state").running
        }
    }

    func stop() async throws {
        try await perform {
            defer { self.closeChannel() }
            guard self.launched, self.process.isRunning else { return }
            do {
                let result = try self.exchange(method: "stop", timeout: 3)
                guard !result.running else { throw ProxyHelperFailure.invalidReply }
                self.waitForExit(seconds: 2)
                if self.process.isRunning { self.terminateOwnedProcess() }
                guard !self.process.isRunning else { throw ProxyHelperFailure.timedOut }
            } catch {
                // A stuck/broken control channel never leaves our Core alive.
                self.terminateOwnedProcess()
                throw error
            }
        }
    }

    private func exchange(method: String, invokeText: String? = nil, port: Int? = nil, timeout: TimeInterval = 10) throws -> ProxyHelperReply {
        guard !closed else { throw ProxyHelperFailure.closed }
        nextCommandID &+= 1
        let command = ProxyHelperCommand(id: nextCommandID, method: method, invokeText: invokeText, proxyPort: port)
        try ProxyHelperWire.write(command, to: parentSocket.fileDescriptor, timeout: timeout)
        let result = try ProxyHelperWire.read(ProxyHelperReply.self, from: parentSocket.fileDescriptor, timeout: timeout)
        guard result.id == command.id else { throw ProxyHelperFailure.invalidReply }
        guard result.success else {
            throw ProxyHelperFailure.core(result.error ?? "The local proxy helper command failed.")
        }
        return result
    }

    private func closeChannel() {
        guard !closed else { return }
        closed = true
        try? parentSocket.close()
        try? childSocket.close()
    }

    private func waitForExit(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    }

    private func terminateOwnedProcess() {
        guard launched, process.isRunning else { return }
        process.terminate()
        waitForExit(seconds: 1)
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
            waitForExit(seconds: 1)
        }
    }

    private func perform<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

/// Keeps repeated AppKit quit requests on the same owned helper shutdown.
@MainActor
final class DesktopProxyTermination {
    private var pending = false

    /// Returns whether AppKit must wait for `reply`. Confirmation concerns the
    /// actual process state, including a successful reap after a command error.
    func deferIfNeeded(
        isProxyActive: Bool,
        stopAndConfirmStopped: @escaping @MainActor () async -> Bool,
        reply: @escaping @MainActor (Bool) -> Void
    ) -> Bool {
        guard !pending else { return true }
        guard isProxyActive else { return false }
        pending = true
        Task {
            let stopped = await stopAndConfirmStopped()
            pending = false
            reply(stopped)
        }
        return true
    }
}
