import Foundation

enum AppleWidgetAction: String, Sendable {
    case startVpn
    case stopVpn
}

/// Foreground App Intents run in the containing app. This inbox deliberately has
/// no shared-container persistence or public URL entry point.
@MainActor
final class AppleWidgetActionInbox {
    static let shared = AppleWidgetActionInbox()
    static let actionAvailable = Notification.Name("OneXray.AppleWidgetActionAvailable")
    private var pending: AppleWidgetAction?

    func submit(_ action: AppleWidgetAction) {
        pending = action
        NotificationCenter.default.post(name: Self.actionAvailable, object: nil)
    }

    func takeAction() -> String? {
        defer { pending = nil }
        return pending?.rawValue
    }
}
