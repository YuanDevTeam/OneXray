import Darwin
import Foundation
import XCTest

final class ProxyHelperProtocolTests: XCTestCase {
    private func sockets() throws -> [Int32] {
        var pair: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else {
            throw ProxyHelperFailure.system(errno)
        }
        do {
            try ProxyHelperWire.prepareSocket(pair[0])
            try ProxyHelperWire.prepareSocket(pair[1])
            return pair
        } catch {
            Darwin.close(pair[0]); Darwin.close(pair[1]); throw error
        }
    }

    func testFramesPreserveJSONTextAndMessageBoundaries() throws {
        let pair = try sockets()
        defer { Darwin.close(pair[0]); Darwin.close(pair[1]) }
        let text = "{\"name\":\"节点\\nстрока\",\"url\":\"https://example.test/\"}"
        try ProxyHelperWire.write(ProxyHelperCommand(id: 7, method: "start", invokeText: text, proxyPort: 1080), to: pair[0])
        try ProxyHelperWire.write(ProxyHelperCommand(id: 8, method: "state"), to: pair[0])
        let start = try ProxyHelperWire.read(ProxyHelperCommand.self, from: pair[1])
        let state = try ProxyHelperWire.read(ProxyHelperCommand.self, from: pair[1])
        XCTAssertEqual(start.id, 7)
        XCTAssertEqual(start.invokeText, text)
        XCTAssertEqual(start.proxyPort, 1080)
        XCTAssertEqual(state.id, 8)
        XCTAssertEqual(state.method, "state")
        XCTAssertNil(state.invokeText)
    }

    func testOversizedFrameFailsBeforeWaitingForBody() throws {
        let pair = try sockets()
        defer { Darwin.close(pair[0]); Darwin.close(pair[1]) }
        var size = UInt32(ProxyHelperWire.maximumFrameBytes + 1).bigEndian
        XCTAssertEqual(withUnsafeBytes(of: &size) { Darwin.write(pair[0], $0.baseAddress, $0.count) }, 4)
        XCTAssertThrowsError(try ProxyHelperWire.read(ProxyHelperCommand.self, from: pair[1], timeout: 0.1)) { error in
            guard case ProxyHelperFailure.invalidReply = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testEOFUnblocksReader() throws {
        let pair = try sockets()
        defer { Darwin.close(pair[1]) }
        Darwin.close(pair[0])
        XCTAssertThrowsError(try ProxyHelperWire.read(ProxyHelperCommand.self, from: pair[1], timeout: 0.1)) { error in
            guard case ProxyHelperFailure.closed = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testUnresponsiveChildHasBoundedRead() throws {
        let pair = try sockets()
        defer { Darwin.close(pair[0]); Darwin.close(pair[1]) }
        let started = Date()
        XCTAssertThrowsError(try ProxyHelperWire.read(ProxyHelperCommand.self, from: pair[1], timeout: 0.03)) { error in
            guard case ProxyHelperFailure.timedOut = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testClosedPeerDoesNotTerminateWriterWithSIGPIPE() throws {
        let pair = try sockets()
        defer { Darwin.close(pair[0]) }
        Darwin.close(pair[1])
        XCTAssertThrowsError(try ProxyHelperWire.write(ProxyHelperCommand(id: 1, method: "state"), to: pair[0], timeout: 0.1))
    }
}

@main
enum ProxyHelperProtocolTestRunner {
    static func main() {
        let suite = ProxyHelperProtocolTests.defaultTestSuite
        suite.run()
        guard let run = suite.testRun, run.executionCount > 0, run.totalFailureCount == 0 else { exit(1) }
    }
}
