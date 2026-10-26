import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  test('a failed connection with retained runtime can still be stopped', () {
    expect(
      ConnectionView(
        phase: ConnectionPhase.failed,
        runtime: _runtime('a'),
      ).canDisconnect,
      isTrue,
    );
    expect(
      const ConnectionView(phase: ConnectionPhase.failed).canDisconnect,
      isFalse,
    );
    expect(
      const ConnectionView(
        phase: ConnectionPhase.failed,
        issue: 'stopFailed',
      ).canDisconnect,
      isTrue,
    );
  });

  test('reconciliation prefers start metadata and retains runtime if it disappears', () async {
    final first = _runtime('a');
    final next = _runtime('b', entryIds: const [2]);
    ConnectionRuntime? stored = first;
    final host = ConnectionRuntimeHost(
      readStatus: () async => VpnStatus.connected,
    );
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => stored,
        inspect: host.inspect,
      ),
    );
    expect(coordinator.state.value.runtime, same(first));
    stored = next;
    await coordinator.refresh();
    expect(coordinator.state.value.runtime, same(next));
    stored = null;
    await coordinator.refresh();
    expect(coordinator.state.value.runtime, same(next));
    expect((await coordinator.readReferences()).runningIds, {2});
  });

  test('initialization trusts native disconnected status', () async {
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
      ),
    );

    expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
    expect(coordinator.state.value.runtime, isNull);
  });

  test(
    'metrics require both a visible window and a visible connection page',
    () async {
      final runtime = _runtime('a');
      var status = VpnStatus.connected;
      var reads = 0;
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => runtime,
          inspect: (_, {observedStatus}) async =>
              HostConnection(status, runtime: runtime),
          readTraffic: (_) async {
            reads++;
            return ConnectionTraffic(
              uplink: reads * 100,
              downlink: reads * 300,
              sampledAtMs: reads * 1000,
            );
          },
        ),
      );
      await coordinator.refreshTraffic();
      expect(reads, 0);
      coordinator.setTrafficVisible(coordinator, true);
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
      await coordinator.refreshTraffic();
      expect(coordinator.state.value.downloadSpeed, 300);

      coordinator.didChangeAppLifecycleState(AppLifecycleState.hidden);
      coordinator.setTrafficVisible(coordinator, false);
      coordinator.setTrafficVisible(coordinator, true);
      await Future<void>.delayed(Duration.zero);
      await coordinator.refreshTraffic();
      expect(reads, 2, reason: 'A visible page cannot sample a hidden window.');

      coordinator.setTrafficVisible(coordinator, false);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await coordinator.refreshTraffic();
      expect(
        reads,
        2,
        reason: 'A visible window cannot sample without a visible page.',
      );

      coordinator.setTrafficVisible(coordinator, true);
      await Future<void>.delayed(Duration.zero);
      expect(reads, 3);
      expect(coordinator.state.value.uploadSpeed, 0);
      expect(coordinator.state.value.downloadSpeed, 0);
      await coordinator.refreshTraffic();
      expect(coordinator.state.value.downloadSpeed, 300);

      status = VpnStatus.disconnected;
      await coordinator.refresh();
      final disconnectedReads = reads;
      await coordinator.refreshTraffic();
      expect(reads, disconnectedReads);
      expect(coordinator.state.value.traffic, isNull);
    },
  );

  test(
    'metrics samples follow page visibility and reset the speed baseline',
    () async {
      final runtime = _runtime('a');
      var status = VpnStatus.connected;
      var reads = 0;
      var failing = false;
      var sample = const ConnectionTraffic(
        uplink: 100,
        downlink: 200,
        sampledAtMs: 1000,
      );
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => runtime,
          inspect: (_, {observedStatus}) async =>
              HostConnection(status, runtime: runtime),
          readTraffic: (_) async {
            reads++;
            if (failing) throw const FormatException('Unavailable metrics');
            return sample;
          },
        ),
      );
      expect(reads, 0);
      coordinator.setTrafficVisible(coordinator, true);
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
      expect(coordinator.state.value.traffic, sample);
      expect(coordinator.state.value.uploadSpeed, 0);

      sample = const ConnectionTraffic(
        uplink: 300,
        downlink: 700,
        sampledAtMs: 2000,
      );
      await coordinator.refreshTraffic();
      expect(coordinator.state.value.uploadSpeed, 200);
      expect(coordinator.state.value.downloadSpeed, 500);
      await coordinator.refresh();
      expect(coordinator.state.value.uploadSpeed, 200);

      coordinator.setTrafficVisible(coordinator, false);
      final hiddenReads = reads;
      await coordinator.refreshTraffic();
      expect(reads, hiddenReads);
      sample = const ConnectionTraffic(
        uplink: 9000,
        downlink: 10000,
        sampledAtMs: 90000,
      );
      coordinator.setTrafficVisible(coordinator, true);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.state.value.traffic, sample);
      expect(coordinator.state.value.uploadSpeed, 0);

      failing = true;
      await coordinator.refreshTraffic();
      expect(coordinator.state.value.phase, ConnectionPhase.connected);
      expect(coordinator.state.value.issue, isNull);
      expect(coordinator.state.value.traffic, sample);
      expect(coordinator.state.value.metricsAvailable, isFalse);
      failing = false;
      sample = const ConnectionTraffic(
        uplink: 9500,
        downlink: 10500,
        sampledAtMs: 91000,
      );
      await coordinator.refreshTraffic();
      expect(coordinator.state.value.uploadSpeed, 0);

      coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
      final backgroundReads = reads;
      await coordinator.refreshTraffic();
      expect(reads, backgroundReads);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.state.value.uploadSpeed, 0);
      status = VpnStatus.disconnected;
      await coordinator.refresh();
      expect(coordinator.state.value.traffic, isNull);
      expect(coordinator.state.value.metricsAvailable, isFalse);
    },
  );

  test('traffic sampling belongs to all visible connection pages', () async {
    final runtime = _runtime('a');
    var reads = 0;
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => runtime,
        inspect: (_, {observedStatus}) async =>
            HostConnection(VpnStatus.connected, runtime: runtime),
        readTraffic: (_) async {
          reads++;
          return ConnectionTraffic(
            uplink: reads * 100,
            downlink: reads * 200,
            sampledAtMs: reads * 1000,
          );
        },
      ),
    );
    final root = Object();
    final secondary = Object();
    coordinator.setTrafficVisible(root, true);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);

    coordinator.setTrafficVisible(root, true);
    coordinator.setTrafficVisible(secondary, true);
    coordinator.setTrafficVisible(root, false);
    coordinator.setTrafficVisible(root, false);
    await coordinator.refreshTraffic();
    expect(reads, 2);
    expect(coordinator.state.value.uploadSpeed, 100);
    expect(coordinator.state.value.downloadSpeed, 200);

    coordinator.setTrafficVisible(secondary, false);
    await coordinator.refreshTraffic();
    expect(reads, 2);
  });

  test(
    'focus changes preserve in-flight traffic and the speed baseline',
    () async {
      final runtime = _runtime('a');
      var reads = 0;
      Completer<ConnectionTraffic>? pending;
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => runtime,
          inspect: (_, {observedStatus}) async =>
              HostConnection(VpnStatus.connected, runtime: runtime),
          readTraffic: (_) async {
            reads++;
            return pending == null
                ? ConnectionTraffic(
                    uplink: reads * 100,
                    downlink: reads * 200,
                    sampledAtMs: reads * 1000,
                  )
                : await pending.future;
          },
        ),
      );
      coordinator.setTrafficVisible(coordinator, true);
      await Future<void>.delayed(Duration.zero);
      await coordinator.refreshTraffic();
      expect(coordinator.state.value.downloadSpeed, 200);

      pending = Completer<ConnectionTraffic>();
      final reading = coordinator.refreshTraffic();
      coordinator.didChangeAppLifecycleState(AppLifecycleState.inactive);
      pending.complete(
        const ConnectionTraffic(uplink: 300, downlink: 600, sampledAtMs: 3000),
      );
      await reading;
      pending = null;
      expect(coordinator.state.value.traffic!.downlink, 600);
      expect(coordinator.state.value.downloadSpeed, 200);

      await coordinator.refreshTraffic();
      expect(reads, 4);
      expect(coordinator.state.value.downloadSpeed, 200);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(
        reads,
        4,
        reason: 'Focus changes must not restart the sampling timer.',
      );
      await coordinator.refreshTraffic();
      expect(reads, 5);
      expect(coordinator.state.value.downloadSpeed, 200);
    },
  );

  testWidgets(
    'visible inactive windows retain traffic sampling without common status polling',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final runtime = _runtime('a');
      var statusReads = 0;
      var trafficReads = 0;
      final coordinator = ConnectionCoordinator(
        database: db,
        readRuntime: () async => runtime,
        inspect: (_, {observedStatus}) async {
          statusReads++;
          return HostConnection(VpnStatus.connected, runtime: runtime);
        },
        readTraffic: (_) async {
          trafficReads++;
          return ConnectionTraffic(
            uplink: trafficReads * 100,
            downlink: trafficReads * 200,
            sampledAtMs: trafficReads * 1000,
          );
        },
        observeStatus: () async {},
        statusEvents: const Stream.empty(),
      );
      try {
        await coordinator.initialize(registerReferences: false);
        coordinator.setTrafficVisible(coordinator, true);
        await tester.pump();
        expect(trafficReads, 1);
        final initialStatusReads = statusReads;
        await tester.pump(const Duration(seconds: 5));
        expect(statusReads, initialStatusReads);
        expect(trafficReads, greaterThan(1));

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        final hiddenStatusReads = statusReads;
        final hiddenTrafficReads = trafficReads;
        await tester.pump(const Duration(seconds: 5));
        await coordinator.refresh();
        await coordinator.refreshTraffic();
        expect(statusReads, hiddenStatusReads);
        expect(trafficReads, hiddenTrafficReads);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(statusReads, greaterThan(hiddenStatusReads));
        expect(trafficReads, greaterThan(hiddenTrafficReads));
        expect(coordinator.state.value.downloadSpeed, 0);
        final restoredStatusReads = statusReads;
        final restoredTrafficReads = trafficReads;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(
          statusReads,
          restoredStatusReads + 1,
          reason:
              'Reactivation still reconciles native status and permissions.',
        );
        expect(trafficReads, restoredTrafficReads);
        await tester.pump(const Duration(seconds: 1));
        expect(coordinator.state.value.downloadSpeed, 200);
      } finally {
        coordinator.dispose();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
    },
  );

  testWidgets('native notifications remain active when the window is hidden', (
    tester,
  ) async {
    final events = StreamController<VpnStatus>.broadcast(sync: true);
    final runtime = _runtime('observed');
    var reads = 0;
    var subscriptions = 0;
    var disposals = 0;
    final coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => runtime,
      inspect: ConnectionRuntimeHost(
        readStatus: () async {
          reads++;
          return VpnStatus.connected;
        },
      ).inspect,
      statusEvents: events.stream,
      observeStatus: () async {
        subscriptions++;
        expect(events.hasListener, isTrue);
      },
      disposeStatus: () => disposals++,
    );
    try {
      await coordinator.initialize(registerReferences: false);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.hidden);
      events.add(VpnStatus.disconnected);
      await tester.pump();
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(coordinator.state.value.runtime, isNull);
      await tester.pump(const Duration(seconds: 15));
      expect(
        reads,
        1,
        reason: 'A native event requires no extra platform query.',
      );
      expect(subscriptions, 1);
    } finally {
      coordinator.dispose();
      await events.close();
    }
    expect(disposals, 1);
  });

  test('connect does not trust the displayed connected state', () async {
    var current = const HostConnection(VpnStatus.disconnected);
    final runtime = _runtime('fresh');
    var starts = 0;
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => current.runtime,
        inspect: (_, {observedStatus}) async => current,
        prepare: (_, _) async => runtime,
        start: (runtime) async {
          starts++;
          return current = HostConnection(
            VpnStatus.connected,
            runtime: runtime,
          );
        },
      ),
    );
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: runtime,
    );
    await coordinator.connect();
    expect(starts, 1);
    // Conversely an idle-looking UI must not start a second running Core.
    coordinator.state.value = const ConnectionView();
    await coordinator.connect();
    expect(starts, 1);
    expect(coordinator.state.value.phase, ConnectionPhase.connected);
  });

  testWidgets('a same-state native notification clears a monitoring error', (
    tester,
  ) async {
    final events = StreamController<VpnStatus>.broadcast(sync: true);
    final runtime = _runtime('recovered');
    final coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => runtime,
      inspect: (_, {observedStatus}) async =>
          HostConnection(VpnStatus.connected, runtime: runtime),
      statusEvents: events.stream,
      observeStatus: () async {},
      disposeStatus: () {},
    );
    try {
      await coordinator.initialize(registerReferences: false);
      events.addError(StateError('Native monitoring failed'));
      await tester.pump();
      expect(coordinator.state.value.issue, 'runtimeUnavailable');
      events.add(VpnStatus.connected);
      await tester.pump();
      expect(coordinator.state.value.phase, ConnectionPhase.connected);
      expect(coordinator.state.value.issue, isNull);
    } finally {
      coordinator.dispose();
      await events.close();
    }
  });

  test(
    'read-only status and metrics do not enter the paused command queue',
    () async {
      final runtime = _runtime('a');
      var status = VpnStatus.connected;
      var reads = 0;
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => runtime,
          inspect: (_, {observedStatus}) async =>
              HostConnection(status, runtime: runtime),
          readTraffic: (_) async {
            reads++;
            return const ConnectionTraffic(
              uplink: 10,
              downlink: 20,
              sampledAtMs: 1000,
            );
          },
        ),
      );
      coordinator.setTrafficVisible(coordinator, true);
      await Future<void>.delayed(Duration.zero);
      final before = reads;
      await coordinator.pauseForDataClear();
      try {
        await coordinator.refreshTraffic();
        expect(reads, before + 1);
        status = VpnStatus.disconnected;
        await coordinator.refresh();
        expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
        expect(coordinator.state.value.issue, isNull);
      } finally {
        coordinator.resumeAfterDataClear();
      }
    },
  );

  test('clear-data stop ignores late status and metrics responses', () async {
    final runtime = _runtime('a');
    final traffic = Completer<ConnectionTraffic>();
    final statusReply = Completer<HostConnection>();
    var holdStatus = false;
    var host = HostConnection(VpnStatus.connected, runtime: runtime);
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => runtime,
        inspect: (_, {observedStatus}) =>
            holdStatus ? statusReply.future : Future.value(host),
        readTraffic: (_) => traffic.future,
        stop: () async => host = const HostConnection(VpnStatus.disconnected),
      ),
    );
    coordinator.setTrafficVisible(coordinator, true);
    await Future<void>.delayed(Duration.zero);
    holdStatus = true;
    final refresh = coordinator.refresh();
    await Future<void>.delayed(Duration.zero);
    holdStatus = false;
    await coordinator.pauseForDataClear();
    await coordinator.stopForMaintenance();
    coordinator.resumeAfterDataClear();
    traffic.complete(
      const ConnectionTraffic(uplink: 10, downlink: 20, sampledAtMs: 1000),
    );
    statusReply.complete(HostConnection(VpnStatus.connected, runtime: runtime));
    await refresh;
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
    expect(coordinator.state.value.traffic, isNull);
    expect(coordinator.state.value.runtime, isNull);
  });

  test('maintenance delegates simulator stops to the native host', () async {
    var stopCalls = 0;
    var statusFails = false;
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async {
          if (statusFails) {
            throw const ConnectionHostException('nativeStatusFailed');
          }
          return HostConnection(
            VpnStatus.disconnected,
            permission: PlatformPermissionResult(
              kind: PlatformPermissionKind.appleVpn,
              state: PlatformPermissionState.notRequired,
            ),
          );
        },
        stop: ConnectionRuntimeHost(
          readStatus: () async => VpnStatus.disconnected,
          stopVpn: () async {
            stopCalls++;
            return NativeVpnCommandResult(
              state: NativeVpnCommandState.success,
              status: VpnStatus.disconnected,
            );
          },
        ).stop,
      ),
    );

    await coordinator.stopForMaintenance();
    await coordinator.stopForMaintenance();

    expect(stopCalls, 2);
    expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
    expect(coordinator.state.value.issue, isNull);

    statusFails = true;
    await expectLater(
      coordinator.stopForMaintenance(),
      throwsA(isA<ConnectionHostException>()),
    );
    expect(coordinator.state.value.phase, ConnectionPhase.failed);

    statusFails = false;
    await coordinator.stopForMaintenance();

    expect(stopCalls, 3);
    expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
    expect(coordinator.state.value.issue, isNull);
  });

  for (final permission in [
    null,
    for (final state in PlatformPermissionState.values)
      if (state != PlatformPermissionState.notRequired)
        PlatformPermissionResult(
          kind: PlatformPermissionKind.appleVpn,
          state: state,
        ),
    PlatformPermissionResult(
      kind: PlatformPermissionKind.androidVpn,
      state: PlatformPermissionState.notRequired,
    ),
  ]) {
    test(
      'maintenance still stops a normal idle host (${permission?.kind.name}/${permission?.state.name})',
      () async {
        var stopCalls = 0;
        final coordinator = await _initialize(
          ConnectionCoordinator(
            database: db,
            readRuntime: () async => null,
            inspect: (_, {observedStatus}) async =>
                HostConnection(VpnStatus.disconnected, permission: permission),
            stop: () async {
              stopCalls++;
              return const HostConnection(VpnStatus.disconnected);
            },
          ),
        );

        await coordinator.stopForMaintenance();

        expect(stopCalls, 1);
        expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      },
    );
  }

  test('maintenance never ignores a running Debug core stop failure', () async {
    var stopCalls = 0;
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async => HostConnection(
          VpnStatus.connected,
          runtime: _runtime('a'),
          permission: PlatformPermissionResult(
            kind: PlatformPermissionKind.appleVpn,
            state: PlatformPermissionState.notRequired,
          ),
        ),
        stop: () async {
          stopCalls++;
          throw const ConnectionHostException('stopFailed');
        },
      ),
    );

    await expectLater(
      coordinator.stopForMaintenance(),
      throwsA(isA<ConnectionHostException>()),
    );

    expect(stopCalls, 1);
    expect(coordinator.state.value.phase, ConnectionPhase.failed);
    expect(coordinator.state.value.runtime, isNotNull);
    expect(coordinator.state.value.issue, 'stopFailed');
  });

  test('initialization exposes a missing platform permission', () async {
    final permission = PlatformPermissionResult(
      kind: PlatformPermissionKind.androidVpn,
      state: PlatformPermissionState.denied,
    );
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async =>
            HostConnection(VpnStatus.disconnected, permission: permission),
      ),
    );

    expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
    expect(coordinator.state.value.issue, 'permissionRequired');
    expect(coordinator.state.value.permission, permission);
  });

  for (final kind in [
    PlatformPermissionKind.appleVpn,
    PlatformPermissionKind.macosSystemExtension,
    PlatformPermissionKind.androidVpn,
    PlatformPermissionKind.androidLocalNetwork,
  ]) {
    test('home initialization requests $kind before becoming ready', () async {
      var permission = PlatformPermissionResult(
        kind: kind,
        state: PlatformPermissionState.notDetermined,
      );
      final calls = <String>[];
      final coordinator = ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async {
          calls.add('read');
          return HostConnection(VpnStatus.disconnected, permission: permission);
        },
        prepare: (_, _) async => fail('Authorization must not prepare nodes'),
        start: (_) async => fail('Authorization must not start VPN'),
        stop: () async => fail('Authorization must not stop VPN'),
      );
      addTearDown(coordinator.dispose);

      final requested = Completer<void>();
      final permissionReply = Completer<PlatformPermissionResult>();
      Future<PlatformPermissionResult> request() {
        calls.add('request');
        requested.complete();
        return permissionReply.future;
      }

      final first = coordinator.initialize(
        observe: false,
        registerReferences: false,
        requestPermission: request,
      );
      final second = coordinator.initialize(
        observe: false,
        registerReferences: false,
        requestPermission: request,
      );
      var ready = false;
      final initialization = Future.wait([first, second]).then((_) {
        ready = true;
      });
      await requested.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['read', 'request']);
      expect(ready, isFalse);

      permission = PlatformPermissionResult(
        kind: kind,
        state: PlatformPermissionState.granted,
      );
      permissionReply.complete(permission);
      await initialization;

      expect(calls, ['read', 'request', 'read']);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(coordinator.state.value.issue, isNull);
      expect(coordinator.state.value.permission, isNull);
    });
  }

  test(
    'home permission denial allows entry without repeated prompts',
    () async {
      var permission = PlatformPermissionResult(
        kind: PlatformPermissionKind.appleVpn,
        state: PlatformPermissionState.notDetermined,
      );
      var requests = 0;
      final coordinator = ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async =>
            HostConnection(VpnStatus.disconnected, permission: permission),
      );
      addTearDown(coordinator.dispose);

      Future<PlatformPermissionResult> request() async {
        requests++;
        permission = PlatformPermissionResult(
          kind: PlatformPermissionKind.appleVpn,
          state: PlatformPermissionState.denied,
        );
        return permission;
      }

      await coordinator.initialize(
        observe: false,
        registerReferences: false,
        requestPermission: request,
      );
      expect(requests, 1);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(coordinator.state.value.issue, 'permissionRequired');
      expect(
        coordinator.state.value.permission?.state,
        PlatformPermissionState.denied,
      );

      await coordinator.initialize(
        observe: false,
        registerReferences: false,
        requestPermission: request,
      );
      await coordinator.refresh();
      expect(requests, 1);
      expect(coordinator.state.value.issue, 'permissionRequired');

      permission = PlatformPermissionResult(
        kind: PlatformPermissionKind.appleVpn,
        state: PlatformPermissionState.granted,
      );
      await coordinator.refresh();
      expect(requests, 1);
      expect(coordinator.state.value.issue, isNull);
    },
  );

  for (final permission in <PlatformPermissionResult?>[
    null,
    PlatformPermissionResult(
      kind: PlatformPermissionKind.appleVpn,
      state: PlatformPermissionState.granted,
    ),
    PlatformPermissionResult(
      kind: PlatformPermissionKind.appleVpn,
      state: PlatformPermissionState.notRequired,
    ),
  ]) {
    test('home initialization skips permission ${permission?.state}', () async {
      var reads = 0;
      final coordinator = ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async {
          reads++;
          return HostConnection(VpnStatus.disconnected, permission: permission);
        },
      );
      addTearDown(coordinator.dispose);

      await coordinator.initialize(
        observe: false,
        registerReferences: false,
        requestPermission: () async => fail('Permission is already satisfied'),
      );
      expect(reads, 1);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(coordinator.state.value.issue, isNull);
    });
  }

  test(
    'startup and foreground refresh track local network permission',
    () async {
      var permission = PlatformPermissionResult(
        kind: PlatformPermissionKind.androidLocalNetwork,
        state: PlatformPermissionState.notDetermined,
      );
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => null,
          inspect: (_, {observedStatus}) async =>
              HostConnection(VpnStatus.disconnected, permission: permission),
        ),
      );
      expect(coordinator.state.value.issue, 'permissionRequired');
      expect(
        coordinator.state.value.permission?.kind,
        PlatformPermissionKind.androidLocalNetwork,
      );

      permission = PlatformPermissionResult(
        kind: PlatformPermissionKind.androidVpn,
        state: PlatformPermissionState.granted,
      );
      await coordinator.refresh();
      expect(coordinator.state.value.issue, isNull);

      permission = PlatformPermissionResult(
        kind: PlatformPermissionKind.androidLocalNetwork,
        state: PlatformPermissionState.denied,
      );
      await coordinator.refresh();
      expect(coordinator.state.value.issue, 'permissionRequired');
      expect(
        coordinator.state.value.permission?.kind,
        PlatformPermissionKind.androidLocalNetwork,
      );
    },
  );

  test(
    'foreground reconciliation clears a resolved permission issue',
    () async {
      var permission = PlatformPermissionResult(
        kind: PlatformPermissionKind.androidVpn,
        state: PlatformPermissionState.denied,
      );
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => null,
          inspect: (_, {observedStatus}) async =>
              HostConnection(VpnStatus.disconnected, permission: permission),
        ),
      );
      expect(coordinator.state.value.issue, 'permissionRequired');

      permission = PlatformPermissionResult(
        kind: PlatformPermissionKind.androidVpn,
        state: PlatformPermissionState.granted,
      );
      await coordinator.refresh();

      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(coordinator.state.value.issue, isNull);
      expect(coordinator.state.value.permission, isNull);
    },
  );

  test('foreground reconciliation exposes a revoked permission', () async {
    var permission = PlatformPermissionResult(
      kind: PlatformPermissionKind.appleVpn,
      state: PlatformPermissionState.granted,
    );
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async =>
            HostConnection(VpnStatus.disconnected, permission: permission),
      ),
    );
    expect(coordinator.state.value.issue, isNull);

    permission = PlatformPermissionResult(
      kind: PlatformPermissionKind.appleVpn,
      state: PlatformPermissionState.denied,
    );
    await coordinator.refresh();

    expect(coordinator.state.value.issue, 'permissionRequired');
    expect(coordinator.state.value.permission, permission);
  });

  test('disconnected actions preserve a missing permission', () async {
    final permission = PlatformPermissionResult(
      kind: PlatformPermissionKind.androidVpn,
      state: PlatformPermissionState.denied,
    );
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async =>
            HostConnection(VpnStatus.disconnected, permission: permission),
      ),
    );

    await coordinator.apply(ConnectionConfiguration(), affectsRuntime: false);

    expect(coordinator.state.value.issue, 'permissionRequired');
    expect(coordinator.state.value.permission, permission);
  });

  for (final initialStatus in [VpnStatus.disconnected, VpnStatus.connected]) {
    test(
      'LAN edits preserve the last native input until the next App connection: ${initialStatus.name}',
      () async {
        final fixtures = Directory(
          p.join('..', 'references', 'onexray-refactor-validation', 'fixtures'),
        ).absolute;
        await fixtures.create(recursive: true);
        final directory = await fixtures.createTemp('lan-next-app-start-');
        addTearDown(() => directory.delete(recursive: true));
        final file = File(p.join(directory.path, 'start.json'));
        final previous = ConnectionConfiguration(
          connection: ConnectionSettings(
            selection: const ServerSelection.server(1),
            trafficMode: TrafficMode.allVpn,
          ),
        );
        ConnectionRuntime compileRuntime(
          ConnectionConfiguration configuration,
        ) {
          final compiled = ConnectionCompiler.compile(
            settings: configuration.connection,
            entries: [
              ResolvedServer(
                id: 1,
                sourceId: 7,
                outbound: {'tag': 'Example', 'protocol': 'freedom'},
              ),
            ],
            regions: const RegionCatalog.empty(),
            options: RuntimeOptions(
              platform: ConnectionPlatform.android,
              sessionDirectory: directory.path,
              metricsPort: 18003,
              socksPort: 18004,
              lanProxyEnabled: configuration.policy.lanProxyEnabled,
              lanProxyPort: configuration.policy.lanProxyPort,
            ),
          );
          return ConnectionRuntime.create(
            configuration: configuration,
            compiled: compiled,
            platform: ConnectionPlatform.android,
            request: StartVpnRequest(
              configuration.policy.toTun(ConnectionPlatform.android),
              '18004',
              '18003',
              jsonEncode(
                LibXrayInvokeRequest(
                  method: LibXrayMethod.runXray,
                  payload: RunXrayRequest(compiled.xrayJson).toJson(),
                ).toJson(),
              ),
            ),
          );
        }

        final previousRuntime = compileRuntime(previous);
        await db.connectionConfigDao.commit(
          configurationJson: previous.encode(),
        );
        await file.writeAsString(jsonEncode(previousRuntime.request.toJson()));
        var host = HostConnection(
          initialStatus,
          runtime: initialStatus == VpnStatus.connected
              ? previousRuntime
              : null,
        );
        final calls = <String>[];
        final runtimeHost = ConnectionRuntimeHost(runDirectory: directory.path);
        final coordinator = await _initialize(
          ConnectionCoordinator(
            database: db,
            readRuntime: runtimeHost.readRuntime,
            inspect: (_, {observedStatus}) async => host,
            prepare: (configuration, _) async {
              calls.add('prepare');
              return compileRuntime(configuration);
            },
            start: (runtime) async {
              calls.add('start');
              await file.writeAsString(jsonEncode(runtime.request.toJson()));
              return host = HostConnection(
                VpnStatus.connected,
                runtime: runtime,
              );
            },
            stop: () async {
              calls.add('stop');
              return host = const HostConnection(VpnStatus.disconnected);
            },
          ),
        );
        final editor = PolicyEditorService(
          coordinator: coordinator,
          platform: ConnectionPlatform.android,
          reservedApiPort: () async => null,
        );

        for (final change in [
          (enabled: true, port: 11024),
          (enabled: true, port: 12024),
          (enabled: false, port: 12024),
        ]) {
          final originalInput = await file.readAsString();
          final originalHost = host;
          final callsBeforeSave = List<String>.of(calls);
          final draft = await editor.load();
          draft.policy['lanProxy']['enabled'] = change.enabled;
          draft.policy['lanProxy']['port'] = change.port;
          expect(
            await editor.save(
              draft: draft,
              confirm: (_) async =>
                  fail('LAN edits must not request a restart'),
            ),
            isTrue,
          );

          expect(await file.readAsString(), originalInput);
          expect(host, same(originalHost));
          expect(calls, callsBeforeSave);
          expect(coordinator.state.value.runtime, same(originalHost.runtime));
          final stored = await coordinator.configuration;
          expect(stored.policy.lanProxyEnabled, change.enabled);
          expect(stored.policy.lanProxyPort, change.port);

          // Background starts keep the saved input. Only a fresh App connection
          // compiles the newly stored policy.
          if (host.connected) await coordinator.disconnect();
          expect(await file.readAsString(), originalInput);
          await coordinator.connect();

          final saved = await runtimeHost.readRuntime();
          expect(saved, isNotNull);
          expect(saved!.configuration.policy.lanProxyEnabled, change.enabled);
          expect(saved.configuration.policy.lanProxyPort, change.port);
          final inbounds =
              (jsonDecode(saved.xrayJson) as Map<String, dynamic>)['inbounds']
                  as List;
          final sharing = inbounds.where(
            (inbound) => inbound['tag'] == 'app-lan-proxy',
          );
          if (change.enabled) {
            expect(sharing, hasLength(1));
            expect(sharing.single['listen'], '0.0.0.0');
            expect(sharing.single['port'], change.port.toString());
          } else {
            expect(sharing, isEmpty);
          }
          expect(coordinator.state.value.phase, ConnectionPhase.connected);
        }
      },
    );
  }

  test(
    'initialization does not report a platform error as missing permission',
    () async {
      final permission = PlatformPermissionResult(
        kind: PlatformPermissionKind.appleVpn,
        state: PlatformPermissionState.failed,
        message: 'load failed',
      );
      final coordinator = ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async => throw ConnectionHostException(
          'nativeStatusFailed',
          permission: permission,
        ),
      );
      addTearDown(coordinator.dispose);

      await expectLater(
        coordinator.initialize(observe: false, registerReferences: false),
        throwsA(isA<ConnectionHostException>()),
      );
      expect(coordinator.state.value.phase, ConnectionPhase.failed);
      expect(coordinator.state.value.issue, 'nativeStatusFailed');
      expect(coordinator.state.value.permission, permission);
    },
  );

  test(
    'a successful initialization retry clears its previous failure',
    () async {
      var fail = true;
      final coordinator = ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async {
          if (fail) {
            throw const ConnectionHostException('nativeStatusFailed');
          }
          return const HostConnection(VpnStatus.disconnected);
        },
      );
      addTearDown(coordinator.dispose);

      await expectLater(
        coordinator.initialize(observe: false, registerReferences: false),
        throwsA(isA<ConnectionHostException>()),
      );
      expect(coordinator.state.value.phase, ConnectionPhase.failed);

      fail = false;
      await coordinator.initialize(observe: false, registerReferences: false);

      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(coordinator.state.value.issue, isNull);
    },
  );

  for (final queuedApply in [false, true]) {
    test(
      'Stop cancels ${queuedApply ? 'queued apply' : 'connect'} before preparation',
      () async {
        final runtime = _runtime('cancelled-start');
        var host = const HostConnection(VpnStatus.disconnected);
        final entered = Completer<void>();
        final release = Completer<void>();
        var pauseNextInspection = false;
        final calls = <String>[];
        final coordinator = await _initialize(
          ConnectionCoordinator(
            database: db,
            readRuntime: () async => host.runtime,
            inspect: (_, {observedStatus}) async {
              if (pauseNextInspection) {
                pauseNextInspection = false;
                entered.complete();
                await release.future;
              }
              return host;
            },
            prepare: (_, _) async {
              calls.add('prepare');
              return runtime;
            },
            start: (runtime) async {
              calls.add('start');
              return host = HostConnection(
                VpnStatus.connected,
                runtime: runtime,
              );
            },
            stop: () async {
              calls.add('stop');
              return host = const HostConnection(VpnStatus.disconnected);
            },
          ),
        );
        pauseNextInspection = true;
        final starting = queuedApply
            ? coordinator.apply(runtime.configuration, connect: true)
            : coordinator.connect();
        final cancelled = expectLater(
          starting,
          throwsA(
            isA<ConnectionHostException>().having(
              (error) => error.reason,
              'reason',
              'cancelled',
            ),
          ),
        );
        await entered.future;
        final stopping = coordinator.disconnect();
        if (!queuedApply) await stopping;
        release.complete();
        await Future.wait([cancelled, stopping]);

        expect(calls, ['stop']);
        expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      },
    );
  }

  for (final lateFailure in [false, true]) {
    test(
      'Stop interrupts native start and ignores its late ${lateFailure ? 'error' : 'success'}',
      () async {
        final runtime = _runtime('delayed-start');
        var host = const HostConnection(VpnStatus.disconnected);
        final entered = Completer<void>();
        final reply = Completer<HostConnection>();
        var starts = 0;
        var stops = 0;
        final coordinator = await _initialize(
          ConnectionCoordinator(
            database: db,
            readRuntime: () async => host.runtime,
            inspect: (_, {observedStatus}) async => host,
            prepare: (_, _) async => runtime,
            start: (runtime) async {
              starts++;
              if (starts == 1) {
                host = HostConnection(VpnStatus.connecting, runtime: runtime);
                entered.complete();
                return reply.future;
              }
              return host = HostConnection(
                VpnStatus.connected,
                runtime: runtime,
              );
            },
            stop: () async {
              stops++;
              return host = const HostConnection(VpnStatus.disconnected);
            },
          ),
        );
        final original = (await coordinator.configuration).encode();
        final cancelled = expectLater(
          coordinator.connect(),
          throwsA(
            isA<ConnectionHostException>().having(
              (error) => error.reason,
              'reason',
              'cancelled',
            ),
          ),
        );
        await entered.future;
        var stopped = false;
        final stopping = coordinator.disconnect().then((_) => stopped = true);
        try {
          await pumpEventQueue();
          expect(stops, greaterThan(0));
          expect(stopped, isTrue);
          expect(reply.isCompleted, isFalse);
          expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
          expect((await coordinator.configuration).encode(), original);
        } finally {
          if (lateFailure) {
            reply.completeError(
              const ConnectionHostException('lateStartFailure'),
            );
          } else {
            reply.complete(
              HostConnection(VpnStatus.connected, runtime: runtime),
            );
          }
          await cancelled;
          await stopping;
        }
        await pumpEventQueue();
        expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
        expect((await coordinator.configuration).encode(), original);

        await coordinator.connect();
        expect(starts, 2);
        expect(coordinator.state.value.phase, ConnectionPhase.connected);
      },
    );
  }

  test('connect prepares, starts and commits selected settings', () async {
    final next = _runtime('b', entryIds: const [2]);
    var status = VpnStatus.disconnected;
    ConnectionRuntime? active;
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => active,
        inspect: (_, {observedStatus}) async => observedStatus == null
            ? HostConnection(status, runtime: active)
            : HostConnection(
                observedStatus,
                runtime: observedStatus == VpnStatus.connected ? next : null,
              ),
        prepare: (_, _) async => next,
        start: (runtime) async {
          status = VpnStatus.connected;
          active = runtime;
          return HostConnection(status, runtime: runtime);
        },
        stop: () async {
          status = VpnStatus.disconnected;
          active = null;
          return HostConnection(status);
        },
      ),
    );

    await coordinator.apply(next.configuration, connect: true);

    expect(coordinator.state.value.phase, ConnectionPhase.connected);
    expect(coordinator.state.value.runtime?.identity, next.identity);
    expect(
      (await coordinator.configuration).encode(),
      next.configuration.encode(),
    );
  });

  test('reconnect validates and prepares only after stopping', () async {
    final old = _runtime('a');
    final next = _runtime('b', entryIds: const [2]);
    var host = HostConnection(VpnStatus.connected, runtime: old);
    final calls = <String>[];
    final phases = <ConnectionPhase>[];
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => host.runtime,
        inspect: (_, {observedStatus}) async => host,
        prepare: (_, _) async {
          calls.add('prepare');
          expect(host.status, VpnStatus.disconnected);
          return next;
        },
        stop: () async {
          calls.add('stop');
          host = const HostConnection(VpnStatus.disconnected);
          return host;
        },
        start: (runtime) async {
          calls.add('start');
          host = HostConnection(VpnStatus.connected, runtime: runtime);
          return host;
        },
      ),
    );
    coordinator.state.addListener(
      () => phases.add(coordinator.state.value.phase),
    );

    await coordinator.apply(
      next.configuration,
      validateAssets: () async {
        calls.add('validate');
        expect(host.status, VpnStatus.disconnected);
      },
    );

    expect(calls, ['stop', 'validate', 'prepare', 'start']);
    expect(phases, [
      ConnectionPhase.disconnecting,
      ConnectionPhase.preparing,
      ConnectionPhase.connecting,
      ConnectionPhase.connected,
    ]);
    expect(coordinator.state.value.runtime?.identity, next.identity);
    expect(
      (await coordinator.configuration).encode(),
      next.configuration.encode(),
    );
  });

  for (final stopThrows in [false, true]) {
    test('failed stop prevents all startup work: throws=$stopThrows', () async {
      final old = _runtime('a');
      final calls = <String>[];
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => old,
          inspect: (_, {observedStatus}) async =>
              HostConnection(VpnStatus.connected, runtime: old),
          prepare: (_, _) async {
            calls.add('prepare');
            return _runtime('b');
          },
          stop: () async {
            if (stopThrows) throw const ConnectionHostException('stopFailed');
            return HostConnection(VpnStatus.connected, runtime: old);
          },
          start: (runtime) async {
            calls.add('start');
            return HostConnection(VpnStatus.connected, runtime: runtime);
          },
        ),
      );

      await expectLater(
        coordinator.apply(
          ConnectionConfiguration(),
          validateAssets: () async {
            calls.add('validate');
          },
        ),
        throwsA(isA<ConnectionHostException>()),
      );

      expect(calls, isEmpty);
      expect(coordinator.state.value.phase, ConnectionPhase.failed);
      expect(coordinator.state.value.runtime?.identity, old.identity);
    });
  }

  test('configuration preparation failure never starts the VPN host', () async {
    var starts = 0;
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
        prepare: (_, _) async =>
            throw const FormatException('Raw configuration is empty'),
        start: (_) async {
          starts++;
          throw StateError('must not start');
        },
      ),
    );

    await expectLater(
      coordinator.apply(ConnectionConfiguration(), connect: true),
      throwsFormatException,
    );

    expect(starts, 0);
  });

  test(
    'resolver reason and counts survive refresh and clear on successful retry',
    () async {
      const error = ConnectionResolutionException(
        ConnectionResolutionFailure.insufficientHealthyServers,
        requiredCount: 3,
        availableCount: 1,
      );
      final runtime = _runtime('a');
      var fail = true;
      var host = const HostConnection(VpnStatus.disconnected);
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => host.runtime,
          inspect: (_, {observedStatus}) async => host,
          prepare: (_, _) async {
            if (fail) throw error;
            return runtime;
          },
          start: (runtime) async =>
              host = HostConnection(VpnStatus.connected, runtime: runtime),
        ),
      );
      await expectLater(coordinator.connect(), throwsA(same(error)));
      expect(coordinator.state.value.issue, 'insufficientHealthyServers');
      expect(coordinator.state.value.error, same(error));
      await coordinator.refresh();
      expect(coordinator.state.value.issue, 'insufficientHealthyServers');
      expect(coordinator.state.value.error, same(error));
      fail = false;
      await coordinator.connect();
      expect(coordinator.state.value.phase, ConnectionPhase.connected);
      expect(coordinator.state.value.issue, isNull);
      expect(coordinator.state.value.error, isNull);
    },
  );

  test('active node IDs protect subscription replacement', () async {
    final active = _runtime('a', entryIds: const [2, 3], exitId: 4);
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => active,
        inspect: (_, {observedStatus}) async =>
            HostConnection(VpnStatus.connected, runtime: active),
      ),
    );

    expect((await coordinator.readReferences()).runningIds, {2, 3, 4});
  });

  test(
    'a provider profile stays protected before preparation completes',
    () async {
      final profiles = await _providerRows(db);
      final selected = profiles.$1;
      final pending = _providerRuntime(selected);
      final preparing = Completer<void>();
      final finish = Completer<void>();
      var starts = 0;
      late ConnectionCoordinator coordinator;
      coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => null,
          inspect: (_, {observedStatus}) async =>
              const HostConnection(VpnStatus.disconnected),
          prepare: (_, _) async {
            coordinator.reportResolvedNodes({selected.id});
            preparing.complete();
            await finish.future;
            throw const FormatException('Provider preparation was cancelled');
          },
          start: (_) async {
            starts++;
            throw StateError('A failed preparation must not start');
          },
        ),
      );
      final connecting = coordinator.apply(
        pending.configuration,
        connect: true,
      );
      final rejected = expectLater(connecting, throwsFormatException);
      await preparing.future;
      try {
        expect(coordinator.state.value.phase, ConnectionPhase.preparing);
        final references = await coordinator.readReferences();
        expect(references.runningIds, {selected.id});
        await db.subscriptionDao.deleteConfigs(
          selected.subId,
          protectedIds: references.protectedIds,
        );
        expect(await db.coreConfigDao.searchRow(selected.id), selected);
        expect(await db.coreConfigDao.searchRow(profiles.$2.id), isNull);
      } finally {
        finish.complete();
        await rejected;
      }
      expect(starts, 0);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(coordinator.state.value.error, isA<FormatException>());
      expect((await coordinator.readReferences()).runningIds, isEmpty);
      expect(
        (await coordinator.configuration).connection.selection.kind,
        SelectionKind.automatic,
      );
    },
  );

  test('pending and restored provider runtimes protect the original subscription row', () async {
    final profiles = await _providerRows(db);
    final selected = profiles.$1;
    final pending = _providerRuntime(selected);
    final starting = Completer<void>();
    final finish = Completer<void>();
    var status = VpnStatus.disconnected;
    ConnectionRuntime? stored;
    final host = ConnectionRuntimeHost(readStatus: () async => status);
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => stored,
        inspect: host.inspect,
        prepare: (_, _) async => pending,
        start: (runtime) async {
          status = VpnStatus.connected;
          starting.complete();
          await finish.future;
          stored = ConnectionRuntime.fromRequest(runtime.request);
          return HostConnection(status, runtime: stored);
        },
      ),
    );
    final connecting = coordinator.apply(pending.configuration, connect: true);
    await starting.future;
    try {
      expect(coordinator.state.value.runtime, isNull);
      final references = await coordinator.readReferences();
      expect(references.runningIds, {selected.id});
      await db.transaction(() async {
        await db.subscriptionDao.deleteConfigs(
          selected.subId,
          protectedIds: references.protectedIds,
        );
        await db.coreConfigDao.insertRow(
          CoreConfigCompanion.insert(
            name: selected.name,
            type: selected.type,
            tags: selected.tags,
            delay: selected.delay,
            subId: selected.subId,
            data: Value(selected.data),
          ),
        );
      });
      expect(await db.coreConfigDao.searchRow(selected.id), selected);
      expect(await db.coreConfigDao.searchRow(profiles.$2.id), isNull);
      expect(await db.coreConfigDao.allActiveServerRows(), hasLength(2));
    } finally {
      finish.complete();
      await connecting;
    }
    expect(coordinator.state.value.phase, ConnectionPhase.connected);
    expect(coordinator.state.value.runtime?.entries, isEmpty);
    expect(coordinator.state.value.runtime?.profile?.id, selected.id);
    expect((await coordinator.readReferences()).runningIds, {selected.id});
    expect(await db.coreConfigDao.searchRow(selected.id), selected);
  });

  test(
    'an unpersisted pending runtime protects nodes while native start waits',
    () async {
      final pending = _runtime('pending', entryIds: const [2, 3], exitId: 4);
      final starting = Completer<void>();
      final finish = Completer<void>();
      var status = VpnStatus.disconnected;
      final host = ConnectionRuntimeHost(readStatus: () async => status);
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => null,
          inspect: host.inspect,
          prepare: (_, _) async => pending,
          start: (runtime) async {
            status = VpnStatus.connected;
            starting.complete();
            await finish.future;
            return HostConnection(status, runtime: runtime);
          },
        ),
      );
      final connecting = coordinator.apply(
        pending.configuration,
        connect: true,
      );
      await starting.future;
      expect(coordinator.state.value.phase, ConnectionPhase.connecting);
      expect(coordinator.state.value.runtime, isNull);
      try {
        expect((await coordinator.readReferences()).runningIds, {2, 3, 4});
      } finally {
        finish.complete();
        await connecting;
      }
      expect(coordinator.state.value.phase, ConnectionPhase.connected);
      expect(coordinator.state.value.runtime, same(pending));
    },
  );

  test(
    'start failure stops the attempt and never restarts the old runtime',
    () async {
      final old = _runtime('a');
      final next = _runtime('b', entryIds: const [2]);
      var status = VpnStatus.connected;
      ConnectionRuntime? active = old;
      var starts = 0;
      var stops = 0;
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => active,
          inspect: (_, {observedStatus}) async => observedStatus == null
              ? HostConnection(status, runtime: active)
              : HostConnection(
                  observedStatus,
                  runtime: observedStatus == VpnStatus.connected ? next : null,
                ),
          prepare: (_, _) async => next,
          start: (_) async {
            starts++;
            throw const ConnectionHostException('startFailed');
          },
          stop: () async {
            stops++;
            status = VpnStatus.disconnected;
            active = null;
            return HostConnection(status);
          },
        ),
      );

      await expectLater(
        coordinator.apply(next.configuration, allowReconnect: true),
        throwsA(isA<ConnectionHostException>()),
      );

      expect(starts, 1);
      expect(stops, 2);
      expect(coordinator.state.value.phase, ConnectionPhase.failed);
      expect(coordinator.state.value.runtime, isNull);
      expect(
        (await coordinator.configuration).encode(),
        isNot(next.configuration.encode()),
      );

      await coordinator.refresh(observedStatus: VpnStatus.connected);

      expect(coordinator.state.value.phase, ConnectionPhase.failed);
      expect(coordinator.state.value.runtime?.identity, next.identity);
    },
  );

  test(
    'preparation failure after stopping does not restore the old connection',
    () async {
      final old = _runtime('a');
      var host = HostConnection(VpnStatus.connected, runtime: old);
      var starts = 0;
      var stops = 0;
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => host.runtime,
          inspect: (_, {observedStatus}) async => host,
          prepare: (_, _) async {
            expect(host.status, VpnStatus.disconnected);
            throw const FormatException('bad input');
          },
          start: (_) async {
            starts++;
            throw StateError('must not start');
          },
          stop: () async {
            stops++;
            host = const HostConnection(VpnStatus.disconnected);
            return host;
          },
        ),
      );

      await expectLater(
        coordinator.apply(ConnectionConfiguration(), allowReconnect: true),
        throwsFormatException,
      );

      expect(coordinator.state.value.phase, ConnectionPhase.failed);
      expect(coordinator.state.value.runtime, isNull);
      expect(starts, 0);
      expect(stops, 2);
    },
  );
}

Future<ConnectionCoordinator> _initialize(
  ConnectionCoordinator coordinator,
) async {
  addTearDown(coordinator.dispose);
  await coordinator.initialize(observe: false, registerReferences: false);
  return coordinator;
}

ConnectionRuntime _runtime(
  String digit, {
  List<int> entryIds = const [1],
  int? exitId,
  PlatformPolicy? policy,
}) {
  final configuration = ConnectionConfiguration(
    policy: policy,
    connection: ConnectionSettings(
      selection: entryIds.length == 1
          ? ServerSelection.server(entryIds.single)
          : const ServerSelection.automatic(),
      smart: SmartRoutingSettings(
        entryCount: entryIds.length,
        finalExitId: exitId,
      ),
    ),
  );
  ResolvedServer server(int id) => ResolvedServer(
    id: id,
    sourceId: 7,
    outbound: {'protocol': 'freedom', 'tag': 'server-$id'},
  );
  final entries = entryIds.map(server).toList();
  final finalExit = exitId == null ? null : server(exitId);
  final xrayJson = jsonEncode({
    if (configuration.policy.lanProxyEnabled)
      'inbounds': [
        {
          'tag': 'app-lan-proxy',
          'protocol': 'socks',
          'listen': '0.0.0.0',
          'port': configuration.policy.lanProxyPort,
          'settings': {'auth': 'noauth', 'udp': true},
        },
      ],
    'outbounds': [
      for (final entry in entries) entry.outbound,
      if (finalExit != null) finalExit.outbound,
    ],
  });
  final compiled = CompiledConnection(
    xrayJson: xrayJson,
    entries: entries,
    finalExit: finalExit,
    nodeTags: const {},
  );
  final invoke = LibXrayInvokeRequest(
    method: LibXrayMethod.runXray,
    payload: RunXrayRequest(xrayJson).toJson(),
  );
  return ConnectionRuntime.create(
    configuration: configuration,
    compiled: compiled,
    platform: ConnectionPlatform.android,
    request: StartVpnRequest(null, null, '18003', jsonEncode(invoke.toJson())),
  );
}

Future<(CoreConfigData, CoreConfigData)> _providerRows(AppDatabase db) async {
  final sourceId = await db.subscriptionDao.insertRow(
    SubscriptionCompanion.insert(
      name: 'Provider',
      url: 'https://example.com/provider',
      timestamp: DateTime(2026, 10, 12),
      mode: Value(SubscriptionMode.providerManaged.name),
    ),
  );
  Future<CoreConfigData> insert(String name) async {
    final id = await db.coreConfigDao.insertRow(
      CoreConfigCompanion.insert(
        name: name,
        type: CoreConfigType.Remnawave.name,
        tags: '',
        delay: PingDelayConstants.unknown,
        subId: sourceId,
        data: Value(
          base64Encode(
            utf8.encode(
              jsonEncode({
                'outbounds': [
                  {'tag': 'provider-proxy', 'protocol': 'freedom'},
                ],
              }),
            ),
          ),
        ),
      ),
    );
    return (await db.coreConfigDao.searchRow(id))!;
  }

  return (await insert('Selected profile'), await insert('Other old profile'));
}

ConnectionRuntime _providerRuntime(CoreConfigData row) {
  final configuration = ConnectionConfiguration(
    connection: ConnectionSettings(selection: ServerSelection.server(row.id)),
  );
  final profile = ResolvedProfile.fromRow(row);
  final xrayJson = jsonEncode(profile.config);
  return ConnectionRuntime.create(
    configuration: configuration,
    compiled: CompiledConnection(
      xrayJson: xrayJson,
      entries: const [],
      finalExit: null,
      nodeTags: const {},
      profile: profile,
    ),
    platform: ConnectionPlatform.android,
    request: StartVpnRequest(
      null,
      null,
      '18003',
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(xrayJson).toJson(),
        ).toJson(),
      ),
    ),
  );
}
