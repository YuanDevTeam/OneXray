import Foundation
import XCTest

// Link the production file without submitting requests to the operating system.
func packetTunnelId() -> String { "net.yuandev.onexray.test.tun" }
func YGLog(_ message: String) {}

final class SystemExtensionActivationTests: XCTestCase {
    @MainActor
    func testMissingExtensionCanBeActivatedAgainAfterSuccess() async {
        let activation = SystemExtensionActivation()
        let first = await activation.request(query: { .notInstalled }) { .installed }
        XCTAssertEqual(first, .installed)

        // A later permission check finds the extension missing; the new request
        // must reach the OS, where it may need approval again.
        let retry = await activation.request(query: { .notInstalled }) { .waitForApproval }
        XCTAssertEqual(retry, .waitForApproval)
        let failed = await activation.request(query: { .notInstalled }) { .notInstalled }
        XCTAssertEqual(failed, .notInstalled)
        let approved = await activation.request(query: { .notInstalled }) { .installed }
        XCTAssertEqual(approved, .installed)
    }

    @MainActor
    func testPendingApprovalIsResubmittedUntilInstalled() async {
        let activation = SystemExtensionActivation()
        var state = SystemExtensionState.notInstalled
        var submissions = 0
        let query = { @MainActor in state }
        let submit = { @MainActor in
            submissions += 1
            state = .waitForApproval
            return state
        }

        let initial = await activation.request(query: query, activate: submit)
        XCTAssertEqual(initial, .waitForApproval)
        XCTAssertEqual(submissions, 1)

        let retry = await activation.request(query: query, activate: submit)
        XCTAssertEqual(retry, .waitForApproval)
        XCTAssertEqual(submissions, 2)

        state = .installed
        let approved = await activation.request(query: query, activate: submit)
        XCTAssertEqual(approved, .installed)
        XCTAssertEqual(submissions, 2)
    }

    @MainActor
    func testForcedReplacementStillActivatesInstalledExtension() async {
        let activation = SystemExtensionActivation()
        var submissions = 0
        let result = await activation.request(forceReplace: true, query: { .installed }) {
            submissions += 1
            return .installed
        }
        XCTAssertEqual(result, .installed)
        XCTAssertEqual(submissions, 1)
    }

    @MainActor
    func testConcurrentPermissionRequestsShareThePendingActivation() async {
        let activation = SystemExtensionActivation()
        let started = expectation(description: "Activation submitted")
        let joined = expectation(description: "Second permission request started")
        var complete: CheckedContinuation<SystemExtensionState, Never>?
        let first = Task {
            await activation.request(query: { .notInstalled }) {
                await withCheckedContinuation {
                    complete = $0
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            joined.fulfill()
            return await activation.request(query: { .notInstalled }) {
                XCTFail("A pending activation must be shared, not resubmitted")
                return .notInstalled
            }
        }
        await fulfillment(of: [joined], timeout: 2)
        complete?.resume(returning: .installed)

        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, .installed)
        XCTAssertEqual(secondResult, .installed)
        let retry = await activation.request(query: { .notInstalled }) { .notInstalled }
        XCTAssertEqual(retry, .notInstalled)
    }
}

@main
enum ActivationTests {
    static func main() {
        let suite = SystemExtensionActivationTests.defaultTestSuite
        suite.run()
        guard let result = suite.testRun, result.executionCount > 0,
              result.totalFailureCount == 0 else { exit(1) }
    }
}
