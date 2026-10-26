import Foundation
import WidgetKit

enum AppleWidgetPublisher {
    static func publish(_ status: AppleWidgetStatus) {
        // A missing shared container must never affect the VPN command itself.
        guard let store = AppleWidgetStore.shared,
              (try? store.writeStatus(status)) == true else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: AppleWidgetStore.kind)
    }

    static func setLanguage(_ code: String) throws {
        guard let store = AppleWidgetStore.shared else { return }
        if try store.writeLanguage(code) {
            WidgetCenter.shared.reloadTimelines(ofKind: AppleWidgetStore.kind)
        }
    }
}
