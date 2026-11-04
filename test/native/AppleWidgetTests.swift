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

    func testActionInboxMergesNativeEnvelopeAndConsumesItOnce() throws {
        try MainActor.assumeIsolated {
            let inbox = AppleWidgetActionInbox()
            XCTAssertNil(inbox.takeAction())
            inbox.recordBackgroundAction()
            inbox.recordNativeStop(invalidatedPreparations: ["second", "first"])
            inbox.recordNativeStop(invalidatedPreparations: ["first"])
            inbox.requestOpenConnect()
            let text = try XCTUnwrap(inbox.takeAction())
            let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            XCTAssertEqual(envelope["version"] as? Int, 1)
            XCTAssertEqual(envelope["suppressAutoConnect"] as? Bool, true)
            XCTAssertEqual(envelope["openConnect"] as? Bool, true)
            XCTAssertEqual(envelope["invalidatedPreparations"] as? [String], ["first", "second"])
            XCTAssertNil(inbox.takeAction())
            inbox.recordBackgroundAction()
            let next = try XCTUnwrap(inbox.takeAction())
            let reset = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(next.utf8)) as? [String: Any])
            XCTAssertEqual(reset["openConnect"] as? Bool, false)
            XCTAssertEqual(reset["invalidatedPreparations"] as? [String], [])
            XCTAssertNil(inbox.takeAction())
        }
    }

    @MainActor
    func testDartPreparationIsConsumedOnceAndStopRetiresItWithoutDrainingDartWork() async throws {
        let admission = AppleVpnStartAdmission()
        let first = try admission.beginDartPreparation()
        let second = try admission.beginDartPreparation()
        XCTAssertTrue(admission.hasCurrentDartPreparation)
        XCTAssertTrue(admission.consumeDartPreparation(token: first))
        XCTAssertFalse(admission.consumeDartPreparation(token: first))
        XCTAssertEqual(admission.invalidate(), [second])
        await admission.waitForPreparation()
        XCTAssertFalse(admission.isCurrent(second))
        XCTAssertFalse(admission.consumeDartPreparation(token: second))
        XCTAssertFalse(admission.hasCurrentDartPreparation)
        admission.finishDartPreparation(token: second)
        let retry = try admission.beginDartPreparation()
        XCTAssertTrue(admission.consumeDartPreparation(token: retry))
        let native = admission.begin()
        try admission.check(native)
        admission.finishPreparation(native)
    }

    @MainActor
    func testMaintenanceMarkerPersistsAcrossAdmissionInstancesOutsideRuntimeDirectory() throws {
        let root = URL(fileURLWithPath: "../references/onexray-tests/native/widget-admission", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let run = root.appendingPathComponent("run", isDirectory: true)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: false)
        let marker = root.appendingPathComponent("vpn-start.blocked")
        let first = AppleVpnStartAdmission(startBlockedURL: marker)
        try first.requireStartAllowed()
        try first.setStartBlocked(true)
        try FileManager.default.removeItem(at: run)
        let reopened = AppleVpnStartAdmission(startBlockedURL: marker)
        XCTAssertThrowsError(try reopened.requireStartAllowed())
        XCTAssertThrowsError(try reopened.beginDartPreparation())
        reopened.invalidate()
        try reopened.setStartBlocked(false)
        try reopened.setStartBlocked(false)
        try reopened.requireStartAllowed()
        XCTAssertTrue(reopened.isCurrent(try reopened.beginDartPreparation()))
    }

    @MainActor
    func testInvalidMaintenanceStorageCannotAdmitStartOrDeleteAnOccupiedDirectory() throws {
        let root = URL(fileURLWithPath: "../references/onexray-tests/native/widget-admission", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let occupied = root.appendingPathComponent("vpn-start.blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: false)
        let admission = AppleVpnStartAdmission(startBlockedURL: occupied)
        XCTAssertThrowsError(try admission.beginDartPreparation())
        XCTAssertThrowsError(try admission.setStartBlocked(false))
        XCTAssertTrue(FileManager.default.fileExists(atPath: occupied.path))
        let regularParent = root.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: regularParent)
        let unreadable = AppleVpnStartAdmission(startBlockedURL: regularParent.appendingPathComponent("marker"))
        XCTAssertThrowsError(try unreadable.beginDartPreparation())
        XCTAssertThrowsError(try unreadable.setStartBlocked(true))
    }

    @MainActor
    func testExplicitStartIsIdempotentForConnectedAndInProgressStates() async throws {
        defer { _ = AppleWidgetActionInbox.shared.takeAction() }
        for status in [AppleWidgetStatus.connected, .connecting, .disconnecting] {
            let actions = AppleWidgetVpnActions(readStatus: { status }, start: {
                XCTFail("An existing native run must not be restarted")
                return .completed
            }, stop: {
                XCTFail("Explicit Start must not become Stop")
                return .completed
            })
            let result = try await actions.perform(.start)
            XCTAssertEqual(result, status == .connected ? .completed : .inProgress)
        }
    }

    @MainActor
    func testToggleStopsConnectedOrPreparingAndDoesNotQueueWhileDisconnecting() async throws {
        defer { _ = AppleWidgetActionInbox.shared.takeAction() }
        for status in [AppleWidgetStatus.connected, .connecting, .disconnecting] {
            var stops = 0
            let actions = AppleWidgetVpnActions(readStatus: { status }, start: {
                XCTFail("A native transition must not enqueue another start")
                return .completed
            }, stop: {
                stops += 1
                return .completed
            })
            let result = try await actions.perform(.toggle)
            XCTAssertEqual(stops, status == .disconnecting ? 0 : 1)
            XCTAssertEqual(result, status == .disconnecting ? .inProgress : .completed)
        }
    }

    @MainActor
    func testToggleRetiresDartPreparationBeforeNativeSubmission() async throws {
        defer { _ = AppleWidgetActionInbox.shared.takeAction() }
        let admission = AppleVpnStartAdmission()
        let token = try admission.beginDartPreparation()
        let actions = AppleWidgetVpnActions(readStatus: {
            admission.hasCurrentDartPreparation ? .connecting : .disconnected
        }, start: {
            XCTFail("Toggle must cancel the pending Dart preparation")
            return .completed
        }, stop: {
            let invalidated = admission.invalidate()
            AppleWidgetActionInbox.shared.recordNativeStop(invalidatedPreparations: invalidated)
            return .completed
        })
        let result = try await actions.perform(.toggle)
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(admission.consumeDartPreparation(token: token))
        let text = try XCTUnwrap(AppleWidgetActionInbox.shared.takeAction())
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(envelope["invalidatedPreparations"] as? [String], [token])
    }

    @MainActor
    func testUnknownOrUnreadableNativeStatusNeverStarts() async throws {
        defer { _ = AppleWidgetActionInbox.shared.takeAction() }
        for command in [AppleWidgetCommand.start, .toggle] {
            let actions = AppleWidgetVpnActions(readStatus: { .unknown }, start: {
                XCTFail("Unknown status must not start Core")
                return .completed
            }, stop: { .completed })
            do {
                _ = try await actions.perform(command)
                XCTFail("Unknown native status must fail")
            } catch {
                XCTAssertTrue(error is AppleWidgetVpnActionError)
            }
        }
        let denied = NSError(domain: "NE-test", code: 403)
        let actions = AppleWidgetVpnActions(readStatus: { throw denied }, start: {
            XCTFail("A failed native query must not start Core")
            return .completed
        }, stop: { .completed })
        do {
            _ = try await actions.perform(.start)
            XCTFail("The native error must propagate")
        } catch {
            XCTAssertEqual((error as NSError).domain, "NE-test")
            XCTAssertEqual((error as NSError).code, 403)
        }
    }

    @MainActor
    func testStopRetiresStartOrToggleWaitingForNativeStatusIncludingLateErrors() async throws {
        defer { _ = AppleWidgetActionInbox.shared.takeAction() }
        for command in [AppleWidgetCommand.start, .toggle] {
            for lateError in [false, true] {
                let admission = AppleVpnStartAdmission()
                let (queries, enteredQuery) = AsyncStream<Void>.makeStream()
                var reply: CheckedContinuation<AppleWidgetStatus, Error>?
                let actions = AppleWidgetVpnActions(readStatus: {
                    try await withCheckedThrowingContinuation { continuation in
                        reply = continuation
                        enteredQuery.yield(())
                    }
                }, start: {
                    XCTFail("A status query issued before Stop must not admit a new start")
                    return .completed
                }, stop: {
                    XCTFail("An old Toggle result must not stop a later run")
                    return .completed
                }, commandGeneration: { admission.invalidationGeneration })
                let pending = Task { @MainActor in try await actions.perform(command) }
                var iterator = queries.makeAsyncIterator()
                _ = await iterator.next()
                admission.invalidate()
                if lateError {
                    reply?.resume(throwing: NSError(domain: "old-status-query", code: 1))
                } else {
                    reply?.resume(returning: .disconnected)
                }
                let result = try await pending.value
                XCTAssertEqual(result, .inProgress)
                enteredQuery.finish()
            }
        }
    }

    @MainActor
    func testSecondToggleQueryStopsTheStartAdmittedByFirstToggle() async throws {
        defer { _ = AppleWidgetActionInbox.shared.takeAction() }
        let admission = AppleVpnStartAdmission()
        let (queries, enteredQuery) = AsyncStream<Int>.makeStream()
        var replies: [CheckedContinuation<Void, Never>] = []
        var starting = false
        var starts = 0
        var stops = 0
        let actions = AppleWidgetVpnActions(readStatus: {
            await withCheckedContinuation { continuation in
                replies.append(continuation)
                enteredQuery.yield(replies.count)
            }
            return starting ? .connecting : .disconnected
        }, start: {
            starts += 1
            let generation = admission.begin()
            admission.finishPreparation(generation)
            starting = true
            return .inProgress
        }, stop: {
            stops += 1
            admission.invalidate()
            starting = false
            return .completed
        }, commandGeneration: { admission.invalidationGeneration })
        var iterator = queries.makeAsyncIterator()
        let first = Task { @MainActor in try await actions.perform(.toggle) }
        _ = await iterator.next()
        let second = Task { @MainActor in try await actions.perform(.toggle) }
        _ = await iterator.next()
        replies[0].resume()
        let firstResult = try await first.value
        XCTAssertEqual(firstResult, .inProgress)
        XCTAssertEqual(admission.generation, 1)
        XCTAssertEqual(admission.invalidationGeneration, 0)
        replies[1].resume()
        let secondResult = try await second.value
        XCTAssertEqual(secondResult, .completed)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, 1)
        XCTAssertFalse(starting)
        XCTAssertEqual(admission.invalidationGeneration, admission.generation)
        enteredQuery.finish()
    }

    @MainActor
    func testStopDoesNotReadStartAvailabilityAndMissingStartRequestsForeground() async throws {
        defer { _ = AppleWidgetActionInbox.shared.takeAction() }
        let stopOnly = AppleWidgetVpnActions(readStatus: {
            XCTFail("Stop must not require a runtime input or a start query")
            throw CocoaError(.fileNoSuchFile)
        }, start: {
            XCTFail("Stop must not prepare input")
            return .needsForeground
        }, stop: { .completed })
        let stopped = try await stopOnly.perform(.stop)
        XCTAssertEqual(stopped, .completed)
        let missing = AppleWidgetVpnActions(readStatus: { .disconnected }, start: { .needsForeground }, stop: { .completed })
        let result = try await missing.perform(.start)
        XCTAssertEqual(result, .needsForeground)
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
