import AppIntents

@available(iOS 17.0, *)
struct StartVpnWidgetIntent: AppIntent {
    static let title = LocalizedStringResource("Start VPN", table: "Widget")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @available(iOS 27.0, *)
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @MainActor
    func perform() async throws -> some IntentResult {
        #if ONEXRAY_WIDGET_EXTENSION
        try requireAppProcess()
        #else
        try await performVpnWidgetCommand(.start, intent: self)
        #endif
        return .result()
    }
}

@available(iOS 17.0, *)
struct StopVpnWidgetIntent: AppIntent {
    static let title = LocalizedStringResource("Stop VPN", table: "Widget")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @available(iOS 27.0, *)
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @MainActor
    func perform() async throws -> some IntentResult {
        #if ONEXRAY_WIDGET_EXTENSION
        try requireAppProcess()
        #else
        try await performVpnWidgetCommand(.stop, intent: self)
        #endif
        return .result()
    }
}

@available(iOS 17.0, *)
struct ToggleVpnWidgetIntent: AppIntent {
    static let title = LocalizedStringResource("Start or stop VPN", table: "Widget")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @available(iOS 27.0, *)
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @MainActor
    func perform() async throws -> some IntentResult {
        #if ONEXRAY_WIDGET_EXTENSION
        try requireAppProcess()
        #else
        try await performVpnWidgetCommand(.toggle, intent: self)
        #endif
        return .result()
    }
}

private enum AppleWidgetIntentError: LocalizedError {
    case requiresAppProcess
    case foregroundUnavailable

    var errorDescription: String? {
        switch self {
        case .requiresAppProcess:
            AppleWidgetLocalization.text("This VPN action must run in OneXray.")
        case .foregroundUnavailable:
            AppleWidgetLocalization.text("OneXray cannot open from this system control right now.")
        }
    }
}

#if ONEXRAY_WIDGET_EXTENSION
private func requireAppProcess() throws {
    // A misrouted intent must fail visibly rather than report false success.
    throw AppleWidgetIntentError.requiresAppProcess
}
#else
// Apple documents this conformance as the app-process background route for
// interactive widgets. Keep it on the app target only: the protocol is
// unavailable to app extensions. supportedModes replaces it on iOS 26+.
@available(iOS 17.0, *)
@available(*, deprecated)
extension StartVpnWidgetIntent: ForegroundContinuableIntent {}

@available(iOS 17.0, *)
@available(*, deprecated)
extension StopVpnWidgetIntent: ForegroundContinuableIntent {}

@available(iOS 17.0, *)
@available(*, deprecated)
extension ToggleVpnWidgetIntent: ForegroundContinuableIntent {}

@available(iOS 17.0, *)
private func performVpnWidgetCommand<Intent: ForegroundContinuableIntent>(
    _ command: AppleWidgetCommand, intent: Intent
) async throws {
    switch try await AppleWidgetVpnActions.shared.perform(command) {
    case .completed, .inProgress:
        return
    case .needsForeground:
        let language = AppleWidgetStore.shared?.languageCode() ?? "en"
        let dialog = IntentDialog(LocalizedStringResource(
            "Open OneXray to finish setup.", table: "Widget", locale: Locale(identifier: language)
        ))
        if #available(iOS 26.0, *) {
            if intent.systemContext.currentMode != .foreground {
                guard intent.systemContext.currentMode.canContinueInForeground else {
                    throw AppleWidgetIntentError.foregroundUnavailable
                }
                try await intent.continueInForeground(dialog, alwaysConfirm: false)
            }
            await AppleWidgetActionInbox.shared.requestOpenConnect()
        } else {
            try await intent.requestToContinueInForeground(dialog) {
                AppleWidgetActionInbox.shared.requestOpenConnect()
            }
        }
        // The facade suppresses startup auto-connect. Foreground continuation
        // only navigates to setup; it never submits another connection request.
    }
}
#endif
