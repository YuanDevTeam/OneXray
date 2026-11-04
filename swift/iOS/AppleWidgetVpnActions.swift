import Foundation

struct AppleWidgetVpnActionError: LocalizedError {
    let message: String
    var errorDescription: String? { AppleWidgetLocalization.text(message) }
}

/// Explicit native commands share one status decision; no Widget snapshot selects an action.
@MainActor
final class AppleWidgetVpnActions {
    #if os(iOS)
    static let shared = AppleWidgetVpnActions(
        readStatus: { try await VPNManager.shared.readWidgetVpnStatus() },
        start: { try await VPNManager.shared.startSavedVpnForWidget() },
        stop: { try await VPNManager.shared.stopVpnForWidget() },
        commandGeneration: { VPNManager.shared.widgetCommandGeneration }
    )
    #endif

    private let readStatus: @MainActor () async throws -> AppleWidgetStatus
    private let start: @MainActor () async throws -> AppleWidgetCommandOutcome
    private let stop: @MainActor () async throws -> AppleWidgetCommandOutcome
    private let commandGeneration: @MainActor () -> UInt64

    init(
        readStatus: @escaping @MainActor () async throws -> AppleWidgetStatus,
        start: @escaping @MainActor () async throws -> AppleWidgetCommandOutcome,
        stop: @escaping @MainActor () async throws -> AppleWidgetCommandOutcome,
        commandGeneration: @escaping @MainActor () -> UInt64 = { 0 }
    ) {
        self.readStatus = readStatus
        self.start = start
        self.stop = stop
        self.commandGeneration = commandGeneration
    }

    func perform(_ command: AppleWidgetCommand) async throws -> AppleWidgetCommandOutcome {
        AppleWidgetActionInbox.shared.recordBackgroundAction()
        if command == .stop { return try await stop() }
        let generation = commandGeneration()
        let status: AppleWidgetStatus
        do {
            status = try await readStatus()
        } catch {
            guard commandGeneration() == generation else { return .inProgress }
            throw error
        }
        guard commandGeneration() == generation else { return .inProgress }
        switch (command, status) {
        case (_, .unknown): throw AppleWidgetVpnActionError(message: "Unable to confirm the current VPN status.")
        case (.stop, _): return try await stop()
        case (.start, .connected): return .completed
        case (.start, .connecting), (.start, .disconnecting), (.toggle, .disconnecting): return .inProgress
        case (.toggle, .connected), (.toggle, .connecting): return try await stop()
        case (.start, .disconnected), (.toggle, .disconnected): return try await start()
        }
    }
}
