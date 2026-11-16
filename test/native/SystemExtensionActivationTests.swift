import Foundation
import SystemExtensions
import XCTest

// Link the production file without submitting requests to the operating system.
func packetTunnelId() -> String { "net.yuandev.onexray.test.tun" }
func YGLog(_ message: String) {}

// The request is accessed only on its delegate queue. No request is submitted
// to OSSystemExtensionManager in these driver tests.
private final class TestExtensionRequest: @unchecked Sendable {
    let request: OSSystemExtensionRequest
    init(_ request: OSSystemExtensionRequest) { self.request = request }
}

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

    @MainActor
    func testDeactivationKeepsApprovalPendingUntilDelayedRestartResult() async {
        let finished = expectation(description: "Terminal deactivation result")
        var observed: OSSystemExtensionRequest.Result?
        Task {
            do {
                observed = try await ExtensionRequestDriver(
                    waitForTerminalResult: true,
                    submitRequest: { request, queue in
                        request.delegate?.requestNeedsUserApproval(request)
                        let pending = TestExtensionRequest(request)
                        queue.asyncAfter(deadline: .now() + .milliseconds(30)) {
                            pending.request.delegate?.request(pending.request, didFinishWithResult: .willCompleteAfterReboot)
                        }
                    }
                ).runResult(timeout: nil) { queue in
                    OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: packetTunnelId(), queue: queue)
                }
            } catch { XCTFail("Unexpected deactivation error: \(error)") }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(observed, .willCompleteAfterReboot)
    }

    @MainActor
    func testDeactivationKeepsApprovalPendingUntilDelayedDenial() async {
        let finished = expectation(description: "Terminal deactivation failure")
        var observedError: NSError?
        Task {
            do {
                _ = try await ExtensionRequestDriver(
                    waitForTerminalResult: true,
                    submitRequest: { request, queue in
                        request.delegate?.requestNeedsUserApproval(request)
                        let pending = TestExtensionRequest(request)
                        queue.asyncAfter(deadline: .now() + .milliseconds(30)) {
                            let denied = NSError(domain: OSSystemExtensionErrorDomain, code: OSSystemExtensionError.requestCanceled.rawValue)
                            pending.request.delegate?.request(pending.request, didFailWithError: denied)
                        }
                    }
                ).runResult(timeout: nil) { queue in
                    OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: packetTunnelId(), queue: queue)
                }
                XCTFail("Approval notification must not finish deactivation before denial")
            } catch { observedError = error as NSError }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(observedError?.domain, OSSystemExtensionErrorDomain)
        XCTAssertEqual(observedError?.code, OSSystemExtensionError.requestCanceled.rawValue)
    }

    @MainActor
    func testActivationDriverStillTimesOutWithoutAReply() async {
        do {
            _ = try await ExtensionRequestDriver(submitRequest: { _, _ in }).runResult(timeout: .milliseconds(20)) { queue in
                OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: packetTunnelId(), queue: queue)
            }
            XCTFail("Activation must retain its timeout")
        } catch {}
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
