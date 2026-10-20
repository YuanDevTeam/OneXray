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

  Expression<bool> _sourceMode(
    SubscriptionMode mode, {
    bool allowUnowned = false,
  }) {
    final sources = attachedDatabase.subscription;
    final matching = selectOnly(sources)
      ..addColumns([sources.id])
      ..where(sources.mode.equals(mode.name));
    final matches = coreConfig.subId.isInQuery(matching);
    if (!allowUnowned) return matches;
    final owned = selectOnly(sources)..addColumns([sources.id]);
    // Manual nodes and retained legacy nodes without a source stay usable.
    return coreConfig.subId.equals(0) |
        coreConfig.subId.isInQuery(owned).not() |
        matches;
  }

  Expression<bool> get _activeOutbound =>
      coreConfig.type.equals(CoreConfigType.outbound.name) &
      _sourceMode(SubscriptionMode.appManaged, allowUnowned: true);

  Expression<bool> get _activeServer =>
      _activeOutbound |
      (coreConfig.type.equals(CoreConfigType.Remnawave.name) &
          _sourceMode(SubscriptionMode.providerManaged));

  Stream<List<CoreConfigData>> watchServers() =>
      (select(coreConfig)
            ..where((_) => _activeServer)
            ..orderBy([(row) => OrderingTerm.asc(row.id)]))
          .watch();

  Future<List<CoreConfigData>> allActiveServerRows() =>
      (select(coreConfig)
            ..where((_) => _activeServer)
            ..orderBy([(row) => OrderingTerm.asc(row.id)]))
          .get();

  Future<CoreConfigData?> searchActiveServerRow(int id) => (select(
    coreConfig,
  )..where((row) => row.id.equals(id) & _activeServer)).getSingleOrNull();

  Future<CoreConfigData?> searchActiveOutboundRow(int id) => (select(
    coreConfig,
  )..where((row) => row.id.equals(id) & _activeOutbound)).getSingleOrNull();

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
            ..where((_) => _activeOutbound)
            ..orderBy([(row) => OrderingTerm.asc(row.delay)]))
          .watch();

  Stream<bool> watchHasOutbounds() =>
      (selectOnly(coreConfig)
            ..addColumns([coreConfig.id])
            ..where(_activeOutbound & coreConfig.data.isNotNull())
            ..orderBy([OrderingTerm.asc(coreConfig.delay)])
            ..limit(1))
          .watch()
          .map((rows) => rows.isNotEmpty)
          .distinct();

  Future<List<int>> get unmeasuredOutboundIds =>
      (selectOnly(coreConfig)
            ..addColumns([coreConfig.id])
            ..where(
              _activeOutbound &
                  coreConfig.data.isNotNull() &
                  coreConfig.delay.equals(PingDelayConstants.unknown),
            ))
          .map((row) => row.read(coreConfig.id)!)
          .get();

  Future<List<CoreConfigData>> allOutboundRowsWithDataBySubId(
    int subId,
  ) async =>
      (select(coreConfig)
            ..where((_) => _activeOutbound)
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
        return insertRow((await _appendManualAssets([entry])).single);
      });

  Future<int> insertAssetRows(List<CoreConfigCompanion> entries) =>
      attachedDatabase.transaction(() async {
        await _checkNewAssets(entries);
        return insertRows(await _appendManualAssets(entries));
      });

  /// Ordinary additions always append to the virtual ungrouped collection.
  /// Full restore uses insertRow(s) and keeps its explicitly restored positions.
  Future<List<CoreConfigCompanion>> _appendManualAssets(
    List<CoreConfigCompanion> entries,
  ) async {
    bool manual(CoreConfigCompanion entry) =>
        entry.type.present &&
        entry.type.value == CoreConfigType.outbound.name &&
        entry.subId.present &&
        entry.subId.value == 0;
    if (!entries.any(manual)) return entries;
    final maximum = coreConfig.manualSortOrder.max();
    final result =
        await (selectOnly(coreConfig)
              ..addColumns([maximum])
              ..where(
                coreConfig.type.equals(CoreConfigType.outbound.name) &
                    coreConfig.subId.equals(0) &
                    coreConfig.manualGroupId.isNull(),
              ))
            .getSingle();
    var next = (result.read(maximum) ?? -1) + 1;
    return [
      for (final entry in entries)
        if (manual(entry))
          entry.copyWith(
            manualGroupId: const Value(null),
            manualSortOrder: Value(next++),
          )
        else
          entry,
    ];
  }

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
