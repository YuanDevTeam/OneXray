import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/pigeon/messages.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/app/src/main/kotlin/net/yuandev/onexray/pigeon/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: "net.yuandev.onexray.pigeon"),
    swiftOut: 'swift/App/pigeon/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'onexray',
  ),
)
@HostApi()
abstract class BridgeHostApi {
  @asyncCallback
  String getTunFilesDir();

  @asyncCallback
  NativeVpnCommandResult readVpnStatus();

  @asyncCallback
  NativeVpnCommandResult startVpn();

  @asyncCallback
  NativeVpnCommandResult stopVpn();

  @asyncCallback
  String invoke(String requestJson);

  //platform======================
  @asyncCallback
  PlatformPermissionResult queryPlatformPermission();

  @asyncCallback
  PlatformPermissionResult requestPlatformPermission();

  //android=======================

  @asyncCallback
  List<AndroidAppInfo> getInstalledApps();

  @asyncCallback
  Uint8List? getAppIcon(String packageName);

  //macOS======================
  @asyncCallback
  bool useSystemExtension();

  @asyncCallback
  AppleVpnCapabilities appleVpnCapabilities();

  @asyncCallback
  NativeLaunchAtLoginResult queryLaunchAtLogin();

  @asyncCallback
  NativeLaunchAtLoginResult setLaunchAtLogin(bool enabled);

  @asyncCallback
  bool openLaunchAtLoginSettings();

  //Apple app icon======================
  @asyncCallback
  bool setAppIcon(String appIcon);

  @asyncCallback
  String getCurrentAppIcon();
}

enum VpnStatus { disconnecting, disconnected, connecting, connected }

class AndroidAutomationSettings {
  AndroidAutomationSettings({required this.enabled, this.token});
  final bool enabled;
  final String? token;
}

@HostApi()
abstract class AndroidAutomationHostApi {
  @asyncCallback
  AndroidAutomationSettings read();

  @asyncCallback
  AndroidAutomationSettings setEnabled(bool enabled);

  @asyncCallback
  AndroidAutomationSettings resetToken();

  @asyncCallback
  void setStartBlocked(bool blocked);

  @asyncCallback
  void clear();
}

class BackupLocation {
  BackupLocation({required this.identifier, required this.label});
  final String identifier;
  final String label;
}

@HostApi()
abstract class BackupHostApi {
  @asyncCallback
  BackupLocation? selectBackupFile(bool create);

  @asyncCallback
  void requireBackupAccess(String identifier);

  @asyncCallback
  void releaseBackupFile(String identifier);
}

@HostApi()
abstract class AppleBackupHostApi {
  @asyncCallback
  bool hasBackupFileContents(String identifier);

  @asyncCallback
  Uint8List readBackupFile(String identifier);

  @asyncCallback
  void writeBackupFile(String identifier, Uint8List bytes);
}

class AppleVpnCapabilities {
  AppleVpnCapabilities({
    required this.serviceExclusions,
    required this.deviceCommunication,
  });
  final bool serviceExclusions;
  final bool deviceCommunication;
}

enum PlatformPermissionKind {
  none,
  androidVpn,
  macosSystemExtension,
  appleVpn,
  androidLocalNetwork,
}

enum PlatformPermissionState {
  notRequired,
  notDetermined,
  awaitingUserApproval,
  granted,
  denied,
  failed,
}

enum NativeVpnCommandState { success, waitingForPlatformPermission, failed }

enum NativeLaunchAtLoginState {
  enabled,
  disabled,
  requiresApproval,
  unavailable,
  error,
}

class NativeLaunchAtLoginResult {
  NativeLaunchAtLoginResult({required this.state, this.message});

  final NativeLaunchAtLoginState state;
  final String? message;
}

class PlatformPermissionResult {
  PlatformPermissionResult({
    required this.kind,
    required this.state,
    this.message,
  });

  final PlatformPermissionKind kind;
  final PlatformPermissionState state;
  final String? message;
}

class NativeVpnCommandResult {
  NativeVpnCommandResult({
    required this.state,
    this.permission,
    this.message,
    this.status,
  });

  final NativeVpnCommandState state;
  // Successful status reads and commands supply the confirmed native status.
  // Failures and permission-waiting results may omit it.
  final VpnStatus? status;
  final PlatformPermissionResult? permission;
  final String? message;
}

class AndroidAppInfo {
  AndroidAppInfo({required this.name, required this.packageName});

  final String name;
  final String packageName;
}

@FlutterApi()
abstract class BridgeFlutterApi {
  @asyncCallback
  void vpnStatusChanged(VpnStatus status);
}
