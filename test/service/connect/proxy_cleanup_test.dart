import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/proxy/core_session.dart';
import 'package:onexray/core/proxy/host.dart';
import 'package:onexray/core/proxy/journal.dart';
import 'package:onexray/core/proxy/system_proxy.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/menu/tray/entry.dart';
import 'package:onexray/service/shared/menu/tray/service.dart';

const _before = <String, dynamic>{
  'enabled': false,
  'host': 'previous.proxy',
  'port': 8080,
  'bypass': '<local>',
};

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

final class _Adapter implements SystemProxyAdapter {
  Map<String, dynamic> value = _copy(_before);
  @override
  String get id => 'cleanup-test';
  @override
  Future<DesktopSystemProxyCapability> capability() async =>
      const DesktopSystemProxyCapability(supported: true);
  @override
  Future<SystemProxySnapshot> read() async => _copy(value);
  @override
  SystemProxySnapshot forEndpoint(SystemProxySnapshot before, int port) => {
    ...before,
    'enabled': true,
    'host': '127.0.0.1',
    'port': port,
  };
  @override
  Future<void> write(SystemProxySnapshot snapshot) async {
    value = _copy(snapshot);
  }

  @override
  bool referencesEndpoint(SystemProxySnapshot snapshot, int port) =>
      snapshot['enabled'] == true &&
      snapshot['host'] == '127.0.0.1' &&
      snapshot['port'] == port;
  @override
  bool restorationMatches(
    SystemProxySnapshot actual,
    SystemProxySnapshot before,
  ) => proxyValuesEqual(actual, before);
}

final class _Core implements ProxyCoreSession {
  _Core(this.events);
  final List<String> events;
  bool running = false;
  int starts = 0;
  int stops = 0;
  @override
  Stream<void> get exits => const Stream.empty();
  @override
  Map<String, dynamic>? get identity =>
      running ? {'pid': 42, 'created': 'owned'} : null;
  @override
  Future<void> ensureRuntime() async {}
  @override
  Future<void> start(StartVpnRequest request) async {
    events.add('start:${request.socksPort}');
    starts++;
    running = true;
  }

  @override
  Future<bool> isRunning() async => running;
  @override
  Future<void> stop() async {
    events.add('stop');
    stops++;
    running = false;
  }

  @override
  Future<void> recover(Map<String, dynamic>? identity) async {}
}

final class _Journal implements ProxyJournalStore {
  Map<String, dynamic>? value;
  @override
  Future<void> lock() async {}
  @override
  Future<Map<String, dynamic>?> read() async =>
      value == null ? null : _copy(value!);
  @override
  Future<void> write(Map<String, dynamic> record) async {
    value = _copy(record);
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

final class _ExitBinding extends AutomatedTestWidgetsFlutterBinding {
  int exits = 0;
  @override
  Future<AppExitResponse> exitApplication(
    AppExitType exitType, [
    int exitCode = 0,
  ]) async {
    exits++;
    return AppExitResponse.cancel;
  }
}

final class _Fixture {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final events = <String>[];
  final adapter = _Adapter();
  final journal = _Journal();
  late final core = _Core(events);
  late final proxy = DesktopProxyHost.forTesting(
    core: core,
    adapter: adapter,
    store: journal,
    checkPort: (_) async {},
    waitReady: (_, _) async {},
    notify: (_) async {},
  );
  ConnectionRuntime? cached;
  int stopRequests = 0;
  int preparations = 0;
  late final host = ConnectionRuntimeHost(
    writeStartFile: (runtime) async {
      cached = runtime;
    },
    prefersProxy: () async => true,
    readStatus: () async => VpnStatus.disconnected,
    stopVpn: () async => NativeVpnCommandResult(
      state: NativeVpnCommandState.success,
      status: VpnStatus.disconnected,
    ),
    startProxy: (runtime) => proxy.start(
      runtime.request,
      autoSetSystemProxy: runtime.request.autoSetSystemProxy,
    ),
    readProxyStatus: proxy.readStatus,
    stopProxy: () {
      stopRequests++;
      return proxy.stop();
    },
  );
  late final coordinator = ConnectionCoordinator(
    database: db,
    readRuntime: () async => cached,
    inspect: host.inspect,
    start: host.start,
    stop: host.stop,
    probe: (_) async => null,
    prepare: (configuration, _) async {
      preparations++;
      events.add('prepare:${configuration.policy.proxyPort}');
      return _runtime(configuration);
    },
  );

  Future<void> initialize() async {
    await coordinator.initialize(observe: false, registerReferences: false);
    await coordinator.apply(
      ConnectionConfiguration(
        connection: ConnectionSettings(trafficMode: TrafficMode.allVpn),
        policy: PlatformPolicy.fromJson({
          'captureMode': 'proxy',
          'autoSetSystemProxy': true,
          'proxyPort': 10808,
        }),
      ),
      connect: true,
    );
  }

  Future<void> failCleanup() async {
    adapter.value['bypass'] = 'changed-by-another-app';
    await expectLater(
      coordinator.disconnect(),
      throwsA(isA<ConnectionHostException>()),
    );
    expect(coordinator.state.value.phase, ConnectionPhase.failed);
    expect(coordinator.state.value.runtime?.isProxy, isTrue);
    expect(coordinator.state.value.error, isNotNull);
    expect(core.running, isTrue);
    expect(core.stops, 0);
    expect(journal.value, isNotNull);
  }

  void resolveConflict() => adapter.value['bypass'] = _before['bypass'];

  Future<void> close() async {
    resolveConflict();
    await proxy.stop();
    coordinator.dispose();
    await db.close();
  }
}

ConnectionRuntime _runtime(ConnectionConfiguration configuration) {
  const json = '{"outbounds":[{"tag":"proxy","protocol":"freedom"}]}';
  return ConnectionRuntime.create(
    configuration: configuration,
    platform: ConnectionPlatform.macos,
    compiled: CompiledConnection(
      xrayJson: json,
      entries: [],
      finalExit: null,
      nodeTags: {},
    ),
    request: StartVpnRequest(
      null,
      '${configuration.policy.proxyPort}',
      '18081',
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(json).toJson(),
        ).toJson(),
      ),
      captureMode: 'proxy',
      autoSetSystemProxy: true,
    ),
  );
}

void main() {
  final binding = _ExitBinding();
  AppEventBus();
  late _Fixture fixture;
  setUp(() async {
    binding.exits = 0;
    fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.initialize();
  });

  test('Disconnect retries owned cleanup despite the real hosts latched recovery error', () async {
    await fixture.failCleanup();
    final firstRequests = fixture.stopRequests;
    await expectLater(
      fixture.coordinator.disconnect(),
      throwsA(isA<ConnectionHostException>()),
    );
    expect(fixture.stopRequests, firstRequests + 1);
    expect(fixture.core.running, isTrue);
    expect(fixture.adapter.value['bypass'], 'changed-by-another-app');

    fixture.resolveConflict();
    expect(
      (await fixture.proxy.readStatus()).state,
      NativeVpnCommandState.failed,
    );
    await fixture.coordinator.disconnect();

    expect(fixture.core.running, isFalse);
    expect(fixture.adapter.value, _before);
    expect(fixture.journal.value, isNull);
    expect(fixture.coordinator.state.value.phase, ConnectionPhase.disconnected);
    expect(fixture.coordinator.state.value.runtime, isNull);
  });

  test(
    'Quit reaches owned cleanup after the system proxy conflict is resolved',
    () async {
      await fixture.failCleanup();
      var shown = 0;
      final tray = TrayService.forTesting(
        coordinator: fixture.coordinator,
        connect: () async => fail('Quit must not start Core'),
        notify: (_) async =>
            fail('Quit must not send a connection notification'),
        showMainWindow: () async => shown++,
      );
      await tray.onMenuAction(TrayMenuEntry(key: 'quitApp'));
      expect(binding.exits, 0);
      expect(shown, 1);
      expect(fixture.core.running, isTrue);
      fixture.resolveConflict();

      await tray.onMenuAction(TrayMenuEntry(key: 'quitApp'));

      expect(binding.exits, 1);
      expect(fixture.core.running, isFalse);
      expect(fixture.adapter.value, _before);
      expect(fixture.journal.value, isNull);
    },
  );

  test('Save and Reconnect cleans the old proxy before preparing or saving the new one', () async {
    await fixture.failCleanup();
    final before = await fixture.coordinator.configuration;
    final next = ConnectionConfiguration(
      connection: before.connection,
      policy: PlatformPolicy.fromJson({
        ...before.policy.toJson(),
        'proxyPort': 10818,
      }),
    );
    var savedAssets = 0;
    await expectLater(
      fixture.coordinator.apply(
        next,
        allowReconnect: true,
        writeAssets: () async => savedAssets++,
      ),
      throwsA(isA<ConnectionHostException>()),
    );
    expect((await fixture.coordinator.configuration).encode(), before.encode());
    expect(fixture.core.starts, 1);
    expect(fixture.preparations, 1);
    expect(savedAssets, 0);
    expect(fixture.coordinator.state.value.runtime, same(fixture.cached));
    fixture.resolveConflict();

    await fixture.coordinator.apply(
      next,
      allowReconnect: true,
      writeAssets: () async => savedAssets++,
    );

    expect(
      fixture.events.indexOf('stop'),
      lessThan(fixture.events.indexOf('prepare:10818')),
    );
    expect(fixture.core.starts, 2);
    expect(fixture.core.stops, 1);
    expect(savedAssets, 1);
    expect((await fixture.coordinator.configuration).policy.proxyPort, 10818);
    expect(fixture.coordinator.state.value.phase, ConnectionPhase.connected);
    expect(fixture.adapter.value['port'], 10818);
    expect(fixture.journal.value?['port'], 10818);
  });

  test(
    'a failed inspection cannot bypass Save and Reconnect confirmation',
    () async {
      await fixture.failCleanup();
      final before = await fixture.coordinator.configuration;
      final requests = fixture.stopRequests;
      final next = ConnectionConfiguration(
        connection: before.connection,
        policy: PlatformPolicy.fromJson({
          ...before.policy.toJson(),
          'proxyPort': 10818,
        }),
      );

      await expectLater(
        fixture.coordinator.apply(next, allowReconnect: false),
        throwsA(
          isA<ConnectionHostException>().having(
            (error) => error.reason,
            'reason',
            'reconnectRequired',
          ),
        ),
      );

      expect(fixture.stopRequests, requests);
      expect(fixture.core.running, isTrue);
      expect(
        (await fixture.coordinator.configuration).encode(),
        before.encode(),
      );
    },
  );
}
