import 'dart:typed_data';

import 'package:onexray/core/errors/failure.dart';

import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/core/ffi/linux_ffi_api.dart';
import 'package:onexray/core/ffi/windows/ffi_api.dart';
import 'package:onexray/core/ffi/windows/model.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/invoke_limits.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/pigeon/model_reader.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

class AppHostApi {
  Future<AppleVpnCapabilities> appleVpnCapabilities() =>
      _api.appleVpnCapabilities();
  final _api = BridgeHostApi();

  static final AppHostApi _singleton = AppHostApi._internal();

  factory AppHostApi() => _singleton;

  AppHostApi._internal();

  // ===============
  var _tunFilesDir = "";
  // Mobile and Apple notifications are registered by the native bridge.
  Future<void> observeVpnStatus() async {
    if (AppPlatform.isWindows) {
      await WindowsFfiApi().observeVpnStatus();
    } else if (AppPlatform.isLinux) {
      await LinuxFfiApi().observeVpnStatus();
    }
  }

  void disposeVpnStatus() {
    if (AppPlatform.isWindows) {
      WindowsFfiApi().disposeVpnStatus();
    } else if (AppPlatform.isLinux) {
      LinuxFfiApi().disposeVpnStatus();
    }
  }

  Future<void> initTunFilesDir() async {
    if (AppPlatform.isLinux) {
      _setTunFilesDir(await LinuxFfiApi().getTunFilesDir());
    } else if (AppPlatform.isWindows) {
      _setTunFilesDir(await WindowsFfiApi().getTunFilesDir());
    } else {
      _setTunFilesDir(await _api.getTunFilesDir());
    }
  }

  void _setTunFilesDir(String value) {
    if (value.isEmpty || !p.isAbsolute(value)) {
      _tunFilesDir = '';
      throw StateError('VPN data directory is unavailable');
    }
    _tunFilesDir = p.normalize(value);
  }

  Future<bool?> cleanupStaleDesktopCore() async {
    if (!AppPlatform.isLinux && !AppPlatform.isWindows) {
      return null;
    }
    try {
      return AppPlatform.isWindows
          ? await WindowsFfiApi().cleanupStaleCore()
          : await LinuxFfiApi().cleanupStaleCore();
    } catch (error, stackTrace) {
      _reportUnexpected('cleanupStaleDesktopCore', error, stackTrace);
      return false;
    }
  }

  Future<NativeVpnCommandResult> readVpnStatus() async {
    try {
      return await _readVpnStatus();
    } catch (error, stackTrace) {
      _reportUnexpected('readVpnStatus', error, stackTrace);
      return _commandFailed(failureDetails(error));
    }
  }

  Future<NativeVpnCommandResult> _readVpnStatus() async {
    if (AppPlatform.isLinux) {
      return LinuxFfiApi().readVpnStatus();
    } else if (AppPlatform.isWindows) {
      return WindowsFfiApi().readVpnStatus();
    } else {
      return _api.readVpnStatus();
    }
  }

  Future<NativeVpnCommandResult> startVpn({
    String? windowsConfigYaml,
    WindowsVpnNetworkSettings? windowsNetworkSettings,
    WindowsVpnPolicy windowsPolicy = const WindowsVpnPolicy(
      alwaysOn: false,
      allowLocalNetwork: true,
      excludedCidrs: [],
    ),
  }) async {
    try {
      return await _startVpn(
        windowsConfigYaml,
        windowsNetworkSettings,
        windowsPolicy,
      );
    } catch (error, stackTrace) {
      _reportUnexpected('startVpn', error, stackTrace);
      return _commandFailed(failureDetails(error));
    }
  }

  Future<NativeVpnCommandResult> _startVpn(
    String? windowsConfigYaml,
    WindowsVpnNetworkSettings? windowsNetworkSettings,
    WindowsVpnPolicy windowsPolicy,
  ) async {
    if (AppPlatform.isLinux) {
      return LinuxFfiApi().startVpn();
    } else if (AppPlatform.isWindows) {
      return WindowsFfiApi().startVpn(
        configYaml: windowsConfigYaml,
        networkSettings: windowsNetworkSettings,
        policy: windowsPolicy,
      );
    } else {
      return _api.startVpn();
    }
  }

  Future<NativeVpnCommandResult> stopVpn() async {
    try {
      return await _stopVpn();
    } catch (error, stackTrace) {
      _reportUnexpected('stopVpn', error, stackTrace);
      return _commandFailed(failureDetails(error));
    }
  }

  Future<NativeVpnCommandResult> _stopVpn() async {
    if (AppPlatform.isLinux) {
      return LinuxFfiApi().stopVpn();
    } else if (AppPlatform.isWindows) {
      return WindowsFfiApi().stopVpn();
    } else {
      return _api.stopVpn();
    }
  }

  String get tunFilesDir => _tunFilesDir;

  Future<List<int>> getFreePorts(int num, {List<int>? excludePorts}) async {
    try {
      final resp = await _invoke(
        LibXrayInvokeRequest(
          method: LibXrayMethod.getFreePorts,
          payload: GetFreePortsRequest(
            num,
            excludePorts: excludePorts,
          ).toJson(),
        ),
      );
      if (resp.success && resp.data != null) {
        final ports = GetFreePortsResponse.fromJson(resp.data!).ports;
        if (ports != null &&
            ports.length == num &&
            ports.toSet().length == num &&
            ports.every(
              (port) =>
                  port > 0 &&
                  port <= 65535 &&
                  !(excludePorts?.contains(port) ?? false),
            )) {
          return ports;
        }
      }
      throw LibXrayInvokeException(
        resp.error.isEmpty ? 'Invalid free ports response' : resp.error,
      );
    } catch (error, stackTrace) {
      _reportUnexpected('getFreePorts', error, stackTrace);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> convertShareLinksToXrayJson(
    String text, {
    String? ageSecretKey,
  }) async {
    final key = ageSecretKey?.trim();
    final response = await _invoke(
      LibXrayInvokeRequest(
        method: LibXrayMethod.convertShareLinksToXrayJson,
        payload: ConvertShareLinksToXrayJsonRequest(
          text,
          age: key == null || key.isEmpty ? null : AgeDecryptConfig(key),
        ).toJson(),
      ),
    );
    final data = response.data;
    if (!response.success || data == null) {
      throw LibXrayInvokeException(response.error);
    }
    final outbounds = data['outbounds'];
    if (outbounds is! List ||
        outbounds.any((value) => value is! Map<String, dynamic>)) {
      throw const FormatException('Invalid import outbounds');
    }
    return outbounds.cast<Map<String, dynamic>>();
  }

  Future<String> decodeSubscriptionText(
    String text, {
    String? ageSecretKey,
  }) async {
    final key = ageSecretKey?.trim();
    final response = await _invoke(
      LibXrayInvokeRequest(
        method: LibXrayMethod.decodeSubscriptionText,
        payload: DecodeSubscriptionTextRequest(
          text,
          age: key == null || key.isEmpty ? null : AgeDecryptConfig(key),
        ).toJson(),
      ),
    );
    final data = response.data;
    if (!response.success || data == null) {
      throw LibXrayInvokeException(response.error);
    }
    if (data['text'] is! String) {
      throw const FormatException('Invalid decoded subscription text');
    }
    return DecodeSubscriptionTextResponse.fromJson(data).text;
  }

  Future<GenerateAgeKeyPairResponse> generateAgeKeyPair({
    AgeKeyType keyType = AgeKeyType.x25519,
  }) async {
    final resp = await _invoke(
      LibXrayInvokeRequest(
        method: LibXrayMethod.generateAgeKeyPair,
        payload: GenerateAgeKeyPairRequest(keyType).toJson(),
      ),
    );
    if (resp.success && resp.data != null) {
      final response = GenerateAgeKeyPairResponse.fromJson(resp.data!);
      if ((response.secretKey?.isNotEmpty ?? false) &&
          (response.publicKey?.isNotEmpty ?? false)) {
        return response;
      }
    }
    throw LibXrayInvokeException(resp.error);
  }

  Future<String> convertXrayJsonToShareLinks(
    Map<String, dynamic> xrayJson,
  ) async {
    try {
      final xrayJsonText = JsonTool.encoder.convert(xrayJson);
      final resp = await _invoke(
        LibXrayInvokeRequest(
          method: LibXrayMethod.convertXrayJsonToShareLinks,
          payload: ConvertXrayJsonToShareLinksRequest(xrayJsonText).toJson(),
        ),
      );
      if (resp.data != null) {
        if (resp.success) {
          final data = ConvertXrayJsonToShareLinksResponse.fromJson(resp.data!);
          return data.links ?? "";
        }
      }
      throw LibXrayInvokeException(resp.error);
    } catch (error, stackTrace) {
      _reportUnexpected('convertXrayJsonToShareLinks', error, stackTrace);
      rethrow;
    }
  }

  Future<String> countGeoData(CountGeoDataRequest request) async {
    try {
      final resp = await _invoke(
        LibXrayInvokeRequest(
          method: LibXrayMethod.countGeoData,
          payload: request.toJson(),
        ),
      );
      if (resp.success) {
        return "";
      }
      return resp.error;
    } catch (error, stackTrace) {
      _reportUnexpected('countGeoData', error, stackTrace);
      rethrow;
    }
  }

  Future<PingBatchResponse?> pingBatch(PingBatchRequest request) async {
    try {
      final resp = await _invoke(
        LibXrayInvokeRequest(
          method: LibXrayMethod.pingBatch,
          payload: request.toJson(),
        ),
      );
      ygLogger("pingBatch result success:${resp.success} error:${resp.error}");
      if (resp.success && resp.data != null) {
        return PingBatchResponse.fromJson(resp.data!);
      }
      throw LibXrayInvokeException(resp.error);
    } catch (error, stackTrace) {
      _reportUnexpected('pingBatch', error, stackTrace);
      rethrow;
    }
  }

  Future<String> testXray(String xrayJson) async {
    try {
      final resp = await _invoke(
        LibXrayInvokeRequest(
          method: LibXrayMethod.testXray,
          payload: TestXrayRequest(xrayJson).toJson(),
        ),
      );
      if (resp.success) {
        return "";
      }
      return resp.error;
    } catch (error, stackTrace) {
      _reportUnexpected('testXray', error, stackTrace);
      rethrow;
    }
  }

  Future<String> xrayVersion() async {
    try {
      final resp = await _invoke(
        LibXrayInvokeRequest(method: LibXrayMethod.xrayVersion),
      );
      if (resp.data != null) {
        if (resp.success) {
          return XrayVersionResponse.fromJson(resp.data!).version ?? "";
        }
      }
    } catch (error, stackTrace) {
      _reportUnexpected('xrayVersion', error, stackTrace);
    }
    return "";
  }

  Future<LibXrayInvokeResponse> _invoke(LibXrayInvokeRequest request) async {
    final requestJson = JsonTool.encoder.convert(request.toJson());
    LibXrayInvokeLimits.validate(requestJson, "request");
    late final String responseJson;
    if (AppPlatform.isLinux) {
      responseJson = await LinuxFfiApi().invoke(requestJson);
    } else if (AppPlatform.isWindows) {
      responseJson = await WindowsFfiApi().invoke(requestJson);
    } else {
      responseJson = await _api.invoke(requestJson);
    }
    LibXrayInvokeLimits.validate(responseJson, "response");
    final response = LibXrayInvokeResponseParser.parse(responseJson);
    if (!response.success) {
      ygLogger(
        "libXray ${request.method?.name ?? 'unknown'} failed: ${response.error}",
      );
    }
    return response;
  }

  Future<PlatformPermissionResult> queryPlatformPermission() async {
    if (AppPlatform.isLinux || AppPlatform.isWindows) {
      return _platformPermissionNotRequired();
    }
    try {
      return await _api.queryPlatformPermission();
    } catch (error, stackTrace) {
      _reportUnexpected('queryPlatformPermission', error, stackTrace);
      return _platformPermissionFailed(failureDetails(error));
    }
  }

  Future<PlatformPermissionResult> requestPlatformPermission() async {
    if (AppPlatform.isLinux || AppPlatform.isWindows) {
      return _platformPermissionNotRequired();
    }
    try {
      final permission = await _api.requestPlatformPermission();
      if (permission.kind != PlatformPermissionKind.androidLocalNetwork) {
        return permission;
      }
      if (await Permission.accessLocalNetwork.isPermanentlyDenied) {
        await openAppSettings();
        return permission;
      }
      final status = await Permission.accessLocalNetwork.request();
      if (!status.isGranted) {
        return PlatformPermissionResult(
          kind: PlatformPermissionKind.androidLocalNetwork,
          state: PlatformPermissionState.denied,
        );
      }
      return await _api.queryPlatformPermission();
    } catch (error, stackTrace) {
      _reportUnexpected('requestPlatformPermission', error, stackTrace);
      return _platformPermissionFailed(failureDetails(error));
    }
  }

  Future<List<AndroidAppInfo>> getInstalledApps() async {
    if (AppPlatform.isAndroid) {
      try {
        final result = await _api.getInstalledApps();
        return result;
      } catch (error, stackTrace) {
        _reportUnexpected('getInstalledApps', error, stackTrace);
        rethrow;
      }
    }
    return [];
  }

  Future<Uint8List?> getAppIcon(String packageName) async {
    if (AppPlatform.isAndroid) {
      try {
        return await _api.getAppIcon(packageName);
      } catch (error, stackTrace) {
        _reportUnexpected('getAppIcon', error, stackTrace);
      }
    }
    return null;
  }

  // macOS
  Future<bool> useSystemExtension() async {
    if (AppPlatform.isMacOS) {
      return await _api.useSystemExtension();
    } else {
      return false;
    }
  }

  // Apple app icon
  Future<bool> setAppIcon(String appIcon) async {
    if (AppPlatform.isIOS || AppPlatform.isMacOS) {
      try {
        return await _api.setAppIcon(appIcon);
      } catch (error, stackTrace) {
        _reportUnexpected('setAppIcon', error, stackTrace);
        rethrow;
      }
    }
    return false;
  }

  Future<String> getCurrentAppIcon() async {
    if (AppPlatform.isIOS || AppPlatform.isMacOS) {
      try {
        return await _api.getCurrentAppIcon();
      } catch (error, stackTrace) {
        _reportUnexpected('getCurrentAppIcon', error, stackTrace);
      }
    }
    return "";
  }

  PlatformPermissionResult _platformPermissionNotRequired() {
    return PlatformPermissionResult(
      kind: PlatformPermissionKind.none,
      state: PlatformPermissionState.notRequired,
    );
  }

  PlatformPermissionResult _platformPermissionFailed([String? message]) {
    return PlatformPermissionResult(
      kind: PlatformPermissionKind.none,
      state: PlatformPermissionState.failed,
      message: message,
    );
  }

  NativeVpnCommandResult _commandFailed([String? message]) {
    return NativeVpnCommandResult(
      state: NativeVpnCommandState.failed,
      permission: _platformPermissionFailed(),
      message: message,
    );
  }

  void _reportUnexpected(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    // Native parser errors can contain the offending JSON or credentials.
    ygLogger(
      'AppHostApi.$operation failed (${error.runtimeType})\n$stackTrace',
    );
  }
}
