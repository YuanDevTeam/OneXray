import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';

void main() {
  test(
    'Settings commands are transient events independent of VPN status',
    () async {
      final api = AppFlutterApi();
      await api.openSettings();
      var settingsRequests = 0;
      final statuses = <VpnStatus>[];
      final settingsSubscription = api.openSettingsController.stream.listen(
        (_) => settingsRequests++,
      );
      final statusSubscription = api.vpnStatusController.stream.listen(
        statuses.add,
      );
      addTearDown(settingsSubscription.cancel);
      addTearDown(statusSubscription.cancel);

      await api.openSettings();
      expect(settingsRequests, 1);
      expect(statuses, isEmpty);
      await settingsSubscription.cancel();
      await api.openSettings();
      expect(settingsRequests, 1);
    },
  );

  test(
    'unchanged native replies still broadcast without repeating logs',
    () async {
      final api = AppFlutterApi();
      await api.vpnStatusChanged(VpnStatus.disconnected);
      final messages = <String?>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => messages.add(message);
      addTearDown(() => debugPrint = previousDebugPrint);
      final statuses = <VpnStatus>[];
      final statusSubscription = api.vpnStatusController.stream.listen(
        statuses.add,
      );
      addTearDown(statusSubscription.cancel);

      await api.vpnStatusChanged(VpnStatus.connected);
      await api.vpnStatusChanged(VpnStatus.connected);
      await api.vpnStatusChanged(VpnStatus.disconnected);
      await api.vpnStatusChanged(VpnStatus.disconnected);
      await Future<void>.delayed(Duration.zero);

      expect(statuses, [
        VpnStatus.connected,
        VpnStatus.connected,
        VpnStatus.disconnected,
        VpnStatus.disconnected,
      ]);
      expect(messages, [
        'vpnStatusChanged connected',
        'vpnStatusChanged disconnected',
      ]);
    },
  );
}
