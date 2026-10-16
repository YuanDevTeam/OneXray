import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, @preconcurrency FlutterImplicitEngineDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        let binaryMessenger = engineBridge.applicationRegistrar.messenger()
        let flutterApi = AppFlutterApi(binaryMessenger: binaryMessenger)
        BridgeHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: AppHostApi(flutterApi: flutterApi))
        let backupApi = AppleBackupApi()
        BackupHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: backupApi)
        AppleBackupHostApiSetup.setUp(binaryMessenger: binaryMessenger, api: backupApi)
        
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    }
}
