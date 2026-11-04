import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/desktop_core_exit.dart';
import 'package:onexray/core/ffi/linux_ffi_api.dart';
import 'package:onexray/core/model/tun_json.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'discovers live Core processes through procps without a procfs mirror',
    () async {
      final fixture = await _Fixture.create();
      fixture.pids.addAll([42, 43]);
      final api = fixture.api();

      expect(await api.queryCoreRunning(), isTrue);
      expect((await api.readVpnStatus()).status, VpnStatus.connected);
      expect(
        fixture.commands,
        everyElement(['pgrep', '-x', '-r', 'R,S,D,T,t,I', 'OneXrayCore']),
      );
    },
  );

  test(
    'stops all matching Cores through exact-name pkill and confirms exit',
    () async {
      final fixture = await _Fixture.create();
      fixture.pids.addAll([42, 43]);
      final api = fixture.api();

      expect((await api.stopVpn()).status, VpnStatus.disconnected);
      expect((await api.readVpnStatus()).status, VpnStatus.disconnected);
      expect(fixture.pkills, [
        ['pkill', '-TERM', '-x', 'OneXrayCore'],
      ]);
      expect(fixture.watchedPids, unorderedEquals([42, 43]));
      expect(fixture.events, [VpnStatus.disconnecting, VpnStatus.disconnected]);
    },
  );

  test('pgrep exit 1 means no live Core and needs no signal', () async {
    final fixture = await _Fixture.create();
    final api = fixture.api();

    expect((await api.readVpnStatus()).status, VpnStatus.disconnected);
    expect(await api.stopCore(), isTrue);
    expect(fixture.pkills, isEmpty);
  });

  test(
    'unreadable legacy PID records do not block discovery or stop',
    () async {
      final fixture = await _Fixture.create();
      final oldRecord = File(
        p.join(fixture.directory.path, 'run', 'core-process.json'),
      );
      await oldRecord.parent.create();
      await oldRecord.writeAsString('invalid JSON');
      fixture.pids.add(42);
      final api = fixture.api();

      expect(await api.cleanupStaleCore(), isTrue);
      expect(fixture.pkills, isEmpty);
      expect((await api.readVpnStatus()).status, VpnStatus.connected);
      expect(await api.stopCore(), isTrue);
      expect((await api.readVpnStatus()).status, VpnStatus.disconnected);
    },
  );

  test('a discovered Core publishes its exit without a status poll', () async {
    final fixture = await _Fixture.create();
    fixture.pids.add(42);
    final api = fixture.api();
    await api.observeVpnStatus();

    final nextStatus = fixture.nextStatus();
    fixture.exitProcess(42);
    expect(await nextStatus, VpnStatus.disconnected);
  });

  test(
    'an owned Core publishes Process.exitCode without a pidfd watch',
    () async {
      final fixture = await _Fixture.create();
      final process = _OwnedProcess(42);
      addTearDown(process.finish);
      final access = File(p.join(fixture.directory.path, 'run', 'access.log'));
      await access.parent.create(recursive: true);
      await access.writeAsString('old access');
      final api = fixture.api(
        startProcess: (_, _) async {
          expect(await access.exists(), isFalse);
          await access.writeAsString('current connection');
          fixture.pids.add(process.pid);
          return process;
        },
      );
      await api.observeVpnStatus();
      expect(await api.startCore(_runConfig(), _tunConfig()), isTrue);
      expect(await access.readAsString(), 'current connection');
      expect(fixture.watchedPids, isEmpty);

      final nextStatus = fixture.nextStatus();
      fixture.pids.remove(process.pid);
      process.finish();
      expect(await nextStatus, VpnStatus.disconnected);

      // Once the owned process exits, a later discovered process uses pidfd again.
      fixture.pids.add(process.pid);
      expect((await api.readVpnStatus()).status, VpnStatus.connected);
      expect(fixture.watchedPids, [process.pid]);
    },
  );

  test(
    'a retired owned exit preserves its replacement and stop wait',
    () async {
      final fixture = await _Fixture.create();
      final previous = _OwnedProcess(42);
      final current = _OwnedProcess(42);
      addTearDown(previous.finish);
      addTearDown(current.finish);
      final signalled = Completer<void>();
      var starts = 0;
      final api = fixture.api(
        startProcess: (_, _) async {
          final process = starts++ == 0 ? previous : current;
          fixture.pids.add(process.pid);
          return process;
        },
        runCommand: (executable, _) async {
          if (executable == 'pgrep') return fixture.queryResult();
          signalled.complete();
          return ProcessResult(1, 0, '', '');
        },
      );
      await api.observeVpnStatus();
      expect(await api.startCore(_runConfig(), _tunConfig()), isTrue);
      api.disposeVpnStatus();
      fixture.pids.clear();
      expect(await api.startCore(_runConfig(), _tunConfig()), isTrue);
      await api.observeVpnStatus();

      previous.finish();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.events, isEmpty);
      expect((await api.readVpnStatus()).status, VpnStatus.connected);
      api.disposeVpnStatus();
      await api.observeVpnStatus();
      expect(fixture.watchedPids, isEmpty);

      // A stop still waits for the owned process when no status observer is active.
      api.disposeVpnStatus();
      var completed = false;
      final stopped = api.stopCore().then((result) {
        completed = true;
        return result;
      });
      await signalled.future;
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      fixture.pids.clear();
      current.finish();
      expect(await stopped, isTrue);
      expect(fixture.events, isEmpty);
    },
  );

  test('only the last named Core exit disconnects the VPN', () async {
    final fixture = await _Fixture.create();
    fixture.pids.addAll([42, 43]);
    final api = fixture.api();
    await api.observeVpnStatus();

    var nextStatus = fixture.nextStatus();
    fixture.exitProcess(42);
    expect(await nextStatus, VpnStatus.connected);
    nextStatus = fixture.nextStatus();
    fixture.exitProcess(43);
    expect(await nextStatus, VpnStatus.disconnected);
  });

  test('disposing exit observation suppresses late notifications', () async {
    final fixture = await _Fixture.create();
    fixture.pids.add(42);
    final api = fixture.api();
    await api.observeVpnStatus();
    api.disposeVpnStatus();
    fixture.exitProcess(42);
    await Future<void>.delayed(Duration.zero);

    expect(fixture.events, isEmpty);
  });

  test(
    'an old exit query cannot disconnect or cancel a new observation',
    () async {
      final fixture = await _Fixture.create();
      fixture.pids.add(42);
      Future<ProcessResult>? nextQuery;
      final api = fixture.api(
        runCommand: (_, _) async {
          final pending = nextQuery;
          nextQuery = null;
          return pending ?? fixture.queryResult();
        },
      );
      await api.observeVpnStatus();
      final pending = Completer<ProcessResult>();
      nextQuery = pending.future;
      fixture.exitProcess(42);
      await Future<void>.delayed(Duration.zero);
      api.disposeVpnStatus();
      fixture.pids.add(84);
      await api.observeVpnStatus();
      pending.complete(ProcessResult(1, 1, '', ''));
      await Future<void>.delayed(Duration.zero);

      expect(fixture.events, isEmpty);
      final nextStatus = fixture.nextStatus();
      fixture.exitProcess(84);
      expect(await nextStatus, VpnStatus.disconnected);
    },
  );

  test('disposing during an exit query suppresses its late result', () async {
    final fixture = await _Fixture.create();
    fixture.pids.add(42);
    final pending = Completer<ProcessResult>();
    var queryPending = false;
    final api = fixture.api(
      runCommand: (_, _) async =>
          queryPending ? pending.future : fixture.queryResult(),
    );
    await api.observeVpnStatus();
    queryPending = true;
    fixture.exitProcess(42);
    await Future<void>.delayed(Duration.zero);
    api.disposeVpnStatus();
    pending.complete(ProcessResult(1, 1, '', ''));
    await Future<void>.delayed(Duration.zero);

    expect(fixture.events, isEmpty);
  });

  for (final failQuery in [false, true]) {
    test(
      'a newer Linux read supersedes an exit query (error: $failQuery)',
      () async {
        final fixture = await _Fixture.create();
        fixture.pids.add(42);
        Future<ProcessResult>? nextQuery;
        final api = fixture.api(
          runCommand: (_, _) async {
            final pending = nextQuery;
            nextQuery = null;
            return pending ?? fixture.queryResult();
          },
        );
        await api.observeVpnStatus();
        final pending = Completer<ProcessResult>();
        nextQuery = pending.future;
        fixture.exitProcess(42);
        await Future<void>.delayed(Duration.zero);
        expect(nextQuery, isNull);

        fixture.pids.add(84);
        expect((await api.readVpnStatus()).status, VpnStatus.connected);
        if (failQuery) {
          pending.completeError(StateError('stale process query failed'));
        } else {
          pending.complete(ProcessResult(1, 1, '', ''));
        }
        await Future<void>.delayed(Duration.zero);
        expect(fixture.events, isEmpty);
        expect(fixture._exits[84]!.isCompleted, isFalse);
        final nextStatus = fixture.nextStatus();
        fixture.exitProcess(84);
        expect(await nextStatus, VpnStatus.disconnected);
      },
    );
  }

  test('an old exit query cannot reconnect after a confirmed stop', () async {
    final fixture = await _Fixture.create();
    fixture.pids.addAll([42, 43]);
    Future<ProcessResult>? nextQuery;
    final api = fixture.api(
      runCommand: (executable, _) async {
        if (executable == 'pgrep') {
          final pending = nextQuery;
          nextQuery = null;
          return pending ?? fixture.queryResult();
        }
        fixture.exitProcess(43);
        return ProcessResult(1, 0, '', '');
      },
    );
    await api.observeVpnStatus();
    final pending = Completer<ProcessResult>();
    nextQuery = pending.future;
    fixture.exitProcess(42);
    await Future<void>.delayed(Duration.zero);
    expect((await api.stopVpn()).status, VpnStatus.disconnected);
    pending.complete(ProcessResult(1, 0, '43\n', ''));
    await Future<void>.delayed(Duration.zero);

    expect(fixture.events, [VpnStatus.disconnecting, VpnStatus.disconnected]);
    expect(fixture.watchedPids.where((pid) => pid == 43), hasLength(2));
  });

  for (final diagnostic in [
    'failed to load geosite: category TEST-MISSING not found',
    '',
  ]) {
    test('Linux preserves Core startup diagnostics: $diagnostic', () async {
      final fixture = await _Fixture.create();
      final api = fixture.api(
        startProcess: (_, arguments) async {
          final config = arguments[arguments.indexOf('-config') + 1];
          expect(
            arguments[arguments.indexOf('-error-file') + 1],
            '$config.error',
          );
          final file = File('$config.error');
          expect(await file.readAsString(), isEmpty);
          await file.writeAsString(diagnostic);
          return _ExitedProcess();
        },
        readRequest: () async => StartVpnRequest(
          TunJson.fromJson({
            'tunDnsIPv4': '8.8.8.8',
            'autoOutboundsInterface': 'eth0',
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
      );

      final result = await api.startVpn();
      expect(result.state, NativeVpnCommandState.failed);
      expect(
        result.message,
        diagnostic.isEmpty
            ? 'The Core process exited during startup.'
            : diagnostic,
      );
      expect(fixture.events.last, VpnStatus.disconnected);
    });
  }

  test('pkill exit 1 is not success while a Core still exists', () async {
    final fixture = await _Fixture.create();
    fixture.pids.add(42);
    final api = fixture.api(
      runCommand: (executable, _) async => executable == 'pgrep'
          ? fixture.queryResult()
          : ProcessResult(1, 1, '', 'permission denied'),
    );

    expect((await api.stopVpn()).state, NativeVpnCommandState.failed);
    expect((await api.readVpnStatus()).status, VpnStatus.connected);
    expect(fixture.pkills, [
      ['pkill', '-TERM', '-x', 'OneXrayCore'],
    ]);
    expect(fixture.events, [VpnStatus.disconnecting]);
  });

  test(
    'pkill exit 1 succeeds if the matched process already disappeared',
    () async {
      final fixture = await _Fixture.create();
      fixture.pids.add(42);
      final api = fixture.api(
        runCommand: (executable, _) async {
          if (executable == 'pgrep') return fixture.queryResult();
          fixture.exitProcess(42);
          return ProcessResult(1, 1, '', '');
        },
      );

      expect((await api.stopVpn()).status, VpnStatus.disconnected);
      expect(fixture.pkills, [
        ['pkill', '-TERM', '-x', 'OneXrayCore'],
      ]);
    },
  );

  test(
    'successful pkill waits for Core exit before reporting disconnected',
    () async {
      final fixture = await _Fixture.create();
      fixture.pids.add(42);
      final signalled = Completer<void>();
      final api = fixture.api(
        runCommand: (executable, _) async {
          if (executable == 'pgrep') return fixture.queryResult();
          signalled.complete();
          return ProcessResult(1, 0, '', '');
        },
      );
      var completed = false;
      final stopped = api.stopVpn().then((result) {
        completed = true;
        return result;
      });
      await signalled.future;
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(fixture.events, [VpnStatus.disconnecting]);

      fixture.exitProcess(42);
      expect((await stopped).status, VpnStatus.disconnected);
    },
  );

  test(
    'a failed final query blocks success even after the watched Core exits',
    () async {
      final fixture = await _Fixture.create();
      fixture.pids.add(42);
      var signalled = false;
      final api = fixture.api(
        runCommand: (executable, _) async {
          if (executable == 'pgrep') {
            return signalled
                ? ProcessResult(1, 3, '', 'query failed')
                : fixture.queryResult();
          }
          signalled = true;
          fixture.exitProcess(42);
          return ProcessResult(1, 0, '', '');
        },
      );

      expect((await api.stopVpn()).state, NativeVpnCommandState.failed);
      expect(fixture.events, [VpnStatus.disconnecting]);
    },
  );

  test(
    'an unresponsive Core receives exact-name KILL after the graceful deadline',
    () async {
      final fixture = await _Fixture.create();
      fixture.pids.add(42);
      final api = fixture.api(
        runCommand: (executable, arguments) async {
          if (executable == 'pgrep') return fixture.queryResult();
          if (arguments.first == '-KILL') fixture.exitProcess(42);
          return ProcessResult(1, 0, '', '');
        },
      );

      expect((await api.stopVpn()).status, VpnStatus.disconnected);
      expect(fixture.pkills, [
        ['pkill', '-TERM', '-x', 'OneXrayCore'],
        ['pkill', '-KILL', '-x', 'OneXrayCore'],
      ]);
    },
  );

  test(
    'even a successful KILL is not a confirmed stop while Core remains',
    () async {
      final fixture = await _Fixture.create();
      fixture.pids.add(42);
      final api = fixture.api(
        runCommand: (executable, _) async => executable == 'pgrep'
            ? fixture.queryResult()
            : ProcessResult(1, 0, '', ''),
      );

      expect((await api.stopVpn()).state, NativeVpnCommandState.failed);
      expect(await api.queryCoreRunning(), isTrue);
      expect(fixture.pkills, hasLength(2));
      expect(fixture.events, [VpnStatus.disconnecting]);
    },
  );

  test('missing procps is an error, not a disconnected VPN', () async {
    final fixture = await _Fixture.create();
    final api = fixture.api(
      runCommand: (executable, arguments) async =>
          throw ProcessException(executable, arguments, 'Not found', 2),
    );

    expect(await api.queryCoreRunning(), isNull);
    expect((await api.readVpnStatus()).state, NativeVpnCommandState.failed);
    expect(await api.cleanupStaleCore(), isFalse);
    expect(await api.stopCore(), isFalse);
    expect(fixture.pkills, isEmpty);
  });

  for (final code in [2, 3]) {
    test('pgrep exit $code is not treated as no matches', () async {
      final fixture = await _Fixture.create();
      final api = fixture.api(
        runCommand: (_, _) async => ProcessResult(1, code, '', 'query failed'),
      );

      expect(await api.queryCoreRunning(), isNull);
      expect(await api.stopCore(), isFalse);
      expect(fixture.pkills, isEmpty);
    });

    test('pkill exit $code never claims a successful stop', () async {
      final fixture = await _Fixture.create();
      fixture.pids.add(42);
      final api = fixture.api(
        runCommand: (executable, _) async => executable == 'pgrep'
            ? fixture.queryResult()
            : ProcessResult(1, code, '', 'stop failed'),
      );

      expect((await api.stopVpn()).state, NativeVpnCommandState.failed);
      expect(await api.queryCoreRunning(), isTrue);
      expect(fixture.events, [VpnStatus.disconnecting]);
    });
  }

  for (final output in ['', '0\n', '-1\n', 'not a PID\n']) {
    test(
      'invalid pgrep output is not a disconnected VPN: ${output.trim()}',
      () async {
        final fixture = await _Fixture.create();
        final api = fixture.api(
          runCommand: (_, _) async => ProcessResult(1, 0, output, ''),
        );

        expect(await api.queryCoreRunning(), isNull);
        expect(await api.stopCore(), isFalse);
        expect(fixture.pkills, isEmpty);
      },
    );
  }
}

LibXrayRunConfig _runConfig() => LibXrayRunConfig(
  LibXrayInvokeRequest(
    method: LibXrayMethod.runXray,
    payload: RunXrayRequest('{"inbounds":[]}').toJson(),
  ),
);

TunJson _tunConfig() => TunJson.fromJson({
  'tunDnsIPv4': '8.8.8.8',
  'autoOutboundsInterface': 'eth0',
});

class _Fixture {
  final Directory directory;
  final pids = <int>{};
  final commands = <List<String>>[];
  final watchedPids = <int>[];
  final events = <VpnStatus>[];
  final _statuses = StreamController<VpnStatus>.broadcast();
  final _exits = <int, Completer<bool>>{};

  _Fixture(this.directory);

  Iterable<List<String>> get pkills =>
      commands.where((command) => command.first == 'pkill');

  static Future<_Fixture> create() async {
    final fixtures = await Directory(
      '../references/onexray-refactor-validation/test-fixtures',
    ).absolute.create(recursive: true);
    final directory = await fixtures.createTemp('onexray-linux-process-');
    final fixture = _Fixture(directory);
    addTearDown(() => directory.delete(recursive: true));
    addTearDown(fixture._statuses.close);
    return fixture;
  }

  LinuxFfiApi api({
    Future<ProcessResult> Function(String, List<String>)? runCommand,
    Future<Process> Function(String, List<String>)? startProcess,
    Future<StartVpnRequest> Function()? readRequest,
  }) {
    final api = LinuxFfiApi.forTesting(
      filesDirectory: directory.path,
      executablePath: p.join(directory.path, 'OneXrayCore'),
      startProcess: startProcess,
      readRequest: readRequest,
      runCommand: (executable, arguments) async {
        commands.add([executable, ...arguments]);
        if (executable == 'pgrep') {
          expect(arguments, ['-x', '-r', 'R,S,D,T,t,I', 'OneXrayCore']);
        } else {
          expect(executable, 'pkill');
          expect(arguments.first, isIn(['-TERM', '-KILL']));
          expect(arguments.skip(1), ['-x', 'OneXrayCore']);
        }
        if (runCommand != null) return runCommand(executable, arguments);
        if (executable == 'pgrep') return queryResult();
        final matched = pids.isNotEmpty;
        for (final pid in pids.toList()) {
          exitProcess(pid);
        }
        return ProcessResult(1, matched ? 0 : 1, '', '');
      },
      watchExit: (pid) {
        watchedPids.add(pid);
        final exited = _exits[pid] = Completer<bool>();
        return DesktopCoreExitWatch(exited.future, () {
          if (!exited.isCompleted) exited.complete(false);
        });
      },
      notify: (status) async {
        events.add(status);
        _statuses.add(status);
      },
      notifyError: (error) => fail('Unexpected watch error: $error'),
    );
    addTearDown(api.disposeVpnStatus);
    addTearDown(api.stopSharedIsolate);
    return api;
  }

  ProcessResult queryResult() =>
      ProcessResult(1, pids.isEmpty ? 1 : 0, '${pids.join('\n')}\n', '');

  void exitProcess(int pid) {
    pids.remove(pid);
    final exited = _exits[pid];
    if (exited != null && !exited.isCompleted) exited.complete(true);
  }

  Future<VpnStatus> nextStatus() =>
      _statuses.stream.first.timeout(const Duration(seconds: 2));
}

class _OwnedProcess extends Fake implements Process {
  @override
  final int pid;
  final _exit = Completer<int>();

  _OwnedProcess(this.pid);

  void finish() {
    if (!_exit.isCompleted) _exit.complete(0);
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();
}

class _ExitedProcess extends Fake implements Process {
  @override
  int get pid => 42;

  @override
  Future<int> get exitCode => Future.value(1);

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();
}
