import 'package:drift/drift.dart';

class CoreConfig extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get type => text()();

  TextColumn get tags => text()();

  TextColumn get data => text().nullable()();

  IntColumn get delay => integer()();

  IntColumn get subId => integer()();

  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
}
