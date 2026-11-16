import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/tunnel/apple/removal.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late ConnectionConfiguration configuration;
  late HostConnection host;
  late PrepareConnection prepare;
  late Future<HostConnection> Function() stop;
  late Future<AppleVpnRemovalResult> Function() remove;
  late int stops;
  late int starts;
  late int removals;
  late int permissionRequests;

  AppleVpnRemovalService service({
    ConnectionPlatform platform = ConnectionPlatform.macos,
    Future<bool> Function()? useSystemExtension,
  }) => AppleVpnRemovalService(
    coordinator: coordinator,
    platform: platform,
    useSystemExtension: useSystemExtension ?? () async => false,
    remove: () async {
      removals++;
      return remove();
    },
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final serverId = await db.coreConfigDao.insertRow(
      CoreConfigCompanion.insert(
        name: 'Saved server',
        type: CoreConfigType.outbound.name,
        tags: 'personal',
        delay: 42,
        subId: 0,
        favorite: const Value(true),
        data: Value(base64Encode(utf8.encode('{"protocol":"freedom"}'))),
      ),
    );
    configuration = ConnectionConfiguration(
      connection: ConnectionSettings(
        selection: ServerSelection.server(serverId),
        trafficMode: TrafficMode.allVpn,
      ),
      policy: PlatformPolicy.fromJson({
        'dnsIpv4Address': '1.1.1.1',
        'apple': {
          'onDemandEnabled': true,
          'connectWifiSsids': ['Saved Wi-Fi'],
        },
      }),
    );
    await db.connectionConfigDao.commit(
      configurationJson: configuration.encode(),
    );
    host = HostConnection(
      VpnStatus.connected,
      runtime: _runtime(configuration, serverId),
      permission: PlatformPermissionResult(
        kind: PlatformPermissionKind.macosSystemExtension,
        state: PlatformPermissionState.granted,
      ),
    );
    stops = 0;
    starts = 0;
    removals = 0;
    permissionRequests = 0;
    prepare = (_, _) async => throw StateError('Unexpected preparation');
    stop = () async {
      stops++;
      return host = const HostConnection(VpnStatus.disconnected);
    };
    remove = () async => AppleVpnRemovalResult.removed;
    coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => host.runtime,
      inspect: (_, {observedStatus}) async => host,
      prepare: (next, cancelled) => prepare(next, cancelled),
      start: (runtime) async {
        starts++;
        return host = HostConnection(VpnStatus.connected, runtime: runtime);
      },
      stop: () => stop(),
      probe: (_) async => null,
    );
    addTearDown(() async {
      coordinator.dispose();
      await db.close();
    });
    await coordinator.initialize(
      observe: false,
      registerReferences: false,
      requestPermission: () async {
        permissionRequests++;
        return PlatformPermissionResult(
          kind: PlatformPermissionKind.macosSystemExtension,
          state: PlatformPermissionState.granted,
        );
      },
    );
  });

  test('only macOS asks whether the system extension is used', () async {
    var queries = 0;
    Future<bool> useSystemExtension() async {
      queries++;
      return true;
    }

    expect(
      await service(useSystemExtension: useSystemExtension)
          .useSystemExtension(),
      isTrue,
    );
    expect(
      await service(
        platform: ConnectionPlatform.ios,
        useSystemExtension: useSystemExtension,
      ).useSystemExtension(),
      isFalse,
    );
    expect(queries, 1);
  });

  test('unsupported platforms leave the VPN and saved data intact', () async {
    final saved = await _savedData(db);
    for (final platform in [
      ConnectionPlatform.android,
      ConnectionPlatform.windows,
      ConnectionPlatform.linux,
    ]) {
      await expectLater(
        service(platform: platform).remove(),
        throwsUnsupportedError,
      );
    }
    expect(stops, 0);
    expect(removals, 0);
    expect(coordinator.state.value.phase, ConnectionPhase.connected);
    expect(await _savedData(db), saved);
  });

  for (final nativeState in [
    NativeVpnCommandState.failed,
    NativeVpnCommandState.success,
  ]) {
    test('a $nativeState stop without confirmation prevents removal', () async {
      final saved = await _savedData(db);
      final runtimeHost = ConnectionRuntimeHost(
        stopVpn: () async => NativeVpnCommandResult(
          state: nativeState,
          status: VpnStatus.connected,
        ),
      );
      stop = runtimeHost.stop;

      await expectLater(
        service().remove(),
        throwsA(
          isA<ConnectionHostException>().having(
            (error) => error.reason,
            'reason',
            nativeState == NativeVpnCommandState.failed
                ? 'stopFailed'
                : 'stopNotConfirmed',
          ),
        ),
      );

      expect(removals, 0);
      expect(coordinator.state.value.phase, ConnectionPhase.failed);
      expect(coordinator.state.value.runtime, same(host.runtime));
      expect(await _savedData(db), saved);
    });
  }

  for (final (platform, result, permissionKind) in [
    (
      ConnectionPlatform.ios,
      AppleVpnRemovalResult.removed,
      PlatformPermissionKind.appleVpn,
    ),
    (
      ConnectionPlatform.macos,
      AppleVpnRemovalResult.restartRequired,
      PlatformPermissionKind.macosSystemExtension,
    ),
  ]) {
    test(
      '$result preserves servers and settings and reconciles permission',
      () async {
        final saved = await _savedData(db);
        final missingPermission = PlatformPermissionResult(
          kind: permissionKind,
          state: PlatformPermissionState.notDetermined,
        );
        remove = () async {
          expect(host.status, VpnStatus.disconnected);
          host = HostConnection(
            VpnStatus.disconnected,
            permission: missingPermission,
          );
          return result;
        };

        expect(await service(platform: platform).remove(), result);

        expect(stops, 1);
        expect(starts, 0);
        expect(removals, 1);
        expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
        expect(coordinator.state.value.runtime, isNull);
        expect(coordinator.state.value.issue, 'permissionRequired');
        expect(coordinator.state.value.permission, same(missingPermission));
        expect(permissionRequests, 0);
        expect(await _savedData(db), saved);
      },
    );
  }

  test('a native removal error preserves data and allows a retry', () async {
    final saved = await _savedData(db);
    final failure = PlatformException(code: 'remove-failed');
    remove = () async => throw failure;
    final removalService = service();

    await expectLater(removalService.remove(), throwsA(same(failure)));

    expect(host.status, VpnStatus.disconnected);
    expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
    expect(coordinator.state.value.busy, isFalse);
    expect(await _savedData(db), saved);

    remove = () async => AppleVpnRemovalResult.removed;
    expect(await removalService.remove(), AppleVpnRemovalResult.removed);
    expect(stops, 2);
    expect(removals, 2);
    expect(starts, 0);
    expect(await _savedData(db), saved);
  });

  test(
    'removal stays busy and shares command ordering with saved edits',
    () async {
      final firstEditEntered = Completer<void>();
      final finishFirstEdit = Completer<void>();
      final removalEntered = Completer<void>();
      final finishRemoval = Completer<void>();
      addTearDown(() {
        if (!finishFirstEdit.isCompleted) finishFirstEdit.complete();
        if (!finishRemoval.isCompleted) finishRemoval.complete();
      });
      final events = <String>[];
      final initialStop = stop;
      stop = () async {
        events.add('stop');
        return initialStop();
      };
      remove = () async {
        events.add('remove-enter');
        removalEntered.complete();
        await finishRemoval.future;
        events.add('remove-exit');
        return AppleVpnRemovalResult.removed;
      };
      final firstEdit = coordinator.apply(
        configuration,
        affectsRuntime: false,
        validateAssets: () async {
          events.add('first-edit-enter');
          firstEditEntered.complete();
          await finishFirstEdit.future;
          events.add('first-edit-exit');
        },
      );
      await firstEditEntered.future;
      final removalService = service();
      final removing = removalService.remove();
      final next = ConnectionConfiguration(
        connection: configuration.connection,
        policy: PlatformPolicy.fromJson({
          ...configuration.policy.toJson(),
          'dnsIpv4Address': '9.9.9.9',
        }),
      );
      final nextEdit = coordinator.apply(
        next,
        affectsRuntime: false,
        writeAssets: () async => events.add('next-edit'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, ['first-edit-enter']);
      expect(removals, 0);

      finishFirstEdit.complete();
      await firstEdit;
      await removalEntered.future;
      expect(events, [
        'first-edit-enter',
        'first-edit-exit',
        'stop',
        'remove-enter',
      ]);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnecting);
      expect(coordinator.state.value.busy, isTrue);
      await coordinator.refresh(observedStatus: VpnStatus.disconnected);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnecting);
      expect(
        (await coordinator.configuration).encode(),
        configuration.encode(),
      );
      await expectLater(removalService.remove(), throwsStateError);
      expect(removals, 1);

      finishRemoval.complete();
      expect(await removing, AppleVpnRemovalResult.removed);
      await nextEdit;
      expect(events, [
        'first-edit-enter',
        'first-edit-exit',
        'stop',
        'remove-enter',
        'remove-exit',
        'next-edit',
      ]);
      expect((await coordinator.configuration).encode(), next.encode());
      expect(coordinator.state.value.busy, isFalse);
      expect(starts, 0);
    },
  );

  test(
    'removal cancels preparation before stopping and never starts it',
    () async {
      final saved = await _savedData(db);
      final prepared = Completer<void>();
      final wasCancelled = Completer<void>();
      host = const HostConnection(VpnStatus.disconnected);
      await coordinator.refresh();
      prepare = (next, cancelled) async {
        prepared.complete();
        await cancelled;
        wasCancelled.complete();
        return _runtime(next, next.connection.selection.id!);
      };
      final connecting = coordinator.apply(configuration, connect: true);
      final connectionResult = expectLater(
        connecting,
        throwsA(
          isA<ConnectionHostException>().having(
            (error) => error.reason,
            'reason',
            'cancelled',
          ),
        ),
      );
      await prepared.future;
      remove = () async {
        expect(wasCancelled.isCompleted, isTrue);
        expect(host.status, VpnStatus.disconnected);
        return AppleVpnRemovalResult.removed;
      };

      expect(await service().remove(), AppleVpnRemovalResult.removed);
      await connectionResult;

      expect(starts, 0);
      expect(stops, 1);
      expect(removals, 1);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(await _savedData(db), saved);
    },
  );
}

Future<Map<String, Object?>> _savedData(AppDatabase db) async => {
  'configuration': (await db.connectionConfigDao.read()).configurationJson,
  'servers': [
    for (final row in await db.select(db.coreConfig).get()) row.toJson(),
  ],
};

ConnectionRuntime _runtime(
  ConnectionConfiguration configuration,
  int serverId,
) {
  const text = '{"outbounds":[{"protocol":"freedom","tag":"saved-server"}]}';
  return ConnectionRuntime.create(
    configuration: configuration,
    compiled: CompiledConnection(
      xrayJson: text,
      entries: [
        ResolvedServer(
          id: serverId,
          sourceId: 0,
          outbound: {'protocol': 'freedom', 'tag': 'saved-server'},
        ),
      ],
      finalExit: null,
      nodeTags: const {},
    ),
    platform: ConnectionPlatform.macos,
    request: StartVpnRequest(
      configuration.policy.toTun(ConnectionPlatform.macos),
      null,
      '18003',
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(text).toJson(),
        ).toJson(),
      ),
    ),
  );
}
