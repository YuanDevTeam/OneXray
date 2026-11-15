import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/proxy/core_session.dart';
import 'package:path/path.dart' as p;

void main() {
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
}
