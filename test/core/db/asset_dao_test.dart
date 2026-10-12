import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
  });

  test('asset lists separate Raw, outbound and retired rows', () async {
    final dao = database.coreConfigDao;
    for (final type in ['setting', 'full']) {
      await dao.insertRow(_config(type));
    }
    final rawId = await dao.insertRow(_config('raw', subId: 7));
    await dao.insertRow(_config('outbound'));

    expect((await dao.allRawRowsWithData).single.id, rawId);
    expect((await dao.allRawRowsWithDataStream.first).single.id, rawId);
    expect((await dao.searchRow(1))!.type, 'setting');
    expect((await dao.searchRow(rawId))!.type, 'raw');
    expect(await dao.allOutboundRowsWithDataBySubId(0), hasLength(1));
  });

  test(
    'outbound UI stream follows inserts, probe ordering and deletions',
    () async {
      final dao = database.coreConfigDao;
      final rows = StreamIterator(dao.watchOutbounds());
      addTearDown(rows.cancel);
      await rows.moveNext();
      expect(rows.current, isEmpty);
      await database.transaction(() async {
        await dao.insertRow(_config('raw'));
        await dao.insertRow(_config('setting'));
        for (final delay in [300, 10, 100]) {
          await dao.insertRow(
            _config('outbound').copyWith(delay: Value(delay)),
          );
        }
      });
      await rows.moveNext();
      expect(rows.current.map((row) => row.delay), [10, 100, 300]);
      final slow = rows.current.last;
      await dao.updateRow(slow.copyWith(delay: 0, favorite: true));
      await rows.moveNext();
      expect(rows.current.map((row) => row.delay), [0, 10, 100]);
      expect(rows.current.first.id, slow.id);
      expect(rows.current.first.favorite, isTrue);
      await dao.deleteRow(slow);
      await rows.moveNext();
      expect(rows.current.map((row) => row.delay), [10, 100]);
    },
  );

  test('node existence stream ignores Raw and missing data', () async {
    final dao = database.coreConfigDao;
    await dao.insertRow(_config('raw'));
    await dao.insertRow(_config('outbound').copyWith(data: const Value(null)));
    final exists = StreamIterator(dao.watchHasOutbounds());
    addTearDown(exists.cancel);
    await exists.moveNext();
    expect(exists.current, isFalse);
    final id = await dao.insertRow(_config('outbound'));
    await exists.moveNext();
    expect(exists.current, isTrue);
    await dao.deleteRow((await dao.searchRow(id))!);
    await exists.moveNext();
    expect(exists.current, isFalse);
  });

  test(
    'Raw additions enforce 0/2/3 limits atomically across mixed batches',
    () async {
      final dao = database.coreConfigDao;
      expect(await dao.allRawRowsWithData, isEmpty);
      expect(await dao.insertAssetRows([_config('raw'), _config('raw')]), 2);
      await expectLater(
        dao.insertAssetRows([
          _config('outbound'),
          _config('raw'),
          _config('raw'),
        ]),
        throwsStateError,
      );
      expect(await dao.allRawRowsWithData, hasLength(2));
      expect(await dao.allOutboundRowsWithDataBySubId(0), isEmpty);

      await dao.insertAssetRow(_config('raw'));
      await expectLater(dao.insertAssetRow(_config('raw')), throwsStateError);
      expect(await dao.allRawRowsWithData, hasLength(3));
    },
  );

  test(
    'restored excess Raw stays editable and deletable until additions fit',
    () async {
      final dao = database.coreConfigDao;
      await dao.insertRows(List.generate(4, (_) => _config('raw')));
      final restored = await dao.allRawRowsWithData;
      expect(restored, hasLength(4));
      await expectLater(dao.insertAssetRow(_config('raw')), throwsStateError);
      expect(
        await dao.updateRow(
          restored.first.copyWith(
            name: 'Edited',
            data: const Value('ZWRpdA=='),
          ),
        ),
        isTrue,
      );
      expect((await dao.searchRow(restored.first.id))!.data, 'ZWRpdA==');
      await dao.deleteRow(restored[3]);
      await dao.deleteRow(restored[2]);
      expect(await dao.allRawRowsWithData, hasLength(2));
      await dao.insertAssetRow(_config('raw'));
      expect(await dao.allRawRowsWithData, hasLength(3));
    },
  );

  test(
    'subscription configurations do not consume the manual Raw quota',
    () async {
      final dao = database.coreConfigDao;
      await dao.insertAssetRows(List.generate(3, (_) => _config('raw')));
      expect(
        await dao.insertAssetRows(
          List.generate(5, (_) => _config('Remnawave', subId: 7)),
        ),
        5,
      );
      expect(await dao.allRawRowsWithData, hasLength(3));
      final provider = (await database.select(database.coreConfig).get())
          .firstWhere((row) => row.type == 'Remnawave');
      expect(await dao.updateRow(provider.copyWith(favorite: true)), isTrue);
      expect((await dao.searchRow(provider.id))!.favorite, isTrue);
      await expectLater(dao.insertAssetRow(_config('raw')), throwsStateError);
      await expectLater(
        dao.insertAssetRow(_config('Remnawave')),
        throwsArgumentError,
      );
      await expectLater(
        dao.insertAssetRow(_config('full', subId: 7)),
        throwsArgumentError,
      );
    },
  );

  test(
    'custom routing enforces three profiles without limiting edits',
    () async {
      final dao = database.routingProfileDao;
      for (var index = 0; index < 2; index++) {
        await dao.insertRow(_routingProfile('Profile $index'));
      }
      final additions = await Future.wait([
        for (final name in ['Third', 'Fourth'])
          dao
              .insertRow(_routingProfile(name))
              .then(
                (_) => true,
                onError: (Object error, StackTrace stackTrace) {
                  expect(error, isStateError);
                  return false;
                },
              ),
      ]);
      expect(additions.where((added) => added), hasLength(1));
      final profiles = await dao.allRows;
      expect(profiles, hasLength(3));
      expect(profiles.first.data, 'eyJvdXRib3VuZHMiOlt7fV19');
      expect(
        await dao.updateRow(profiles.first.copyWith(name: 'Edited')),
        isTrue,
      );
      expect((await dao.searchRow(profiles.first.id))!.name, 'Edited');
      await dao.deleteRow(profiles.last.id);
      await dao.insertRow(_routingProfile('Replacement'));
      expect(await dao.allRowsStream.first, hasLength(3));
      expect(await dao.clear(), 3);
      expect(await dao.allRows, isEmpty);
    },
  );
}

CoreConfigCompanion _config(String type, {int subId = 0}) =>
    CoreConfigCompanion.insert(
      name: '$type config',
      type: type,
      tags: 'test-tags',
      data: const Value('eyJ0YWciOiJ0ZXN0In0='),
      delay: PingDelayConstants.unknown,
      subId: subId,
    );

RoutingProfileCompanion _routingProfile(String name) =>
    RoutingProfileCompanion.insert(
      name: name,
      data: 'eyJvdXRib3VuZHMiOlt7fV19',
    );
