import Darwin
import Foundation
import LibXray
import NetworkExtension

enum TunnelError: Error {
    case noSocketFd
    case noStartModel
    case noGroupContainer
    case noXrayJson
    case startXrayTimeout
    case startXrayFailed(String)
    case noRoutingData
}

final class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    /// https://github.com/WireGuard/wireguard-apple/blob/master/Sources/WireGuardKit/WireGuardAdapter.swift
    /// Tunnel device file descriptor.
    private var tunnelFileDescriptor: Int32? {
        var ctlInfo = ctl_info()
        withUnsafeMutablePointer(to: &ctlInfo.ctl_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) {
                _ = strcpy($0, "com.apple.net.utun_control")
            }
        }
        for fd: Int32 in 0 ... 1024 {
            var addr = sockaddr_ctl()
            var ret: Int32 = -1
            var len = socklen_t(MemoryLayout.size(ofValue: addr))
            withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    ret = getpeername(fd, $0, &len)
                }
            }
            if ret != 0 || addr.sc_family != AF_SYSTEM {
                continue
            }
            if ctlInfo.ctl_id == 0 {
                ret = ioctl(fd, CTLIOCGINFO, &ctlInfo)
                if ret != 0 {
                    continue
                }
            }
            if addr.sc_id == ctlInfo.ctl_id {
                return fd
            }
        }
        return nil
    }

    private static let stateQueue = DispatchQueue(label: "net.yuandev.onexray.tunnel.state")
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var pendingStartSignal = false

    override func startTunnel(
        options: [String: NSObject]? = nil,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        let startedByApp = options != nil
        let systemExtensionRequest: StartVpnRequest?
        do {
            if Constants.useSystemExtension {
                systemExtensionRequest = try prepareSystemExtensionRequest()
            } else {
                systemExtensionRequest = nil
            }
        } catch {
            completionHandler(error)
            return
        }
        Task {
            do {
                if let systemExtensionRequest {
                    try await startTunnelSE(request: systemExtensionRequest, startedByApp: startedByApp)
                } else {
                    try await startTunnelLegacy()
                }
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    private func startTunnelLegacy() async throws {
        guard let request = StartVpnRequest.startModel else {
            YGLog("startTunnel noStartModel")
            throw TunnelError.noStartModel
        }
        let settings = try buildSettings(request: request)
        try await setTunnelNetworkSettings(settings)
        if let coreInvokeText = request.coreInvokeText {
            try await startXray(coreInvokeText)
        }
        YGLog("startTunnel finished")
    }

    // Set up before the asynchronous start task so provider messages can use
    // the shared runtime directories immediately.
    private func prepareSystemExtensionRequest() throws -> StartVpnRequest {
        guard let providerConfig = (self.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration else {
            YGLog("startTunnel no providerConfiguration")
            throw TunnelError.noStartModel
        }
        guard let requestData = providerConfig["request"] as? Data,
              let request = try? JsonTool.decode(StartVpnRequest.self, from: requestData) else {
            YGLog("startTunnel decode request failed")
            throw TunnelError.noStartModel
        }
        guard request.coreInvokeText?.isEmpty == false else {
            throw TunnelError.noStartModel
        }

        guard let extGroupURL = extensionGroupContainerURL() else {
            YGLog("startTunnel noGroupContainer")
            throw TunnelError.noGroupContainer
        }
        let fm = FileManager.default
        let runDirectory = extGroupURL.adaptedAppendPath(path: "run")
        if try !runtimeDirectoryExists(runDirectory) {
            try fm.createDirectory(at: runDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        for name in ["access.log", "error.log"] {
            let file = runDirectory.adaptedAppendPath(path: name)
            var attributes = stat()
            if lstat(file.adaptedPath(), &attributes) == 0 {
                try fm.removeItem(at: file)
            } else if errno != ENOENT {
                throw RuntimeStateError.invalid
            }
        }
        // A failed transfer may leave only this shared temporary directory.
        let staging = extGroupURL.adaptedAppendPath(path: "dat.staging")
        if try runtimeDirectoryExists(staging) { try fm.removeItem(at: staging) }
        Self.stateQueue.sync {
            self.pendingStartSignal = false
        }
        return request
    }

    private func startTunnelSE(request: StartVpnRequest, startedByApp: Bool) async throws {
        // App-driven starts synchronize the shared root first. On Demand reuses
        // the last complete root published by an App-driven start.
        if startedByApp {
            YGLog("startTunnel awaiting start_xray signal")
            try await waitStartSignal(timeout: 30)
        } else {
            YGLog("startTunnel on-demand, skipping XPC sync")
        }
        guard let dat = datDir(), try DatFileTransfer.directoryExists(dat) else {
            throw TunnelError.noRoutingData
        }

        let settings = try buildSettings(request: request)
        try await setTunnelNetworkSettings(settings)

        if let coreInvokeText = request.coreInvokeText {
            try await startXray(coreInvokeText)
        }
    }

    private func buildSettings(request: StartVpnRequest) throws -> NEPacketTunnelNetworkSettings {
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.254.0.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: ProxyHost)
        settings.ipv4Settings = ipv4
        settings.mtu = TunMtu
        var servers: [String] = []
        if let tun = request.tun {
            if let tunDnsIPv4 = tun.tunDnsIPv4 {
                servers.append(tunDnsIPv4)
            }
            if let enableIPv6 = tun.enableIPv6, enableIPv6 {
                let ipv6 = NEIPv6Settings(addresses: ["fc00::1"], networkPrefixLengths: [64])
                ipv6.includedRoutes = [NEIPv6Route.default()]
                settings.ipv6Settings = ipv6
                if let tunDnsIPv6 = tun.tunDnsIPv6 {
                    servers.append(tunDnsIPv6)
                }
            }

            if let enableDot = tun.enableDot, enableDot {
                let dnsSettings = NEDNSOverTLSSettings(servers: servers)
                if let serverName = tun.dnsServerName {
                    dnsSettings.serverName = serverName
                }
                settings.dnsSettings = dnsSettings
            } else {
                settings.dnsSettings = NEDNSSettings(servers: servers)
            }
            if tun.includeAllNetworks != true {
                var excludedRoutes = tun.excludedRoutes ?? []
                #if os(iOS)
                // Keep the default routes; these exceptions affect iOS's VPN badge.
                // They are runtime-only and never alter the user's exclusion list.
                if tun.hideVpnIcon == true {
                    if !excludedRoutes.contains("0.0.0.0/31") {
                        excludedRoutes.append("0.0.0.0/31")
                    }
                    if tun.enableIPv6 == true, !excludedRoutes.contains("::/127") {
                        excludedRoutes.append("::/127")
                    }
                }
                #endif
                try applyExcludedRoutes(excludedRoutes, to: settings)
            }
        }
        return settings
    }

    private func applyExcludedRoutes(_ cidrs: [String], to settings: NEPacketTunnelNetworkSettings) throws {
        var ipv4Routes: [NEIPv4Route] = []
        var ipv6Routes: [NEIPv6Route] = []
        for cidr in cidrs {
            let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
            let invalid = NSError(
                domain: "OneXray.Tunnel", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid excluded route: \(cidr)"]
            )
            guard parts.count == 2, let prefix = Int(parts[1]), prefix >= 0 else {
                throw invalid
            }
            let address = String(parts[0])
            var ipv4 = in_addr()
            var ipv6 = in6_addr()
            if inet_pton(AF_INET, address, &ipv4) == 1 {
                guard prefix <= 32 else { throw invalid }
                let mask = (0..<4).map { index in
                    let bits = min(8, max(0, prefix - index * 8))
                    return String((0xff << (8 - bits)) & 0xff)
                }.joined(separator: ".")
                ipv4Routes.append(NEIPv4Route(destinationAddress: address, subnetMask: mask))
            } else if inet_pton(AF_INET6, address, &ipv6) == 1 {
                guard prefix <= 128 else { throw invalid }
                if settings.ipv6Settings != nil {
                    ipv6Routes.append(NEIPv6Route(destinationAddress: address, networkPrefixLength: NSNumber(value: prefix)))
                }
            } else {
                throw invalid
            }
        }
        settings.ipv4Settings?.excludedRoutes = ipv4Routes
        settings.ipv6Settings?.excludedRoutes = ipv6Routes
    }

    private func waitStartSignal(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.stateQueue.async {
                if self.pendingStartSignal {
                    self.pendingStartSignal = false
                    continuation.resume(returning: ())
                    return
                }
                self.startContinuation = continuation
                let deadline = DispatchTime.now() + timeout
                Self.stateQueue.asyncAfter(deadline: deadline) {
                    if let c = self.startContinuation {
                        self.startContinuation = nil
                        c.resume(throwing: TunnelError.startXrayTimeout)
                    }
                }
            }
        }
    }

    private func fulfillStartSignal() {
        Self.stateQueue.async {
            if let c = self.startContinuation {
                self.startContinuation = nil
                c.resume(returning: ())
            } else {
                self.pendingStartSignal = true
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        self.stopXray()
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        if Constants.useSystemExtension {
            return handleAppMessageSE(messageData)
        }
        return messageData
    }

    private func handleAppMessageSE(_ data: Data) -> Data? {
        let request: TunnelRequest
        do {
            request = try TunnelMessageCoder.decode(TunnelRequest.self, from: data)
        } catch {
            YGLog("handleAppMessage decode error: \(error)")
            return try? TunnelMessageCoder.encode(TunnelResponse.error("decode"))
        }

        let response: TunnelResponse
        do {
            guard let dat = datDir(), let staging = stagingDir() else {
                throw TunnelError.noGroupContainer
            }
            switch request {
            case .listDat:
                response = .datManifest(try DatFileTransfer.manifest(in: dat))
            case .clearDat:
                try DatFileTransfer.clearStaging(staging)
                response = .ok
            case let .putDat(name, content, mtimeMs):
                try DatFileTransfer.put(name: name, content: content, mtimeMs: mtimeMs, in: staging)
                response = .ok
            case let .commitDatFiles(expected):
                try DatFileTransfer.commit(staging: staging, to: dat, expected: expected)
                response = .ok
            case .startXray:
                fulfillStartSignal()
                response = .ok
            }
        } catch {
            YGLog("dat transfer error: \(error)")
            response = .error(String(describing: error))
        }
        return try? TunnelMessageCoder.encode(response)
    }

    private func logFile(access: Bool) throws -> URL? {
        guard Constants.useSystemExtension, let container = extensionGroupContainerURL() else {
            throw RuntimeStateError.unsupported
        }
        let directory = container.adaptedAppendPath(path: "run")
        guard try runtimeDirectoryExists(directory) else { return nil }
        return directory.adaptedAppendPath(path: access ? "access.log" : "error.log")
    }

    private func runtimeDirectoryExists(_ directory: URL) throws -> Bool {
        do {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw RuntimeStateError.invalid
            }
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return false
        }
    }

    // MARK: - dat staging operations

    private func datDir() -> URL? {
        extensionGroupContainerURL()?.adaptedAppendPath(path: "dat")
    }

    private func stagingDir() -> URL? {
        extensionGroupContainerURL()?.adaptedAppendPath(path: "dat.staging")
    }

    // MARK: - Xray lifecycle

    private func startXray(_ requestJson: String) async throws {
        guard let fd = self.tunnelFileDescriptor else {
            YGLog("PacketTunnelProvider TunnelError.noSocketFd")
            throw TunnelError.noSocketFd
        }
        let request = try patchRuntimeEnv(
            fd: fd,
            request: LibXrayInvokeRequest.fromText(requestJson)
        )
        let requestText = try request.toText()

        let responseText = await Task.detached(priority: .userInitiated) {
            requestText.withCString { p -> String? in
                let p0 = UnsafeMutablePointer(mutating: p)
                guard let response = CGoInvoke(p0) else { return nil }
                defer { CGoFree(response) }
                return String(cString: response)
            }
        }.value
        let result = LibXrayInvokeResponse.fromText(responseText)
        if !result.isSuccess {
            let error = result.error
            YGLog("PacketTunnelProvider startXray \(error)")
            throw TunnelError.startXrayFailed(error)
        }
    }

    private func patchRuntimeEnv(
        fd: Int32,
        request: LibXrayInvokeRequest
    ) throws -> LibXrayInvokeRequest {
        guard let xrayJson = request.payload?.xrayJson, !xrayJson.isEmpty else {
            YGLog("PacketTunnelProvider TunnelError.noXrayJson")
            throw TunnelError.noXrayJson
        }
        var root = try JsonTool.decodeObject(from: Data(xrayJson.utf8))
        var env = try xrayRuntimeEnvWithTunFd(root["env"], fd: fd)
        if Constants.useSystemExtension {
            guard let dat = datDir() else {
                YGLog("PacketTunnelProvider TunnelError.noGroupContainer")
                throw TunnelError.noGroupContainer
            }
            let datPath = dat.adaptedPath()
            env["xray.location.asset"] = datPath
            env["xray.location.cert"] = datPath
            if var log = root["log"] as? [String: Any] {
                for (key, access) in [("access", true), ("error", false)] {
                    guard let path = log[key] as? String, !path.isEmpty, path != "none" else { continue }
                    guard let file = try logFile(access: access) else {
                        throw TunnelError.noGroupContainer
                    }
                    log[key] = file.adaptedPath()
                }
                root["log"] = log
            }
        }
        root["env"] = env
        let data = try JsonTool.encodeObject(root)
        guard let updatedJson = String(data: data, encoding: .utf8) else {
            throw TunnelError.noXrayJson
        }
        var updatedRequest = request
        var payload = request.payload ?? RunXrayRequest(xrayJson: nil)
        payload.xrayJson = updatedJson
        updatedRequest.payload = payload
        return updatedRequest
    }

    private func stopXray() {
        do {
            let request = try LibXrayInvokeRequest(method: .stopXray).toText()
            let res = request.withCString { p in
                let p0 = UnsafeMutablePointer(mutating: p)
                return CGoInvoke(p0)
            }
            let result = LibXrayInvokeResponse.fromResponse(res)
            if !result.isSuccess {
                let error = result.error
                YGLog("PacketTunnelProvider stopXray \(error)")
                killProcess()
            }
        } catch {
            YGLog("PacketTunnelProvider stopXray \(error.localizedDescription)")
            killProcess()
        }
    }
}


private func killProcess() {
    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
        exit(0)
    }
}
