import Foundation
import XCTest

final class StartRequestStorageTests: XCTestCase {
    private func withContainer(_ action: (URL) throws -> Void) throws {
        let container = URL(fileURLWithPath: "../references/onexray-tests/native/fixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        try action(container)
    }

    func testMissingAndExplicitTunnelModesRetainTheOriginalInputPath() throws {
        for mode: String? in [nil, "tun"] {
            let kind = try StartRequestKind(captureMode: mode)
            XCTAssertEqual(kind, .tunnel)
            XCTAssertEqual(kind.relativePath, "run/start.json")
            XCTAssertNoThrow(try kind.requireTunnel())
        }
    }

    func testProxyIsRejectedByTunnelAdmission() throws {
        let kind = try StartRequestKind(captureMode: "proxy")
        XCTAssertEqual(kind.relativePath, "run/proxy-start.json")
        XCTAssertThrowsError(try kind.requireTunnel()) { error in
            guard case StartRequestKindError.notTunnel = error else {
                return XCTFail("Unexpected rejection: \(error)")
            }
        }
    }

    func testProxyPublicationNeverChangesTheSavedTunnelBytes() throws {
        try withContainer { container in
            let savedTunnel = Data("{\n  \"coreInvokeText\": \"last TUN input\"\n}\n".utf8)
            try StartRequestKind.tunnel.writeSnapshot(savedTunnel, in: container)
            for index in 1...2 {
                let proxy = Data("{\"captureMode\":\"proxy\",\"session\":\(index)}".utf8)
                try StartRequestKind.proxy.writeSnapshot(proxy, in: container)
                XCTAssertEqual(try Data(contentsOf: container.appendingPathComponent(StartModelFile)), savedTunnel)
                XCTAssertEqual(try Data(contentsOf: container.appendingPathComponent(ProxyStartModelFile)), proxy)
            }
        }
    }

    func testTunnelPublicationDoesNotChangeTheProxySnapshot() throws {
        try withContainer { container in
            let proxy = Data("{\"captureMode\":\"proxy\"}".utf8)
            let tunnel = Data("{\"captureMode\":\"tun\"}".utf8)
            try StartRequestKind.proxy.writeSnapshot(proxy, in: container)
            try StartRequestKind.tunnel.writeSnapshot(tunnel, in: container)
            XCTAssertEqual(try Data(contentsOf: container.appendingPathComponent(ProxyStartModelFile)), proxy)
            XCTAssertEqual(try Data(contentsOf: container.appendingPathComponent(StartModelFile)), tunnel)
        }
    }

    func testUnknownModeCannotPublishOrChangeEitherSnapshot() throws {
        try withContainer { container in
            let saved = Data("unchanged".utf8)
            try StartRequestKind.tunnel.writeSnapshot(saved, in: container)
            try StartRequestKind.proxy.writeSnapshot(saved, in: container)
            for mode in ["", "TUN", "Proxy", "unknown"] {
                XCTAssertThrowsError(try StartRequestKind(captureMode: mode).writeSnapshot(Data(), in: container)) { error in
                    guard case StartRequestKindError.unsupportedMode = error else {
                        return XCTFail("Unexpected rejection: \(error)")
                    }
                }
            }
            for path in [StartModelFile, ProxyStartModelFile] {
                XCTAssertEqual(try Data(contentsOf: container.appendingPathComponent(path)), saved)
            }
        }
    }

    func testExistingMisplacedCacheIsNotMigratedOrRewritten() throws {
        try withContainer { container in
            let oldCache = Data("{\"captureMode\":\"proxy\",\"session\":\"old\"}".utf8)
            let savedFile = container.appendingPathComponent(StartModelFile)
            try FileManager.default.createDirectory(at: savedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try oldCache.write(to: savedFile)
            try StartRequestKind.proxy.writeSnapshot(Data("new proxy snapshot".utf8), in: container)
            XCTAssertEqual(try Data(contentsOf: savedFile), oldCache)
        }
    }
}
