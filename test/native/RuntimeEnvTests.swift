import Foundation
import XCTest

final class RuntimeEnvTests: XCTestCase {
    func testPreservesCoreEnvironmentWhenReplacingNativeDescriptor() throws {
        let original: [String: Any] = [
            "xray.location.asset": "/assets",
            "xray.location.cert": "/certs",
            "xray.tun.fd": "4",
            "provider.future-option": "保留",
            "XRAY_CUSTOM": "enabled",
        ]
        let updated = try xrayRuntimeEnvWithTunFd(original, fd: 37)
        XCTAssertEqual(updated["xray.tun.fd"] as? String, "37")
        for (key, value) in original where key != "xray.tun.fd" {
            XCTAssertEqual(updated[key] as? String, value as? String)
        }
        XCTAssertEqual(Set(updated.keys), Set(original.keys))
        XCTAssertEqual(original["xray.tun.fd"] as? String, "4")
    }

    func testSystemExtensionResourceOverridesKeepOtherEnvironmentEntries() throws {
        let original: [String: Any] = [
            "xray.location.asset": "/app/assets",
            "xray.location.cert": "/app/certs",
            "provider.future-option": "enabled",
        ]
        var updated = try xrayRuntimeEnvWithTunFd(original, fd: 11)
        // The SE caller owns these two paths; it must not rebuild the env model.
        updated["xray.location.asset"] = "/extension/dat"
        updated["xray.location.cert"] = "/extension/dat"
        XCTAssertEqual(updated["provider.future-option"] as? String, "enabled")
        XCTAssertEqual(updated["xray.tun.fd"] as? String, "11")
        XCTAssertEqual(updated["xray.location.asset"] as? String, "/extension/dat")
        XCTAssertEqual(updated["xray.location.cert"] as? String, "/extension/dat")
        XCTAssertEqual(original["xray.location.asset"] as? String, "/app/assets")
    }

    func testMissingEnvironmentCreatesOnlyDescriptorAndInvalidShapeFails() throws {
        for object: Any? in [nil, NSNull()] {
            let updated = try xrayRuntimeEnvWithTunFd(object, fd: 9)
            XCTAssertEqual(updated as NSDictionary, ["xray.tun.fd": "9"] as NSDictionary)
        }
        XCTAssertThrowsError(try xrayRuntimeEnvWithTunFd(["invalid"], fd: 9))
        XCTAssertThrowsError(try xrayRuntimeEnvWithTunFd("invalid", fd: 9))
    }
}

@main
enum RuntimeEnvTestRunner {
    static func main() {
        let suite = RuntimeEnvTests.defaultTestSuite
        suite.run()
        guard let result = suite.testRun, result.executionCount > 0,
              result.totalFailureCount == 0 else { exit(1) }
    }
}
