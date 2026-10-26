import Foundation
import XCTest

final class AppleWidgetTests: XCTestCase {
    private func temporaryStore() throws -> AppleWidgetStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppleWidgetStore(directory: directory)
    }

    func testStatusAndLanguageHaveIndependentAtomicFiles() throws {
        let store = try temporaryStore()
        let now = Date()
        XCTAssertNil(store.snapshot())
        XCTAssertEqual(store.languageCode(), "en")
        XCTAssertTrue(try store.writeStatus(.connected, at: now))
        XCTAssertTrue(try store.writeLanguage("zh_Hant"))
        XCTAssertEqual(store.snapshot(), AppleWidgetSnapshot(status: .connected, observedAt: now))
        XCTAssertEqual(store.languageCode(), "zh-Hant")
        XCTAssertTrue(try store.writeStatus(.disconnected, at: now.addingTimeInterval(1)))
        XCTAssertEqual(store.languageCode(), "zh-Hant")
        XCTAssertFalse(try store.writeLanguage("zh-Hant"))
        XCTAssertFalse(try store.writeStatus(.disconnected, at: now.addingTimeInterval(2)))
        XCTAssertTrue(try store.writeStatus(.disconnected, at: now.addingTimeInterval(65)))
    }

    func testUnconfirmedAndExpiredStatusNeverClaimsConnected() {
        let now = Date()
        let status = AppleWidgetSnapshot(status: .connected, observedAt: now)
        XCTAssertEqual(status.displayedStatus(at: now), .connected)
        XCTAssertEqual(status.displayedStatus(at: now.addingTimeInterval(AppleWidgetSnapshot.maximumAge)), .unknown)
        XCTAssertEqual(status.displayedStatus(at: now.addingTimeInterval(-61)), .unknown)
        XCTAssertEqual(AppleWidgetSnapshot(status: .unknown, observedAt: now).displayedStatus(at: now), .unknown)
    }

    func testMalformedLargeAndNewerSchemaSnapshotsAreUnavailable() throws {
        let store = try temporaryStore()
        let status = store.directory.appendingPathComponent("status.json")
        for data in [Data("broken".utf8), Data(repeating: 32, count: 4097),
                     Data("{\"version\":2,\"status\":\"connected\",\"observedAt\":0}".utf8),
                     Data("{\"version\":1,\"status\":\"future-status\",\"observedAt\":0}".utf8)] {
            try data.write(to: status)
            XCTAssertNil(store.snapshot())
        }
    }

    func testLanguagesMatchTheAppCodesAndUnsupportedFallsBackToEnglish() {
        for (input, expected) in [("en", "en"), ("zh", "zh-Hans"), ("zh-Hans", "zh-Hans"),
                                  ("zh_Hant", "zh-Hant"), ("ru", "ru"), ("fa", "fa"), ("de", "en")] {
            XCTAssertEqual(AppleWidgetLanguage.normalized(input), expected)
        }
    }

    func testActionInboxPreservesEarlyIntentAndConsumesItOnce() {
        MainActor.assumeIsolated {
            let inbox = AppleWidgetActionInbox()
            XCTAssertNil(inbox.takeAction())
            inbox.submit(.startVpn)
            XCTAssertEqual(inbox.takeAction(), "startVpn")
            XCTAssertNil(inbox.takeAction())
            inbox.submit(.startVpn)
            inbox.submit(.stopVpn)
            XCTAssertEqual(inbox.takeAction(), "stopVpn")
            XCTAssertNil(inbox.takeAction())
        }
    }

    @MainActor
    func testStopDrainsPreparationAndRejectsEveryOldStart() async throws {
        let admission = AppleVpnStartAdmission()
        let first = admission.begin()
        let second = admission.begin()
        XCTAssertThrowsError(try admission.check(first))
        try admission.check(second)
        admission.invalidate()
        var stopped = false
        let stopping = Task { @MainActor in
            await admission.waitForPreparation()
            stopped = true
        }
        await Task.yield()
        XCTAssertFalse(stopped)
        XCTAssertThrowsError(try admission.check(first))
        XCTAssertThrowsError(try admission.check(second))
        admission.finishPreparation(first)
        await Task.yield()
        XCTAssertFalse(stopped, "The second profile write is still in progress.")
        admission.finishPreparation(second)
        await stopping.value
        XCTAssertTrue(stopped)
        let retry = admission.begin()
        try admission.check(retry)
        XCTAssertThrowsError(try admission.check(second))
        admission.finishPreparation(second)
        try admission.check(retry)
        admission.finishPreparation(retry)
    }

    @MainActor
    func testStopDoesNotWaitForSubmittedStartStatusConfirmation() async throws {
        let admission = AppleVpnStartAdmission()
        let submitted = admission.begin()
        try admission.check(submitted)
        admission.finishPreparation(submitted)
        // The original request may still await a native connected callback.
        admission.invalidate()
        await admission.waitForPreparation()
        XCTAssertThrowsError(try admission.check(submitted))
        let retry = admission.begin()
        admission.finishPreparation(submitted)
        try admission.check(retry)
        admission.finishPreparation(retry)
    }
}

@main
enum AppleWidgetTestRunner {
    static func main() {
        let suite = AppleWidgetTests.defaultTestSuite
        suite.run()
        guard let result = suite.testRun, result.executionCount > 0,
              result.totalFailureCount == 0 else { exit(1) }
    }
}
