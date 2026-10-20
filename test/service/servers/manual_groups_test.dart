import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/servers/manual_groups.dart';

void main() {
  late AppDatabase db;
  late ManualServerGroupService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ManualServerGroupService(database: db);
    addTearDown(db.close);
    addTearDown(ManualServerGroupService.resumeAfterDataClear);
  });

  Future<CoreConfigData> node(
    String name, {
    String type = 'outbound',
    int subId = 0,
  }) async {
    final id = await db.coreConfigDao.insertAssetRow(
      CoreConfigCompanion.insert(
        name: name,
        type: type,
        tags: 'saved-tags',
        data: const Value('original-payload'),
        delay: 27,
        subId: subId,
        favorite: const Value(true),
      ),
    );
    return (await db.coreConfigDao.searchRow(id))!;
  }

  test(
    'empty groups persist, names are trimmed and group order is atomic',
    () async {
      final first = await service.create('  AWS  ');
      final second = await service.create('Azure');
      expect((await db.manualServerGroupDao.allRows).map((row) => row.name), [
        'AWS',
        'Azure',
      ]);
      expect(await db.coreConfigDao.allActiveServerRows(), isEmpty);
      await service.rename(first, '  Household  ');
      await service.reorderGroups(
        expectedIds: [first, second],
        orderedIds: [second, first],
      );
      expect((await db.manualServerGroupDao.allRows).map((row) => row.id), [
        second,
        first,
      ]);
      await expectLater(service.rename(first, '   '), throwsFormatException);
      final third = await service.create('Azure');
      await expectLater(
        service.reorderGroups(
          expectedIds: [first, second],
          orderedIds: [first, second],
        ),
        throwsFormatException,
      );
      expect((await db.manualServerGroupDao.allRows).map((row) => row.id), [
        second,
        first,
        third,
      ]);
    },
  );

  test(
    'moves and reorders preserve node identity and runtime-facing data',
    () async {
      final group = await service.create('AWS');
      final a = await node('A');
      final b = await node('B');
      final c = await node('C');
      await service.move({a.id, b.id}, targetGroupId: group);
      await service.reorderServers(
        groupId: group,
        expectedIds: [a.id, b.id],
        orderedIds: [b.id, a.id],
      );
      final movedA = (await db.coreConfigDao.searchRow(a.id))!;
      expect(movedA.manualGroupId, group);
      expect(movedA.manualSortOrder, 1);
      expect(
        movedA.copyWith(
          manualGroupId: const Value(null),
          manualSortOrder: a.manualSortOrder,
        ),
        a,
      );
      await service.move({c.id}, targetGroupId: group);
      expect((await db.coreConfigDao.searchRow(c.id))!.manualSortOrder, 2);
      // Moving an already present node is a no-op and cannot create tied ranks.
      await service.move({b.id, c.id}, targetGroupId: group);
      expect((await db.coreConfigDao.searchRow(b.id))!.manualSortOrder, 0);
      expect((await db.coreConfigDao.searchRow(c.id))!.manualSortOrder, 2);
    },
  );

  test(
    'additions append to ungrouped order and restore keeps explicit positions',
    () async {
      final a = await node('A');
      final b = await node('B');
      await service.reorderServers(
        groupId: null,
        expectedIds: [a.id, b.id],
        orderedIds: [b.id, a.id],
      );
      final c = await node('C');
      expect(c.manualGroupId, isNull);
      expect(c.manualSortOrder, 2);
      final restored = await db.coreConfigDao.insertRow(
        CoreConfigCompanion.insert(
          name: 'Restored',
          type: 'outbound',
          tags: '',
          delay: 1,
          subId: 0,
          manualGroupId: const Value(99),
          manualSortOrder: const Value(17),
        ),
      );
      expect((await db.coreConfigDao.searchRow(restored))!.manualGroupId, 99);
      expect((await db.coreConfigDao.searchRow(restored))!.manualSortOrder, 17);
    },
  );

  test(
    'dissolve appends members in their saved order and preserves the nodes',
    () async {
      final group = await service.create('AWS');
      final a = await node('A');
      final b = await node('B');
      final c = await node('C');
      await service.move({a.id, b.id}, targetGroupId: group);
      await service.reorderServers(
        groupId: group,
        expectedIds: [a.id, b.id],
        orderedIds: [b.id, a.id],
      );
      await service.dissolve(group);
      expect(await db.manualServerGroupDao.allRows, isEmpty);
      final rows = await db.coreConfigDao.allActiveServerRows();
      final sorted = [...rows]
        ..sort((a, b) => a.manualSortOrder.compareTo(b.manualSortOrder));
      expect(sorted.map((row) => row.id), [c.id, b.id, a.id]);
      expect(rows.every((row) => row.manualGroupId == null), isTrue);
      expect((await db.coreConfigDao.searchRow(a.id))!.data, a.data);
      final empty = await service.create('Empty');
      await service.dissolve(empty);
      expect(await db.manualServerGroupDao.allRows, isEmpty);
    },
  );

  test('reorder accepts latency and favorite updates but rejects changed membership', () async {
    final group = await service.create('AWS');
    final a = await node('A');
    final b = await node('B');
    await service.move({a.id, b.id}, targetGroupId: group);
    final currentA = (await db.coreConfigDao.searchRow(a.id))!;
    await db.coreConfigDao.updateRow(
      currentA.copyWith(delay: 15, favorite: false),
    );
    await service.reorderServers(
      groupId: group,
      expectedIds: [a.id, b.id],
      orderedIds: [b.id, a.id],
    );
    expect((await db.coreConfigDao.searchRow(a.id))!.delay, 15);
    expect((await db.coreConfigDao.searchRow(a.id))!.favorite, isFalse);
    await service.move({b.id});
    await expectLater(
      service.reorderServers(
        groupId: group,
        expectedIds: [a.id, b.id],
        orderedIds: [a.id, b.id],
      ),
      throwsFormatException,
    );
    expect((await db.coreConfigDao.searchRow(b.id))!.manualGroupId, isNull);
    await expectLater(
      service.reorderServers(
        groupId: null,
        expectedIds: [b.id],
        orderedIds: [b.id, b.id],
      ),
      throwsFormatException,
    );
  });

  test(
    'manual operations reject subscription/Raw members without partial writes',
    () async {
      final group = await service.create('AWS');
      final manual = await node('Manual');
      final provider = await node('Subscription', subId: 7);
      final raw = await node('Raw', type: 'raw');
      for (final invalid in [provider, raw]) {
        await expectLater(
          service.move({manual.id, invalid.id}, targetGroupId: group),
          throwsFormatException,
        );
        expect(await db.coreConfigDao.searchRow(manual.id), manual);
        expect(await db.coreConfigDao.searchRow(invalid.id), invalid);
      }
      await service.dissolve(group);
      await expectLater(
        service.move({manual.id}, targetGroupId: group),
        throwsFormatException,
      );
      expect(await db.coreConfigDao.searchRow(manual.id), manual);
    },
  );

  test('cleanup pause drains already admitted group writes before data replacement', () async {
    await db.manualServerGroupDao.allRows;
    final entered = Completer<void>();
    final release = Completer<void>();
    final blocked = db.transaction(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final admitted = service.create('Already admitted');
    var paused = false;
    final pause = ManualServerGroupService.pauseForDataClear().then(
      (_) => paused = true,
    );
    await expectLater(service.create('Too late'), throwsStateError);
    expect(paused, isFalse);
    release.complete();
    await blocked;
    await admitted;
    await pause;
    expect(paused, isTrue);
    expect(
      (await db.manualServerGroupDao.allRows).single.name,
      'Already admitted',
    );
  });

  test(
    'cleanup pause rejects all new organization writes until resumed',
    () async {
      await ManualServerGroupService.pauseForDataClear();
      await expectLater(service.create('Paused'), throwsStateError);
      ManualServerGroupService.resumeAfterDataClear();
      await service.create('Allowed');
      expect((await db.manualServerGroupDao.allRows).single.name, 'Allowed');
    },
  );
}
