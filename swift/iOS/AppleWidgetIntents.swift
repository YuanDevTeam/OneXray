import AppIntents

@available(iOS 17.0, *)
struct StartVpnWidgetIntent: AppIntent {
    static var title: LocalizedStringResource { LocalizedStringResource("Start VPN", table: "Widget") }
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { false }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppleWidgetActionInbox.shared.submit(.startVpn)
        return .result()
    }
}

@available(iOS 17.0, *)
struct StopVpnWidgetIntent: AppIntent {
    static var title: LocalizedStringResource { LocalizedStringResource("Stop VPN", table: "Widget") }
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { false }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppleWidgetActionInbox.shared.submit(.stopVpn)
        return .result()
    }
}
