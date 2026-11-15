import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/proxy/journal.dart';
import 'package:path/path.dart' as p;

import '../../support/test_directory.dart';

void main() {
  test('device-local journal atomically replaces state and never enters runtime exports', () async {
    final directory = await createTestDirectory('onexray-proxy-journal-');
    final store = FileProxyJournalStore(() async => directory.path);
    addTearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
    await store.lock();
    expect(await store.read(), isNull);
    await store.write({
      'version': 1,
      'phase': 'prepared',
      'before': {
        'mode': {'effective': "'none'", 'user': null},
      },
    });
    await store.write({'version': 1, 'phase': 'active'});
    expect(await store.read(), {'version': 1, 'phase': 'active'});
    expect(
      await File(p.join(directory.path, 'proxy-state', 'session.json.pending'))
          .exists(),
      isFalse,
    );
    expect(await Directory(p.join(directory.path, 'run')).exists(), isFalse);
    if (!Platform.isWindows) {
      expect(
        (await File(
              p.join(directory.path, 'proxy-state', 'session.json'),
            ).stat()).mode &
            0x3f,
        0,
      );
    }
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('linked state directories are rejected before reading or writing outside them', () async {
    final directory = await createTestDirectory('onexray-proxy-link-');
    final outside = await createTestDirectory('onexray-proxy-outside-');
    addTearDown(() async {
      await directory.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    await Link(p.join(directory.path, 'proxy-state')).create(outside.path);
    final store = FileProxyJournalStore(() async => directory.path);
    await expectLater(store.lock(), throwsA(isA<FileSystemException>()));
    expect(await outside.list().toList(), isEmpty);
  });
}
