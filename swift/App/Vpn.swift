import Combine
import Foundation
import NetworkExtension

typealias VPNStatusCallback = @MainActor () async throws -> Void

enum VPNError: LocalizedError {
    case sessionNotReady
    case noGroupContainer
    case routingDataSyncFailed
    case statusTimeout

    var errorDescription: String? {
        switch self {
        case .sessionNotReady: return "The VPN session is not ready."
        case .noGroupContainer: return "The App Group data directory is unavailable."
        case .routingDataSyncFailed: return "Unable to transfer routing data to the VPN extension."
        case .statusTimeout: return "Timed out waiting for the system VPN to finish the operation."
        }
    }
}

@MainActor
class VPNManager {
    static let shared = VPNManager()

    var vpn: NETunnelProviderManager?
    private(set) var lastCommandError: String?
    private var awaitingStart = false
    private var observedConnecting = false
    private var cancellable: Cancellable?
    private var statusObserver: VPNStatusCallback?
    #if os(macOS)
    private let systemExtensionActivation = SystemExtensionActivation()
    #endif
    private struct StatusWait {
        let session: NETunnelProviderSession
        let accepted: [NEVPNStatus]
        let continuation: CheckedContinuation<Void, Error>
        let timeout: Task<Void, Never>
        var observedTransition: Bool
    }
    private var statusWaits: [UUID: StatusWait] = [:]

    init() {
        YGLog("VPNManager init")
        #if !targetEnvironment(simulator)
        cancellable = NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)
            .sink(receiveValue: { noti in
                if let session = noti.object as? NETunnelProviderSession {
                    if session == self.vpn?.connection || self.statusWaits.values.contains(where: { $0.session == session }) {
                        self.checkStatusWaits()
                        self.runStatusObserver()
                    }
                }
            })
        #endif
    }

    // Register before issuing a command; notifications, not a timer loop,
    // confirm its completion. The timer only bounds a missing system reply.
    private func waitForStatus(
        session: NETunnelProviderSession,
        accepted: [NEVPNStatus],
        timeout: UInt64,
        action: (() throws -> Void)? = nil
    ) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                let timer = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: timeout * 1_000_000_000) }
                    catch { return }
                    self.finishStatusWait(id, result: .failure(VPNError.statusTimeout))
                }
                statusWaits[id] = StatusWait(
                    session: session, accepted: accepted, continuation: continuation, timeout: timer,
                    observedTransition: action == nil || [.connecting, .connected, .reasserting, .disconnecting].contains(session.status)
                )
                do {
                    try action?()
                    checkStatusWaits(initial: action != nil)
                } catch {
                    finishStatusWait(id, result: .failure(error))
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.finishStatusWait(id, result: .failure(CancellationError()))
            }
        }
    }

    private func checkStatusWaits(initial: Bool = false) {
        for (id, wait) in statusWaits {
            let status = wait.session.status
            if wait.accepted.contains(status) {
                finishStatusWait(id, result: .success(()))
            } else if [.connecting, .connected, .reasserting, .disconnecting].contains(status) {
                statusWaits[id]?.observedTransition = true
            } else if !initial && wait.observedTransition &&
                        (status == .disconnected || status == .invalid) {
                finishStatusWait(id, result: .failure(VPNError.sessionNotReady))
            }
        }
    }

    private func finishStatusWait(_ id: UUID, result: Result<Void, Error>) {
        guard let wait = statusWaits.removeValue(forKey: id) else { return }
        wait.timeout.cancel()
        wait.continuation.resume(with: result)
    }

    private func runStatusObserver() {
        if let observer = statusObserver {
            Task {
                do {
                    try await observer()
                } catch {
                    YGLog("VPN status is unavailable")
                }
            }
        }
    }

    func registerStatusObserver(_ observer: @escaping VPNStatusCallback) {
        statusObserver = observer
    }

    func unregisterStatusObserver() {
        statusObserver = nil
    }

    private func findVpn() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        for vpn in managers {
            if let conf = vpn.protocolConfiguration as? NETunnelProviderProtocol {
                if conf.providerBundleIdentifier == packetTunnelId() {
                    return vpn
                }
            }
        }
        return nil
    }

    private func newVpn() -> NETunnelProviderManager {
        let serverAddress = vpnServerAddress()

        let vpn = NETunnelProviderManager()
        let conf = NETunnelProviderProtocol()
        conf.providerBundleIdentifier = packetTunnelId()
        conf.serverAddress = serverAddress

        conf.username = serverAddress

        vpn.protocolConfiguration = conf
        vpn.localizedDescription = serverAddress
        return vpn
    }

    func queryPlatformPermission() async -> PlatformPermissionResult {
        #if targetEnvironment(simulator)
        // The simulator cannot query NetworkExtension VPN preferences.
        return PlatformPermissionResult(
            kind: .appleVpn,
            state: .notRequired,
            message: nil
        )
        #else
        #if os(macOS)
        if Constants.useSystemExtension {
            let state = await querySystemExtensionIfNeeded()
            if state != .installed {
                return platformPermissionResult(from: state)
            }
        }
        #endif
        do {
            vpn = try await findVpn()
            return PlatformPermissionResult(
                kind: .appleVpn,
                state: vpn == nil ? .notDetermined : .granted,
                message: nil
            )
        } catch {
            YGLog(error.localizedDescription)
            return PlatformPermissionResult(
                kind: .appleVpn,
                state: .failed,
                message: error.localizedDescription
            )
        }
        #endif
    }

    func requestPlatformPermission() async -> PlatformPermissionResult {
        #if targetEnvironment(simulator)
        return await queryPlatformPermission()
        #else
        #if os(macOS)
        if Constants.useSystemExtension {
            var state = await querySystemExtensionIfNeeded()
            if state != .installed {
                state = await requestSystemExtensionIfNeeded()
            }
            if state != .installed {
                return platformPermissionResult(from: state, requested: true)
            }
        }
        #endif
        do {
            if let existing = try await findVpn() {
                vpn = existing
            } else {
                let manager = newVpn()
                // Prepare authorization only; the initial profile has no On Demand rules.
                try await saveVpn(vpn: manager, tun: TunJson())
                vpn = manager
            }
            return PlatformPermissionResult(
                kind: .appleVpn,
                state: .granted,
                message: nil
            )
        } catch {
            YGLog(error.localizedDescription)
            return PlatformPermissionResult(
                kind: .appleVpn,
                state: .failed,
                message: error.localizedDescription
            )
        }
        #endif
    }

    #if os(macOS)
    private func platformPermissionResult(
        from state: SystemExtensionState,
        requested: Bool = false
    ) -> PlatformPermissionResult {
        switch state {
        case .installed:
            return PlatformPermissionResult(
                kind: .macosSystemExtension,
                state: .granted,
                message: nil
            )
        case .waitForApproval:
            return PlatformPermissionResult(
                kind: .macosSystemExtension,
                state: .awaitingUserApproval,
                message: nil
            )
        case .notInstalled:
            return PlatformPermissionResult(
                kind: .macosSystemExtension,
                state: requested ? .failed : .notDetermined,
                message: requested ? "System Extension activation did not complete." : nil
            )
        }
    }

    private func querySystemExtensionIfNeeded() async -> SystemExtensionState {
        await SystemExtensionManager.isInstalled()
    }

    private func requestSystemExtensionIfNeeded() async -> SystemExtensionState {
        await systemExtensionActivation.request { await self.runSystemExtensionSetup() }
    }

    private func runSystemExtensionSetup() async -> SystemExtensionState {
        #if DEBUG
        let force = true
        #else
        let force = false
        #endif
        do {
            let installed = await SystemExtensionManager.isInstalled()
            if (installed == .installed || installed == .waitForApproval) && !force {
                return installed
            }
            if let result = try await SystemExtensionManager.activate(forceReplace: force) {
                if result == .completed {
                    return .installed
                } else {
                    return .notInstalled
                }
            }
            return .waitForApproval
        } catch {
            YGLog("setup system extension error: \(error.localizedDescription)")
            return .notInstalled
        }
    }
    #endif

    private func readStatus() async throws -> NEVPNStatus? {
        #if targetEnvironment(simulator)
        return try await SimulatorProxy.isRunning() ? .connected : .disconnected
        #else
        let status = vpn?.connection.status
        if status == .connected {
            awaitingStart = false
            lastCommandError = nil
        } else if status == .connecting || status == .reasserting {
            observedConnecting = true
        } else if status == .disconnected, awaitingStart, observedConnecting {
            awaitingStart = false
            if #available(iOS 16.0, macOS 13.0, *), let connection = vpn?.connection {
                lastCommandError = await withCheckedContinuation { continuation in
                    connection.fetchLastDisconnectError { error in
                        continuation.resume(returning: error?.localizedDescription)
                    }
                }
            }
        }
        return status
        #endif
    }

    func readVpnStatus() async throws -> VpnStatus {
        guard let status = try await readStatus() else {
            #if os(iOS)
            AppleWidgetPublisher.publish(.unknown)
            #endif
            return .disconnected
        }
        YGLog("readRunningVpn \(status.rawValue)")
        let result: VpnStatus
        switch status {
        case .disconnecting: result = .disconnecting
        case .connecting, .reasserting: result = .connecting
        case .connected: result = .connected
        default: result = .disconnected
        }
        #if os(iOS)
        // Only the system's observed status may publish a connected snapshot.
        let widgetStatus: AppleWidgetStatus = switch result {
        case .disconnecting: .disconnecting
        case .disconnected: .disconnected
        case .connecting: .connecting
        case .connected: .connected
        }
        AppleWidgetPublisher.publish(widgetStatus)
        #endif
        return result
    }

    private func commandResult(_ state: NativeVpnCommandState) async -> NativeVpnCommandResult {
        let permission = await queryPlatformPermission()
        switch state {
        case .success:
            do {
                return NativeVpnCommandResult(
                    state: .success,
                    status: try await readVpnStatus(),
                    permission: permission,
                    message: nil
                )
            } catch {
                return NativeVpnCommandResult(
                    state: .failed,
                    permission: permission,
                    message: error.localizedDescription
                )
            }
        case .waitingForPlatformPermission:
            return NativeVpnCommandResult(
                state: .waitingForPlatformPermission,
                permission: permission,
                message: nil
            )
        case .failed:
            if permission.state == .awaitingUserApproval || permission.state == .notDetermined {
                return NativeVpnCommandResult(
                    state: .waitingForPlatformPermission,
                    permission: permission,
                    message: nil
                )
            }
            return NativeVpnCommandResult(
                state: .failed,
                permission: permission,
                message: lastCommandError ?? permission.message
            )
        }
    }

    func startVpn() async -> NativeVpnCommandResult {
        lastCommandError = nil
        awaitingStart = true
        observedConnecting = false
        guard let request = StartVpnRequest.startModel else {
            lastCommandError = "Unable to read run/start.json."
            return await commandResult(.failed)
        }
        #if targetEnvironment(simulator)
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId()) else {
            lastCommandError = VPNError.noGroupContainer.localizedDescription
            runStatusObserver()
            return await commandResult(.failed)
        }
        let state: NativeVpnCommandState
        do {
            try await SimulatorProxy.start(request, at: groupURL.adaptedAppendPath(path: StartModelFile))
            state = .success
        } catch {
            YGLog("Simulator proxy start failed: \(error)")
            lastCommandError = error.localizedDescription
            state = .failed
        }
        runStatusObserver()
        return await commandResult(state)
        #else
        do {
            let permission = await queryPlatformPermission()
            switch permission.state {
            case .granted, .notRequired:
                break
            case .awaitingUserApproval:
                return await commandResult(.waitingForPlatformPermission)
            default:
                return await commandResult(.failed)
            }
            if let vpn = vpn {
                if let tun = request.tun {
                    try await saveVpn(vpn: vpn, tun: tun, request: request)
                } else {
                    try await saveVpn(vpn: vpn, tun: TunJson(), request: request)
                }
                if let session = vpn.connection as? NETunnelProviderSession {
                    if Constants.useSystemExtension {
                        try await waitForStatus(
                            session: session, accepted: [.connecting, .connected, .reasserting], timeout: 10
                        ) {
                            try session.startTunnel(options: ["source": "app" as NSString])
                        }
                        try await syncDatAndStart(session: session)
                        try await waitForStatus(session: session, accepted: [.connected], timeout: 30)
                    } else {
                        try await waitForStatus(session: session, accepted: [.connected], timeout: 30) {
                            try session.startTunnel()
                        }
                    }
                    return await commandResult(.success)
                } else {
                    lastCommandError = VPNError.sessionNotReady.localizedDescription
                    return await commandResult(.failed)
                }
            } else {
                lastCommandError = VPNError.sessionNotReady.localizedDescription
                return await commandResult(.failed)
            }
        } catch {
            YGLog(error.localizedDescription)
            _ = try? await readStatus()
            if lastCommandError == nil { lastCommandError = error.localizedDescription }
            return await commandResult(.failed)
        }
        #endif
    }

    func stopVpn() async -> NativeVpnCommandResult {
        lastCommandError = nil
        awaitingStart = false
        #if targetEnvironment(simulator)
        let state: NativeVpnCommandState
        do {
            try await SimulatorProxy.stop()
            state = .success
        } catch {
            YGLog("Simulator proxy stop failed: \(error)")
            lastCommandError = error.localizedDescription
            state = .failed
        }
        runStatusObserver()
        return await commandResult(state)
        #else
        #if os(macOS)
        if Constants.useSystemExtension {
            let installed = await querySystemExtensionIfNeeded()
            YGLog("querySystemExtensionIfNeeded \(installed)")
            if installed != .installed {
                return await commandResult(
                    installed == .waitForApproval ? .waitingForPlatformPermission : .failed
                )
            }
        }
        #endif
        if vpn == nil {
            do {
                vpn = try await findVpn()
            } catch {
                YGLog(error.localizedDescription)
                lastCommandError = error.localizedDescription
                return await commandResult(.failed)
            }
        }
        guard let vpn = vpn else {
            lastCommandError = VPNError.sessionNotReady.localizedDescription
            return await commandResult(.failed)
        }
        do {
            try await saveVpn(vpn: vpn, tun: TunJson())
        } catch {
            YGLog(error.localizedDescription)
            lastCommandError = error.localizedDescription
            return await commandResult(.failed)
        }
        do {
            guard let session = vpn.connection as? NETunnelProviderSession else {
                throw VPNError.sessionNotReady
            }
            try await waitForStatus(session: session, accepted: [.disconnected, .invalid], timeout: 15) {
                session.stopTunnel()
            }
            runStatusObserver()
            return await commandResult(.success)
        } catch {
            lastCommandError = error.localizedDescription
            return await commandResult(.failed)
        }
        #endif
    }

    private func saveVpn(vpn: NETunnelProviderManager, tun: TunJson, request: StartVpnRequest? = nil) async throws {
        vpn.isEnabled = true
        if let conf = vpn.protocolConfiguration as? NETunnelProviderProtocol {
            applyAppleNetworkRouting(conf, tun: tun)
            if let request {
                var providerConfig = conf.providerConfiguration ?? [:]
                let encodedRequest: Data
                if Constants.useSystemExtension {
                    let rewritten = rewriteRequestForExtension(request)
                    encodedRequest = try JsonTool.encode(rewritten)
                } else {
                    encodedRequest = try JsonTool.encode(request)
                }
                providerConfig["request"] = encodedRequest
                conf.providerConfiguration = providerConfig
            }
        }
        if let onDemandEnabled = tun.onDemandEnabled, onDemandEnabled {
            if let rules = tun.onDemandRules, !rules.isEmpty {
                let onDemandRules = convertRules(rules)
                if onDemandRules.isEmpty {
                    vpn.isOnDemandEnabled = false
                    vpn.onDemandRules = nil
                } else {
                    vpn.isOnDemandEnabled = true
                    vpn.onDemandRules = onDemandRules
                }
            } else {
                vpn.isOnDemandEnabled = true
                vpn.onDemandRules = [NEOnDemandRuleConnect()]
            }
        } else {
            vpn.isOnDemandEnabled = false
            vpn.onDemandRules = nil
        }
        vpn.protocolConfiguration?.disconnectOnSleep = false
        try await vpn.saveToPreferences()
        try await vpn.loadFromPreferences()
    }

    private func applyAppleNetworkRouting(_ conf: NETunnelProviderProtocol, tun: TunJson) {
        conf.includeAllNetworks = tun.includeAllNetworks ?? false
        conf.excludeLocalNetworks = tun.excludeLocalNetworks ?? true
        if #available(macOS 13.3, iOS 16.4, *) {
            conf.excludeCellularServices = tun.excludeCellularServices ?? true
            conf.excludeAPNs = tun.excludeAPNs ?? true
        }
        if #available(macOS 14.4, iOS 17.4, *) {
            conf.excludeDeviceCommunication = tun.excludeDeviceCommunication ?? true
        }
    }

    private func convertRules(_ rules: [OnDemandRule]) -> [NEOnDemandRule] {
        var onDemandRules: [NEOnDemandRule] = []
        for rule in rules {
            if let onDemandRule = convertRule(rule) {
                onDemandRules.append(onDemandRule)
            }
        }
        return onDemandRules
    }

    private func convertRule(_ rule: OnDemandRule) -> NEOnDemandRule? {
        guard let mode = rule.mode else { return nil }
        let onDemandRule: NEOnDemandRule
        switch mode {
        case .connect:
            onDemandRule = NEOnDemandRuleConnect()
        case .disconnect:
            onDemandRule = NEOnDemandRuleDisconnect()
        case .ignore:
            onDemandRule = NEOnDemandRuleIgnore()
        }
        return fillOnDemandRule(onDemandRule, rule) ? onDemandRule : nil
    }

    private func fillOnDemandRule(_ onDemandRule: NEOnDemandRule, _ rule: OnDemandRule) -> Bool {
        guard let interfaceType = rule.interfaceType,
              let interfaceTypeMatch = convertInterfaceType(interfaceType) else {
            return false
        }
        onDemandRule.interfaceTypeMatch = interfaceTypeMatch
        if interfaceTypeMatch == .wiFi {
            if let ssid = rule.ssid, !ssid.isEmpty {
                onDemandRule.ssidMatch = ssid
            }
        }
        return true
    }

    private func convertInterfaceType(_ interfaceType: OnDemandRuleInterfaceType) -> NEOnDemandRuleInterfaceType? {
        switch interfaceType {
        case .any:
            return .any
        case .wifi:
            return .wiFi
        #if os(macOS)
        case .ethernet:
            return .ethernet
        case .cellular:
            return nil
        #else
        case .cellular:
            return .cellular
        case .ethernet:
            return nil
        #endif
        }
    }

    // MARK: - System Extension path rewriting + XPC dat sync

    private func pathMapping() -> (user: String, ext: String)? {
        guard let userGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId()),
              let extGroup = extensionGroupContainerURL()
        else {
            return nil
        }
        var u = userGroup.adaptedPath()
        var e = extGroup.adaptedPath()
        while u.hasSuffix("/") {
            u.removeLast()
        }
        while e.hasSuffix("/") {
            e.removeLast()
        }
        if u == e { return nil }
        return (u, e)
    }

    private func rewriteRequestForExtension(_ request: StartVpnRequest) -> StartVpnRequest {
        guard let mapping = pathMapping() else { return request }
        var newRequest = request
        if let text = request.coreInvokeText,
           var invoke = try? LibXrayInvokeRequest.fromText(text),
           var payload = invoke.payload,
           let xrayJson = payload.xrayJson {
            payload.xrayJson = xrayJson.replacingOccurrences(
                of: mapping.user,
                with: mapping.ext
            )
            invoke.payload = payload
            if let rewritten = try? invoke.toText() {
                newRequest.coreInvokeText = rewritten
            }
        }
        return newRequest
    }

    private func syncDatAndStart(session: NETunnelProviderSession) async throws {
        guard let userGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId()) else {
            throw VPNError.routingDataSyncFailed
        }
        let directory = userGroup.adaptedAppendPath(path: "dat")
        guard let local = try DatFileTransfer.manifest(in: directory) else {
            throw VPNError.routingDataSyncFailed
        }

        let remote: [String: Int64]?
        let listResp = try await sendTunnelRequest(session: session, .listDat, timeoutSeconds: 10)
        if case let .datManifest(m) = listResp {
            remote = m
        } else {
            throw VPNError.routingDataSyncFailed
        }

        if DatFileTransfer.needsSync(local: local, remote: remote) {
            YGLog("dat manifest mismatch, syncing \(local.count) files")
            guard case .ok = try await sendTunnelRequest(session: session, .clearDat, timeoutSeconds: 10) else {
                throw VPNError.routingDataSyncFailed
            }
            for (name, mtime) in local {
                let content = try DatFileTransfer.read(name: name, in: directory)
                guard case .ok = try await sendTunnelRequest(session: session, .putDat(name: name, content: content, mtimeMs: mtime), timeoutSeconds: 10) else {
                    throw VPNError.routingDataSyncFailed
                }
            }
            guard case .ok = try await sendTunnelRequest(session: session, .commitDatFiles(expected: local), timeoutSeconds: 10) else {
                throw VPNError.routingDataSyncFailed
            }
        } else {
            YGLog("dat manifest in sync")
        }

        guard case .ok = try await sendTunnelRequest(session: session, .startXray, timeoutSeconds: 10) else {
            throw VPNError.routingDataSyncFailed
        }
    }

    private func sendTunnelRequest(
        session: NETunnelProviderSession,
        _ request: TunnelRequest,
        timeoutSeconds: UInt64? = nil
    ) async throws -> TunnelResponse {
        let data = try TunnelMessageCoder.encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            let pending = PendingTunnelResponse(continuation)
            let timeout = timeoutSeconds.map { seconds in
                Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) }
                    catch { return }
                    pending.resolve(.failure(RuntimeStateError.timeout))
                }
            }
            do {
                try session.sendProviderMessage(data) { response in
                    Task { @MainActor in
                        timeout?.cancel()
                        guard let response else {
                            pending.resolve(.failure(RuntimeStateError.unavailable))
                            return
                        }
                        do {
                            let decoded = try TunnelMessageCoder.decode(TunnelResponse.self, from: response)
                            pending.resolve(.success(decoded))
                        } catch {
                            pending.resolve(.failure(RuntimeStateError.invalid))
                        }
                    }
                }
            } catch {
                timeout?.cancel()
                pending.resolve(.failure(RuntimeStateError.unavailable))
            }
        }
    }

}

@MainActor
private final class PendingTunnelResponse {
    private var continuation: CheckedContinuation<TunnelResponse, Error>?

    init(_ continuation: CheckedContinuation<TunnelResponse, Error>) {
        self.continuation = continuation
    }

    func resolve(_ result: Result<TunnelResponse, Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}
