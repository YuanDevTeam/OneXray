import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/windows/core_process.dart';
import 'package:onexray/core/ffi/windows/msix_ffi_api.dart';
import 'package:onexray/core/ffi/windows/model.dart';
import 'package:onexray/core/ffi/windows/native_api.dart';
import 'package:onexray/core/model/tun_json.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';

void main() {
  final token = 'vole-session-v2:${'a' * 64}';
  String response(String status) => jsonEncode({
    'success': true,
    'error': '',
    'data': {
      'status': status,
      'snapshotToken': status == 'disconnected' ? null : token,
    },
  });

  test('status reads are pure and never return the last successful status on error', () async {
    var failQuery = false;
    final calls = <String>[];
    final api = WindowsMsixFfiApi(
      native: WindowsNativeApi.forTest((request) async {
        calls.add(jsonDecode(request)['method'] as String);
        if (failQuery) throw StateError('System query failed');
        return response('connected');
      }),
      readRequest: () async => throw StateError('No matching token'),
    );
    expect((await api.readVpnStatus()).status, VpnStatus.connected);
    failQuery = true;
    final failed = await api.readVpnStatus();
    expect(failed.state, NativeVpnCommandState.failed);
    expect(failed.status, isNull);
    expect(calls, ['getVpnStatus', 'getVpnStatus']);
  });

  test(
    'MSIX owns periodic notifications and cancels them on disposal',
    () async {
      var status = 'connected';
      var reads = 0;
      final disconnected = Completer<void>();
      final events = <VpnStatus>[];
      final api = WindowsMsixFfiApi(
        native: WindowsNativeApi.forTest((request) async {
          expect(jsonDecode(request)['method'], 'getVpnStatus');
          reads++;
          return response(status);
        }),
        readRequest: () async =>
            StartVpnRequest(null, null, null, null)..snapshotToken = token,
        notify: (value) async {
          events.add(value);
          if (value == VpnStatus.disconnected) disconnected.complete();
        },
        monitorInterval: const Duration(milliseconds: 10),
      );
      addTearDown(api.disposeVpnStatus);
      await api.observeVpnStatus();
      expect(events, [VpnStatus.connected]);
      status = 'disconnected';
      await disconnected.future.timeout(const Duration(seconds: 2));
      api.disposeVpnStatus();
      final stoppedReads = reads;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(reads, stoppedReads);
      expect(events, [VpnStatus.connected, VpnStatus.disconnected]);
    },
  );

  test(
    'restored stale sessions are stopped by monitoring, not by a read',
    () async {
      final calls = <String>[];
      final events = <VpnStatus>[];
      final api = WindowsMsixFfiApi(
        native: WindowsNativeApi.forTest((request) async {
          final method = jsonDecode(request)['method'] as String;
          calls.add(method);
          return response(method == 'stopVpn' ? 'disconnected' : 'connected');
        }),
        readRequest: () async => StartVpnRequest(null, null, null, null),
        notify: (status) async => events.add(status),
      );
      addTearDown(api.disposeVpnStatus);
      await api.readVpnStatus();
      expect(calls, ['getVpnStatus']);
      await api.observeVpnStatus();
      expect(calls, ['getVpnStatus', 'getVpnStatus', 'stopVpn']);
      expect(events, [VpnStatus.disconnecting, VpnStatus.disconnected]);
    },
  );

  test(
    'stop is confirmed internally and times out without inventing success',
    () async {
      var status = 'disconnecting';
      var reads = 0;
      final api = WindowsMsixFfiApi(
        native: WindowsNativeApi.forTest((request) async {
          if (jsonDecode(request)['method'] == 'getVpnStatus') reads++;
          return response(status);
        }),
        notify: (_) async {},
        confirmInterval: const Duration(milliseconds: 1),
        stopTimeout: const Duration(milliseconds: 5),
      );
      expect((await api.stopVpn()).state, NativeVpnCommandState.failed);
      expect(reads, greaterThan(0));
      status = 'disconnected';
      final result = await api.stopVpn();
      expect(result.state, NativeVpnCommandState.success);
      expect(result.status, VpnStatus.disconnected);
    },
  );

  for (final diagnostic in [
    'failed to load geosite: category TEST-MISSING not found',
    '',
    null,
  ]) {
    test('MSIX preserves Core startup diagnostics: $diagnostic', () async {
      final root = await Directory('../references/windows-msix-tests').absolute
          .create(recursive: true);
      final directory = await root.createTemp('ffi-');
      addTearDown(() => directory.delete(recursive: true));
      final calls = <String>[];
      final events = <VpnStatus>[];
      final access = File('${directory.path}/run/access.log');
      final logError = File('${directory.path}/run/error.log');
      await access.parent.create();
      await access.writeAsString('old access');
      await logError.writeAsString('old error');
      File? errorFile;
      List<String>? arguments;
      final api = WindowsMsixFfiApi(
        coreProcess: _CoreProcesses(),
        native: WindowsNativeApi.forTest((text) async {
          final request = jsonDecode(text) as Map<String, dynamic>;
          final method = request['method'] as String;
          calls.add(method);
          if (method == 'getEnvironment') {
            return jsonEncode({
              'success': true,
              'error': '',
              'data': {
                'packageFamilyName': 'OneXray.Test',
                'packageLocalDataDir': directory.path,
              },
            });
          }
          if (method == 'startVpn') {
            expect(await access.exists(), isFalse);
            expect(await logError.exists(), isFalse);
            await logError.writeAsString('current connection');
            final process =
                request['payload']['sessionBackend']['processes'].single;
            expect(process['executableRelativePath'], 'OneXrayCore.exe');
            arguments = (process['arguments'] as List).cast<String>();
            final config = arguments![arguments!.indexOf('-config') + 1];
            expect(arguments, [
              'run',
              '-set-dns=true',
              '-dns',
              '8.8.8.8:53',
              '-interface',
              'Ethernet 2',
              '-config',
              config,
              '-error-file',
              '$config.error',
            ]);
            errorFile = File('$config.error');
            // The GUI creates the file before dispatching the managed process.
            expect(await errorFile!.readAsString(), isEmpty);
            throw const WindowsNativeException(
              'Session backend process exited',
            );
          }
          expect(method, 'stopVpn');
          if (errorFile == null) return response('disconnected');
          // Diagnostics may finish writing while the failed session is stopped.
          if (diagnostic == null) {
            await errorFile!.delete();
          } else {
            await errorFile!.writeAsString(diagnostic);
          }
          return response('disconnected');
        }),
        readRequest: () async => StartVpnRequest(
          TunJson.fromJson({'autoOutboundsInterface': 'Ethernet 2'}),
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
      );
      addTearDown(api.stopSharedIsolate);
      final result = await api.startVpn(
        configYaml: 'fixture',
        networkSettings: const WindowsVpnNetworkSettings(
          ipv4Address: '172.19.0.1',
          ipv6Address: '',
          dnsIpv4Address: '8.8.8.8',
          dnsIpv6Address: '',
        ),
      );
      expect(result.state, NativeVpnCommandState.failed);
      expect(
        result.message,
        diagnostic == null || diagnostic.isEmpty
            ? 'Session backend process exited'
            : diagnostic,
      );
      expect(arguments, contains('-error-file'));
      expect(
        arguments![arguments!.indexOf('-error-file') + 1],
        errorFile!.path,
      );
      expect(calls, ['stopVpn', 'getEnvironment', 'startVpn', 'stopVpn']);
      expect(events, [
        VpnStatus.disconnected,
        VpnStatus.connecting,
        VpnStatus.disconnected,
      ]);
      expect(await logError.readAsString(), 'current connection');
    });
  }

  for (final failure in ['stop', 'running', 'query']) {
    test(
      'MSIX preserves logs when previous Core cannot be confirmed stopped: $failure',
      () async {
        final root = await Directory('../references/windows-msix-tests')
            .absolute
            .create(recursive: true);
        final directory = await root.createTemp('logs-');
        addTearDown(() => directory.delete(recursive: true));
        final access = File('${directory.path}/run/access.log');
        await access.parent.create();
        await access.writeAsString('previous connection');
        final processes = _CoreProcesses()
          ..pids = failure == 'running' ? {42} : {}
          ..error = failure == 'query'
              ? StateError('process enumeration denied')
              : null;
        final calls = <String>[];
        final events = <VpnStatus>[];
        final api = WindowsMsixFfiApi(
          coreProcess: processes,
          native: WindowsNativeApi.forTest((text) async {
            final method = jsonDecode(text)['method'] as String;
            calls.add(method);
            expect(method, 'stopVpn');
            if (failure == 'stop') throw StateError('Stop failed');
            return response('disconnected');
          }),
          readRequest: () async => StartVpnRequest(null, null, null, null),
          notify: (status) async => events.add(status),
        );
        addTearDown(api.stopSharedIsolate);
        final result = await api.startVpn(
          configYaml: 'fixture',
          networkSettings: const WindowsVpnNetworkSettings(
            ipv4Address: '172.19.0.1',
            ipv6Address: '',
            dnsIpv4Address: '8.8.8.8',
            dnsIpv6Address: '',
          ),
        );
        expect(result.state, NativeVpnCommandState.failed);
        expect(
          result.message,
          contains(switch (failure) {
            'stop' => 'Stop failed',
            'running' => 'previous Windows Core process is still running',
            _ => 'process enumeration denied',
          }),
        );
        expect(calls, ['stopVpn']);
        expect(await access.readAsString(), 'previous connection');
        if (failure == 'stop') expect(events, isEmpty);
      },
    );
  }
}

class _CoreProcesses extends WindowsCoreProcess {
  Set<int> pids = {};
  Object? error;

  @override
  Future<Set<int>> findPids() async {
    if (error != null) throw error!;
    return {...pids};
  }
}
