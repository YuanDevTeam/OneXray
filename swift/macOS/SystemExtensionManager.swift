import Foundation
import SystemExtensions

enum SystemExtensionState {
    case installed
    case notInstalled
    case waitForApproval
}

@MainActor
final class SystemExtensionActivation {
    private var task: Task<SystemExtensionState, Never>?

    func request(
        forceReplace: Bool = false,
        query: @escaping @MainActor () async -> SystemExtensionState,
        activate: @escaping @MainActor () async -> SystemExtensionState
    ) async -> SystemExtensionState {
        if let existing = task {
            return await existing.value
        }
        let pending = Task {
            // Only the activation clears its slot, before waiters can start
            // another request. Completed results are never permission caches.
            defer { self.task = nil }
            let installed = await query()
            if installed == .installed && !forceReplace {
                return installed
            }
            // Explicit retries must resubmit requests that still need approval.
            return await activate()
        }
        task = pending
        return await pending.value
    }
}

/// Public entry points for managing the bundled packet tunnel system extension.
/// Each call constructs a one-shot driver around a single OSSystemExtensionRequest;
/// no state is retained between calls.
enum SystemExtensionManager {
    static func isInstalled() async -> SystemExtensionState {
        guard let properties = try? await ExtensionRequestDriver().runProperties(timeout: .seconds(5), { queue in
            OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: packetTunnelId(), queue: queue)
        }) else { return .notInstalled }
        let waitForApproval = properties.contains(where: { item in
            item.bundleIdentifier == packetTunnelId() && item.isAwaitingUserApproval
        })
        if waitForApproval {
            return .waitForApproval
        }
        guard let current = ExtensionIdentity.bundled() else {
            return .notInstalled
        }
        let success = properties.contains(where: { item in
            item.matches(current) && !item.isAwaitingUserApproval && !item.isUninstalling
        })
        if success {
            return .installed
        }
        let activeDifferentVersion = properties.contains(where: { item in
            item.bundleIdentifier == current.bundleIdentifier && !item.isAwaitingUserApproval && !item.isUninstalling
        })
        if activeDifferentVersion {
            YGLog("system extension version mismatch; activation required")
        }
        return .notInstalled
    }

    static func activate(forceReplace: Bool = false) async throws -> OSSystemExtensionRequest.Result? {
        try await ExtensionRequestDriver(forceReplace: forceReplace).runResult(timeout: .seconds(20)) { queue in
            OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: packetTunnelId(), queue: queue)
        }
    }

    static func deactivate() async throws -> OSSystemExtensionRequest.Result? {
        try await ExtensionRequestDriver().runResult(timeout: .seconds(20)) { queue in
            OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: packetTunnelId(), queue: queue)
        }
    }
}

// MARK: - Private

private typealias RequestFactory = @Sendable (DispatchQueue) -> OSSystemExtensionRequest

private enum SystemExtensionRequestError: Error {
    case timeout
}

private struct ExtensionIdentity: Sendable {
    let bundleIdentifier: String
    let bundleVersion: String
    let bundleShortVersion: String

    static func bundled() -> ExtensionIdentity? {
        let identifier = packetTunnelId()
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Library")
            .appendingPathComponent("SystemExtensions")
            .appendingPathComponent("\(identifier).systemextension")
        guard let bundle = Bundle(url: url) else {
            YGLog("bundled system extension not found: \(url.path)")
            return nil
        }
        return ExtensionIdentity(
            bundleIdentifier: bundle.bundleIdentifier ?? identifier,
            bundleVersion: stringValue(bundle.object(forInfoDictionaryKey: "CFBundleVersion")) ?? "",
            bundleShortVersion: stringValue(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")) ?? ""
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }
}

private struct ExtensionPropertiesSnapshot: Sendable {
    let bundleIdentifier: String
    let bundleVersion: String
    let bundleShortVersion: String
    let isAwaitingUserApproval: Bool
    let isUninstalling: Bool

    init(_ properties: OSSystemExtensionProperties) {
        bundleIdentifier = properties.bundleIdentifier
        bundleVersion = properties.bundleVersion
        bundleShortVersion = properties.bundleShortVersion
        isAwaitingUserApproval = properties.isAwaitingUserApproval
        isUninstalling = properties.isUninstalling
    }
}

private extension ExtensionPropertiesSnapshot {
    func matches(_ identity: ExtensionIdentity) -> Bool {
        bundleIdentifier == identity.bundleIdentifier
            && bundleVersion == identity.bundleVersion
            && bundleShortVersion == identity.bundleShortVersion
    }
}

/// Handles a single OSSystemExtensionRequest. Delegate callbacks run on a
/// dedicated serial queue that also guards all mutable state, making the
/// driver effectively single-threaded despite its `@unchecked Sendable`.
private final class ExtensionRequestDriver: NSObject, OSSystemExtensionRequestDelegate, @unchecked Sendable {
    private enum Waiter {
        case none
        case result(UUID, CheckedContinuation<OSSystemExtensionRequest.Result?, Error>)
        case properties(UUID, CheckedContinuation<[ExtensionPropertiesSnapshot], Error>)

        var token: UUID? {
            switch self {
            case .none:
                return nil
            case let .result(token, _), let .properties(token, _):
                return token
            }
        }
    }

    private static let delegateQueue = DispatchQueue(label: "net.yuandev.onexray.system-extension")

    private let forceReplace: Bool
    private var waiter: Waiter = .none

    init(forceReplace: Bool = false) {
        self.forceReplace = forceReplace
        super.init()
    }

    func runResult(
        timeout: DispatchTimeInterval,
        _ make: @escaping RequestFactory
    ) async throws -> OSSystemExtensionRequest.Result? {
        try await withCheckedThrowingContinuation { continuation in
            submit(.result(UUID(), continuation), timeout: timeout, make: make)
        }
    }

    func runProperties(
        timeout: DispatchTimeInterval,
        _ make: @escaping RequestFactory
    ) async throws -> [ExtensionPropertiesSnapshot] {
        try await withCheckedThrowingContinuation { continuation in
            submit(.properties(UUID(), continuation), timeout: timeout, make: make)
        }
    }

    private func submit(_ waiter: Waiter, timeout: DispatchTimeInterval, make: @escaping RequestFactory) {
        Self.delegateQueue.async {
            self.waiter = waiter
            if let token = waiter.token {
                self.scheduleTimeout(token, timeout: timeout)
            }
            let request = make(Self.delegateQueue)
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    private func scheduleTimeout(_ token: UUID, timeout: DispatchTimeInterval) {
        Self.delegateQueue.asyncAfter(deadline: .now() + timeout) {
            self.timeout(token)
        }
    }

    private func timeout(_ token: UUID) {
        switch waiter {
        case let .result(current, continuation) where current == token:
            waiter = .none
            YGLog("system extension request timeout")
            continuation.resume(throwing: SystemExtensionRequestError.timeout)
        case let .properties(current, continuation) where current == token:
            waiter = .none
            YGLog("system extension properties request timeout")
            continuation.resume(throwing: SystemExtensionRequestError.timeout)
        default:
            break
        }
    }

    // MARK: - OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension new: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction
    {
        if forceReplace { return .replace }
        let identical = existing.bundleIdentifier == new.bundleIdentifier
            && existing.bundleVersion == new.bundleVersion
            && existing.bundleShortVersion == new.bundleShortVersion
        if identical {
            YGLog("system extension already at current version; cancel")
            return .cancel
        }
        YGLog("system extension differs; replacing")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        // Caller isn't blocked while the user walks over to System Settings.
        // Resolve with nil so callers treat "pending approval" as "not ready";
        // the success path is detected later via isInstalled().
        YGLog("system extension awaiting user approval in System Settings")
        if case let .result(_, continuation) = waiter {
            waiter = .none
            continuation.resume(returning: nil)
        }
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result)
    {
        if case let .result(_, continuation) = waiter {
            waiter = .none
            continuation.resume(returning: result)
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        switch waiter {
        case let .result(_, c):
            waiter = .none
            c.resume(throwing: error)
        case let .properties(_, c):
            waiter = .none
            c.resume(throwing: error)
        case .none:
            break
        }
    }

    func request(_ request: OSSystemExtensionRequest,
                 foundProperties properties: [OSSystemExtensionProperties])
    {
        if case let .properties(_, continuation) = waiter {
            waiter = .none
            continuation.resume(returning: properties.map(ExtensionPropertiesSnapshot.init))
        }
    }
}
