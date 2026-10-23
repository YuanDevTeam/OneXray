import Foundation
#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#else
#error("Unsupported platform.")
#endif

@MainActor
class AppFlutterApi {
    private let flutterApi: BridgeFlutterApi
    init(binaryMessenger: FlutterBinaryMessenger) {
        self.flutterApi = BridgeFlutterApi(binaryMessenger: binaryMessenger)
        VPNManager.shared.registerStatusObserver(vpnStatusChanged)
    }

    deinit {
        Task {
            await VPNManager.shared.unregisterStatusObserver()
        }
    }

    func vpnStatusChanged() async throws {
        let status = try await VPNManager.shared.readVpnStatus()
        flutterApi.vpnStatusChanged(status: status) { _ in }
    }

    #if os(macOS)
    func openSettings() {
        // Setup or startup can still be registering the Dart receiver. This
        // navigation command is intentionally not queued or retried.
        flutterApi.openSettings { _ in }
    }
    #endif
}
