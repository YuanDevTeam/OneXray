import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

abstract interface class ProxyJournalStore {
  Future<void> lock();
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
  Future<void> clear();
}

/// Private, device-local recovery state. This directory is never exported.
final class FileProxyJournalStore implements ProxyJournalStore {
  FileProxyJournalStore(this.directory);

  final Future<String> Function() directory;
  RandomAccessFile? _lock;
  Directory? _root;

  Future<Directory> _directory() async {
    if (_root != null) return _root!;
    final root = Directory(p.join(await directory(), 'proxy-state'));
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Invalid local proxy state directory',
        root.path,
      );
    }
    await root.create(recursive: true);
    if (!Platform.isWindows) await _restrict(root.path, '700');
    return _root = root;
  }

  Future<void> _restrict(String path, String mode) async {
    final result = await Process.run('/bin/chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException('Unable to protect local proxy state', path);
    }
  }

  @override
  Future<void> lock() async {
    if (_lock != null) return;
    final root = await _directory();
    final file = File(p.join(root.path, 'owner.lock'));
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException('Invalid local proxy lock', file.path);
    }
    final handle = await file.open(mode: FileMode.append);
    try {
      // Nonblocking: a live App must never lose its proxy ownership to another.
      await handle.lock(FileLock.exclusive);
      _lock = handle;
    } catch (_) {
      await handle.close();
      throw StateError(
        'Another OneXray instance owns the local proxy session.',
      );
    }
  }

  Future<File> _file() async =>
      File(p.join((await _directory()).path, 'session.json'));

  @override
  Future<Map<String, dynamic>?> read() async {
    final file = await _file();
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file || await file.length() > 65536) {
      throw const FormatException('Invalid local proxy recovery record');
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic> || value['version'] != 1) {
      throw const FormatException('Invalid local proxy recovery record');
    }
    return value;
  }

  @override
  Future<void> write(Map<String, dynamic> value) async {
    final file = await _file();
    final temporary = File('${file.path}.pending');
    final type = await FileSystemEntity.type(
      temporary.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Invalid local proxy recovery temporary file',
        temporary.path,
      );
    }
    await temporary.writeAsString(jsonEncode(value), flush: true);
    if (!Platform.isWindows) await _restrict(temporary.path, '600');
    // Dart's rename replaces the existing file on supported desktop platforms.
    await temporary.rename(file.path);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  /// Used by fixture/embedding lifecycles. Production keeps the lock for the App.
  Future<void> close() async {
    final handle = _lock;
    _lock = null;
    await handle?.close();
  }
}
