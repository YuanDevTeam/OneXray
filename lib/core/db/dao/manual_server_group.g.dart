// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manual_server_group.dart';

// ignore_for_file: type=lint
mixin _$ManualServerGroupDaoMixin on DatabaseAccessor<AppDatabase> {
  $ManualServerGroupTable get manualServerGroup =>
      attachedDatabase.manualServerGroup;
  ManualServerGroupDaoManager get managers => ManualServerGroupDaoManager(this);
}

class ManualServerGroupDaoManager {
  final _$ManualServerGroupDaoMixin _db;
  ManualServerGroupDaoManager(this._db);
  $$ManualServerGroupTableTableManager get manualServerGroup =>
      $$ManualServerGroupTableTableManager(
        _db.attachedDatabase,
        _db.manualServerGroup,
      );
}
