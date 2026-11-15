import Darwin
import Foundation
import LibXray

@main
enum ProxyHelperMain {
    private struct CoreReply: Decodable {
        let success: Bool
        let error: String
        let data: CoreState?
    }

    private struct CoreState: Decodable { let running: Bool? }

    private static func invoke(_ request: String) throws -> CoreReply {
        let result = request.withCString { CGoInvoke(UnsafeMutablePointer(mutating: $0)) }
        guard let result else { throw ProxyHelperFailure.invalidReply }
        defer { CGoFree(result) }
        let response = try JSONDecoder().decode(CoreReply.self, from: Data(String(cString: result).utf8))
        guard response.success else { throw ProxyHelperFailure.core(response.error) }
        return response
    }

    private static func state() throws -> Bool {
        try invoke(#"{"apiVersion":3,"method":"getXrayState"}"#).data?.running == true
    }

    private static func stop() {
        _ = try? invoke(#"{"apiVersion":3,"method":"stopXray"}"#)
    }

    static func main() {
        // Foundation Process duplicates the child end of an AF_UNIX socketpair
        // onto fd 0. It is full duplex and independent of Go's stdout/stderr.
        let channel = STDIN_FILENO
        var type: Int32 = 0
        var size = socklen_t(MemoryLayout.size(ofValue: type))
        guard getsockopt(channel, SOL_SOCKET, SO_TYPE, &type, &size) == 0,
              type == SOCK_STREAM else { exit(EXIT_FAILURE) }
        do { try ProxyHelperWire.prepareSocket(channel) }
        catch { exit(EXIT_FAILURE) }
        defer { stop() }
        while true {
            let command: ProxyHelperCommand
            do { command = try ProxyHelperWire.read(ProxyHelperCommand.self, from: channel, timeout: nil) }
            catch { return } // Parent EOF/crash owns the runtime lifetime.
            do {
                switch command.method {
                case "start":
                    guard let text = command.invokeText,
                          let port = command.proxyPort,
                          (1024...65535).contains(port),
                          let envelope = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                          envelope["method"] as? String == "runXray",
                          envelope["apiVersion"] as? Int == 3 else {
                        throw ProxyHelperFailure.invalidRequest
                    }
                    _ = try invoke(text)
                    let deadline = Date().addingTimeInterval(5)
                    while !ProxyHelperEndpoint.isListening(port: port) {
                        guard try state() else { throw ProxyHelperFailure.closed }
                        guard Date() < deadline else { throw ProxyHelperFailure.timedOut }
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    guard try state() else { throw ProxyHelperFailure.closed }
                    try ProxyHelperWire.write(ProxyHelperReply(id: command.id, success: true, running: true), to: channel)
                case "state":
                    try ProxyHelperWire.write(ProxyHelperReply(id: command.id, success: true, running: try state()), to: channel)
                case "stop":
                    _ = try invoke(#"{"apiVersion":3,"method":"stopXray"}"#)
                    try ProxyHelperWire.write(ProxyHelperReply(id: command.id, success: true, running: false), to: channel)
                    return
                default: throw ProxyHelperFailure.invalidRequest
                }
            } catch {
                let reply = ProxyHelperReply(id: command.id, success: false, running: (try? state()) == true, error: error.localizedDescription)
                try? ProxyHelperWire.write(reply, to: channel)
                if command.method == "start" { return }
            }
        }
    }
}
