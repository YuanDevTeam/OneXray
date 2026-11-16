import Foundation
import XCTest

@MainActor
private final class RemovalSystem {
    struct Profile: Equatable {
        let id: Int
        let owner: String?
    }
    enum Failure: Error { case denied, stopFailed, preferencesFailed }
    var profiles = [Profile(id: 1, owner: "own"), Profile(id: 2, owner: "other"), Profile(id: 3, owner: "own")]
    var events: [String] = []
    var failStop = false
    var failRemove = false
    var failLoad = false
    var failDeactivate = false
    var ignoreRemove = false
    var outcome = AppleVpnRemovalOutcome.removed
    var didClearCachedProfile = false

    func run(_ removal: AppleVpnRemoval, prepare: @MainActor () async throws -> Void = {}) async throws -> AppleVpnRemovalOutcome {
        try await removal.remove(
            providerIdentifier: "own",
            invalidateStarts: { self.events.append("invalidate") },
            prepare: prepare,
            load: {
                self.events.append("load")
                if self.failLoad { throw Failure.preferencesFailed }
                return self.profiles
            },
            identifier: { $0.owner },
            stop: {
                self.events.append("stop:\($0.id)")
                if self.failStop { throw Failure.stopFailed }
            },
            remove: { profile in
                self.events.append("remove:\(profile.id)")
                if self.failRemove { throw Failure.denied }
                if !self.ignoreRemove { self.profiles.removeAll { $0 == profile } }
            },
            profilesRemoved: {
                self.events.append("clear")
                self.didClearCachedProfile = true
            },
            deactivate: {
                self.events.append("deactivate")
                if self.failDeactivate { throw Failure.denied }
                return self.outcome
            }
        )
    }
}

final class AppleVpnRemovalTests: XCTestCase {
    @MainActor
    func testAllOwnedDuplicatesStopBeforeDeletionAndForeignProfilesSurvive() async throws {
        let system = RemovalSystem()
        let removal = AppleVpnRemoval()
        let result = try await system.run(removal)
        XCTAssertEqual(result, .removed)
        XCTAssertEqual(system.events, ["invalidate", "load", "stop:1", "stop:3", "remove:1", "remove:3", "load", "clear", "deactivate"])
        XCTAssertEqual(system.profiles.map(\.id), [2])
        XCTAssertFalse(removal.isRemoving)
        XCTAssertNoThrow(try removal.requireMutationAllowed())
    }

    @MainActor
    func testAbsentProfilesStillRemoveSystemExtensionAndReportRestart() async throws {
        let system = RemovalSystem()
        system.profiles = []
        system.outcome = .restartRequired
        let result = try await system.run(AppleVpnRemoval())
        XCTAssertEqual(result, .restartRequired)
        XCTAssertEqual(system.events, ["invalidate", "load", "load", "clear", "deactivate"])
    }

    @MainActor
    func testStopFailurePreventsEveryDeletionAndExtensionDeactivation() async {
        let system = RemovalSystem()
        system.failStop = true
        do {
            _ = try await system.run(AppleVpnRemoval())
            XCTFail("Unconfirmed stop must fail removal")
        } catch {}
        XCTAssertEqual(system.profiles.count, 3)
        XCTAssertFalse(system.events.contains(where: { $0.hasPrefix("remove:") }))
        XCTAssertFalse(system.events.contains("deactivate"))
        XCTAssertFalse(system.didClearCachedProfile)
    }

    @MainActor
    func testPreferenceLoadAndDeleteErrorsPropagateAndAllowRetry() async throws {
        for loading in [true, false] {
            let system = RemovalSystem()
            let removal = AppleVpnRemoval()
            system.failLoad = loading
            system.failRemove = !loading
            do {
                _ = try await system.run(removal)
                XCTFail("A system failure must fail removal")
            } catch {}
            XCTAssertFalse(system.didClearCachedProfile)
            XCTAssertFalse(system.events.contains("deactivate"))
            XCTAssertFalse(removal.isRemoving)
            system.failLoad = false
            system.failRemove = false
            let result = try await system.run(removal)
            XCTAssertEqual(result, .removed)
        }
    }

    @MainActor
    func testProfilesStillPresentAfterSystemReplyAreNotReportedRemoved() async {
        let system = RemovalSystem()
        system.ignoreRemove = true
        do {
            _ = try await system.run(AppleVpnRemoval())
            XCTFail("Profiles must actually disappear")
        } catch {
            XCTAssertTrue(error is AppleVpnRemovalError)
        }
        XCTAssertFalse(system.didClearCachedProfile)
        XCTAssertFalse(system.events.contains("deactivate"))
    }

    @MainActor
    func testExtensionDenialPropagatesAfterProfilesWereRemoved() async {
        let system = RemovalSystem()
        system.failDeactivate = true
        do {
            _ = try await system.run(AppleVpnRemoval())
            XCTFail("Extension denial must fail the whole operation")
        } catch {}
        XCTAssertEqual(system.profiles.map(\.id), [2])
        XCTAssertTrue(system.didClearCachedProfile)
    }

    @MainActor
    func testRemovalBlocksNewMutationsAndDrainsOldProfileWrites() async throws {
        let system = RemovalSystem()
        let removal = AppleVpnRemoval()
        let pendingWrite = try removal.beginMutation()
        let removalStarted = expectation(description: "Removal starts")
        let task = Task {
            removalStarted.fulfill()
            return try await system.run(removal)
        }
        await fulfillment(of: [removalStarted], timeout: 2)
        XCTAssertTrue(removal.isRemoving)
        XCTAssertEqual(system.events, ["invalidate"])
        XCTAssertThrowsError(try removal.beginMutation())
        do {
            _ = try await system.run(removal)
            XCTFail("Concurrent removal must fail")
        } catch {}
        XCTAssertTrue(removal.isRemoving)
        // An already admitted permission request may finish saving its profile.
        // The removal must include it when the pending mutation is drained.
        system.profiles.append(.init(id: 4, owner: "own"))
        removal.finishMutation(pendingWrite)
        let result = try await task.value
        XCTAssertEqual(result, .removed)
        XCTAssertTrue(system.events.contains("remove:4"))
        let nextWrite = try removal.beginMutation()
        removal.finishMutation(nextWrite)
    }

    @MainActor
    func testPendingStopIsDrainedThenEveryProfileIsIndependentlyConfirmed() async throws {
        let system = RemovalSystem()
        let removal = AppleVpnRemoval()
        let waiting = expectation(description: "Removal waits for the earlier stop")
        var finishStop: CheckedContinuation<Bool, Never>?
        let pendingStop = Task {
            await withCheckedContinuation { finishStop = $0 }
        }
        let task = Task {
            try await system.run(removal, prepare: {
                waiting.fulfill()
                // A stale stop result must not replace checking all profiles.
                _ = await pendingStop.value
            })
        }
        await fulfillment(of: [waiting], timeout: 2)
        XCTAssertTrue(removal.isRemoving)
        XCTAssertEqual(system.events, ["invalidate"])
        finishStop?.resume(returning: false)
        let result = try await task.value
        XCTAssertEqual(result, .removed)
        XCTAssertEqual(system.events.filter { $0.hasPrefix("stop:") }, ["stop:1", "stop:3"])
        XCTAssertFalse(removal.isRemoving)
    }
}

@main
enum RemovalTests {
    static func main() {
        let suite = AppleVpnRemovalTests.defaultTestSuite
        suite.run()
        guard let result = suite.testRun, result.executionCount > 0,
              result.totalFailureCount == 0 else { exit(1) }
    }
}
