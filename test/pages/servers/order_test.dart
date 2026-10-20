import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/pages/servers/order/controller.dart';
import 'package:onexray/service/servers/manual_groups.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';

void main() {
  late AppDatabase db;
  late ManualServerGroupService groups;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    groups = ManualServerGroupService(database: db);
  });
  tearDown(() => db.close());

  Future<int> add(String name) => db.coreConfigDao.insertAssetRow(
    outboundCompanion({'tag': name, 'protocol': 'socks'}),
  );

  Future<List<ManualOrderItem>> load() async {
    final rows = await db.coreConfigDao.allActiveServerRows();
    rows.sort((a, b) {
      final rank = a.manualSortOrder.compareTo(b.manualSortOrder);
      return rank == 0 ? a.id.compareTo(b.id) : rank;
    });
    return rows.map((row) => ManualOrderItem(row.id, row.name)).toList();
  }

  Future<ManualOrderController> draft() async => ManualOrderController(
    ManualOrderParams(
      title: 'Order',
      items: await load(),
      reload: load,
      save: (expected, ordered) => groups.reorderServers(
        groupId: null,
        expectedIds: expected,
        orderedIds: ordered,
      ),
    ),
  );

  test(
    'a draft can be discarded without writing any server position',
    () async {
      final first = await add('First');
      final second = await add('Second');
      final controller = await draft();
      controller.reorder(1, 0);
      expect(controller.state.items.map((item) => item.id), [second, first]);
      expect((await load()).map((item) => item.id), [first, second]);
      await controller.close();
      expect((await load()).map((item) => item.id), [first, second]);
    },
  );

  test(
    'saving a draft preserves concurrent favorite and delay changes',
    () async {
      final first = await add('First');
      final second = await add('Second');
      final controller = await draft();
      addTearDown(controller.close);
      controller.reorder(1, 0);
      final row = (await db.coreConfigDao.searchRow(first))!;
      await db.coreConfigDao.updateRow(row.copyWith(delay: 35, favorite: true));
      expect(controller.state.items.map((item) => item.id), [second, first]);
      expect(await controller.save(), isTrue);
      expect((await load()).map((item) => item.id), [second, first]);
      final saved = (await db.coreConfigDao.searchRow(first))!;
      expect(saved.delay, 35);
      expect(saved.favorite, isTrue);
    },
  );

  test(
    'changed membership rejects a stale draft and reload allows a fresh save',
    () async {
      final first = await add('First');
      final second = await add('Second');
      final controller = await draft();
      addTearDown(controller.close);
      controller.reorder(1, 0);
      final third = await add('Third');
      expect(await controller.save(), isFalse);
      expect(controller.state.failure, isA<FormatException>());
      expect((await load()).map((item) => item.id), [first, second, third]);
      await controller.reload();
      expect(controller.state.failure, isNull);
      expect(controller.state.items.map((item) => item.id), [
        first,
        second,
        third,
      ]);
      controller.reorder(2, 0);
      expect(await controller.save(), isTrue);
      expect((await load()).map((item) => item.id), [third, first, second]);
    },
  );
}
