import Foundation

enum AppleVpnRemovalOutcome {
    case removed
    case restartRequired
}

enum AppleVpnRemovalError: LocalizedError {
    case inProgress
    case profilesRemain
    case extensionApprovalRequired
    case unexpectedExtensionResult

    var errorDescription: String? {
        switch self {
        case .inProgress: return "VPN removal is in progress."
        case .profilesRemain: return "The system still has a VPN configuration for this app."
        case .extensionApprovalRequired: return "System Extension removal has not been approved."
        case .unexpectedExtensionResult: return "System Extension removal did not complete."
        }
    }
}

/// Serializes removal against native profile writes and extension activation.
/// The app and Runner-hosted iOS intents share this in-memory admission guard.
@MainActor
final class AppleVpnRemoval {
    private(set) var isRemoving = false
    private(set) var generation: UInt64 = 0
    private var mutations: Set<UUID> = []
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    func requireMutationAllowed() throws {
        if isRemoving { throw AppleVpnRemovalError.inProgress }
    }

    func beginMutation() throws -> UUID {
        try requireMutationAllowed()
        let token = UUID()
        mutations.insert(token)
        return token
    }

    func finishMutation(_ token: UUID) {
        mutations.remove(token)
        guard mutations.isEmpty else { return }
        let waiters = drainWaiters
        drainWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func remove<Profile>(
        providerIdentifier: String,
        invalidateStarts: @MainActor () -> Void,
        prepare: @MainActor () async throws -> Void,
        load: @MainActor () async throws -> [Profile],
        identifier: @MainActor (Profile) -> String?,
        stop: @MainActor (Profile) async throws -> Void,
        remove: @MainActor (Profile) async throws -> Void,
        profilesRemoved: @MainActor () -> Void,
        deactivate: @MainActor () async throws -> AppleVpnRemovalOutcome
    ) async throws -> AppleVpnRemovalOutcome {
        try requireMutationAllowed()
        isRemoving = true
        generation &+= 1
        defer { isRemoving = false }
        invalidateStarts()
        if !mutations.isEmpty {
            await withCheckedContinuation { drainWaiters.append($0) }
        }
        try await prepare()
        let profiles = try await load().filter { identifier($0) == providerIdentifier }
        // Confirm every owned tunnel has stopped before deleting any profile.
        for profile in profiles { try await stop(profile) }
        for profile in profiles { try await remove(profile) }
        guard try await load().allSatisfy({ identifier($0) != providerIdentifier }) else {
            throw AppleVpnRemovalError.profilesRemain
        }
        profilesRemoved()
        return try await deactivate()
    }
}
