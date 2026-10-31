import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/advanced/xray/runtime_files.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;

  @override
  Future<String?> getApplicationCachePath() async => path;
}

Future<String> _hash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

class _SaveLocation extends FileSelectorPlatform {
  _SaveLocation(this.destination);
  final String destination;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    expect(options.suggestedName, 'access.log');
    expect(acceptedTypeGroups!.single.extensions, ['log']);
    return FileSaveLocation(destination);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = 'dev.flutter.pigeon.onexray.FileExportHostApi.saveFile';
  const codec = StandardMessageCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late Directory cache;
  late File source;
  late PathProviderPlatform previousPaths;

  setUp(() async {
    final root = await Directory('../references/runtime-log-tests').absolute
        .create(recursive: true);
    directory = await root.createTemp('export-');
    cache = await Directory('${directory.path}/cache').create();
    source = await File('${directory.path}/access.log')
        .writeAsString('first\n');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(cache.path);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() async {
    messenger.setMockMessageHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    PathProviderPlatform.instance = previousPaths;
    await directory.delete(recursive: true);
  });

  test(
    'exports over 64 MiB by path and keeps a stable copy while logs grow',
    () async {
      const size = 64 * 1024 * 1024 + 1;
      final handle = await source.open(mode: FileMode.append);
      await handle.truncate(size);
      await handle.close();
      final originalHash = await _hash(source);
      late File snapshot;
      messenger.setMockMessageHandler(channel, (data) async {
        final args = codec.decodeMessage(data) as List;
        snapshot = File(args[0] as String);
        expect(args[1], 'access.log');
        expect(snapshot.path, isNot(source.path));
        expect(await snapshot.length(), size);
        expect(await _hash(snapshot), originalHash);
        expect(await _hash(source), originalHash);
        await source.writeAsString('next\n', mode: FileMode.append);
        expect(await snapshot.length(), size);
        expect(await _hash(snapshot), originalHash);
        return codec.encodeMessage([true]);
      });

      expect(
        await RuntimeDiagnosticFiles.exportLog(source.path, 'access.log'),
        isTrue,
      );
      expect(await snapshot.exists(), isFalse);
      expect(await cache.list().toList(), isEmpty);
      expect(await source.length(), size + 5);
      final tail = await RuntimeDiagnosticFiles.readLog(source.path, limit: 5);
      expect(String.fromCharCodes(tail!.data), 'next\n');
    },
  );

  test('cancel removes the copy and preserves the original', () async {
    messenger.setMockMessageHandler(
      channel,
      (_) async => codec.encodeMessage([false]),
    );
    expect(
      await RuntimeDiagnosticFiles.exportLog(source.path, 'access.log'),
      isFalse,
    );
    expect(await source.readAsString(), 'first\n');
    expect(await cache.list().toList(), isEmpty);
  });

  test('save failures remove the copy and preserve the original', () async {
    messenger.setMockMessageHandler(
      channel,
      (_) async =>
          codec.encodeMessage(['export-failed', 'Synthetic disk error', null]),
    );
    await expectLater(
      RuntimeDiagnosticFiles.exportLog(source.path, 'access.log'),
      throwsA(isA<PlatformException>()),
    );
    expect(await source.readAsString(), 'first\n');
    expect(await cache.list().toList(), isEmpty);
  });

  test('desktop copies to the path chosen by the save dialog', () async {
    final originalSelector = FileSelectorPlatform.instance;
    addTearDown(() => FileSelectorPlatform.instance = originalSelector);
    final destination = File('${directory.path}/saved.log');
    FileSelectorPlatform.instance = _SaveLocation(destination.path);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    expect(
      await RuntimeDiagnosticFiles.exportLog(source.path, 'access.log'),
      isTrue,
    );
    expect(await destination.readAsString(), 'first\n');
    expect(await source.readAsString(), 'first\n');
    expect(await cache.list().toList(), isEmpty);
  });
}
