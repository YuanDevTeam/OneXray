import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/proxy/core_session.dart';
import 'package:onexray/core/proxy/host.dart';
import 'package:onexray/core/proxy/journal.dart';
import 'package:onexray/core/proxy/system_proxy.dart';
import 'package:onexray/core/proxy/windows_proxy.dart';
import 'package:onexray/core/proxy/gnome_proxy.dart';

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

const _baseline = <String, dynamic>{
  'flags': 13,
  'server': 'http=old.proxy:8080;https=secure.proxy:8081',
  'bypass': '<local>;*.example.test',
  'autoConfigUrl': 'https://config.example.test/proxy.pac',
};

StartVpnRequest _request({String port = '10808', String metrics = '10809'}) =>
    StartVpnRequest(null, port, metrics, 'unused-by-fake-core');

final class _Adapter implements SystemProxyAdapter {
  _Adapter(this.events);
  final List<String> events;
  Map<String, dynamic> value = _copy(_baseline);
  bool supported = true;
  Future<void> Function(SystemProxySnapshot)? writer;
  int writes = 0;
  int reads = 0;
  Future<void>? readGate;
  void Function()? onRead;

  @override
  String get id => 'fake-user-proxy';
  @override
  Future<DesktopSystemProxyCapability> capability() async =>
      DesktopSystemProxyCapability(
        supported: supported,
        reason: supported ? null : 'Managed desktop',
      );
  @override
  Future<SystemProxySnapshot> read() async {
    reads++;
    events.add('settings-read');
    onRead?.call();
    await readGate;
    return _copy(value);
  }

  @override
  SystemProxySnapshot forEndpoint(SystemProxySnapshot before, int port) =>
      WindowsSystemProxyAdapter().forEndpoint(before, port);
  @override
  Future<void> write(SystemProxySnapshot snapshot) async {
    events.add(snapshot['flags'] == 3 ? 'settings-apply' : 'settings-restore');
    writes++;
    if (writer != null) return writer!(snapshot);
    value = _copy(snapshot);
  }

  @override
  bool referencesEndpoint(SystemProxySnapshot snapshot, int port) =>
      WindowsSystemProxyAdapter().referencesEndpoint(snapshot, port);

  @override
  bool restorationMatches(
    SystemProxySnapshot actual,
    SystemProxySnapshot before,
  ) => proxyValuesEqual(actual, before);
}

final class _Core implements ProxyCoreSession {
  _Core(this.events);
  final List<String> events;
  final controller = StreamController<void>.broadcast(sync: true);
  bool running = false;
  bool failStart = false;
  int starts = 0;
  int stops = 0;
  int recovered = 0;
  int reads = 0;
  @override
  Map<String, dynamic>? get identity =>
      running ? {'pid': 42, 'created': 'fixture'} : null;
  @override
  Stream<void> get exits => controller.stream;
  @override
  Future<void> ensureRuntime() async => events.add('runtime-check');
  @override
  Future<void> start(StartVpnRequest request) async {
    events.add('core-start');
    starts++;
    if (failStart) throw StateError('Core failed');
    running = true;
  }

  @override
  Future<bool> isRunning() async {
    reads++;
    return running;
  }

  @override
  Future<void> stop() async {
    events.add('core-stop');
    stops++;
    running = false;
  }

  @override
  Future<void> recover(Map<String, dynamic>? identity) async {
    events.add('core-recover');
    recovered++;
    running = false;
  }

  void crash() {
    running = false;
    controller.add(null);
  }
}

final class _Journal implements ProxyJournalStore {
  _Journal(this.events);
  final List<String> events;
  Map<String, dynamic>? value;
  bool failLock = false;
  int clears = 0;
  int locks = 0;
  @override
  Future<void> lock() async {
    locks++;
    if (failLock) throw StateError('Another App owns this session');
  }

  @override
  Future<Map<String, dynamic>?> read() async =>
      value == null ? null : _copy(value!);
  @override
  Future<void> write(Map<String, dynamic> record) async {
    events.add('journal-${record['phase']}');
    value = _copy(record);
  }

  @override
  Future<void> clear() async {
    events.add('journal-clear');
    clears++;
    value = null;
  }
}

final class _InheritedAdapter implements SystemProxyAdapter {
  Map<String, dynamic> value = {
    'mode': {'effective': "'none'", 'user': null},
  };
  @override
  String get id => 'fixture-gnome';
  @override
  Future<DesktopSystemProxyCapability> capability() async =>
      const DesktopSystemProxyCapability(supported: true);
  @override
  Future<SystemProxySnapshot> read() async => _copy(value);
  @override
  SystemProxySnapshot forEndpoint(SystemProxySnapshot before, int port) => {
    'mode': {'effective': "'manual'", 'user': "'manual'"},
  };
  @override
  Future<void> write(SystemProxySnapshot snapshot) async {
    value = _copy(snapshot);
    if ((value['mode'] as Map)['user'] == null) {
      // reset() inherits a new default changed while OneXray was running.
      (value['mode'] as Map)['effective'] = "'auto'";
    }
  }

  @override
  bool restorationMatches(
    SystemProxySnapshot actual,
    SystemProxySnapshot before,
  ) => GnomeSystemProxyAdapter().restorationMatches(actual, before);
  @override
  bool referencesEndpoint(SystemProxySnapshot snapshot, int port) =>
      (snapshot['mode'] as Map)['effective'] == "'manual'";
}

void main() {
  late List<String> events;
  late _Adapter adapter;
  late _Core core;
  late _Journal journal;
  late DesktopProxyHost host;
  setUp(() {
    events = [];
    adapter = _Adapter(events);
    core = _Core(events);
    journal = _Journal(events);
    host = DesktopProxyHost.forTesting(
      core: core,
      adapter: adapter,
      store: journal,
      checkPort: (_) async => events.add('port-check'),
      waitReady: (_, _) async => events.add('listener-ready'),
      notify: (_) async => events.add('notify-disconnected'),
    );
  });
  tearDown(() async => core.controller.close());

  test('auto start confirms readiness and journals before applying; stop restores before closing Core', () async {
    final started = await host.start(_request(), autoSetSystemProxy: true);
    expect(started.state, NativeVpnCommandState.success);
    expect(started.status, VpnStatus.connected);
    expect(host.systemProxyActive, isTrue);
    expect(
      events.indexOf('listener-ready'),
      lessThan(events.indexOf('settings-apply')),
    );
    expect(
      events.indexOf('journal-applying'),
      lessThan(events.indexOf('settings-apply')),
    );
    expect(journal.value?['phase'], 'active');
    expect(adapter.value['bypass'], _baseline['bypass']);
    expect(adapter.value['autoConfigUrl'], _baseline['autoConfigUrl']);
    final stopped = await host.stop();
    expect(stopped.state, NativeVpnCommandState.success);
    expect(adapter.value, _baseline);
    expect(
      events.indexOf('settings-restore'),
      lessThan(events.indexOf('core-stop')),
    );
    expect(journal.value, isNull);
    expect(host.systemProxyActive, isFalse);
  });

  test('manual mode works when automatic settings are unsupported and never reads OS settings', () async {
    adapter.supported = false;
    expect(
      (await host.start(_request(), autoSetSystemProxy: false)).state,
      NativeVpnCommandState.success,
    );
    expect((await host.readStatus()).status, VpnStatus.connected);
    expect(host.systemProxyActive, isFalse);
    expect((await host.stop()).state, NativeVpnCommandState.success);
    expect(events.where((event) => event.startsWith('settings-')), isEmpty);
  });

  test('an unsupported automatic mode fails before starting a Core or writing state', () async {
    adapter.supported = false;
    expect(
      (await host.start(_request(), autoSetSystemProxy: true)).state,
      NativeVpnCommandState.failed,
    );
    expect(core.starts, 0);
    expect(journal.value, isNull);
    expect(journal.clears, 0);
  });

  test('an external endpoint change is preserved and clears the actual automatic status', () async {
    await host.start(_request(), autoSetSystemProxy: true);
    adapter.value['server'] = 'http=other.proxy:3128;https=other.proxy:3128';
    final external = _copy(adapter.value);
    expect((await host.readStatus()).status, VpnStatus.connected);
    expect(host.systemProxyActive, isFalse);
    expect((await host.stop()).state, NativeVpnCommandState.success);
    expect(adapter.value, external);
    expect(adapter.writes, 1);
    expect(core.running, isFalse);
  });

  test('a changed bypass with our endpoint keeps Core alive rather than overwriting outside changes', () async {
    await host.start(_request(), autoSetSystemProxy: true);
    adapter.value['bypass'] = 'user-added.example';
    final stopped = await host.stop();
    expect(stopped.state, NativeVpnCommandState.failed);
    expect(core.running, isTrue);
    expect(core.stops, 0);
    expect(adapter.value['bypass'], 'user-added.example');
    expect(journal.value, isNotNull);
    adapter.value = _copy(_baseline); // user resolves the conflict
    expect((await host.stop()).state, NativeVpnCommandState.success);
    expect(core.running, isFalse);
  });

  test('an apply failure with a known partial write rolls back before stopping Core', () async {
    adapter.writer = (snapshot) async {
      if (snapshot['flags'] == 3) {
        adapter.value['server'] = snapshot['server'];
        throw StateError('Write failed part way through');
      }
      adapter.value = _copy(snapshot);
    };
    final started = await host.start(_request(), autoSetSystemProxy: true);
    expect(started.state, NativeVpnCommandState.failed);
    expect(adapter.value, _baseline);
    expect(
      events.indexOf('settings-restore'),
      lessThan(events.indexOf('core-stop')),
    );
    expect(core.running, isFalse);
    expect(journal.value, isNull);
  });

  test('rollback failure retains the live Core and recovery journal', () async {
    adapter.writer = (snapshot) async {
      if (snapshot['flags'] == 3) {
        adapter.value = _copy(snapshot);
        throw StateError('Unable to confirm setting refresh');
      }
      throw StateError('Restore is blocked');
    };
    final result = await host.start(_request(), autoSetSystemProxy: true);
    expect(result.state, NativeVpnCommandState.failed);
    expect(result.message, contains('Restore is blocked'));
    expect(core.running, isTrue);
    expect(core.stops, 0);
    expect(journal.value, isNotNull);
    expect((await host.readStatus()).state, NativeVpnCommandState.failed);
  });

  test(
    'cold recovery restores owned settings before recovering the recorded Core',
    () async {
      final expected = adapter.forEndpoint(_copy(_baseline), 10808);
      adapter.value = _copy(expected);
      journal.value = {
        'version': 1,
        'automatic': true,
        'adapter': adapter.id,
        'port': 10808,
        'phase': 'active',
        'before': _baseline,
        'expected': expected,
        'core': {'pid': 42, 'created': 'fixture'},
      };
      await host.recover();
      expect(adapter.value, _baseline);
      expect(
        events.indexOf('settings-restore'),
        lessThan(events.indexOf('core-recover')),
      );
      expect(core.recovered, 1);
      expect(journal.value, isNull);
    },
  );

  test(
    'a lock failure never clears another live Apps journal or stops its Core',
    () async {
      journal.failLock = true;
      journal.value = {'version': 1, 'owner': 'another App'};
      final result = await host.start(_request(), autoSetSystemProxy: false);
      expect(result.state, NativeVpnCommandState.failed);
      expect(core.starts, 0);
      expect(core.stops, 0);
      expect(journal.clears, 0);
      expect(journal.value?['owner'], 'another App');
    },
  );

  test('unavailable listeners fail without any OS proxy write', () async {
    host = DesktopProxyHost.forTesting(
      core: core,
      adapter: adapter,
      store: journal,
      checkPort: (_) async {},
      waitReady: (_, _) async => throw StateError('No listener'),
    );
    final result = await host.start(_request(), autoSetSystemProxy: true);
    expect(result.state, NativeVpnCommandState.failed);
    expect(adapter.writes, 0);
    expect(core.running, isFalse);
    expect(journal.value, isNull);
  });

  test('occupied ports are rejected before starting Core', () async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(listener.close);
    host = DesktopProxyHost.forTesting(
      core: core,
      adapter: adapter,
      store: journal,
      waitReady: (_, _) async {},
    );
    final result = await host.start(
      _request(port: '${listener.port}'),
      autoSetSystemProxy: false,
    );
    expect(result.state, NativeVpnCommandState.failed);
    expect(core.starts, 0);
    expect(journal.clears, 0);
  });

  test('start and stop are serialized through readiness', () async {
    final entered = Completer<void>();
    final ready = Completer<void>();
    host = DesktopProxyHost.forTesting(
      core: core,
      adapter: adapter,
      store: journal,
      checkPort: (_) async {},
      waitReady: (_, _) async {
        entered.complete();
        await ready.future;
      },
    );
    final start = host.start(_request(), autoSetSystemProxy: true);
    await entered.future;
    final stop = host.stop();
    expect(core.stops, 0);
    ready.complete();
    expect((await start).state, NativeVpnCommandState.success);
    expect((await stop).state, NativeVpnCommandState.success);
    expect(adapter.value, _baseline);
    expect(core.running, isFalse);
  });

  test(
    'unexpected exit restores settings before notifying the coordinator',
    () async {
      final notified = Completer<void>();
      host = DesktopProxyHost.forTesting(
        core: core,
        adapter: adapter,
        store: journal,
        checkPort: (_) async {},
        waitReady: (_, _) async {},
        notify: (_) async {
          events.add('notify-disconnected');
          notified.complete();
        },
      );
      await host.start(_request(), autoSetSystemProxy: true);
      core.crash();
      await notified.future;
      expect(adapter.value, _baseline);
      expect(
        events.indexOf('settings-restore'),
        lessThan(events.indexOf('notify-disconnected')),
      );
      expect(journal.value, isNull);
      expect((await host.readStatus()).status, VpnStatus.disconnected);
    },
  );

  test(
    'mobile startup recovery is a no-op and never constructs desktop state',
    () async {
      host = DesktopProxyHost.forTesting(
        core: core,
        adapter: adapter,
        store: journal,
        desktop: false,
      );
      await host.recover();
      expect(journal.locks, 0);
      expect(core.recovered, 0);
      expect(events, isEmpty);
      expect((await host.capability()).supported, isFalse);
    },
  );

  test(
    'a delayed old Core exit cannot retire the replacement session',
    () async {
      final entered = Completer<void>();
      final ready = Completer<void>();
      var notifications = 0;
      host = DesktopProxyHost.forTesting(
        core: core,
        adapter: adapter,
        store: journal,
        checkPort: (_) async {},
        waitReady: (_, _) async {
          if (core.starts == 2) {
            entered.complete();
            await ready.future;
          }
        },
        notify: (_) async {
          notifications++;
        },
      );
      await host.start(_request(), autoSetSystemProxy: false);
      await host.stop();
      final replacement = host.start(_request(), autoSetSystemProxy: false);
      await entered.future;
      core.controller.add(null); // delayed notification from the retired child
      ready.complete();
      expect((await replacement).state, NativeVpnCommandState.success);
      expect((await host.readStatus()).status, VpnStatus.connected);
      expect(core.starts, 2);
      expect(core.stops, 1);
      expect(journal.value?['phase'], 'active');
      expect(notifications, 0);
      await host.stop();
    },
  );

  test(
    'GNOME reset restoration accepts changed inherited defaults and stops Core',
    () async {
      final inherited = _InheritedAdapter();
      host = DesktopProxyHost.forTesting(
        core: core,
        adapter: inherited,
        store: journal,
        checkPort: (_) async {},
        waitReady: (_, _) async {},
        notify: (_) async {},
      );
      await host.start(_request(), autoSetSystemProxy: true);
      final result = await host.stop();
      expect(result.state, NativeVpnCommandState.success);
      expect(inherited.value, {
        'mode': {'effective': "'auto'", 'user': null},
      });
      expect(core.running, isFalse);
      expect(journal.value, isNull);
    },
  );

  test(
    'automatic proxy observes external setting changes without polling Core',
    () async {
      final changed = Completer<void>();
      var notifications = 0;
      host = DesktopProxyHost.forTesting(
        core: core,
        adapter: adapter,
        store: journal,
        checkPort: (_) async {},
        waitReady: (_, _) async {},
        systemProxyPollInterval: const Duration(milliseconds: 10),
        notify: (status) async {
          expect(status, VpnStatus.connected);
          notifications++;
          if (!changed.isCompleted) changed.complete();
        },
      );
      await host.start(_request(), autoSetSystemProxy: true);
      final coreReads = core.reads;
      adapter.value['server'] =
          'http=external.proxy:3128;https=external.proxy:3128';
      final external = _copy(adapter.value);
      await changed.future.timeout(const Duration(seconds: 2));
      expect(host.systemProxyActive, isFalse);
      expect(adapter.value, external);
      expect(adapter.writes, 1);
      expect(core.reads, coreReads);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(notifications, 1);
      await host.stop();
    },
  );

  test(
    'settings observation never queues overlapping reads and stops after stop',
    () async {
      host = DesktopProxyHost.forTesting(
        core: core,
        adapter: adapter,
        store: journal,
        checkPort: (_) async {},
        waitReady: (_, _) async {},
        systemProxyPollInterval: const Duration(milliseconds: 10),
        notify: (_) async {},
      );
      await host.start(_request(), autoSetSystemProxy: true);
      final entered = Completer<void>();
      final gate = Completer<void>();
      adapter.readGate = gate.future;
      adapter.onRead = () {
        if (!entered.isCompleted) entered.complete();
      };
      final before = adapter.reads;
      await entered.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(adapter.reads - before, 1);
      final stopping = host.stop();
      gate.complete();
      expect((await stopping).state, NativeVpnCommandState.success);
      final stoppedReads = adapter.reads;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(adapter.reads, stoppedReads);
      expect(host.systemProxyActive, isFalse);
    },
  );

  test(
    'SOCKS readiness checks the protocol without contacting an external target',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final accepted = Completer<List<int>>();
      final subscription = server.listen((socket) {
        socket.listen((bytes) {
          if (!accepted.isCompleted) accepted.complete(bytes);
          socket.add([5, 0]);
        });
      });
      addTearDown(subscription.cancel);
      await waitForProxyListener(server.port, () async => true);
      expect(await accepted.future, [5, 1, 0]);
    },
  );
}
