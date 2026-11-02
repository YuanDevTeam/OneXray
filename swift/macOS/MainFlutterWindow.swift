import Cocoa
import FlutterMacOS
import window_manager

class MainFlutterWindow: NSWindow {
    private var flutterApi: AppFlutterApi?

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
        hiddenWindowAtLaunch()
    }
}
