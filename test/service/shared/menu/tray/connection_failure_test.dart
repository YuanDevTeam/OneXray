import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/failure.dart';
import 'package:onexray/service/connect/platform_requirements.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/menu/tray/service.dart';
import 'package:onexray/service/shared/menu/tray/entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppEventBus();

  test(
    'tray reports empty servers without opening the window or starting VPN',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final resolver = ConnectionResolver(
        rows: db.coreConfigDao.watchOutbounds,
      );
      var starts = 0;
      final coordinator = ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
        prepare: (configuration, cancelled) async {
          await resolver.resolve(
            configuration.connection,
            cancelled: cancelled,
          );
          throw StateError('Empty servers must fail resolution');
        },
        start: (_) async {
          starts++;
          throw StateError('Empty servers must not start VPN');
        },
      );
      addTearDown(coordinator.dispose);
      await coordinator.initialize(observe: false, registerReferences: false);
      final notifications = <String>[];
      var shown = 0;
      final tray = TrayService.forTesting(
        connect: coordinator.connect,
        notify: (message) async => notifications.add(message),
        showMainWindow: () async => shown++,
      );

      await tray.onMenuAction(TrayMenuEntry(key: 'startVpn'));

      final l = appLocalizationsNoContext();
      expect(
        (starts, coordinator.state.value.issue, shown),
        (0, 'selectionUnavailable', 0),
      );
      expect(notifications, [
        '${l.prototypeNoAvailableEntries} · ${l.prototypeAddServers}',
      ]);
      expect(
        coordinator.state.value.error,
        isA<ConnectionResolutionException>(),
      );
      await coordinator.refresh();
      expect(coordinator.state.value.issue, 'selectionUnavailable');
      expect(
        coordinator.state.value.error,
        isA<ConnectionResolutionException>(),
      );
    },
  );

  for (final reason in [
    ConnectionResolutionFailure.insufficientCandidates,
    ConnectionResolutionFailure.insufficientCandidates,
  ]) {
    test(
      'tray notifies counts without taking focus for ${reason.name}',
      () async {
        final notifications = <String>[];
        var shown = 0;
        final tray = TrayService.forTesting(
          connect: () async => throw ConnectionResolutionException(
            reason,
            requiredCount: 3,
            availableCount: 1,
          ),
          notify: (message) async => notifications.add(message),
          showMainWindow: () async => shown++,
        );
        await tray.onMenuAction(TrayMenuEntry(key: 'startVpn'));
        expect(notifications, [
          '${appLocalizationsNoContext().prototypeNotEnoughServers} (1/3)',
        ]);
        expect(shown, 0);
      },
    );
  }

  for (final error in [
    const ConnectionHostException('permissionRequired'),
    const ConnectionPlatformRequirementException(
      ConnectionPlatformRequirementFailure.outboundInterfaceRequired,
    ),
    const ConnectionPlatformRequirementException(
      ConnectionPlatformRequirementFailure.outboundInterfaceUnavailable,
    ),
    const ConnectionHostException('startFailed'),
  ]) {
    test(
      'tray still shows recoverable host/interface errors: ${connectionFailureReason(error)}',
      () async {
        final notifications = <String>[];
        var shown = 0;
        final tray = TrayService.forTesting(
          connect: () async => throw error,
          notify: (message) async => notifications.add(message),
          showMainWindow: () async => shown++,
        );
        await tray.onMenuAction(TrayMenuEntry(key: 'startVpn'));
        final l = appLocalizationsNoContext();
        final message = error is ConnectionPlatformRequirementException
            ? l.prototypeChooseInterfaceNotice
            : error is ConnectionHostException &&
                  error.reason == 'permissionRequired'
            ? l.prototypeVpnPermissionRequired
            : l.prototypeConnectionFailed;
        expect(notifications, [message]);
        expect(shown, 1);
      },
    );
  }

  for (final error in [
    const ConnectionHostException('cancelled'),
    const ConnectionResolutionException(ConnectionResolutionFailure.cancelled),
    null,
  ]) {
    test(
      'tray success/cancellation does not notify or take focus: $error',
      () async {
        var notifications = 0;
        var shown = 0;
        final tray = TrayService.forTesting(
          connect: () async {
            if (error != null) throw error;
          },
          notify: (_) async => notifications++,
          showMainWindow: () async => shown++,
        );
        await tray.onMenuAction(TrayMenuEntry(key: 'startVpn'));
        expect(notifications, 0);
        expect(shown, 0);
      },
    );
  }

  test('notification failure does not turn an empty selection into a window action', () async {
    var notifications = 0;
    var shown = 0;
    final tray = TrayService.forTesting(
      connect: () async => throw const ConnectionResolutionException(
        ConnectionResolutionFailure.selectionUnavailable,
      ),
      notify: (_) async {
        notifications++;
        throw StateError('Notifications unavailable');
      },
      showMainWindow: () async => shown++,
    );
    await tray.onMenuAction(TrayMenuEntry(key: 'startVpn'));
    expect(notifications, 1);
    expect(shown, 0);
  });

  test(
    'notification failure still opens the window for required permission',
    () async {
      var shown = 0;
      final tray = TrayService.forTesting(
        connect: () async =>
            throw const ConnectionHostException('permissionRequired'),
        notify: (_) async => throw StateError('Notifications unavailable'),
        showMainWindow: () async => shown++,
      );
      await tray.onMenuAction(TrayMenuEntry(key: 'startVpn'));
      expect(shown, 1);
    },
  );
}
