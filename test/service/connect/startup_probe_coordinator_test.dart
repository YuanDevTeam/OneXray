import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  test(
    'a slow probe does not delay connect or change a successful connection',
    () async {
      final started = Completer<void>();
      final result = Completer<bool?>();
      final fixture = await _initialize(
        db,
        probe: (_) {
          started.complete();
          return result.future;
        },
      );

      await fixture.coordinator.connect().timeout(const Duration(seconds: 2));
      await started.future.timeout(const Duration(seconds: 2));
      expect(result.isCompleted, isFalse);
      expect(fixture.coordinator.state.value.phase, ConnectionPhase.connected);
      expect(fixture.coordinator.state.value.failed, isFalse);
      expect(fixture.coordinator.state.value.issue, isNull);
      expect(fixture.coordinator.startupProbeFailure.value, isNull);
      expect(fixture.starts, 1);
      expect(fixture.stops, 0);

      result.complete(true);
      await _flush();
      expect(fixture.coordinator.startupProbeFailure.value, isNull);
      expect(fixture.coordinator.state.value.phase, ConnectionPhase.connected);
      expect(fixture.starts, 1);
      expect(fixture.stops, 0);
    },
  );

  test(
    'a failed probe only offers one weak notice and preserves node data',
    () async {
      final nodeId = await db.coreConfigDao.insertRow(
        CoreConfigCompanion.insert(
          name: 'Saved node',
          type: CoreConfigType.outbound.name,
          tags: '',
          delay: 321,
          subId: 7,
          manualSortOrder: const Value(17),
          data: Value(base64Encode(utf8.encode('{"protocol":"freedom"}'))),
        ),
      );
      final before = await db.coreConfigDao.searchRow(nodeId);
      final started = Completer<void>();
      final result = Completer<bool?>();
      final fixture = await _initialize(
        db,
        runtime: _runtime(entryId: nodeId),
        probe: (_) {
          started.complete();
          return result.future;
        },
      );
      await fixture.coordinator.connect();
      await started.future.timeout(const Duration(seconds: 2));
      final failed = _nextFailure(fixture.coordinator);
      result.complete(false);
      final token = await failed;

      expect(fixture.coordinator.state.value.phase, ConnectionPhase.connected);
      expect(fixture.coordinator.state.value.failed, isFalse);
      expect(fixture.coordinator.state.value.issue, isNull);
      expect(fixture.coordinator.state.value.error, isNull);
      expect(fixture.starts, 1);
      expect(fixture.stops, 0);
      expect(await db.coreConfigDao.searchRow(nodeId), before);
      expect(fixture.coordinator.consumeStartupProbeFailure(token), isTrue);
      expect(fixture.coordinator.startupProbeFailure.value, isNull);
      expect(fixture.coordinator.consumeStartupProbeFailure(token), isFalse);
    },
  );

  test('success and unsupported probes stay silent without retrying', () async {
    for (final outcome in <bool?>[true, null]) {
      var calls = 0;
      final started = Completer<void>();
      final fixture = await _initialize(
        db,
        probe: (_) async {
          calls++;
          started.complete();
          return outcome;
        },
      );
      await fixture.coordinator.connect();
      await started.future.timeout(const Duration(seconds: 2));
      await _flush();
      await fixture.coordinator.refresh();
      await _flush();

      expect(calls, 1);
      expect(fixture.coordinator.startupProbeFailure.value, isNull);
      expect(fixture.coordinator.state.value.phase, ConnectionPhase.connected);
      fixture.dispose();
    }
  });

  test(
    'refresh, native duplicates, samples and metadata saves do not reprobe',
    () async {
      var calls = 0;
      final started = Completer<void>();
      final fixture = await _initialize(
        db,
        observe: true,
        probe: (_) async {
          calls++;
          if (!started.isCompleted) started.complete();
          return true;
        },
      );
      await fixture.coordinator.connect();
      await started.future.timeout(const Duration(seconds: 2));
      await _flush();

      await fixture.coordinator.refresh();
      fixture.events.add(VpnStatus.connected);
      fixture.events.add(VpnStatus.connected);
      await _flush();
      await fixture.coordinator.apply(
        await fixture.coordinator.configuration,
        affectsRuntime: false,
      );
      fixture.coordinator.setTrafficVisible(fixture, true);
      await fixture.coordinator.refreshTraffic();
      await _flush();

      expect(calls, 1);
      expect(fixture.starts, 1);
      expect(fixture.stops, 0);
      expect(fixture.coordinator.startupProbeFailure.value, isNull);
    },
  );

  test(
    'iOS connected-time calibration preserves an in-flight probe and failure',
    () async {
      final runtime = _runtime(platform: ConnectionPlatform.ios);
      final calibrated = runtime.withStartedAt(
        runtime.startedAt.add(const Duration(seconds: 5)),
      );
      final started = Completer<void>();
      final result = Completer<bool?>();
      var calls = 0;
      final fixture = await _initialize(
        db,
        runtime: runtime,
        probe: (_) {
          calls++;
          if (!started.isCompleted) started.complete();
          return result.future;
        },
      );
      await fixture.coordinator.connect();
      await started.future.timeout(const Duration(seconds: 2));

      fixture.current = HostConnection(
        VpnStatus.connected,
        runtime: calibrated,
      );
      await fixture.coordinator.refresh();
      await _flush();
      expect(calls, 1);
      expect(
        fixture.coordinator.state.value.runtime?.identity,
        calibrated.identity,
      );

      final failure = _nextFailure(fixture.coordinator);
      result.complete(false);
      final token = await failure;
      expect(fixture.coordinator.consumeStartupProbeFailure(token), isTrue);
      expect(fixture.coordinator.state.value.phase, ConnectionPhase.connected);
      expect(fixture.stops, 0);
    },
  );

  test('iOS metadata reads between calibrated snapshots do not start another probe', () async {
    final runtime = _runtime(platform: ConnectionPlatform.ios);
    final calibrated = runtime.withStartedAt(
      runtime.startedAt.add(const Duration(seconds: 5)),
    );
    final started = Completer<void>();
    var calls = 0;
    final fixture = await _initialize(
      db,
      runtime: runtime,
      probe: (_) async {
        calls++;
        if (!started.isCompleted) started.complete();
        return true;
      },
    );
    await fixture.coordinator.connect();
    await started.future.timeout(const Duration(seconds: 2));
    await _flush();

    for (final snapshot in [calibrated, runtime, calibrated]) {
      fixture.current = HostConnection(VpnStatus.connected, runtime: snapshot);
      await fixture.coordinator.refresh();
      await _flush();
      expect(calls, 1);
    }
    expect(fixture.coordinator.startupProbeFailure.value, isNull);
    expect(fixture.coordinator.state.value.phase, ConnectionPhase.connected);
    expect(fixture.starts, 1);
    expect(fixture.stops, 0);
  });

  test('a later iOS system connection time starts a new probe for the saved request', () async {
    final runtime = _runtime(platform: ConnectionPlatform.ios);
    final calibrated = runtime.withStartedAt(
      runtime.startedAt.add(const Duration(seconds: 5)),
    );
    final nextConnection = runtime.withStartedAt(
      runtime.startedAt.add(const Duration(minutes: 1)),
    );
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    var calls = 0;
    final fixture = await _initialize(
      db,
      runtime: runtime,
      probe: (_) async {
        calls++;
        if (calls == 1) {
          firstStarted.complete();
          return true;
        }
        if (!secondStarted.isCompleted) secondStarted.complete();
        return false;
      },
    );
    await fixture.coordinator.connect();
    await firstStarted.future.timeout(const Duration(seconds: 2));
    fixture.current = HostConnection(VpnStatus.connected, runtime: calibrated);
    await fixture.coordinator.refresh();
    await _flush();
    expect(calls, 1);

    expect(nextConnection.request.metadataJson, runtime.request.metadataJson);
    final failure = _nextFailure(fixture.coordinator);
    fixture.current = HostConnection(
      VpnStatus.connected,
      runtime: nextConnection,
    );
    await fixture.coordinator.refresh();
    await secondStarted.future.timeout(const Duration(seconds: 2));
    final token = await failure;
    expect(calls, 2);
    expect(fixture.coordinator.consumeStartupProbeFailure(token), isTrue);
    expect(
      fixture.coordinator.state.value.runtime?.identity,
      nextConnection.identity,
    );
    expect(fixture.starts, 1);
    expect(fixture.stops, 0);
  });

  test('disconnect discards a late failure from the old session', () async {
    final started = Completer<void>();
    final result = Completer<bool?>();
    final fixture = await _initialize(
      db,
      probe: (_) {
        started.complete();
        return result.future;
      },
    );
    await fixture.coordinator.connect();
    await started.future.timeout(const Duration(seconds: 2));
    await fixture.coordinator.disconnect();
    result.complete(false);
    await _flush();

    expect(fixture.coordinator.state.value.phase, ConnectionPhase.disconnected);
    expect(fixture.coordinator.startupProbeFailure.value, isNull);
    expect(fixture.stops, 1);
  });

  test(
    'a new connection with reused runtime identity gets a fresh probe',
    () async {
      final runtime = _runtime();
      var calls = 0;
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      final fixture = await _initialize(
        db,
        runtime: runtime,
        probe: (value) async {
          expect(value.identity, runtime.identity);
          calls++;
          if (calls == 1) firstStarted.complete();
          if (calls == 2) secondStarted.complete();
          return false;
        },
      );
      final firstNotice = _nextFailure(fixture.coordinator);
      await fixture.coordinator.connect();
      await firstStarted.future.timeout(const Duration(seconds: 2));
      final firstToken = await firstNotice;
      await fixture.coordinator.disconnect();
      expect(fixture.coordinator.startupProbeFailure.value, isNull);

      final secondNotice = _nextFailure(fixture.coordinator);
      await fixture.coordinator.connect();
      await secondStarted.future.timeout(const Duration(seconds: 2));
      final secondToken = await secondNotice;

      expect(calls, 2);
      expect(secondToken, isNot(firstToken));
      expect(
        fixture.coordinator.consumeStartupProbeFailure(firstToken),
        isFalse,
      );
      expect(
        fixture.coordinator.consumeStartupProbeFailure(secondToken),
        isTrue,
      );
      expect(fixture.starts, 2);
      expect(fixture.stops, 1);
    },
  );

  test(
    'a pending old probe cannot warn about a newly connected session',
    () async {
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      final firstResult = Completer<bool?>();
      final secondResult = Completer<bool?>();
      var calls = 0;
      final fixture = await _initialize(
        db,
        probe: (_) {
          calls++;
          if (calls == 1) {
            firstStarted.complete();
            return firstResult.future;
          }
          secondStarted.complete();
          return secondResult.future;
        },
      );
      await fixture.coordinator.connect();
      await firstStarted.future.timeout(const Duration(seconds: 2));
      await fixture.coordinator.disconnect();
      await fixture.coordinator.connect();
      await secondStarted.future.timeout(const Duration(seconds: 2));

      firstResult.complete(false);
      await _flush();
      expect(fixture.coordinator.startupProbeFailure.value, isNull);
      expect(fixture.coordinator.state.value.phase, ConnectionPhase.connected);
      secondResult.complete(true);
      await _flush();
      expect(fixture.coordinator.startupProbeFailure.value, isNull);
      expect(calls, 2);
    },
  );

  test(
    'a failure completed in the background is not replayed on resume',
    () async {
      var calls = 0;
      final started = Completer<void>();
      final result = Completer<bool?>();
      final fixture = await _initialize(
        db,
        probe: (_) {
          calls++;
          started.complete();
          return result.future;
        },
      );
      await fixture.coordinator.connect();
      await started.future.timeout(const Duration(seconds: 2));
      fixture.coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
      result.complete(false);
      await _flush();
      expect(fixture.coordinator.startupProbeFailure.value, isNull);

      fixture.coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await fixture.coordinator.refresh();
      await _flush();
      expect(calls, 1);
      expect(fixture.coordinator.startupProbeFailure.value, isNull);
      expect(fixture.coordinator.state.value.phase, ConnectionPhase.connected);
    },
  );

  test(
    'a connection first seen in the background is probed once on resume',
    () async {
      var calls = 0;
      final started = Completer<void>();
      final fixture = await _initialize(
        db,
        probe: (_) async {
          calls++;
          started.complete();
          return true;
        },
      );
      fixture.coordinator.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await fixture.coordinator.connect();
      await _flush();
      expect(calls, 0);

      fixture.coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await fixture.coordinator.refresh();
      await started.future.timeout(const Duration(seconds: 2));
      await fixture.coordinator.refresh();
      await _flush();
      expect(calls, 1);
      expect(fixture.coordinator.startupProbeFailure.value, isNull);
    },
  );

  test(
    'a native disconnect invalidates a probe before reconciliation finishes',
    () async {
      final started = Completer<void>();
      final result = Completer<bool?>();
      final fixture = await _initialize(
        db,
        observe: true,
        probe: (_) {
          started.complete();
          return result.future;
        },
      );
      await fixture.coordinator.connect();
      await started.future.timeout(const Duration(seconds: 2));
      final inspected = Completer<HostConnection>();
      fixture.nextInspection = inspected;
      fixture.current = const HostConnection(VpnStatus.disconnected);
      fixture.events.add(VpnStatus.disconnected);
      result.complete(false);
      await _flush();
      expect(fixture.coordinator.startupProbeFailure.value, isNull);

      inspected.complete(const HostConnection(VpnStatus.disconnected));
      await _flush();
      expect(
        fixture.coordinator.state.value.phase,
        ConnectionPhase.disconnected,
      );
      expect(fixture.coordinator.startupProbeFailure.value, isNull);
    },
  );

  test('dispose ignores an in-flight probe result', () async {
    final started = Completer<void>();
    final result = Completer<bool?>();
    final fixture = await _initialize(
      db,
      probe: (_) {
        started.complete();
        return result.future;
      },
    );
    await fixture.coordinator.connect();
    await started.future.timeout(const Duration(seconds: 2));
    fixture.dispose();
    result.complete(false);
    await _flush();
    expect(fixture.starts, 1);
    expect(fixture.stops, 0);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<int> _nextFailure(ConnectionCoordinator coordinator) {
  final result = Completer<int>();
  void changed() {
    final token = coordinator.startupProbeFailure.value;
    if (token == null || result.isCompleted) return;
    coordinator.startupProbeFailure.removeListener(changed);
    result.complete(token);
  }

  coordinator.startupProbeFailure.addListener(changed);
  addTearDown(() {
    if (!result.isCompleted) {
      coordinator.startupProbeFailure.removeListener(changed);
    }
  });
  changed();
  return result.future.timeout(const Duration(seconds: 2));
}

Future<_Fixture> _initialize(
  AppDatabase db, {
  required Future<bool?> Function(ConnectionRuntime) probe,
  ConnectionRuntime? runtime,
  bool observe = false,
}) async {
  final fixture = _Fixture(db, runtime ?? _runtime(), probe);
  addTearDown(fixture.close);
  await fixture.coordinator.initialize(
    observe: observe,
    registerReferences: false,
  );
  return fixture;
}

class _Fixture {
  final ConnectionRuntime runtime;
  final events = StreamController<VpnStatus>.broadcast(sync: true);
  HostConnection current = const HostConnection(VpnStatus.disconnected);
  Completer<HostConnection>? nextInspection;
  int starts = 0;
  int stops = 0;
  bool _disposed = false;
  late final ConnectionCoordinator coordinator;

  _Fixture(
    AppDatabase db,
    this.runtime,
    Future<bool?> Function(ConnectionRuntime) probe,
  ) {
    coordinator = ConnectionCoordinator(
      database: db,
      probe: probe,
      startupProbeDelay: Duration.zero,
      readRuntime: () async => current.runtime,
      inspect: (_, {observedStatus}) async {
        final blocked = nextInspection;
        if (blocked != null) {
          nextInspection = null;
          return blocked.future;
        }
        return current;
      },
      prepare: (_, _) async => runtime,
      start: (value) async {
        starts++;
        return current = HostConnection(VpnStatus.connected, runtime: value);
      },
      stop: () async {
        stops++;
        return current = const HostConnection(VpnStatus.disconnected);
      },
      readTraffic: (_) async =>
          const ConnectionTraffic(uplink: 10, downlink: 20, sampledAtMs: 1000),
      statusEvents: events.stream,
      observeStatus: () async {},
      disposeStatus: () {},
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    coordinator.dispose();
  }

  Future<void> close() async {
    dispose();
    await events.close();
  }
}

ConnectionRuntime _runtime({
  int entryId = 1,
  ConnectionPlatform platform = ConnectionPlatform.android,
}) {
  final configuration = ConnectionConfiguration(
    connection: ConnectionSettings(selection: ServerSelection.server(entryId)),
  );
  final server = ResolvedServer(
    id: entryId,
    sourceId: 7,
    outbound: {'protocol': 'freedom', 'tag': 'app-entry-1'},
  );
  final xrayJson = jsonEncode({
    'outbounds': [server.outbound],
    'routing': {
      'balancers': [
        {
          'tag': 'proxy',
          'selector': ['app-entry-1'],
          'strategy': {'type': 'roundRobin'},
        },
      ],
    },
  });
  return ConnectionRuntime.create(
    configuration: configuration,
    compiled: CompiledConnection(
      xrayJson: xrayJson,
      entries: [server],
      finalExit: null,
      nodeTags: const {},
    ),
    platform: platform,
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
