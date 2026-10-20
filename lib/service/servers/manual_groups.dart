import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/shared/in_flight_operations.dart';

/// Manual organization changes never compile or reconnect a running server.
class ManualServerGroupService {
  static final _operations = InFlightOperations();

  static Future<void> pauseForDataClear() => _operations.pause();

  static void resumeAfterDataClear() => _operations.resume();

  final AppDatabase db;

  ManualServerGroupService({AppDatabase? database})
    : db = database ?? AppDatabase();

  static bool isManual(CoreConfigData row) =>
      row.type == CoreConfigType.outbound.name && row.subId == 0;

  Future<int> create(String name) => _write(() async {
    final groups = await db.manualServerGroupDao.allRows;
    final order = groups.isEmpty ? 0 : groups.last.sortOrder + 1;
    return db.manualServerGroupDao.insertRow(
      ManualServerGroupCompanion.insert(
        name: _name(name),
        sortOrder: Value(order),
      ),
    );
  });

  Future<void> rename(int id, String name) => _write(() async {
    await _requireGroup(id);
    await (db.update(db.manualServerGroup)..where((row) => row.id.equals(id)))
        .write(ManualServerGroupCompanion(name: Value(_name(name))));
  });

  Future<void> move(Set<int> ids, {int? targetGroupId}) => _write(() async {
    await _requireGroup(targetGroupId);
    final rows = await _manualRows();
    final moving = rows.where((row) => ids.contains(row.id)).toList();
    if (moving.length != ids.length) {
      throw const FormatException('Manual servers changed');
    }
    final groups = await db.manualServerGroupDao.allRows;
    final groupOrder = {for (final group in groups) group.id: group.sortOrder};
    moving.sort((a, b) {
      if (a.manualGroupId != b.manualGroupId) {
        if (a.manualGroupId == null) return -1;
        if (b.manualGroupId == null) return 1;
        final comparison = (groupOrder[a.manualGroupId] ?? 0).compareTo(
          groupOrder[b.manualGroupId] ?? 0,
        );
        if (comparison != 0) return comparison;
        final groupComparison = a.manualGroupId!.compareTo(b.manualGroupId!);
        if (groupComparison != 0) return groupComparison;
      }
      return _compareServers(a, b);
    });
    var next = _nextOrder(
      rows.where((row) => row.manualGroupId == targetGroupId),
    );
    for (final row in moving) {
      if (row.manualGroupId == targetGroupId) continue;
      await _writePosition(row.id, targetGroupId, next++);
    }
  });

  Future<void> reorderGroups({
    required List<int> expectedIds,
    required List<int> orderedIds,
  }) => _write(() async {
    final current = (await db.manualServerGroupDao.allRows)
        .map((row) => row.id)
        .toList();
    _requireMembership(current, expectedIds, orderedIds);
    for (var index = 0; index < orderedIds.length; index++) {
      await (db.update(db.manualServerGroup)
            ..where((row) => row.id.equals(orderedIds[index])))
          .write(ManualServerGroupCompanion(sortOrder: Value(index)));
    }
  });

  Future<void> reorderServers({
    required int? groupId,
    required List<int> expectedIds,
    required List<int> orderedIds,
  }) => _write(() async {
    await _requireGroup(groupId);
    final current = (await _manualRows())
        .where((row) => row.manualGroupId == groupId)
        .map((row) => row.id)
        .toList();
    _requireMembership(current, expectedIds, orderedIds);
    for (var index = 0; index < orderedIds.length; index++) {
      await _writePosition(orderedIds[index], groupId, index);
    }
  });

  /// Dissolving only moves assets. Destructive group deletion goes through
  /// ServerAssetService's runtime-aware deletion preview and coordinator.
  Future<void> dissolve(int id) => _write(() async {
    await _requireGroup(id);
    final rows = await _manualRows();
    final moving = rows.where((row) => row.manualGroupId == id).toList()
      ..sort(_compareServers);
    var next = _nextOrder(rows.where((row) => row.manualGroupId == null));
    for (final row in moving) {
      await _writePosition(row.id, null, next++);
    }
    await db.manualServerGroupDao.deleteRow(id);
  });

  Future<T> _write<T>(Future<T> Function() action) =>
      _operations.track(() => db.transaction(action));

  Future<List<CoreConfigData>> _manualRows() =>
      (db.select(db.coreConfig)..where(
            (row) =>
                row.type.equals(CoreConfigType.outbound.name) &
                row.subId.equals(0),
          ))
          .get();

  Future<void> _requireGroup(int? id) async {
    if (id != null && await db.manualServerGroupDao.searchRow(id) == null) {
      throw const FormatException('Manual group no longer exists');
    }
  }

  Future<void> _writePosition(int id, int? groupId, int order) =>
      (db.update(db.coreConfig)..where((row) => row.id.equals(id)))
          .write(
            CoreConfigCompanion(
              manualGroupId: Value(groupId),
              manualSortOrder: Value(order),
            ),
          )
          .then((_) {});

  static String _name(String value) {
    final name = value.trim();
    if (name.isEmpty) throw const FormatException('Group name is required');
    return name;
  }

  static int _nextOrder(Iterable<CoreConfigData> rows) =>
      rows.fold(
        -1,
        (order, row) =>
            row.manualSortOrder > order ? row.manualSortOrder : order,
      ) +
      1;

  static int _compareServers(CoreConfigData a, CoreConfigData b) {
    final comparison = a.manualSortOrder.compareTo(b.manualSortOrder);
    return comparison == 0 ? a.id.compareTo(b.id) : comparison;
  }

  static void _requireMembership(
    List<int> current,
    List<int> expected,
    List<int> ordered,
  ) {
    const equality = SetEquality<int>();
    final currentSet = current.toSet();
    if (expected.length != current.length ||
        ordered.length != current.length ||
        !equality.equals(currentSet, expected.toSet()) ||
        !equality.equals(currentSet, ordered.toSet())) {
      throw const FormatException('Group members changed; reload the order');
    }
  }
}
