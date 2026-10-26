import Foundation

/// Stop retires old starts and drains profile writes, not native status waits.
@MainActor
final class AppleVpnStartAdmission {
    private(set) var generation: UInt64 = 0
    private var preparing: Set<UInt64> = []
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    func begin() -> UInt64 {
        generation &+= 1
        preparing.insert(generation)
        return generation
    }

    func isCurrent(_ token: UInt64) -> Bool { token == generation }

    func check(_ token: UInt64) throws {
        guard isCurrent(token) else { throw CancellationError() }
    }

    func finishPreparation(_ token: UInt64) {
        preparing.remove(token)
        guard preparing.isEmpty else { return }
        let waiters = drainWaiters
        drainWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func invalidate() { generation &+= 1 }

    func waitForPreparation() async {
        guard !preparing.isEmpty else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }
}
