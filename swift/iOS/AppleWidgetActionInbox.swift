import Foundation

/// Native intents complete VPN actions themselves. This process-local inbox
/// only suppresses startup, cancels superseded Dart preparations, or navigates.
@MainActor
final class AppleWidgetActionInbox {
    static let shared = AppleWidgetActionInbox()
    static let actionAvailable = Notification.Name("OneXray.AppleWidgetActionAvailable")
    private var suppressAutoConnect = false
    private var openConnect = false
    private var invalidatedPreparations = Set<String>()

    func recordBackgroundAction() {
        suppressAutoConnect = true
        notify()
    }

    func recordNativeStop(invalidatedPreparations tokens: [String]) {
        suppressAutoConnect = true
        invalidatedPreparations.formUnion(tokens)
        notify()
    }

    func requestOpenConnect() {
        suppressAutoConnect = true
        openConnect = true
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.actionAvailable, object: nil)
    }

    func takeAction() -> String? {
        guard suppressAutoConnect || openConnect || !invalidatedPreparations.isEmpty else { return nil }
        let envelope: [String: Any] = [
            "version": 1,
            "suppressAutoConnect": suppressAutoConnect,
            "openConnect": openConnect,
            "invalidatedPreparations": invalidatedPreparations.sorted(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope),
              let text = String(data: data, encoding: .utf8) else { return nil }
        suppressAutoConnect = false
        openConnect = false
        invalidatedPreparations.removeAll()
        return text
    }
}
