import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/proxy/core_session.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// Test-only platform seam supplied by the path_provider plugin.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:win32/win32.dart';

import '../../support/test_directory.dart';

class _SupportDirectory extends PathProviderPlatform {
  _SupportDirectory(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Windows recovery ignores a real exited child PID after its handle disappears', () async {
    final directory = await createTestDirectory('proxy-windows-recovery-');
    addTearDown(() => directory.delete(recursive: true));
    final child = await Process.start(
      p.join(Platform.environment['SystemRoot']!, 'System32', 'cmd.exe'),
      ['/d', '/q', '/c', 'exit', '0'],
      workingDirectory: directory.path,
    );
    var exited = false;
    addTearDown(() async {
      if (!exited) {
        child.kill();
        await child.exitCode.timeout(const Duration(seconds: 5));
      }
      await child.stdin.close();
    });
    final output = [child.stdout.drain<void>(), child.stderr.drain<void>()];
    final exitCode = await child.exitCode.timeout(const Duration(seconds: 5));
    exited = true;
    expect(exitCode, 0);
    await Future.wait(output);

    // Windows can briefly retain an exited process object. Establish that
    // this owned PID is gone before exercising the real recovery reader.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final opened = OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION,
        false,
        child.pid,
      );
      if (!opened.value.isValid) {
        expect(opened.error, isIn([ERROR_INVALID_PARAMETER, ERROR_NOT_FOUND]));
        break;
      }
      CloseHandle(opened.value);
      if (DateTime.now().isAfter(deadline)) {
        fail('The exited fixture PID ${child.pid} is still openable.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final core = ProcessProxyCoreSession(
      directory: () async => directory.path,
      executable: p.join(directory.path, 'missing-installation', 'Core.exe'),
    );
    await core.recover({
      'platform': 'windows',
      'pid': child.pid,
      // Deliberately cannot match a numeric Windows creation time, so even
      // an immediately reused PID must never identify another process.
      'created': 'exited-fixture',
      'executable': p.join(directory.path, 'old-installation', 'Core.exe'),
    });
    expect(await core.isRunning(), false);
  }, skip: !Platform.isWindows);

  for (final reused in [false, true]) {
    test(
      'recovery clears a ${reused ? 'reused' : 'gone'} PID after the installation moves',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'proxy-recovery-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final recorded = <String, dynamic>{
          'platform': Platform.operatingSystem,
          'pid': 42,
          'created': 'old-process',
          'executable': p.join(
            directory.path,
            'old-installation',
            'OneXrayCore',
          ),
        };
        var reads = 0;
        final core = ProcessProxyCoreSession(
          directory: () async => directory.path,
          executable: p.join(directory.path, 'new-installation', 'OneXrayCore'),
          readProcessIdentity: (pid) async {
            expect(pid, 42);
            reads++;
            return reused
                ? {...recorded, 'created': 'different-process'}
                : null;
          },
        );

        await core.recover(recorded);

        expect(reads, 1);
      },
    );
  }

  test(
    'a matching live process still requires installed image verification',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'proxy-recovery-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final recorded = <String, dynamic>{
        'platform': Platform.operatingSystem,
        'pid': 42,
        'created': 'owned-process',
        'executable': p.join(directory.path, 'old-installation', 'OneXrayCore'),
      };
      final core = ProcessProxyCoreSession(
        directory: () async => directory.path,
        executable: p.join(directory.path, 'new-installation', 'OneXrayCore'),
        readProcessIdentity: (_) async => recorded,
      );

      await expectLater(
        core.recover(recorded),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  group('native runtime directory', () {
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.onexray.BridgeHostApi.getTunFilesDir',
      BridgeHostApi.pigeonChannelCodec,
    );
    late Directory root;
    late Directory support;
    late Directory native;
    late PathProviderPlatform previousPaths;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('proxy-runtime-paths-');
      support = await Directory(p.join(root.path, 'application-support'))
          .create();
      native = await Directory(p.join(root.path, 'package-local-data'))
          .create();
      previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _SupportDirectory(support.path);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockDecodedMessageHandler(
        channel,
        (_) async => [native.path],
      );
      await AppHostApi().initTunFilesDir();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler(channel, null);
      PathProviderPlatform.instance = previousPaths;
      await root.delete(recursive: true);
    });

    StartVpnRequest request(bool logging) => StartVpnRequest(
      null,
      '10808',
      '10809',
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(
            jsonEncode({
              'log': {
                'access': logging
                    ? p.join(VpnConstants.runDir, 'access.log')
                    : 'none',
                'error': logging
                    ? p.join(VpnConstants.runDir, 'error.log')
                    : 'none',
              },
            }),
          ).toJson(),
        ).toJson(),
      ),
      captureMode: 'proxy',
    );

    for (final logging in [false, true]) {
      test('clears native logs before launch with logging=$logging', () async {
        expect((await getApplicationSupportDirectory()).path, support.path);
        final runtime = await Directory(VpnConstants.runDir).create();
        final otherRun = await Directory(p.join(support.path, 'run')).create();
        for (final name in ['access.log', 'error.log']) {
          await File(p.join(runtime.path, name))
              .writeAsString('old native log');
          await File(p.join(otherRun.path, name))
              .writeAsString('unrelated support file');
        }
        final reachedSpawn = StateError('launch boundary');
        final core = ProcessProxyCoreSession(
          executable: Platform.resolvedExecutable,
          startProcess: (_, arguments) async {
            for (final name in ['access.log', 'error.log']) {
              expect(await File(p.join(runtime.path, name)).exists(), false);
              expect(
                await File(p.join(otherRun.path, name)).readAsString(),
                'unrelated support file',
              );
            }
            final configPath = arguments[arguments.indexOf('-config') + 1];
            expect(p.isWithin(runtime.path, configPath), true);
            final config =
                jsonDecode(await File(configPath).readAsString()) as Map;
            expect(
              config['log']['access'],
              logging ? p.join(runtime.path, 'access.log') : 'none',
            );
            throw reachedSpawn;
          },
        );
        await expectLater(
          core.start(request(logging)),
          throwsA(same(reachedSpawn)),
        );
      });
    }

    test(
      'rejects a linked native log before removing either log or launching',
      () async {
        final runtime = await Directory(VpnConstants.runDir).create();
        final sentinel = await File(p.join(root.path, 'keep.txt'))
            .writeAsString('keep');
        final linkedLog = await Link(p.join(runtime.path, 'access.log'))
            .create(sentinel.path);
        final errorLog = await File(p.join(runtime.path, 'error.log'))
            .writeAsString('keep error');
        var launched = false;
        final core = ProcessProxyCoreSession(
          executable: Platform.resolvedExecutable,
          startProcess: (_, _) async {
            launched = true;
            throw StateError('must not launch');
          },
        );
        await expectLater(core.start(request(false)), throwsFormatException);
        expect(launched, false);
        expect(await linkedLog.exists(), true);
        expect(await sentinel.readAsString(), 'keep');
        expect(await errorLog.readAsString(), 'keep error');
      },
    );
  }, skip: !Platform.isMacOS);
}
