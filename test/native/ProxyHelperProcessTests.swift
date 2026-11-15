import Darwin
import Foundation
import XCTest

final class ProxyHelperProcessTests: XCTestCase {
    private var executable: URL { URL(fileURLWithPath: CommandLine.arguments[1]) }

    private func port() throws -> Int {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ProxyHelperFailure.system(errno) }
        defer { Darwin.close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw ProxyHelperFailure.system(errno) }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
        }
        guard read == 0 else { throw ProxyHelperFailure.system(errno) }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private func request(port: Int, consoleLogs: Bool = false) throws -> String {
        let config: [String: Any] = [
            "log": ["loglevel": consoleLogs ? "debug" : "none"],
            "inbounds": [["listen": "127.0.0.1", "port": port, "protocol": "socks"]],
            "outbounds": [["protocol": "freedom"]],
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: config), as: UTF8.self)
        return String(decoding: try JSONSerialization.data(withJSONObject: [
            "apiVersion": 3, "method": "runXray", "payload": ["xrayJson": json],
        ]), as: UTF8.self)
    }

    func testActualFoundationProcessStartStatusStopAndReplacement() async throws {
        for _ in 0..<2 {
            let child = try DesktopProxyProcess(executable: executable, onExit: {})
            let port = try port()
            try await child.start(invokeText: request(port: port), port: port)
            XCTAssertTrue(child.isRunning)
            let running = try await child.readStatus()
            XCTAssertTrue(running)
            XCTAssertTrue(ProxyHelperEndpoint.isListening(port: port))
            try await child.stop()
            XCTAssertFalse(child.isRunning)
            XCTAssertFalse(ProxyHelperEndpoint.isListening(port: port))
        }
    }

    func testConcurrentReadsDoNotMixRepliesOrCoreConsoleOutput() async throws {
        let child = try DesktopProxyProcess(executable: executable, onExit: {})
        let port = try port()
        try await child.start(invokeText: request(port: port, consoleLogs: true), port: port)
        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 { group.addTask { try await child.readStatus() } }
            var results: [Bool] = []
            for try await running in group { results.append(running) }
            return results
        }
        XCTAssertEqual(results.count, 8)
        XCTAssertTrue(results.allSatisfy { $0 })
        try await child.stop()
        XCTAssertFalse(child.isRunning)
    }

    func testInvalidCoreRequestReturnsFailureAndReapsProcess() async throws {
        let child = try DesktopProxyProcess(executable: executable, onExit: {})
        let invoke = #"{"apiVersion":3,"method":"runXray","payload":{"xrayJson":"{\"outbounds\":[{\"protocol\":\"does-not-exist\"}]}"}}"#
        do {
            try await child.start(invokeText: invoke, port: port())
            XCTFail("Core startup must fail")
        } catch {
            guard case ProxyHelperFailure.core = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertFalse(child.isRunning)
        }
    }
}

@main
enum ProxyHelperProcessTestRunner {
    static func main() {
        guard CommandLine.arguments.count == 2 else { exit(1) }
        let suite = ProxyHelperProcessTests.defaultTestSuite
        suite.run()
        guard let run = suite.testRun, run.executionCount > 0, run.totalFailureCount == 0 else { exit(1) }
    }
}
