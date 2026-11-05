import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/platform.dart';

/// Device authorization only; VPN lifecycle remains entirely native.
class AndroidAutomationService {
  AndroidAutomationService({
    AndroidAutomationHostApi? api,
    bool? supported,
    AppleWidgetHostApi? appleApi,
    bool? supportedIOS,
  }) : _api = api ?? AndroidAutomationHostApi(),
       _supported = supported ?? AppPlatform.isAndroid,
       _appleApi = appleApi ?? AppleWidgetHostApi(),
       _supportedIOS = supportedIOS ?? AppPlatform.isIOS;

  final AndroidAutomationHostApi _api;
  final bool _supported;
  final AppleWidgetHostApi _appleApi;
  final bool _supportedIOS;

  static const packageName = 'net.yuandev.onexray';
  static const receiver = '$packageName.automation.VpnAutomationReceiver';
  static const startAction = '$packageName.action.START_VPN';
  static const stopAction = '$packageName.action.STOP_VPN';
  static const parameters =
      'Target: Broadcast Receiver\n'
      'Package: $packageName\nClass: $receiver\n'
      'START: $startAction\nSTOP: $stopAction\nExtra: token (String)';

  Future<AndroidAutomationSettings> read() => _api.read();
  Future<AndroidAutomationSettings> setEnabled(bool enabled) =>
      _api.setEnabled(enabled);
  Future<AndroidAutomationSettings> resetToken() => _api.resetToken();

  Future<void> setStartBlocked(bool blocked) async {
    if (_supported) {
      await _api.setStartBlocked(blocked);
    } else if (_supportedIOS) {
      await _appleApi.setStartBlocked(blocked);
    }
  }

  Future<void> clear() async {
    if (_supported) await _api.clear();
  }
}
