import Cocoa
import FlutterMacOS

@main
@MainActor
class AppDelegate: FlutterAppDelegate {
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreMainWindow()
        return true
    }

    @IBAction func showMainWindow(_ sender: Any?) {
        restoreMainWindow()
    }

    @IBAction func showSettings(_ sender: Any?) {
        restoreMainWindow()
        guard NSApp.modalWindow == nil,
              let window = mainFlutterWindow as? MainFlutterWindow,
              window.attachedSheet == nil else {
            return
        }
        window.openSettings()
    }

    private func restoreMainWindow() {
        guard let window = mainFlutterWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0 is MainFlutterWindow }) else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

}
