import 'dart:async';

import 'package:drift/drift.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/db/table/core_config.dart';

part 'core_config.g.dart';

@DriftAccessor(tables: [CoreConfig])
class CoreConfigDao extends DatabaseAccessor<AppDatabase>
    with _$CoreConfigDaoMixin {
  CoreConfigDao(super.db);

  Future<List<CoreConfigData>> get allRawRowsWithData =>
      (select(coreConfig)
            ..where((table) => table.type.equals(CoreConfigType.raw.name))
            ..orderBy([(table) => OrderingTerm.asc(table.id)]))
          .get();

  Stream<List<CoreConfigData>> get allRawRowsWithDataStream =>
      (select(coreConfig)
            ..where((table) => table.type.equals(CoreConfigType.raw.name))
            ..orderBy([(table) => OrderingTerm.asc(table.id)]))
          .watch();

  Stream<List<CoreConfigData>> watchOutbounds() =>
      (select(coreConfig)
            ..where((row) => row.type.equals(CoreConfigType.outbound.name))
            ..orderBy([(row) => OrderingTerm.asc(row.delay)]))
          .watch();

  Stream<bool> watchHasOutbounds() =>
      (selectOnly(coreConfig)
            ..addColumns([coreConfig.id])
            ..where(
              coreConfig.type.equals(CoreConfigType.outbound.name) &
                  coreConfig.data.isNotNull(),
            )
            ..orderBy([OrderingTerm.asc(coreConfig.delay)])
            ..limit(1))
          .watch()
          .map((rows) => rows.isNotEmpty)
          .distinct();

  Future<List<int>> get unmeasuredOutboundIds =>
      (selectOnly(coreConfig)
            ..addColumns([coreConfig.id])
            ..where(
              coreConfig.type.equals(CoreConfigType.outbound.name) &
                  coreConfig.data.isNotNull() &
                  coreConfig.delay.equals(PingDelayConstants.unknown),
            ))
          .map((row) => row.read(coreConfig.id)!)
          .get();

  Future<List<CoreConfigData>> allOutboundRowsWithDataBySubId(
    int subId,
  ) async =>
      (select(coreConfig)
            ..where((tbl) => tbl.type.equals(CoreConfigType.outbound.name))
            ..where((tbl) => tbl.subId.equals(subId))
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.delay)]))
          .get();

  Future<CoreConfigData?> searchRow(int id) async {
    return (select(
      coreConfig,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<bool> updateRow(CoreConfigData entry) async {
    if (entry.type != CoreConfigType.outbound.name &&
        entry.type != CoreConfigType.raw.name &&
        entry.type != CoreConfigType.Remnawave.name) {
      throw StateError('Unsupported asset type');
    }
    return await (update(coreConfig)..where(
              (table) =>
                  table.id.equals(entry.id) & table.type.equals(entry.type),
            ))
            .write(entry.toCompanion(false)) >
        0;
  }

  /// Internal/complete-restore insertion. Does not enforce asset types or limits.
  /// Ordinary additions and imports must use [insertAssetRow]/[insertAssetRows].
  Future<int> insertRow(CoreConfigCompanion entry) async {
    return into(coreConfig).insert(entry);
  }

  /// Internal/complete-restore batch; retained Raw rows may exceed the new limit.
  Future<int> insertRows(List<CoreConfigCompanion> entries) async {
    if (entries.isEmpty) {
      return 0;
    }
    await coreConfig.insertAll(entries);
    return entries.length;
  }

  static const maxRawConfigs = 3;

  Future<int> insertAssetRow(CoreConfigCompanion entry) =>
      attachedDatabase.transaction(() async {
        await _checkNewAssets([entry]);
        return insertRow(entry);
      });

  Future<int> insertAssetRows(List<CoreConfigCompanion> entries) =>
      attachedDatabase.transaction(() async {
        await _checkNewAssets(entries);
        return insertRows(entries);
      });

  Future<void> _checkNewAssets(List<CoreConfigCompanion> entries) async {
    var addedRaw = 0;
    for (final entry in entries) {
      final type = entry.type.present ? entry.type.value : null;
      if (type != CoreConfigType.outbound.name &&
          type != CoreConfigType.raw.name &&
          type != CoreConfigType.Remnawave.name) {
        throw ArgumentError('Unsupported asset type');
      }
      if (type == CoreConfigType.Remnawave.name &&
          (!entry.subId.present || entry.subId.value <= 0)) {
        throw ArgumentError('Provider configurations require a subscription');
      }
      if (type == CoreConfigType.raw.name) {
        addedRaw += 1;
      }
    }
    if (addedRaw == 0) {
      return;
    }
    final count = coreConfig.id.count();
    final row =
        await (selectOnly(coreConfig)
              ..addColumns([count])
              ..where(coreConfig.type.equals(CoreConfigType.raw.name)))
            .getSingle();
    if (row.read(count)! + addedRaw > maxRawConfigs) {
      throw StateError('At most three new Raw configurations are allowed');
    }
  }

  Future<int> deleteRow(CoreConfigData entry) async {
    final res = await (delete(
      coreConfig,
    )..where((tbl) => tbl.id.equals(entry.id))).go();
    return res;
  }

  Future<int> clear() async {
    final res = await delete(coreConfig).go();
    return res;
  }
}
