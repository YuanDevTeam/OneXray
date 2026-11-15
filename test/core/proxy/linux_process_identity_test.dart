import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/proxy/linux_process_identity.dart';
import 'package:onexray/core/proxy/system_proxy.dart';

const _boot = 'f57011b5-29c7-49aa-9b7e-6080fa5646b4';
String _stat({String created = '12345'}) =>
    '42 (OneXray (Core)) ${['S', ...List.filled(18, '0'), created].join(' ')}';

Future<String> _read(String path) async => switch (path) {
  '/proc/42/stat' => _stat(),
  '/proc/42/status' => 'Name:\tOneXrayCore\nUid:\t1000\t1000\t1000\t1000\n',
  '/proc/sys/kernel/random/boot_id' => _boot,
  _ => throw FileSystemException('Missing fixture', path, const OSError('', 2)),
};

void main() {
  test('a new owned spawn records known image and readable identity without ptrace-gated readlink', () async {
    var imageReads = 0;
    final identity = LinuxProxyProcessIdentity(
      readText: _read,
      resolveImage: (path) async {
        imageReads++;
        throw FileSystemException(
          'Permission denied for capability-bearing Core',
          path,
          const OSError('', 13),
        );
      },
    );
    expect(await identity.captureSpawned(42, '/opt/OneXray/OneXrayCore'), {
      'platform': 'linux',
      'pid': 42,
      'created': '12345',
      'uid': '1000',
      'effectiveUid': '1000',
      'bootId': _boot,
      'executable': '/opt/OneXray/OneXrayCore',
    });
    expect(imageReads, 0);
  });

  test('cold recovery refuses an unverifiable image rather than assuming its PID is owned', () async {
    final identity = LinuxProxyProcessIdentity(
      readText: _read,
      resolveImage: (path) async => throw FileSystemException(
        'Permission denied',
        path,
        const OSError('', 13),
      ),
    );
    await expectLater(
      identity.read(42),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Stop that process manually'),
        ),
      ),
    );
  });

  test('PID start time is rechecked around the image lookup', () async {
    var reads = 0;
    final identity = LinuxProxyProcessIdentity(
      readText: (path) async {
        if (path == '/proc/42/stat') {
          return _stat(created: ++reads == 1 ? '12345' : '99999');
        }
        return _read(path);
      },
      resolveImage: (_) async => '/opt/OneXray/OneXrayCore',
    );
    expect(await identity.read(42), isNull);
  });

  test(
    'boot identity distinguishes a reused PID and start time after reboot',
    () async {
      final first = await LinuxProxyProcessIdentity(readText: _read)
          .captureSpawned(42, '/opt/OneXray/OneXrayCore');
      final second = await LinuxProxyProcessIdentity(
        readText: (path) async => path.endsWith('boot_id')
            ? 'a3a0ffb2-3e2d-43fb-9579-f536ef00ca18'
            : _read(path),
      ).captureSpawned(42, '/opt/OneXray/OneXrayCore');
      expect(proxyValuesEqual(first, second), isFalse);
    },
  );

  test(
    'a process gone before metadata capture is not a successful launch',
    () async {
      final identity = LinuxProxyProcessIdentity(
        readText: (path) async => throw FileSystemException(
          'No such process',
          path,
          const OSError('', 2),
        ),
      );
      expect(
        await identity.captureSpawned(42, '/opt/OneXray/OneXrayCore'),
        isNull,
      );
    },
  );
}
