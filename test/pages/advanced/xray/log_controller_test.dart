import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/pages/advanced/xray/log/controller.dart';
import 'package:onexray/pages/advanced/xray/log/params.dart';
import 'package:onexray/service/advanced/xray/runtime_files.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';

import '../../../support/test_directory.dart';

void main() {
  late File file;
  late ConnectionCoordinator coordinator;
  late ConnectionRuntime first;

  setUp(() async {
    final directory = await createTestDirectory('log-viewer-session-');
    addTearDown(() => directory.delete(recursive: true));
    file = File('${directory.path}/access.log');
    await file.writeAsString('OLD\n');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    coordinator = ConnectionCoordinator(
      database: db,
      statusEvents: const Stream.empty(),
      disposeStatus: () {},
    );
    addTearDown(coordinator.dispose);
    first = _runtime(1);
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: first,
    );
  });

  for (final replacement in ['NEW\n', 'NEW\nMORE\n']) {
    test(
      'new session replaces equal or larger log without keeping old lines: ${replacement.length} bytes',
      () async {
        final controller = LogFileViewerController(
          LogFileViewerParams(title: 'Access log', path: file.path),
          coordinator: coordinator,
        );
        addTearDown(controller.close);
        await _waitFor(controller, (state) => state.lines.join('\n') == 'OLD');
        await file.delete();
        await file.writeAsString(replacement);
        coordinator.state.value = ConnectionView(
          phase: ConnectionPhase.connected,
          runtime: _runtime(2),
        );
        final expected = replacement.trimRight();
        final state = await _waitFor(
          controller,
          (state) => state.lines.join('\n') == expected,
        );
        expect(state.lines, isNot(contains('OLD')));
        expect(state.failure, isNull);
      },
    );
  }

  test('same-session append and repeated connected preserve content; disconnect retains diagnostics and a new connected edge reloads', () async {
    final controller = LogFileViewerController(
      LogFileViewerParams(title: 'Access log', path: file.path),
      coordinator: coordinator,
    );
    addTearDown(controller.close);
    await _waitFor(controller, (state) => state.lines.join('\n') == 'OLD');
    var missingStates = 0;
    final subscription = controller.stream.listen((state) {
      if (!state.fileExists) missingStates++;
    });
    addTearDown(subscription.cancel);
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: first,
      uploadSpeed: 20,
    );
    await file.writeAsString('APPEND\n', mode: FileMode.append);
    await _waitFor(
      controller,
      (state) => state.lines.join('\n') == 'OLD\nAPPEND',
    );
    expect(missingStates, 0);

    coordinator.state.value = const ConnectionView(
      phase: ConnectionPhase.disconnected,
    );
    expect(controller.state.lines, ['OLD', 'APPEND']);
    expect(controller.state.fileExists, isTrue);
    await file.delete();
    await file.writeAsString('RESTART ENTRY\n');
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: first,
    );
    await _waitFor(
      controller,
      (state) => state.lines.join('\n') == 'RESTART ENTRY',
    );
    expect(missingStates, 1);
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: first,
      downloadSpeed: 30,
    );
    await pumpEventQueue();
    expect(missingStates, 1);
    expect(controller.state.lines, ['RESTART ENTRY']);
    await controller.close();
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: _runtime(3),
    );
    await pumpEventQueue();
    expect(controller.state.lines, ['RESTART ENTRY']);
  });

  for (final lateError in [false, true]) {
    test(
      'new session discards an in-flight old ${lateError ? 'error' : 'chunk'} and reads the replacement',
      () async {
        final readStarted = Completer<void>();
        final release = Completer<({Uint8List data, int offset, int size})?>();
        ({Uint8List data, int offset, int size})? oldChunk;
        var blockNextRead = false;
        final controller = LogFileViewerController(
          LogFileViewerParams(title: 'Access log', path: file.path),
          coordinator: coordinator,
          readLog: (path, {int offset = -1}) async {
            final chunk = await RuntimeDiagnosticFiles.readLog(
              path,
              offset: offset,
            );
            if (blockNextRead) {
              blockNextRead = false;
              oldChunk = chunk;
              readStarted.complete();
              return release.future;
            }
            return chunk;
          },
        );
        addTearDown(controller.close);
        await _waitFor(controller, (state) => state.lines.join('\n') == 'OLD');
        blockNextRead = true;
        await file.writeAsString('LATE OLD\n', mode: FileMode.append);
        await readStarted.future.timeout(const Duration(seconds: 4));
        await file.delete();
        await file.writeAsString('NEW\nCURRENT\n');
        coordinator.state.value = ConnectionView(
          phase: ConnectionPhase.connected,
          runtime: _runtime(2),
        );
        final observed = <LogFileViewerPageState>[];
        final subscription = controller.stream.listen(observed.add);
        addTearDown(subscription.cancel);
        if (lateError) {
          release.completeError(const FileSystemException('old read failed'));
        } else {
          release.complete(oldChunk);
        }
        final state = await _waitFor(
          controller,
          (state) => state.lines.join('\n') == 'NEW\nCURRENT',
        );
        expect(state.failure, isNull);
        expect(observed.every((state) => state.failure == null), isTrue);
        expect(
          observed.expand((state) => state.lines),
          isNot(contains('LATE OLD')),
        );
      },
    );
  }
}

Future<LogFileViewerPageState> _waitFor(
  LogFileViewerController controller,
  bool Function(LogFileViewerPageState) predicate,
) {
  if (predicate(controller.state)) return Future.value(controller.state);
  return controller.stream
      .firstWhere(predicate)
      .timeout(const Duration(seconds: 4));
}

ConnectionRuntime _runtime(int startedAt) => ConnectionRuntime.create(
  configuration: ConnectionConfiguration(),
  compiled: CompiledConnection(
    xrayJson: '{}',
    entries: const [],
    finalExit: null,
    nodeTags: const {},
  ),
  platform: ConnectionPlatform.android,
  request: StartVpnRequest(
    null,
    null,
    '18003',
    '{"apiVersion":3,"method":"runXray","payload":{"xrayJson":"{}"}}',
  ),
  startedAt: DateTime.fromMicrosecondsSinceEpoch(startedAt),
);
