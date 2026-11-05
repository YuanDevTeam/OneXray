import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/desktop_core_exit.dart';
import 'package:onexray/core/ffi/windows/core_process.dart';
import 'package:onexray/core/ffi/windows/exe_ffi_api.dart';
import 'package:onexray/core/ffi/windows/ffi_api.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/ffi/windows/msix_ffi_api.dart';
import 'package:onexray/core/ffi/windows/native_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/model/tun_json.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late _Process process;
  late List<VpnStatus> events;
  late List<Object> errors;

  WindowsExeFfiApi create({Future<StartVpnRequest> Function()? readRequest}) =>
      WindowsExeFfiApi(
        filesDirectory: directory.path,
        executable: p.join(directory.path, 'OneXrayCore.exe'),
        process: process,
        readRequest:
            readRequest ??
            () async => StartVpnRequest(
              TunJson.fromJson({
                'tunDnsIPv4': '8.8.8.8',
                'autoOutboundsInterface': 'Ethernet 2',
              }),
              '18187',
              '18186',
              jsonEncode(
                LibXrayInvokeRequest(
                  method: LibXrayMethod.runXray,
                  payload: RunXrayRequest('{"inbounds":[]}').toJson(),
                ).toJson(),
              ),
            ),
        notify: (status) async => events.add(status),
        notifyError: (error) => errors.add(error),
      );

  setUp(() async {
    final root = Directory('../references/windows-exe-tests').absolute;
    await root.create(recursive: true);
    directory = await root.createTemp('ffi-');
    process = _Process();
    events = [];
    errors = [];
    addTearDown(() => directory.delete(recursive: true));
  });

  test('the compile-time mode chooses one Windows implementation', () {
    const configured = String.fromEnvironment(
      'ONEXRAY_WINDOWS_MODE',
      defaultValue: 'exe',
    );
    expect(windowsBuildMode.name, configured);
    expect(
      WindowsFfiApi(),
      configured == 'msix' ? isA<WindowsMsixFfiApi>() : isA<WindowsExeFfiApi>(),
    );
  });

  test(
    'MSIX environment failures never fall back to an unpackaged directory',
    () async {
      final api = WindowsMsixFfiApi(
        native: WindowsNativeApi.forTest((_) async {
          throw StateError('Package identity is unavailable');
        }),
      );
      await expectLater(api.getTunFilesDir(), throwsStateError);
    },
  );

  test('EXE discovers a named Core without any saved PID record', () async {
    process.running = true;
    final api = create();
    expect((await api.readVpnStatus()).status, VpnStatus.connected);
  });

  test('EXE stops every named Core without a saved PID record', () async {
    process.pids.addAll({42, 84});
    final api = create();
    expect((await api.stopVpn()).state, NativeVpnCommandState.success);
    expect((await api.readVpnStatus()).status, VpnStatus.disconnected);
  });

  test(
    'EXE query failures are unknown, not disconnected or safe to clean',
    () async {
      process.queryError = StateError('process enumeration denied');
      final api = create();
      final result = await api.readVpnStatus();
      expect(result.state, NativeVpnCommandState.failed);
      expect(result.status, isNull);
      expect(result.message, contains('enumeration denied'));
      expect(await api.cleanupStaleCore(), isFalse);
      await expectLater(api.observeVpnStatus(), throwsStateError);
      expect(events, isEmpty);
    },
  );

  test('empty EXE status/stop need no Vole or package identity', () async {
    final api = create();
    expect(await api.getTunFilesDir(), directory.path);
    expect((await api.readVpnStatus()).status, VpnStatus.disconnected);
    expect((await api.stopVpn()).status, VpnStatus.disconnected);
    expect(process.stops, 0);
  });

  test(
    'an unusable legacy PID file cannot block EXE lifecycle actions',
    () async {
      final legacy = Directory(
        p.join(directory.path, 'run', 'core-process.json'),
      );
      await legacy.create(recursive: true);
      process.pids.add(777);
      final api = create();
      expect((await api.readVpnStatus()).status, VpnStatus.connected);
      expect((await api.startVpn()).status, VpnStatus.connected);
      expect((await create().stopVpn()).status, VpnStatus.disconnected);
      expect(await legacy.exists(), isTrue);
    },
  );

  test(
    'failed old-Core stop prevents input replacement and a new start',
    () async {
      process.pids.addAll({10, 20});
      process.failStop = true;
      final old = File(
        p.join(directory.path, 'run', 'core-inputs', 'old.json'),
      );
      await old.parent.create(recursive: true);
      await old.writeAsString('{}');
      final access = File(p.join(directory.path, 'run', 'access.log'));
      await access.writeAsString('previous connection');
      var requestRead = false;
      final api = create(
        readRequest: () async {
          requestRead = true;
          throw StateError('must not prepare a new start');
        },
      );
      final result = await api.startVpn();
      expect(result.state, NativeVpnCommandState.failed);
      expect(result.message, contains('Stop failed'));
      expect(requestRead, isFalse);
      expect(await old.exists(), isTrue);
      expect(await access.readAsString(), 'previous connection');
      expect(process.arguments, isNull);
      expect((await api.readVpnStatus()).status, VpnStatus.connected);
      expect(events, isNot(contains(VpnStatus.disconnected)));
    },
  );

  test('EXE replaces all existing named Cores before starting', () async {
    process.pids.addAll({10, 20});
    final access = File(p.join(directory.path, 'run', 'access.log'));
    final error = File(p.join(directory.path, 'run', 'error.log'));
    await access.parent.create(recursive: true);
    await access.writeAsString('old access');
    await error.writeAsString('old error');
    process.onStart = () async {
      expect(process.pids, isEmpty);
      expect(await access.exists(), isFalse);
      expect(await error.exists(), isFalse);
      await error.writeAsString('current connection');
    };
    final api = create();
    expect((await api.startVpn()).status, VpnStatus.connected);
    expect(process.pids, {42});
    expect(await error.readAsString(), 'current connection');
  });

  test(
    'an invalid managed log blocks EXE launch and preserves both inputs',
    () async {
      final access = File(p.join(directory.path, 'run', 'access.log'));
      await access.parent.create(recursive: true);
      await access.writeAsString('old access');
      await Directory(p.join(access.parent.path, 'error.log')).create();
      final result = await create().startVpn();
      expect(result.state, NativeVpnCommandState.failed);
      expect(result.message, contains('Invalid runtime log file'));
      expect(process.arguments, isNull);
      expect(await access.readAsString(), 'old access');
    },
  );

  test(
    'EXE starts with current CLI arguments and replaces old inputs',
    () async {
      final old = File(
        p.join(directory.path, 'run', 'core-inputs', 'old.json'),
      );
      await old.parent.create(recursive: true);
      await old.writeAsString('{}');
      final api = create();
      final starting = api.startVpn();
      await process.launched.future;
      expect((await api.readVpnStatus()).status, VpnStatus.connecting);
      expect((await starting).status, VpnStatus.connected);
      expect(await old.exists(), false);
      expect(process.arguments!.take(5), [
        'run',
        '-dns',
        '8.8.8.8:53',
        '-interface',
        'Ethernet 2',
      ]);
      expect(process.arguments![5], '-config');
      expect(
        await File(process.arguments![6]).readAsString(),
        '{"inbounds":[]}',
      );
      expect(process.arguments![7], '-error-file');
      expect(process.arguments!.last, '${process.arguments![6]}.error');
      expect(await File(process.arguments!.last).readAsString(), isEmpty);
      expect(
        await File(p.join(directory.path, 'run', 'core-process.json')).exists(),
        isFalse,
      );
      // A second App instance discovers and stops the same named process.
      final reopened = create();
      expect((await reopened.readVpnStatus()).status, VpnStatus.connected);
      expect((await reopened.stopVpn()).status, VpnStatus.disconnected);
    },
  );

  test(
    'UAC cancellation fails without leaving a running/connecting state',
    () async {
      process.failStart = true;
      final api = create();
      final result = await api.startVpn();
      expect(result.state, NativeVpnCommandState.failed);
      expect(result.message, contains('cancelled'));
      expect((await api.readVpnStatus()).status, VpnStatus.disconnected);
      expect(events.last, VpnStatus.disconnected);
    },
  );

  test('EXE returns the actual Core startup diagnostic', () async {
    final api = create();
    final starting = api.startVpn();
    await process.launched.future;
    final arguments = process.arguments!;
    final config = arguments[arguments.indexOf('-config') + 1];
    const diagnostic =
        'failed to load geosite: category TEST-MISSING not found';
    await File('$config.error').writeAsString(diagnostic);
    process.exitPid(42);

    final result = await starting;
    expect(result.state, NativeVpnCommandState.failed);
    expect(result.message, contains(diagnostic));
    expect(events.last, VpnStatus.disconnected);
    expect((await api.readVpnStatus()).status, VpnStatus.disconnected);
  });

  test(
    'another named Core cannot mask the newly launched Core exiting',
    () async {
      final api = create();
      final starting = api.startVpn();
      await process.launched.future;
      process.exitPid(42);
      process.pids.add(84);
      final result = await starting;
      expect(result.state, NativeVpnCommandState.failed);
      expect(result.message, contains('exited during start'));
      expect((await api.readVpnStatus()).status, VpnStatus.disconnected);
      expect(events, isNot(contains(VpnStatus.connected)));
    },
  );

  test(
    'a connecting transition does not hide a native query failure',
    () async {
      final api = create();
      final starting = api.startVpn();
      await process.launched.future;
      process.queryError = StateError('process query failed');
      final status = await api.readVpnStatus();
      expect(status.state, NativeVpnCommandState.failed);
      expect(status.status, isNull);
      expect((await starting).state, NativeVpnCommandState.failed);
      expect(events, isNot(contains(VpnStatus.connected)));
    },
  );

  test(
    'stop failure keeps the actual running state available for retry',
    () async {
      final api = create();
      await api.startVpn();
      process.failStop = true;
      expect((await api.stopVpn()).state, NativeVpnCommandState.failed);
      expect((await api.readVpnStatus()).status, VpnStatus.connected);
      process.failStop = false;
      expect((await api.stopVpn()).status, VpnStatus.disconnected);
    },
  );

  test(
    'partial stop failure never announces that all Cores disconnected',
    () async {
      process.pids.addAll({42, 84});
      process.failStop = true;
      process.stopBeforeFailure = 42;
      final api = create();
      final result = await api.stopVpn();
      expect(result.state, NativeVpnCommandState.failed);
      expect(result.status, isNull);
      expect(process.pids, {84});
      expect((await api.readVpnStatus()).status, VpnStatus.connected);
      expect(events, [VpnStatus.disconnecting]);
      process.failStop = false;
      expect((await api.stopVpn()).status, VpnStatus.disconnected);
    },
  );

  test('process exit is disconnected without a saved PID record', () async {
    final api = create();
    await api.startVpn();
    process.running = false;
    expect((await api.readVpnStatus()).status, VpnStatus.disconnected);
  });

  test(
    'a failed exit wait reports an error and can be observed again',
    () async {
      process.pids.add(42);
      final api = create();
      addTearDown(api.disposeVpnStatus);
      await api.observeVpnStatus();
      process.exited.completeError(StateError('exit wait denied'));
      await Future<void>.delayed(Duration.zero);
      expect(errors.single.toString(), contains('exit wait denied'));
      expect(events, isEmpty);
      expect((await api.readVpnStatus()).status, VpnStatus.connected);
      process.exitPid(42);
      await Future<void>.delayed(Duration.zero);
      expect(events, [VpnStatus.disconnected]);
    },
  );

  test(
    'an old exit query cannot disconnect or cancel a new observation',
    () async {
      process.pids.add(42);
      final api = create();
      addTearDown(api.disposeVpnStatus);
      await api.observeVpnStatus();
      final pending = Completer<Set<int>>();
      process.nextQuery = pending.future;
      process.exitPid(42);
      await Future<void>.delayed(Duration.zero);
      api.disposeVpnStatus();
      process.pids.add(84);
      await api.observeVpnStatus();
      pending.complete({});
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      process.exitPid(84);
      await Future<void>.delayed(Duration.zero);
      expect(events, [VpnStatus.disconnected]);
    },
  );

  test(
    'a failed re-query after exit reports an error, not disconnection',
    () async {
      process.pids.add(42);
      final api = create();
      addTearDown(api.disposeVpnStatus);
      await api.observeVpnStatus();
      process.queryError = StateError('post-exit query failed');
      process.exitPid(42);
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      expect(errors.single.toString(), contains('post-exit query failed'));
      expect((await api.readVpnStatus()).state, NativeVpnCommandState.failed);
    },
  );

  for (final failQuery in [false, true]) {
    test(
      'a newer EXE read supersedes an exit query (error: $failQuery)',
      () async {
        process.pids.add(42);
        final api = create();
        addTearDown(api.disposeVpnStatus);
        await api.observeVpnStatus();
        final pending = Completer<Set<int>>();
        process.nextQuery = pending.future;
        process.exitPid(42);
        await Future<void>.delayed(Duration.zero);
        expect(process.nextQuery, isNull);

        process.pids.add(84);
        expect((await api.readVpnStatus()).status, VpnStatus.connected);
        if (failQuery) {
          pending.completeError(StateError('stale process query failed'));
        } else {
          pending.complete({});
        }
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        expect(errors, isEmpty);
        expect(process.exits[84]!.isCompleted, isFalse);
        process.exitPid(84);
        await Future<void>.delayed(Duration.zero);
        expect(events, [VpnStatus.disconnected]);
      },
    );
  }

  test(
    'a failed EXE stop invalidates pending queries without losing live watches',
    () async {
      process.pids.addAll({42, 84});
      final api = create();
      addTearDown(api.disposeVpnStatus);
      await api.observeVpnStatus();
      final pending = Completer<Set<int>>();
      process.nextQuery = pending.future;
      process.exitPid(42);
      await Future<void>.delayed(Duration.zero);
      expect(process.nextQuery, isNull);

      process.failStop = true;
      expect((await api.stopVpn()).state, NativeVpnCommandState.failed);
      events.clear();
      pending.complete({});
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      expect(errors, isEmpty);
      expect(process.exits[84]!.isCompleted, isFalse);
      process.exitPid(84);
      await Future<void>.delayed(Duration.zero);
      expect(events, [VpnStatus.disconnected]);
    },
  );

  test(
    'a restored EXE stays connected until the last named Core exits',
    () async {
      process.pids.addAll({42, 84});
      final api = create();
      addTearDown(api.disposeVpnStatus);
      await api.observeVpnStatus();
      process.exitPid(42);
      await Future<void>.delayed(Duration.zero);
      expect(events, [VpnStatus.connected]);
      process.exitPid(84);
      await Future<void>.delayed(Duration.zero);
      expect(events, [VpnStatus.connected, VpnStatus.disconnected]);
    },
  );

  test('restored EXE exits notify without another read; disposing cancels the wait', () async {
    final api = create();
    await api.startVpn();
    final restored = create();
    addTearDown(restored.disposeVpnStatus);
    await restored.observeVpnStatus();
    expect(process.watches, 1);
    events.clear();
    process.running = false;
    process.exited.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(events, [VpnStatus.disconnected]);

    process.running = true;
    process.exited = Completer<bool>();
    await restored.observeVpnStatus();
    events.clear();
    restored.disposeVpnStatus();
    await Future<void>.delayed(Duration.zero);
    expect(await process.exited.future, isFalse);
    expect(events, isEmpty);
  });

  test('Windows arguments preserve spaces, quotes and trailing slashes', () {
    expect(quoteWindowsArgument('Ethernet 2'), '"Ethernet 2"');
    expect(quoteWindowsArgument(''), '""');
    expect(quoteWindowsArgument(r'a"b'), r'"a\"b"');
    expect(quoteWindowsArgument('C:\\目录\\'), '"C:\\目录\\\\"');
    expect(quoteWindowsArgument(r'a\"b'), r'"a\\\"b"');
  });
}

class _Process extends WindowsCoreProcess {
  final pids = <int>{};
  bool get running => pids.isNotEmpty;
  set running(bool value) => value ? pids.add(42) : pids.clear();
  Object? queryError;
  Future<Set<int>>? nextQuery;
  bool failStart = false;
  bool failStop = false;
  Future<void> Function()? onStart;
  int? stopBeforeFailure;
  int stops = 0;
  List<String>? arguments;
  final launched = Completer<void>();
  final exits = <int, Completer<bool>>{};
  Completer<bool> get exited => exits.putIfAbsent(42, Completer<bool>.new);
  set exited(Completer<bool> value) => exits[42] = value;
  int watches = 0;

  void exitPid(int pid) {
    pids.remove(pid);
    final completion = exits[pid];
    if (completion != null && !completion.isCompleted) {
      completion.complete(true);
    }
  }

  @override
  Future<Set<int>> findPids() async {
    if (queryError != null) throw queryError!;
    final pending = nextQuery;
    nextQuery = null;
    return pending == null ? {...pids} : await pending;
  }

  @override
  Future<void> stopAll() async {
    if (failStop) {
      if (stopBeforeFailure != null) exitPid(stopBeforeFailure!);
      throw StateError('Stop failed');
    }
    if (pids.isNotEmpty) stops++;
    pids.clear();
  }

  @override
  DesktopCoreExitWatch watchExit(int pid) {
    watches++;
    final completion = Completer<bool>();
    exits[pid] = completion;
    return DesktopCoreExitWatch(completion.future, () {
      if (!completion.isCompleted) completion.complete(false);
    });
  }

  @override
  Future<int> start(String executable, List<String> arguments) async {
    await onStart?.call();
    if (failStart) throw StateError('UAC cancelled');
    this.arguments = arguments;
    running = true;
    launched.complete();
    return 42;
  }
}
