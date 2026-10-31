import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:onexray/core/tools/file.dart';
import 'package:onexray/service/connect/runtime.dart';

abstract final class RuntimeDiagnosticFiles {
  static const logChunkBytes = 1024 * 1024;

  static String? logPath(ConnectionRuntime? runtime, {required bool access}) {
    if (runtime == null) return null;
    final log = (jsonDecode(runtime.xrayJson) as Map<String, dynamic>)['log'];
    final path = log is Map ? log[access ? 'access' : 'error'] : null;
    return path is String && path.isNotEmpty && path != 'none' ? path : null;
  }

  static Future<String> readConfiguration({String? text, String? path}) async {
    const limit = 16 * 1024 * 1024;
    if (text != null) {
      if (utf8.encode(text).length > limit) {
        throw const FormatException('Configuration is too large');
      }
      return text;
    }
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Configuration is unavailable');
    }
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > limit) {
      throw const FileSystemException('Configuration is unavailable');
    }
    return file.readAsString();
  }

  static Future<bool> exportConfiguration(String text) => FileTool.saveData(
    Uint8List.fromList(utf8.encode(text)),
    'OneXray-runtime.json',
    'json',
  );

  static Future<({Uint8List data, int offset, int size})?> readLog(
    String path, {
    int offset = -1,
    int limit = logChunkBytes,
  }) async {
    if (offset < -1 || limit <= 0 || limit > logChunkBytes) {
      throw const FormatException('Invalid log request');
    }
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw const FileSystemException('Log file is unavailable');
    }
    final file = await File(path).open();
    try {
      final size = await file.length();
      final start = offset == -1 ? max(0, size - limit) : min(offset, size);
      await file.setPosition(start);
      final data = await file.read(min(size - start, limit));
      return (data: data, offset: start, size: size);
    } finally {
      await file.close();
    }
  }

  static Future<bool> exportLog(String path, String name) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException('Log file is unavailable');
    }
    return FileTool.saveFile(path, name, 'log');
  }
}
