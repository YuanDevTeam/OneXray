import 'package:drift/drift.dart';

class ManualServerGroup extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
