import Foundation
import XCTest

final class DesktopProxyTerminationTests: XCTestCase {
    @MainActor
    func testInactiveProxyExitsWithoutStopOrDeferredReply() {
        let termination = DesktopProxyTermination()
        let deferred = termination.deferIfNeeded(
            isProxyActive: false,
            stopAndConfirmStopped: { XCTFail("No helper needs stopping"); return false },
            reply: { _ in XCTFail("No deferred quit was requested") }
        )
        XCTAssertFalse(deferred)
    }

    @MainActor
    func testRepeatedQuitWaitsForTheSameShutdown() async {
        let termination = DesktopProxyTermination()
        let stopping = expectation(description: "Stop started")
        let replied = expectation(description: "Only the original quit receives a reply")
        var finish: CheckedContinuation<Bool, Never>?
        var stops = 0
        var replies: [Bool] = []
        XCTAssertTrue(termination.deferIfNeeded(
            isProxyActive: true,
            stopAndConfirmStopped: {
                stops += 1
                stopping.fulfill()
                return await withCheckedContinuation { finish = $0 }
            },
            reply: { replies.append($0); replied.fulfill() }
        ))
        await fulfillment(of: [stopping], timeout: 2)
        // Even if the helper just exited, finish the pending AppKit request.
        XCTAssertTrue(termination.deferIfNeeded(
            isProxyActive: false,
            stopAndConfirmStopped: { XCTFail("A second stop must not start"); return false },
            reply: { _ in XCTFail("A second reply must not be sent") }
        ))
        finish?.resume(returning: true)
        await fulfillment(of: [replied], timeout: 2)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(replies, [true])
    }

    @MainActor
    func testUnconfirmedStopCancelsTerminationAndAllowsRetry() async {
        let termination = DesktopProxyTermination()
        let cancelled = expectation(description: "Unconfirmed stop cancels quit")
        XCTAssertTrue(termination.deferIfNeeded(
            isProxyActive: true,
            stopAndConfirmStopped: { false },
            reply: { XCTAssertFalse($0); cancelled.fulfill() }
        ))
        await fulfillment(of: [cancelled], timeout: 2)
        let retried = expectation(description: "A later quit can stop and exit")
        XCTAssertTrue(termination.deferIfNeeded(
            isProxyActive: true,
            stopAndConfirmStopped: { true },
            reply: { XCTAssertTrue($0); retried.fulfill() }
        ))
        await fulfillment(of: [retried], timeout: 2)
    }

}
