import Foundation
#if os(iOS)
import Flutter
#elseif os(macOS)
import AppKit
import FlutterMacOS
#else
#error("Unsupported platform.")
#endif

@MainActor
final class AppHostApi: @preconcurrency BridgeHostApi {
    // Retain the native status observer for the bridge's lifetime.
    private let flutterApi: AppFlutterApi
    init(flutterApi: AppFlutterApi) {
        self.flutterApi = flutterApi
    }
    
    func getTunFilesDir(completion: @escaping (Result<String, any Error>) -> Void) {
        if let groupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId()) {
            let path = groupUrl.path(percentEncoded: false)
            completion(.success(path))
        } else {
            completion(.success(""))
        }
    }

    func readVpnStatus(completion: @escaping (Result<NativeVpnCommandResult, any Error>) -> Void) {
        Task {
            let permission = await VPNManager.shared.queryPlatformPermission()
            do {
                let status = try await VPNManager.shared.readVpnStatus()
                if permission.state == .failed {
                    completion(.success(NativeVpnCommandResult(
                        state: .failed,
                        permission: permission,
                        message: permission.message
                    )))
                } else {
                    completion(.success(NativeVpnCommandResult(
                        state: .success,
                        status: status,
                        permission: permission,
                        message: status == .disconnected ? VPNManager.shared.lastCommandError : nil
                    )))
                }
            } catch {
                completion(.success(NativeVpnCommandResult(
                    state: .failed,
                    permission: permission,
                    message: error.localizedDescription
                )))
            }
        }
    }
    
    func startVpn(completion: @escaping (Result<NativeVpnCommandResult, any Error>) -> Void) {
        Task {
            completion(.success(await VPNManager.shared.startVpn()))
        }
    }

    func stopVpn(completion: @escaping (Result<NativeVpnCommandResult, any Error>) -> Void) {
        Task {
            completion(.success(await VPNManager.shared.stopVpn()))
        }
    }

    func invoke(requestJson: String, completion: @escaping (Result<String, any Error>) -> Void) {
        Task {
            do {
                completion(.success(try await LibXrayInvoker.invoke(requestJson)))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func queryPlatformPermission(completion: @escaping (Result<PlatformPermissionResult, any Error>) -> Void) {
        Task {
            completion(.success(await VPNManager.shared.queryPlatformPermission()))
        }
    }

    func requestPlatformPermission(completion: @escaping (Result<PlatformPermissionResult, any Error>) -> Void) {
        Task {
            completion(.success(await VPNManager.shared.requestPlatformPermission()))
        }
    }
    
    /// android
    func getInstalledApps(completion: @escaping (Result<[AndroidAppInfo], any Error>) -> Void) {
        completion(.success([]))
    }

    func getAppIcon(packageName: String, completion: @escaping (Result<FlutterStandardTypedData?, any Error>) -> Void) {
        completion(.success(nil))
    }

    /// macOS
    func useSystemExtension(completion: @escaping (Result<Bool, any Error>) -> Void) {
        completion(.success(Constants.useSystemExtension))
    }

    func appleVpnCapabilities(completion: @escaping (Result<AppleVpnCapabilities, any Error>) -> Void) {
        let serviceExclusions: Bool
        let deviceCommunication: Bool
        if #available(iOS 16.4, macOS 13.3, *) {
            serviceExclusions = true
        } else {
            serviceExclusions = false
        }
        if #available(iOS 17.4, macOS 14.4, *) {
            deviceCommunication = true
        } else {
            deviceCommunication = false
        }
        completion(.success(AppleVpnCapabilities(
            serviceExclusions: serviceExclusions,
            deviceCommunication: deviceCommunication
        )))
    }

    func queryLaunchAtLogin(
        completion: @escaping (Result<NativeLaunchAtLoginResult, any Error>) -> Void
    ) {
#if os(macOS)
        completion(.success(LaunchAtLoginService.query()))
#else
        completion(.success(NativeLaunchAtLoginResult(
            state: .unavailable,
            message: nil
        )))
#endif
    }

    func setLaunchAtLogin(
        enabled: Bool,
        completion: @escaping (Result<NativeLaunchAtLoginResult, any Error>) -> Void
    ) {
#if os(macOS)
        completion(.success(LaunchAtLoginService.setEnabled(enabled)))
#else
        completion(.success(NativeLaunchAtLoginResult(
            state: .unavailable,
            message: nil
        )))
#endif
    }

    func openLaunchAtLoginSettings(
        completion: @escaping (Result<Bool, any Error>) -> Void
    ) {
#if os(macOS)
        completion(.success(LaunchAtLoginService.openSettings()))
#else
        completion(.success(false))
#endif
    }

    /// Apple app icon
    func setAppIcon(appIcon: String, completion: @escaping (Result<Bool, any Error>) -> Void) {
#if os(iOS)
        var iconName: String? = appIcon
        if appIcon.isEmpty {
            iconName = nil
        }
        if UIApplication.shared.alternateIconName == iconName {
            completion(.success(true))
            return
        }
        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error = error {
                YGLog(error.localizedDescription)
                completion(.failure(error))
            } else {
                completion(.success(true))
            }
        }
#elseif os(macOS)
        completion(.success(DockIconService.setIcon(appIcon)))
#endif
    }

    func getCurrentAppIcon(completion: @escaping (Result<String, any Error>) -> Void) {
#if os(iOS)
        var appIcon = ""
        if let iconName = UIApplication.shared.alternateIconName {
            appIcon = iconName
        }
        completion(.success(appIcon))
#elseif os(macOS)
        completion(.success(DockIconService.currentIconName))
#endif
    }
}
