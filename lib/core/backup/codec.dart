import 'dart:convert';
import 'dart:typed_data';

import 'package:onexray/core/backup/model.dart';

const backupFileName = 'OneXray-backup.json';
const backupByteLimit = 64 * 1024 * 1024;

BackupDocument decodeBackup(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > backupByteLimit) {
    throw const FormatException('Backup must be between 1 byte and 64 MiB');
  }
  // Do not include malformed JSON, private keys or Base64 source in diagnostics.
  try {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic> ||
        json['format'] != 'onexray-backup' ||
        json['version'] != 1 ||
        json['createdAt'] is! int ||
        (json['createdAt'] as int) <= 0) {
      throw const FormatException('Unsupported backup format');
    }
    _checkManualGroupFieldTypes(json);
    final document = BackupDocument.fromJson(json);
    DateTime.fromMillisecondsSinceEpoch(document.createdAt);
    validateBackupManualGroups(document);
    return document;
  } catch (_) {
    throw const FormatException('Invalid or unsupported OneXray backup');
  }
}

Uint8List encodeBackup(BackupDocument document) {
  if (document.format != 'onexray-backup' ||
      document.version != 1 ||
      document.createdAt <= 0) {
    throw const FormatException('Unsupported backup format');
  }
  validateBackupManualGroups(document);
  try {
    DateTime.fromMillisecondsSinceEpoch(document.createdAt);
  } on ArgumentError {
    throw const FormatException('Invalid backup creation time');
  }
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(document.toJson())));
  if (bytes.length > backupByteLimit) {
    throw const FormatException('Backup must be between 1 byte and 64 MiB');
  }
  return bytes;
}

void _checkManualGroupFieldTypes(Map<String, dynamic> json) {
  if (json.containsKey('manualGroups')) {
    final groups = json['manualGroups'];
    if (groups is! List) {
      throw const FormatException('Invalid manual groups');
    }
    for (final group in groups) {
      if (group is! Map<String, dynamic> || group['sortOrder'] is! int) {
        throw const FormatException('Invalid manual group order');
      }
    }
  }
  if (json['coreConfigs'] case final List rows) {
    for (final row in rows) {
      if (row is Map<String, dynamic> &&
          row.containsKey('manualSortOrder') &&
          row['manualSortOrder'] is! int) {
        throw const FormatException('Invalid manual node order');
      }
    }
  }
}

/// Group keys belong only to this document; database identities never cross
/// the backup boundary. Protocol configuration validation stays with Xray.
void validateBackupManualGroups(BackupDocument document) {
  final keys = <String>{};
  for (final group in document.manualGroups) {
    if (group.key.trim().isEmpty ||
        !keys.add(group.key) ||
        group.name.trim().isEmpty ||
        group.sortOrder < 0) {
      throw const FormatException('Invalid or duplicate manual group');
    }
  }
  for (final row in document.coreConfigs) {
    if (row.manualSortOrder < 0 ||
        (row.manualGroupKey != null && !keys.contains(row.manualGroupKey)) ||
        (row.type != 'outbound' &&
            (row.manualGroupKey != null || row.manualSortOrder != 0))) {
      throw const FormatException('Invalid manual node grouping');
    }
  }
}

Map<String, dynamic> decodeBackupConfiguration(String data) {
  try {
    final json = jsonDecode(utf8.decode(base64Decode(data)));
    if (json is Map<String, dynamic>) return json;
  } catch (_) {
    // The caller reports the configuration's name, never its credentials.
  }
  throw const FormatException('Invalid Base64 JSON configuration in backup');
}
