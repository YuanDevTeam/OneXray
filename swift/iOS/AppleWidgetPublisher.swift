import Foundation
import WidgetKit

enum AppleWidgetPublisher {
    static let controlAttemptOption = "onexray-control-attempt"

    static func publish(_ status: AppleWidgetStatus) {
        // A missing shared container must never affect the VPN command itself.
        guard let store = AppleWidgetStore.shared,
              (try? store.writeStatus(status)) == true else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: AppleWidgetStore.kind)
        reloadControl()
    }

    static func beginControlStart() -> AppleWidgetControlAttempt {
        let attempt = UUID()
        if #available(iOS 18.0, *), let store = AppleWidgetStore.shared,
           (try? store.beginControlAttempt(attempt)) == true { reloadControl() }
        return attempt
    }

    static func beginTunnelStart(options: [String: NSObject]?) -> AppleWidgetControlAttempt {
        if let option = options?[controlAttemptOption] as? String, let attempt = UUID(uuidString: option) {
            return attempt
        }
        return beginControlStart()
    }

    static func finishTunnelStart(for attempt: AppleWidgetControlAttempt) {
        if #available(iOS 18.0, *), let store = AppleWidgetStore.shared,
           (try? store.completeControlStart(attempt)) == true { reloadControl() }
    }

    static func publishFailure(_ failure: AppleWidgetControlFailure, for attempt: AppleWidgetControlAttempt) {
        if #available(iOS 18.0, *), let store = AppleWidgetStore.shared,
           (try? store.writeControlFailure(failure, for: attempt)) == true { reloadControl() }
    }

    static func finishTunnelStop(for attempt: AppleWidgetControlAttempt, failed: Bool) {
        if !failed {
            clearControlFailure(for: attempt)
        } else if #available(iOS 18.0, *), let store = AppleWidgetStore.shared,
                  (try? store.writeControlFailure(.vpnService, for: attempt, afterStart: true)) == true {
            reloadControl()
        }
    }

    static func clearControlFailure(for attempt: AppleWidgetControlAttempt? = nil) {
        if #available(iOS 18.0, *), let store = AppleWidgetStore.shared,
           (try? store.endControlAttempt(attempt)) == true { reloadControl() }
    }

    private static func reloadControl() {
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: AppleWidgetStore.controlKind)
        }
    }

    static func setLanguage(_ code: String) throws {
        guard let store = AppleWidgetStore.shared else { return }
        if try store.writeLanguage(code) {
            WidgetCenter.shared.reloadTimelines(ofKind: AppleWidgetStore.kind)
            if #available(iOS 18.0, *) {
                ControlCenter.shared.reloadAllControls()
            }
        }
    }
}
