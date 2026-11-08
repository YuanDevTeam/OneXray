import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/base_ffi_api.dart';
import 'package:onexray/core/ffi/linux_ffi_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:path/path.dart' as p;

import '../../support/test_directory.dart';

void main() {
  test('builds protected desktop Core arguments', () {
    expect(
      desktopCoreRunArguments(
        setDns: true,
        dns: '8.8.8.8',
        interfaceName: 'Ethernet',
        configPath: r'C:\run\xray.json',
        errorFile: r'C:\run\xray.json.error',
      ),
      <String>[
        'run',
        '-set-dns=true',
        '-dns',
        '8.8.8.8:53',
        '-interface',
        'Ethernet',
        '-config',
        r'C:\run\xray.json',
        '-error-file',
        r'C:\run\xray.json.error',
      ],
    );
    expect(
      desktopCoreRunArguments(
        dns: '8.8.8.8',
        interfaceName: 'eth0',
        configPath: '/runtime-input/xray.json',
      ),
      [
        'run',
        '-dns',
        '8.8.8.8:53',
        '-interface',
        'eth0',
        '-config',
        '/runtime-input/xray.json',
      ],
    );
  });

  test(
    'replaces old inputs with one unique immutable runtime directory',
    () async {
      final directory = await createTestDirectory('onexray-desktop-inputs-');
      addTearDown(() => directory.delete(recursive: true));
      final api = _TestFfiApi(stopResult: true, directory: directory.path);
      addTearDown(api.stopSharedIsolate);
      final stale = File(
        p.join(directory.path, 'run', 'core-inputs', 'stale', 'xray.json'),
      );
      await stale.parent.create(recursive: true);
      await stale.writeAsString('stale');
      final sibling = File(p.join(directory.path, 'run', 'keep'));
      await sibling.writeAsString('keep');
      const text = '{"outbounds":[{"protocol":"freedom"}]}';
      final request = _request(text);
      final first = (await api.materializeRunXrayConfig(request))!;
      expect(
        p.dirname(p.dirname(first)),
        p.join(directory.path, 'run', 'core-inputs'),
      );
      expect(await stale.exists(), isFalse);
      expect(await sibling.readAsString(), 'keep');
      expect(await File(first).readAsString(), text);
      expect(await desktopCoreErrorFile(first).exists(), isFalse);
      await desktopCoreErrorFile(first).writeAsString('old startup failure');
      expect(
        await readDesktopCoreStartError(first, 'Core exited'),
        'old startup failure',
      );
      final second = (await api.materializeRunXrayConfig(request))!;
      expect(second, isNot(first));
      expect(await Directory(p.dirname(first)).exists(), isFalse);
      expect(await File(second).readAsString(), text);
      expect(await desktopCoreErrorFile(second).exists(), isFalse);
      await desktopCoreErrorFile(second).writeAsString('');
      expect(
        await readDesktopCoreStartError(second, 'Core exited'),
        'Core exited',
      );
      await desktopCoreErrorFile(second).delete();
      expect(
        await readDesktopCoreStartError(second, 'Core exited'),
        'Core exited',
      );
      final arguments = desktopCoreRunArguments(
        dns: '8.8.8.8',
        interfaceName: 'eth0',
        configPath: second,
      );
      expect(arguments, isNot(contains('-runtime')));
    },
  );

  test('reports disconnected only after Core stops successfully', () async {
    final api = _TestFfiApi(stopResult: true);
    addTearDown(api.stopSharedIsolate);

    final result = await api.stopVpn();

    expect(result.state, NativeVpnCommandState.success);
    expect(api.statuses, [VpnStatus.disconnecting, VpnStatus.disconnected]);
  });

  test('clears only managed logs and tolerates missing files', () async {
    final directory = await createTestDirectory('onexray-runtime-logs-');
    addTearDown(() => directory.delete(recursive: true));
    final api = _TestFfiApi(stopResult: true, directory: directory.path);
    addTearDown(api.stopSharedIsolate);
    await api.clearLogs();
    final run = Directory(p.join(directory.path, 'run'));
    await run.create();
    for (final name in [
      'access.log',
      'error.log',
      'start.json',
      'export.log',
    ]) {
      await File(p.join(run.path, name)).writeAsString(name);
    }
    await api.clearLogs();
    await api.clearLogs();
    expect(await File(p.join(run.path, 'access.log')).exists(), isFalse);
    expect(await File(p.join(run.path, 'error.log')).exists(), isFalse);
    expect(
      await File(p.join(run.path, 'start.json')).readAsString(),
      'start.json',
    );
    expect(
      await File(p.join(run.path, 'export.log')).readAsString(),
      'export.log',
    );
  });

  for (final link in [false, true]) {
    test(
      'rejects ${link ? 'linked' : 'directory'} logs before clearing either',
      () async {
        final directory = await createTestDirectory('onexray-invalid-logs-');
        addTearDown(() => directory.delete(recursive: true));
        final api = _TestFfiApi(stopResult: true, directory: directory.path);
        addTearDown(api.stopSharedIsolate);
        final access = File(p.join(directory.path, 'run', 'access.log'));
        await access.parent.create();
        await access.writeAsString('old access');
        final error = p.join(access.parent.path, 'error.log');
        if (link) {
          final target = File(p.join(directory.path, 'outside.log'));
          await target.writeAsString('outside');
          await Link(error).create(target.path);
        } else {
          await Directory(error).create();
        }
        await expectLater(api.clearLogs(), throwsA(isA<FileSystemException>()));
        expect(await access.readAsString(), 'old access');
        if (link) {
          expect(
            await File(p.join(directory.path, 'outside.log')).readAsString(),
            'outside',
          );
        }
      },
    );
  }

  test('a stop failure never invents a connected state', () async {
    final api = _TestFfiApi(stopResult: false);
    addTearDown(api.stopSharedIsolate);

    final result = await api.stopVpn();

    expect(result.state, NativeVpnCommandState.failed);
    expect(api.statuses, [VpnStatus.disconnecting]);
  });
}

final class _TestFfiApi extends LinuxFfiApi {
  final bool stopResult;
  final String? directory;
  final List<VpnStatus> statuses;

  factory _TestFfiApi({required bool stopResult, String? directory}) =>
      _TestFfiApi._(stopResult, directory, []);

  _TestFfiApi._(this.stopResult, this.directory, this.statuses)
    : super.forTesting(
        filesDirectory: directory ?? '',
        executablePath: '',
        runCommand: (_, _) => throw UnimplementedError(),
        watchExit: (_) => throw UnimplementedError(),
        notify: (status) async => statuses.add(status),
      );

  @override
  Future<String> getTunFilesDir() async =>
      directory ?? await super.getTunFilesDir();

  @override
  Future<bool> stopCore() async => stopResult;

  Future<void> clearLogs() => clearRuntimeLogs();
}

LibXrayRunConfig _request(String json) => LibXrayRunConfig(
  LibXrayInvokeRequest(
    method: LibXrayMethod.runXray,
    payload: RunXrayRequest(json).toJson(),
  ),
);
