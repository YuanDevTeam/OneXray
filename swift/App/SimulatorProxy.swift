#if targetEnvironment(simulator)
import Foundation

/// Simulator implementation of the normal native VPN lifecycle.
enum SimulatorProxy {
    enum Failure: Error {
        case invalidRequest
        case alreadyRunning
        case invocationFailed
        case invalidResponse
    }

    static func start(_ request: StartVpnRequest, at startURL: URL) async throws {
        if try await isRunning() { throw Failure.alreadyRunning }
        let adapted = try adaptedRequest(request)
        try FileManager.default.createDirectory(
            at: startURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JsonTool.encode(adapted).write(to: startURL, options: .atomic)
        // Persist exactly what is passed to the core; a failed write must not start it.
        try clearXrayRuntimeLogs(in: startURL.deletingLastPathComponent())
        _ = try await invoke(adapted.coreInvokeText!)
    }

    static func stop() async throws {
        _ = try await invoke(LibXrayInvokeRequest(method: .stopXray).toText())
    }

    static func isRunning() async throws -> Bool {
        let response = try await invoke(LibXrayInvokeRequest(method: .getXrayState).toText())
        let object = try JsonTool.decodeObject(from: Data(response.utf8))
        guard let data = object["data"] as? [String: Any],
              let running = data["running"] as? Bool
        else { throw Failure.invalidResponse }
        return running
    }

    private static func invoke(_ requestJson: String) async throws -> String {
        let response = try await LibXrayInvoker.invoke(requestJson)
        guard LibXrayInvokeResponse.fromText(response).isSuccess else {
            throw Failure.invocationFailed
        }
        return response
    }

    private static func adaptedRequest(_ request: StartVpnRequest) throws -> StartVpnRequest {
        guard let portText = request.socksPort,
              let port = Int(portText), (1...65535).contains(port),
              port != Int(request.metricsPort ?? ""),
              let text = request.coreInvokeText
        else { throw Failure.invalidRequest }
        var invoke = try LibXrayInvokeRequest.fromText(text)
        guard invoke.method == .runXray, let xrayJson = invoke.payload?.xrayJson else {
            throw Failure.invalidRequest
        }
        var config = try JsonTool.decodeObject(from: Data(xrayJson.utf8))
        guard var inbounds = config["inbounds"] as? [[String: Any]] else {
            throw Failure.invalidRequest
        }
        let managed = inbounds.indices.filter { inbounds[$0]["tag"] as? String == "tunIn" }
        guard managed.count == 1 else { throw Failure.invalidRequest }
        let index = managed[0]
        inbounds[index]["protocol"] = "socks"
        inbounds[index]["listen"] = ProxyHost
        inbounds[index]["port"] = port
        inbounds[index]["settings"] = ["auth": "noauth", "udp": true]
        // Keep tunIn's tag/sniffing, other inbounds and the complete Raw configuration.
        config["inbounds"] = inbounds
        invoke.payload?.xrayJson = String(decoding: try JsonTool.encodeObject(config), as: UTF8.self)
        var adapted = request
        adapted.coreInvokeText = try invoke.toText()
        return adapted
    }
}
#endif
