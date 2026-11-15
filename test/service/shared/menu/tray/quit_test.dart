import 'dart:async';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/menu/tray/entry.dart';
import 'package:onexray/service/shared/menu/tray/service.dart';

class _QuitTestBinding extends AutomatedTestWidgetsFlutterBinding {
  final actions = <String>[];

  @override
  Future<AppExitResponse> exitApplication(
    AppExitType exitType, [
    int exitCode = 0,
  ]) async {
    expect(exitType, AppExitType.cancelable);
    expect(exitCode, 0);
    actions.add('exit');
    return AppExitResponse.cancel;
  }
}

void main() {
  final binding = _QuitTestBinding();
  AppEventBus();

  final independentVpn =
      AppPlatform.isMacOS ||
      (AppPlatform.isWindows && windowsBuildMode == WindowsMode.msix);
  late ConnectionCoordinator coordinator;
  late TrayService tray;
  late Completer<void> stopping;
  late Completer<HostConnection> stopped;
  late VpnStatus status;
  ConnectionRuntime? runtime;
  final actions = binding.actions;

  Future<void> select(String key) => tray.onMenuAction(TrayMenuEntry(key: key));

  setUp(() async {
    actions.clear();
    status = VpnStatus.connected;
    runtime = null;
    stopping = Completer<void>();
    stopped = Completer<HostConnection>();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => runtime,
      inspect: (_, {observedStatus}) async => HostConnection(
        status,
        runtime: status == VpnStatus.disconnected ? null : runtime,
      ),
      stop: () async {
        actions.add('stop');
        stopping.complete();
        final result = await stopped.future;
        status = result.status;
        actions.add('stopped');
        return result;
      },
    );
    addTearDown(coordinator.dispose);
    await coordinator.initialize(observe: false, registerReferences: false);
    tray = TrayService.forTesting(
      coordinator: coordinator,
      connect: () async => fail('Quit must not start VPN'),
      notify: (_) async => fail('Quit must not send a connection notification'),
      showMainWindow: () async => actions.add('showWindow'),
    );
  });

  for (final key in ['quitAndStopVpn', if (!independentVpn) 'quitApp']) {
    test('$key exits only after VPN has stopped', () async {
      final quitting = select(key);
      await stopping.future.timeout(const Duration(seconds: 2));
      expect(actions, ['stop']);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnecting);

      stopped.complete(const HostConnection(VpnStatus.disconnected));
      await quitting;

      expect(actions, ['stop', 'stopped', 'exit']);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
    });

    test(
      '$key keeps the App running on stop failure and allows retry',
      () async {
        final quitting = select(key);
        await stopping.future.timeout(const Duration(seconds: 2));
        stopped.completeError(const ConnectionHostException('stopFailed'));
        await quitting;

        expect(actions, ['stop', 'showWindow']);
        expect(coordinator.state.value.phase, ConnectionPhase.failed);
        expect(coordinator.state.value.issue, 'stopFailed');
        expect(coordinator.state.value.canDisconnect, isTrue);

        stopping = Completer<void>();
        stopped = Completer<HostConnection>();
        final retrying = select(key);
        await stopping.future.timeout(const Duration(seconds: 2));
        expect(actions, ['stop', 'showWindow', 'stop']);
        stopped.complete(const HostConnection(VpnStatus.disconnected));
        await retrying;

        expect(actions, ['stop', 'showWindow', 'stop', 'stopped', 'exit']);
        expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
        expect(coordinator.state.value.issue, isNull);
      },
    );
  }

  test(
    'proxy Quit always stops its Core before exiting, including after failure',
    () async {
      runtime = _proxyRuntime();
      await coordinator.refresh();
      final quitting = select('quitApp');
      await stopping.future.timeout(const Duration(seconds: 2));
      expect(actions, ['stop']);
      stopped.completeError(const ConnectionHostException('stopFailed'));
      await quitting;
      expect(actions, ['stop', 'showWindow']);
      expect(coordinator.state.value.runtime?.isProxy, true);

      stopping = Completer<void>();
      stopped = Completer<HostConnection>();
      final retry = select('quitApp');
      await stopping.future.timeout(const Duration(seconds: 2));
      expect(actions, ['stop', 'showWindow', 'stop']);
      stopped.complete(const HostConnection(VpnStatus.disconnected));
      await retry;
      expect(actions, ['stop', 'showWindow', 'stop', 'stopped', 'exit']);
    },
  );

  if (independentVpn) {
    test('plain Quit exits without stopping the independent VPN', () async {
      await select('quitApp');

      expect(actions, ['exit']);
      expect(coordinator.state.value.phase, ConnectionPhase.connected);
    });
  }

  test('Stop VPN stops the connection without exiting the App', () async {
    final disconnecting = select('stopVpn');
    await stopping.future.timeout(const Duration(seconds: 2));
    expect(actions, ['stop']);
    stopped.complete(const HostConnection(VpnStatus.disconnected));
    await disconnecting;

    expect(actions, ['stop', 'stopped']);
    expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
  });
}

ConnectionRuntime _proxyRuntime() => ConnectionRuntime.create(
  configuration: ConnectionConfiguration(
    policy: PlatformPolicy.fromJson({'captureMode': 'proxy'}),
  ),
  compiled: CompiledConnection(
    xrayJson: '{}',
    entries: [],
    finalExit: null,
    nodeTags: {},
  ),
  platform: ConnectionPlatform.macos,
  request: StartVpnRequest(null, '10808', null, '{}', captureMode: 'proxy'),
);
