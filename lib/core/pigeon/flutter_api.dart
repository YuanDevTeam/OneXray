import 'dart:async';

import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';

class AppFlutterApi extends BridgeFlutterApi {
  static final AppFlutterApi _singleton = AppFlutterApi._internal();

  factory AppFlutterApi() => _singleton;

  AppFlutterApi._internal();

  final vpnStatusController = StreamController<VpnStatus>.broadcast();
  final openSettingsController = StreamController<void>.broadcast(sync: true);
  final appleWidgetActions = StreamController<void>.broadcast(sync: true);
  VpnStatus? _lastLoggedVpnStatus;

  @override
  Future<void> vpnStatusChanged(VpnStatus status) async {
    if (_lastLoggedVpnStatus != status) {
      ygLogger("vpnStatusChanged ${status.name}");
      _lastLoggedVpnStatus = status;
    }
    vpnStatusController.add(status);
  }

  @override
  Future<void> appleWidgetActionAvailable() async {
    appleWidgetActions.add(null);
  }

  @override
  Future<void> openSettings() async {
    openSettingsController.add(null);
  }
}
