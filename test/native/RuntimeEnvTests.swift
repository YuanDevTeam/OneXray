import Foundation
import XCTest

final class RuntimeEnvTests: XCTestCase {
    private func withRuntimeDirectory(_ action: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: "../references/onexray-tests/native/fixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try action(root)
    }

    func testStopDuringStateQueryRetiresStartBeforeClearingLogs() throws {
        try withRuntimeDirectory { root in
            let access = root.appendingPathComponent("access.log")
            try Data("previous connection".utf8).write(to: access)
            let lifecycle = XrayRuntimeLifecycle()
            let generation = lifecycle.beginStart()
            let queried = expectation(description: "state query entered")
            let started = expectation(description: "retired start completes")
            let stopped = expectation(description: "stop completes")
            let releaseQuery = DispatchSemaphore(value: 0)
            defer { releaseQuery.signal() }
            lifecycle.start(generation: generation, operation: {
                queried.fulfill()
                XCTAssertEqual(releaseQuery.wait(timeout: .now() + 3), .success)
                // The provider checks again after the synchronous Core query.
                try lifecycle.check(generation)
                try clearXrayRuntimeLogs(in: root)
                XCTFail("A retired start must not invoke Core")
            }) { error in
                XCTAssertTrue(error is CancellationError)
                started.fulfill()
            }
            wait(for: [queried], timeout: 2)
            lifecycle.stop(operation: {}) { _ in stopped.fulfill() }
            // Stop invalidates immediately, without waiting for the Core queue.
            XCTAssertFalse(lifecycle.isCurrent(generation))
            releaseQuery.signal()
            wait(for: [started, stopped], timeout: 3)
            XCTAssertEqual(try String(contentsOf: access, encoding: .utf8), "previous connection")
        }
    }

    func testStopDrainsAdmittedRunBeforeReplacementAndOldCompletionCannotStopIt() {
        let lifecycle = XrayRuntimeLifecycle()
        let events = RuntimeLifecycleEvents()
        let first = lifecycle.beginStart()
        let running = expectation(description: "first Core entered run")
        let firstCompleted = expectation(description: "first start retired")
        let stopped = expectation(description: "stop drains first Core")
        let replacementCompleted = expectation(description: "replacement starts")
        let releaseRun = DispatchSemaphore(value: 0)
        defer { releaseRun.signal() }
        lifecycle.start(generation: first, operation: {
            events.append("run first")
            running.fulfill()
            XCTAssertEqual(releaseRun.wait(timeout: .now() + 3), .success)
            events.append("first run returned")
        }) { error in
            XCTAssertTrue(error is CancellationError)
            events.append("old completion cancelled")
            firstCompleted.fulfill()
        }
        wait(for: [running], timeout: 2)
        lifecycle.stop(operation: {
            events.append("stop first")
        }) { _ in stopped.fulfill() }
        let replacement = lifecycle.beginStart()
        lifecycle.start(generation: replacement, operation: {
            events.append("run replacement")
        }) { error in
            XCTAssertNil(error)
            replacementCompleted.fulfill()
        }
        releaseRun.signal()
        wait(for: [firstCompleted, stopped, replacementCompleted], timeout: 3)
        XCTAssertEqual(events.values, ["run first", "first run returned", "old completion cancelled", "stop first", "run replacement"])
        XCTAssertTrue(lifecycle.isCurrent(replacement))
        XCTAssertThrowsError(try lifecycle.check(first))
    }

    func testStartPreparedBeforeStopCannotRunAfterNewGeneration() {
        let lifecycle = XrayRuntimeLifecycle()
        let events = RuntimeLifecycleEvents()
        let old = lifecycle.beginStart()
        let stopped = expectation(description: "stop completes")
        let replacementCompleted = expectation(description: "replacement completes")
        let oldCompleted = expectation(description: "late preparation is rejected")
        lifecycle.stop(operation: { events.append("stop") }) { _ in stopped.fulfill() }
        let replacement = lifecycle.beginStart()
        lifecycle.start(generation: replacement, operation: { events.append("replacement") }) { error in
            XCTAssertNil(error)
            replacementCompleted.fulfill()
        }
        lifecycle.start(generation: old, operation: {
            XCTFail("Late preparation must not clear logs or invoke Core")
        }) { error in
            XCTAssertTrue(error is CancellationError)
            oldCompleted.fulfill()
        }
        wait(for: [stopped, replacementCompleted, oldCompleted], timeout: 3)
        XCTAssertEqual(events.values, ["stop", "replacement"])
        XCTAssertTrue(lifecycle.isCurrent(replacement))
    }

    func testClearsOnlyManagedLogsAndAllowsMissingFiles() throws {
        try withRuntimeDirectory { root in
            let run = root.appendingPathComponent("run")
            try clearXrayRuntimeLogs(in: run)
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: false)
            for name in ["access.log", "error.log", "start.json", "export.log"] {
                try Data(name.utf8).write(to: run.appendingPathComponent(name))
            }
            try clearXrayRuntimeLogs(in: run)
            try clearXrayRuntimeLogs(in: run)
            for name in ["access.log", "error.log"] {
                XCTAssertFalse(FileManager.default.fileExists(atPath: run.appendingPathComponent(name).path))
            }
            for name in ["start.json", "export.log"] {
                XCTAssertEqual(try String(contentsOf: run.appendingPathComponent(name), encoding: .utf8), name)
            }
        }
    }

    func testRejectsLinkedOrDirectoryLogsBeforeClearingEither() throws {
        for link in [false, true] {
            try withRuntimeDirectory { root in
                let access = root.appendingPathComponent("access.log")
                let error = root.appendingPathComponent("error.log")
                let target = root.appendingPathComponent("outside.log")
                try Data("old access".utf8).write(to: access)
                try Data("outside".utf8).write(to: target)
                if link {
                    try FileManager.default.createSymbolicLink(at: error, withDestinationURL: target)
                } else {
                    try FileManager.default.createDirectory(at: error, withIntermediateDirectories: false)
                }
                XCTAssertThrowsError(try clearXrayRuntimeLogs(in: root))
                XCTAssertEqual(try String(contentsOf: access, encoding: .utf8), "old access")
                XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "outside")
            }
        }
    }

    func testRejectsLinkedRuntimeDirectory() throws {
        try withRuntimeDirectory { root in
            let run = root.appendingPathComponent("run")
            try FileManager.default.createSymbolicLink(at: run, withDestinationURL: root)
            let access = root.appendingPathComponent("access.log")
            try Data("old".utf8).write(to: access)
            XCTAssertThrowsError(try clearXrayRuntimeLogs(in: run))
            XCTAssertEqual(try String(contentsOf: access, encoding: .utf8), "old")
        }
    }

    func testRemovalFailurePropagatesAndPreservesExistingLog() throws {
        try withRuntimeDirectory { root in
            let access = root.appendingPathComponent("access.log")
            try Data("old".utf8).write(to: access)
            XCTAssertThrowsError(try clearXrayRuntimeLogs(in: root, fileManager: FailingLogRemoval()))
            XCTAssertEqual(try String(contentsOf: access, encoding: .utf8), "old")
        }
    }

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

private final class RuntimeLifecycleEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        stored.append(value)
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

private final class FailingLogRemoval: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws { throw CocoaError(.fileWriteNoPermission) }
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
