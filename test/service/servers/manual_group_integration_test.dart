import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/manual_groups.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manual organization streams change display order without narrowing source or fixed selection', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final bus = AppEventBus();
    addTearDown(bus.close);
    final groups = ManualServerGroupService(database: db);
    final groupA = await groups.create('AWS');
    final groupB = await groups.create('Azure');

    Future<int> node(String name, int delay, {int source = 0}) =>
        db.coreConfigDao.insertAssetRow(
          outboundCompanion({'tag': name, 'protocol': 'freedom'})
              .copyWith(delay: Value(delay), subId: Value(source)),
        );

    final a = await node('A', 80);
    final b = await node('B', 10);
    final c = await node('C', 40);
    final ungrouped = await node('Ungrouped', 25);
    final source = await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'Provider',
        url: 'https://example.com/sub',
        timestamp: DateTime(2026),
      ),
    );
    final subscription = await node('Subscription fastest', 1, source: source);
    await groups.move({a, c}, targetGroupId: groupA);
    await groups.move({b}, targetGroupId: groupB);
    final fixed = ConnectionConfiguration(
      connection: ConnectionSettings(selection: ServerSelection.server(a)),
    );
    await db.connectionConfigDao.commit(configurationJson: fixed.encode());

    final events = StreamIterator(ServerCatalog.watch(db, eventBus: bus));
    addTearDown(events.cancel);
    Future<ServerCatalog> display(
      List<int> ids,
      List<int> groupIds, {
      bool Function(ServerCatalog)? committed,
    }) async {
      while (await events.moveNext()) {
        final catalog = events.current;
        if (const ListEquality<int>().equals(
              catalog.servers.map((row) => row.id).toList(),
              ids,
            ) &&
            const ListEquality<int>().equals(
              catalog.orderedManualGroups.map((row) => row.id).toList(),
              groupIds,
            ) &&
            catalog.sourcesById.containsKey(source) &&
            (committed == null || committed(catalog))) {
          return catalog;
        }
      }
      throw StateError('Catalog closed before the committed order appeared');
    }

    final resolver = ConnectionResolver(
      rows: db.coreConfigDao.watchOutbounds,
      probe: (_) async => fail(
        'All candidates are measured; organization must not request probes',
      ),
    );
    Future<void> unchangedSelections({int fastest = -1}) async {
      final manual = await resolver.resolve(
        ConnectionSettings(selection: const ServerSelection.source(0)),
      );
      expect(manual.single.id, fastest == -1 ? b : fastest);
      final fixedResult = await resolver.resolve(fixed.connection);
      expect(fixedResult.single.id, a);
      expect(
        (await db.connectionConfigDao.read()).configurationJson,
        fixed.encode(),
      );
      final automatic = await resolver.resolve(ConnectionSettings());
      expect(automatic.single.id, subscription);
    }

    await display([ungrouped, a, c, b, subscription], [groupA, groupB]);
    await unchangedSelections();
    await groups.reorderGroups(
      expectedIds: [groupA, groupB],
      orderedIds: [groupB, groupA],
    );
    await display([ungrouped, b, a, c, subscription], [groupB, groupA]);
    await unchangedSelections();
    await groups.reorderServers(
      groupId: groupA,
      expectedIds: [a, c],
      orderedIds: [c, a],
    );
    await display([ungrouped, b, c, a, subscription], [groupB, groupA]);
    await unchangedSelections();
    await groups.move({ungrouped}, targetGroupId: groupA);
    await display([b, c, a, ungrouped, subscription], [groupB, groupA]);
    await groups.move({c}, targetGroupId: groupB);
    await display(
      [b, c, a, ungrouped, subscription],
      [groupB, groupA],
      committed: (catalog) =>
          catalog.servers.singleWhere((row) => row.id == c).manualGroupId ==
          groupB,
    );
    await unchangedSelections();

    final before = await db.coreConfigDao.searchRow(a);
    await (db.update(db.coreConfig)..where((row) => row.id.equals(a))).write(
      const CoreConfigCompanion(delay: Value(5)),
    );
    await display(
      [b, c, a, ungrouped, subscription],
      [groupB, groupA],
      committed: (catalog) =>
          catalog.servers.singleWhere((row) => row.id == a).delay == 5,
    );
    final after = (await db.coreConfigDao.searchRow(a))!;
    expect(after.manualGroupId, before!.manualGroupId);
    expect(after.manualSortOrder, before.manualSortOrder);
    await unchangedSelections(fastest: a);
  });
}
