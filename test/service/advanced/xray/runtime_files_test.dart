import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/advanced/xray/runtime_files.dart';

void main() {
  test('local logs keep bounded reads across appends and truncation', () async {
    final root = await Directory('../references/runtime-log-tests').absolute
        .create(recursive: true);
    final directory = await root.createTemp('files-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/access.log');
    await file.writeAsString('first\nsecond\n');
    final tail = await RuntimeDiagnosticFiles.readLog(file.path, limit: 7);
    expect(tail!.offset, 6);
    expect(tail.size, 13);
    expect(String.fromCharCodes(tail.data), 'second\n');

    await file.writeAsString('third\n', mode: FileMode.append);
    final next = await RuntimeDiagnosticFiles.readLog(
      file.path,
      offset: tail.size,
    );
    expect(next!.offset, 13);
    expect(next.size, 19);
    expect(String.fromCharCodes(next.data), 'third\n');

    await file.writeAsString('new\n');
    final truncated = await RuntimeDiagnosticFiles.readLog(
      file.path,
      offset: next.size,
    );
    expect(truncated!.offset, 4);
    expect(truncated.size, 4);
    expect(truncated.data, isEmpty);

    expect(
      await RuntimeDiagnosticFiles.readLog('${directory.path}/missing.log'),
      isNull,
    );
    await expectLater(
      RuntimeDiagnosticFiles.exportLog(
        '${directory.path}/missing.log',
        'missing.log',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}
