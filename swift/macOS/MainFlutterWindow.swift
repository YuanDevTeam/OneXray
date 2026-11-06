import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    private var flutterApi: AppFlutterApi?
    private var hasHandledInitialOrder = false

    override func awakeFromNib() {
        MainActor.assumeIsolated {
            let flutterViewController = FlutterViewController()
            let windowFrame = frame
            contentViewController = flutterViewController
            setFrame(windowFrame, display: true)

            let binaryMessenger = flutterViewController.engine.binaryMessenger
            let flutterApi = AppFlutterApi(binaryMessenger: binaryMessenger)
            self.flutterApi = flutterApi
            BridgeHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: AppHostApi(flutterApi: flutterApi))
            let backupApi = AppleBackupApi()
            BackupHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: backupApi)
            AppleBackupHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: backupApi)

            RegisterGeneratedPlugins(registry: flutterViewController)

            super.awakeFromNib()
            DockIconService.restoreIcon()
        }
    }

    func openSettings() {
        flutterApi?.openSettings()
    }

    override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        // Dart startup owns when the prepared window is first shown.
        if !hasHandledInitialOrder {
            hasHandledInitialOrder = true
            setIsVisible(false)
        }
    }
}
