import Cocoa
import Foundation

@MainActor
final class DesktopProxyHost {
    static let shared = DesktopProxyHost()
    private var process: DesktopProxyProcess?
    private var processGeneration: UInt64?
    private var generation: UInt64 = 0
    private(set) var status: VpnStatus = .disconnected
    private var lastError: String?
    var onStatus: ((VpnStatus) -> Void)?

    var isActive: Bool { status != .disconnected }

    private func publish(_ value: VpnStatus) {
        status = value
        onStatus?(value)
    }

    private func result(_ error: Error? = nil) -> NativeVpnCommandResult {
        NativeVpnCommandResult(
            state: error == nil ? .success : .failed,
            status: status,
            permission: PlatformPermissionResult(kind: .none, state: .notRequired),
            message: error?.localizedDescription ?? lastError
        )
    }

    func start(_ requestJson: String) async -> NativeVpnCommandResult {
        guard process == nil, status == .disconnected else {
            return result(ProxyHelperFailure.core("The local proxy is already running or changing state."))
        }
        generation &+= 1
        let token = generation
        lastError = nil
        publish(.connecting)
        do {
            guard requestJson.utf8.count <= 32 * 1024 * 1024,
                  let request = try? JSONDecoder().decode(StartVpnRequest.self, from: Data(requestJson.utf8)),
                  request.captureMode == "proxy",
                  let invokeText = request.coreInvokeText,
                  let portText = request.socksPort,
                  let port = Int(portText), (1024...65535).contains(port),
                  let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId()) else {
                throw ProxyHelperFailure.invalidRequest
            }
            let helper = Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers/OneXrayProxyHelper.app/Contents/MacOS/OneXrayProxyHelper")
            guard FileManager.default.isExecutableFile(atPath: helper.path) else {
                throw ProxyHelperFailure.unavailable
            }
            try await VPNManager.shared.prepareForLocalProxy()
            guard token == generation else { throw CancellationError() }
            let run = group.appendingPathComponent("run", isDirectory: true)
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            try clearXrayRuntimeLogs(in: run)
            try StartRequestKind.proxy.writeSnapshot(Data(requestJson.utf8), in: group)
            let child = try DesktopProxyProcess(executable: helper) { [weak self] in
                Task { @MainActor in self?.didExit(generation: token) }
            }
            process = child
            processGeneration = token
            try await child.start(invokeText: invokeText, port: port)
            guard token == generation else {
                try? await child.stop()
                throw CancellationError()
            }
            publish(.connected)
            return result()
        } catch {
            if token == generation {
                lastError = error.localizedDescription
                if process?.isRunning == true {
                    // Preserve ownership if even forced termination could not
                    // be confirmed, so Stop can retry and Start stays blocked.
                    publish(.disconnecting)
                } else {
                    process = nil
                    processGeneration = nil
                    publish(.disconnected)
                }
            }
            return result(error)
        }
    }

    func stop() async -> NativeVpnCommandResult {
        generation &+= 1
        let token = generation
        let child = process
        publish(.disconnecting)
        do {
            try await child?.stop()
            if token == generation {
                process = nil
                processGeneration = nil
                lastError = nil
                publish(.disconnected)
            }
            return result()
        } catch {
            if token == generation {
                lastError = error.localizedDescription
                if child?.isRunning == true {
                    publish(.disconnecting)
                } else {
                    process = nil
                    processGeneration = nil
                    publish(.disconnected)
                }
            }
            return result(error)
        }
    }

    func readStatus() async -> NativeVpnCommandResult {
        if let child = process, !child.isRunning, status != .connecting,
           let token = processGeneration {
            didExit(generation: token)
        }
        if process != nil, status == .disconnecting, let lastError {
            return result(ProxyHelperFailure.core(lastError))
        }
        guard status == .connected, let child = process else { return result() }
        let token = generation
        do {
            let running = try await child.readStatus()
            if !running, token == generation, let owned = processGeneration {
                try? await child.stop()
                if !child.isRunning { didExit(generation: owned) }
                else { throw ProxyHelperFailure.closed }
            }
            return result()
        } catch {
            if token == generation {
                lastError = error.localizedDescription
                _ = await stop()
            }
            return result(error)
        }
    }

    private func didExit(generation token: UInt64) {
        guard token == processGeneration, process != nil else { return }
        generation &+= 1
        process = nil
        processGeneration = nil
        if status != .disconnected && status != .disconnecting {
            lastError = "The local proxy helper stopped unexpectedly."
        }
        publish(.disconnected)
    }
}

@MainActor
final class DesktopProxyHostApi: @preconcurrency BridgeDesktopProxyApi {
    func startProxy(requestJson: String, completion: @escaping (Result<NativeVpnCommandResult, any Error>) -> Void) {
        Task { completion(.success(await DesktopProxyHost.shared.start(requestJson))) }
    }

    func stopProxy(completion: @escaping (Result<NativeVpnCommandResult, any Error>) -> Void) {
        Task { completion(.success(await DesktopProxyHost.shared.stop())) }
    }

    func readProxyStatus(completion: @escaping (Result<NativeVpnCommandResult, any Error>) -> Void) {
        Task { completion(.success(await DesktopProxyHost.shared.readStatus())) }
    }
}
