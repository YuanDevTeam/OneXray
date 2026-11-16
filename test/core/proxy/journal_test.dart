import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/proxy/journal.dart';
import 'package:path/path.dart' as p;

import '../../support/test_directory.dart';

Map<String, dynamic> _recordWithByteLength(int length, String prefix) {
  final value = <String, dynamic>{'version': 1, 'payload': prefix};
  final padding = length - utf8.encode(jsonEncode(value)).length;
  value['payload'] = prefix + List<String>.filled(padding, 'a').join();
  return value;
}

void main() {
  for (final prefix in ['', '中文😀']) {
    test(
      'journal enforces its UTF-8 byte boundary with ${prefix.isEmpty ? 'ASCII' : 'multibyte'} data before touching pending state',
      () async {
        final directory = await createTestDirectory('onexray-proxy-size-');
        final store = FileProxyJournalStore(() async => directory.path);
        addTearDown(() async {
          await store.close();
          await directory.delete(recursive: true);
        });
        final root = Directory(p.join(directory.path, 'proxy-state'));
        final accepted = _recordWithByteLength(65536, prefix);
        final rejected = _recordWithByteLength(65537, prefix);
        final rejectedBytes = utf8.encode(jsonEncode(rejected));
        expect(rejectedBytes.length, 65537);
        if (prefix.isNotEmpty) {
          expect(jsonEncode(rejected).length, lessThan(65536));
        }
        await expectLater(store.write(rejected), throwsFormatException);
        expect(await root.exists(), isFalse);

        await store.lock();
        await store.write(accepted);
        final file = File(p.join(root.path, 'session.json'));
        final pending = File('${file.path}.pending');
        final savedBytes = await file.readAsBytes();
        expect(savedBytes.length, 65536);
        expect(await store.read(), accepted);
        await pending.writeAsString('untouched pending state');

        await expectLater(store.write(rejected), throwsFormatException);

        expect(await file.readAsBytes(), savedBytes);
        expect(await store.read(), accepted);
        expect(await pending.readAsString(), 'untouched pending state');
        // A record written externally must obey the same bound as write().
        await file.writeAsBytes(rejectedBytes, flush: true);
        await expectLater(store.read(), throwsFormatException);
      },
    );
  }

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
