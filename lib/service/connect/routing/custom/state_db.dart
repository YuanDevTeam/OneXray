import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/connect/routing/custom/document.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';

/// Converts the persisted Base64 UTF-8 Xray document to and from editable state.
extension RoutingProfileStateDb on RoutingConfiguration {
  static RoutingProfileState read(RoutingProfileData row) {
    if (row.advanced) {
      throw const FormatException('Use the advanced JSON editor');
    }
    return readData(id: row.id, name: row.name, data: row.data);
  }

  static RoutingConfiguration readConfiguration(RoutingProfileData row) =>
      row.advanced
      ? AdvancedRoutingDocument.parse(
          utf8.decode(base64Decode(row.data)),
          id: row.id,
          name: row.name,
          allowMetadata: false,
        ).state
      : read(row);

  static RoutingProfileState readData({
    int? id,
    required String name,
    required String data,
  }) {
    if (name.trim().isEmpty || name.trim().runes.length > 32) {
      throw const FormatException('Invalid Custom routing profile name');
    }
    return RoutingProfileDocument.parse(
      utf8.decode(base64Decode(data)),
      id: id,
      name: name,
      allowMetadata: false,
      ignoreRetiredFields: true,
    ).state;
  }

  String get databaseData => JsonTool.encodeJsonToBase64(toJson());

  RoutingProfileCompanion get insertCompanion => RoutingProfileCompanion.insert(
    name: name,
    data: databaseData,
    advanced: Value(advanced),
  );

  RoutingProfileData updateData(RoutingProfileData row) =>
      row.copyWith(name: name, data: databaseData, advanced: advanced);
}
