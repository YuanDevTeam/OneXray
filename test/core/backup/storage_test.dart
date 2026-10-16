import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/icloud_storage.dart';
import 'package:onexray/core/backup/codec.dart';
import 'package:onexray/core/backup/storage.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/atomic_file.dart';
import 'package:saf_stream/saf_stream_platform_interface.dart';

class PullStorage extends SafStreamPlatform {
  final List<Uint8List> chunks;
  bool closed = false;
  Object? failure;
  int expectedBufferSize = 64 * 1024;
  PullStorage(this.chunks);
  @override
  Future<String> startReadCustomFileStream(
    String uri, {
    int? bufferSize,
  }) async {
    expect(uri, 'content://fixture/backup');
    expect(bufferSize, expectedBufferSize);
    return 'fixture';
  }

  @override
  Future<Uint8List?> readCustomFileStreamChunk(String session) async {
    if (failure != null) throw failure!;
    return chunks.isEmpty ? null : chunks.removeAt(0);
  }

  @override
  Future<void> endReadCustomFileStream(String session) async {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('icloud_storage_plus');
  final originalSaf = SafStreamPlatform.instance;
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    SafStreamPlatform.instance = originalSaf;
  });

  test(
    'Apple binding is local; only explicit reads and writes access iCloud',
    () async {
      final storage = PlatformBackupStorage(platform: TargetPlatform.iOS);
      final calls = <String>[];
      Uint8List? saved;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        final args = call.arguments as Map;
        expect(args['containerId'], backupContainerId);
        expect(args['relativePath'], backupCloudPath);
        switch (call.method) {
          case 'getItemMetadata':
            return null;
          case 'readInPlaceBytes':
            return saved;
          case 'writeInPlaceBytes':
            saved = args['contents'] as Uint8List;
            return null;
          default:
            fail('Unexpected cloud operation');
        }
      });
      final target = (await storage.select(create: false))!;
      expect(calls, isEmpty);
      await storage.write(target, Uint8List.fromList([1, 2]));
      await storage.write(target, Uint8List.fromList([3]));
      expect(await storage.read(target), [3]);
      expect(calls, [
        'writeInPlaceBytes',
        'writeInPlaceBytes',
        'getItemMetadata',
        'readInPlaceBytes',
      ]);
    },
  );

  test(
    'Apple metadata rejects oversized files before requesting contents',
    () async {
      final storage = PlatformBackupStorage(platform: TargetPlatform.macOS);
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getItemMetadata');
        return {
          'relativePath': backupCloudPath,
          'sizeInBytes': backupByteLimit + 1,
        };
      });
      await expectLater(
        storage.read((await storage.select(create: false))!),
        throwsFormatException,
      );
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    test(
      '$platform file binding reuses one target without accessing iCloud',
      () async {
        const identifier = 'file:///fixture/selected-backup.json';
        final calls = <String>[];
        Uint8List bytes = Uint8List.fromList([1]);
        void mock(
          String api,
          String method,
          Future<Object> Function(Object?) handler,
        ) {
          final channel = BasicMessageChannel<Object?>(
            'dev.flutter.pigeon.onexray.$api.$method',
            BackupHostApi.pigeonChannelCodec,
          );
          messenger.setMockDecodedMessageHandler<Object?>(channel, handler);
          addTearDown(
            () =>
                messenger.setMockDecodedMessageHandler<Object?>(channel, null),
          );
        }

        messenger.setMockMethodCallHandler(
          channel,
          (_) async => fail('Local files must not access iCloud'),
        );
        mock('BackupHostApi', 'selectBackupFile', (args) async {
          calls.add('select');
          expect(args, [true]);
          return [
            BackupLocation(
              identifier: identifier,
              label: '/fixture/selected-backup.json',
            ),
          ];
        });
        mock('AppleBackupHostApi', 'writeBackupFile', (args) async {
          final values = args! as List;
          expect(values.first, identifier);
          bytes = values[1] as Uint8List;
          calls.add('write');
          return [null];
        });
        mock('AppleBackupHostApi', 'hasBackupFileContents', (args) async {
          expect(args, [identifier]);
          calls.add('probe');
          return [bytes.isNotEmpty];
        });
        mock('AppleBackupHostApi', 'readBackupFile', (args) async {
          expect(args, [identifier]);
          calls.add('read');
          return [bytes];
        });
        mock('BackupHostApi', 'releaseBackupFile', (args) async {
          expect(args, [identifier]);
          calls.add('release');
          return [null];
        });
        final storage = PlatformBackupStorage(platform: platform);
        final target = (await storage.select(create: true, local: true))!;
        expect(target.identifier, identifier);
        expect(BackupTarget.fromJson(target.toJson()).identifier, identifier);
        expect(await storage.hasContents(target), true);
        await storage.write(target, Uint8List.fromList([2, 3]));
        expect(await storage.read(target), [2, 3]);
        await storage.release(target);
        await storage.release((await storage.select(create: false))!);
        expect(calls, ['select', 'probe', 'write', 'read', 'release']);
      },
    );
  }

  test('SAF pull reads continue after short chunks and close at EOF', () async {
    final fake = PullStorage([
      Uint8List.fromList([1]),
      Uint8List.fromList([2, 3]),
    ]);
    SafStreamPlatform.instance = fake;
    expect(await readSafBackup('content://fixture/backup'), [1, 2, 3]);
    expect(fake.closed, isTrue);
  });

  test(
    'SAF content probe requests one byte and closes without reading the rest',
    () async {
      final fake = PullStorage([
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
      ])..expectedBufferSize = 1;
      SafStreamPlatform.instance = fake;
      expect(await readSafBackup('content://fixture/backup', probeOnly: true), [
        1,
      ]);
      expect(fake.chunks, hasLength(1));
      expect(fake.closed, true);
    },
  );

  test(
    'iCloud content probe uses metadata and propagates access failures',
    () async {
      final storage = PlatformBackupStorage(platform: TargetPlatform.iOS);
      final target = (await storage.select(create: false))!;
      for (final size in [null, 0, 1, backupByteLimit + 1]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getItemMetadata');
          return size == null
              ? null
              : {'relativePath': backupCloudPath, 'sizeInBytes': size};
        });
        expect(await storage.hasContents(target), size != null && size > 0);
      }
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'accessDenied'),
      );
      await expectLater(
        storage.hasContents(target),
        throwsA(isA<ICloudOperationException>()),
      );
    },
  );

  test('directory content probe distinguishes an absent file from a missing directory', () async {
    final root = await Directory('../references/onexray-tests').absolute
        .create(recursive: true);
    final dir = await root.createTemp('backup-probe-');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final storage = PlatformBackupStorage(platform: TargetPlatform.windows);
    final target = BackupTarget(dir.path, '${dir.path}/$backupFileName');
    expect(await storage.hasContents(target), false);
    final file = File(target.label);
    await file.writeAsBytes([]);
    expect(await storage.hasContents(target), false);
    await file.writeAsBytes([42]);
    expect(await storage.hasContents(target), true);
    await dir.delete(recursive: true);
    await expectLater(
      storage.hasContents(target),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('SAF pull closes after size rejection or provider failure', () async {
    for (final failure in [null, const FileSystemException('access revoked')]) {
      final fake = PullStorage([Uint8List(backupByteLimit + 1)])
        ..failure = failure;
      SafStreamPlatform.instance = fake;
      await expectLater(
        readSafBackup('content://fixture/backup'),
        throwsA(isA<Exception>()),
      );
      expect(fake.closed, isTrue);
    }
  });

  test(
    'local replacement preserves unrelated files and rejects missing folders',
    () async {
      final root = await Directory('../references/cloud-backup/file-tests')
          .absolute
          .create(recursive: true);
      final dir = await root.createTemp('replacement-');
      addTearDown(() => dir.delete(recursive: true));
      final target = File('${dir.path}/$backupFileName');
      final unrelated = File('${target.path}.tmp');
      await unrelated.writeAsString('not ours');
      await writeBytesAtomically(target, [1, 2]);
      await writeBytesAtomically(target, [3]);
      expect(await target.readAsBytes(), [3]);
      expect(await unrelated.readAsString(), 'not ours');
      expect(await dir.list().length, 2);
      await expectLater(
        writeBytesAtomically(File('${dir.path}/missing/$backupFileName'), [4]),
        throwsA(isA<FileSystemException>()),
      );
      expect(await Directory('${dir.path}/missing').exists(), isFalse);
    },
  );
}
