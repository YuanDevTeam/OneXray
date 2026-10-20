import 'package:drift/drift.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/table/manual_server_group.dart';

part 'manual_server_group.g.dart';

@DriftAccessor(tables: [ManualServerGroup])
class ManualServerGroupDao extends DatabaseAccessor<AppDatabase>
    with _$ManualServerGroupDaoMixin {
  ManualServerGroupDao(super.db);

  Future<List<ManualServerGroupData>> get allRows =>
      (select(manualServerGroup)..orderBy([
            (row) => OrderingTerm.asc(row.sortOrder),
            (row) => OrderingTerm.asc(row.id),
          ]))
          .get();

  Stream<List<ManualServerGroupData>> get allRowsStream =>
      (select(manualServerGroup)..orderBy([
            (row) => OrderingTerm.asc(row.sortOrder),
            (row) => OrderingTerm.asc(row.id),
          ]))
          .watch();

  Future<ManualServerGroupData?> searchRow(int id) => (select(
    manualServerGroup,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<int> insertRow(ManualServerGroupCompanion entry) =>
      into(manualServerGroup).insert(entry);

  Future<int> deleteRow(int id) =>
      (delete(manualServerGroup)..where((row) => row.id.equals(id))).go();

  Future<int> clear() => delete(manualServerGroup).go();
}
