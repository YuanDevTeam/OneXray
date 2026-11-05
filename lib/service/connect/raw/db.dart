import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/tools/empty.dart';

class XrayRawDb {
  /// Selection reads the stored asset strictly, independently of editor recovery.
  /// This checks readability only; Core validation remains the save/start path.
  static String readSelectionFromDbData(CoreConfigData config) {
    if (config.type != CoreConfigType.raw.name ||
        config.data == null ||
        config.data!.isEmpty) {
      throw const FormatException('Raw configuration is unavailable');
    }
    final text = utf8.decode(base64Decode(config.data!));
    if (jsonDecode(text) is! Map<String, dynamic>) {
      throw const FormatException('Raw configuration must be a JSON object');
    }
    return text;
  }

  static String readFromDbData(CoreConfigData config) {
    if (EmptyTool.checkString(config.data)) {
      final bytes = base64Decode(config.data!);
      final text = utf8.decode(bytes);
      return text;
    }
    return "";
  }

  static CoreConfigCompanion configCompanion(String name, String rawText) {
    final bytes = utf8.encode(rawText);
    final base64Data = base64Encode(bytes);
    final row = CoreConfigCompanion.insert(
      name: name,
      type: CoreConfigType.raw.name,
      tags: "",
      data: Value<String>(base64Data),
      delay: PingDelayConstants.unknown,
      subId: DBConstants.defaultId,
    );
    return row;
  }
}
