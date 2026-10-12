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

  test('subscription mode switches server and outbound streams without rewriting caches', () async {
    final dao = database.coreConfigDao;
    final sourceId = await database.subscriptionDao.insertRow(
      _subscription('switching'),
    );
    final outboundId = await dao.insertRow(
      _config('outbound', subId: sourceId),
    );
    final completeId = await dao.insertRow(
      _config('Remnawave', subId: sourceId).copyWith(
        data: const Value('eyJvdXRib3VuZHMiOlt7fV0sInJvdXRpbmciOnt9fQ=='),
      ),
    );
    final rawId = await dao.insertRow(_config('raw'));
    final stored = {
      for (final row in await database.select(database.coreConfig).get())
        row.id: row.toJson(),
    };
    final servers = StreamIterator(dao.watchServers());
    final outbounds = StreamIterator(dao.watchOutbounds());
    final exists = StreamIterator(dao.watchHasOutbounds());
    addTearDown(servers.cancel);
    addTearDown(outbounds.cancel);
    addTearDown(exists.cancel);
    expect(await servers.moveNext(), isTrue);
    expect(servers.current.map((row) => row.id), [outboundId]);
    expect(await outbounds.moveNext(), isTrue);
    expect(outbounds.current.map((row) => row.id), [outboundId]);
    expect(await exists.moveNext(), isTrue);
    expect(exists.current, isTrue);

    final source = (await database.subscriptionDao.searchRow(sourceId))!;
    expect(
      await database.subscriptionDao.updateRow(
        source.copyWith(mode: 'providerManaged'),
      ),
      isTrue,
    );
    expect(
      await servers.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(servers.current.map((row) => row.id), [completeId]);
    expect(
      await outbounds.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(outbounds.current, isEmpty);
    expect(await exists.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(exists.current, isFalse);
    expect((await dao.allActiveServerRows()).map((row) => row.id), [
      completeId,
    ]);
    expect(await dao.allOutboundRowsWithDataBySubId(sourceId), isEmpty);

    expect(await database.subscriptionDao.updateRow(source), isTrue);
    expect(
      await servers.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(servers.current.map((row) => row.id), [outboundId]);
    expect(
      await outbounds.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(outbounds.current.map((row) => row.id), [outboundId]);
    expect(await exists.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(exists.current, isTrue);
    expect((await dao.allRawRowsWithData).single.id, rawId);
    expect({
      for (final row in await database.select(database.coreConfig).get())
        row.id: row.toJson(),
    }, stored);
  });

  test('active lookups keep manual and orphan nodes but require a provider source for complete rows', () async {
    final dao = database.coreConfigDao;
    final appSource = await database.subscriptionDao.insertRow(
      _subscription('app'),
    );
    final providerSource = await database.subscriptionDao.insertRow(
      _subscription('provider', mode: 'providerManaged'),
    );
    final appNode = await dao.insertRow(_config('outbound', subId: appSource));
    final hiddenComplete = await dao.insertRow(
      _config('Remnawave', subId: appSource),
    );
    final providerComplete = await dao.insertRow(
      _config('Remnawave', subId: providerSource),
    );
    final hiddenNode = await dao.insertRow(
      _config('outbound', subId: providerSource),
    );
    final manual = await dao.insertRow(_config('outbound'));
    final orphanNode = await dao.insertRow(_config('outbound', subId: 999));
    // Internal restore can contain orphan/legacy rows. Visibility does not
    // grant those complete configurations a missing provider identity.
    final orphanComplete = await dao.insertRow(
      _config('Remnawave', subId: 999),
    );
    final manualComplete = await dao.insertRow(_config('Remnawave'));
    final raw = await dao.insertRow(_config('raw', subId: providerSource));

    expect(
      (await dao.allActiveServerRows()).map((row) => row.id),
      unorderedEquals([appNode, providerComplete, manual, orphanNode]),
    );
    for (final id in [appNode, providerComplete, manual, orphanNode]) {
      expect((await dao.searchActiveServerRow(id))!.id, id);
    }
    for (final id in [
      hiddenComplete,
      hiddenNode,
      orphanComplete,
      manualComplete,
      raw,
      9999,
    ]) {
      expect(await dao.searchActiveServerRow(id), isNull);
    }
    for (final id in [appNode, manual, orphanNode]) {
      expect((await dao.searchActiveOutboundRow(id))!.id, id);
    }
    for (final id in [providerComplete, hiddenNode, hiddenComplete, raw]) {
      expect(await dao.searchActiveOutboundRow(id), isNull);
    }
    expect((await dao.searchRow(hiddenNode))!.id, hiddenNode);
    expect((await dao.searchRow(hiddenComplete))!.id, hiddenComplete);
  });

  test(
    'unmeasured candidates include only active ordinary rows with data',
    () async {
      final dao = database.coreConfigDao;
      final appSource = await database.subscriptionDao.insertRow(
        _subscription('measure-app'),
      );
      final providerSource = await database.subscriptionDao.insertRow(
        _subscription('measure-provider', mode: 'providerManaged'),
      );
      final appNode = await dao.insertRow(
        _config('outbound', subId: appSource),
      );
      final measured = await dao.insertRow(
        _config('outbound', subId: appSource).copyWith(delay: const Value(0)),
      );
      await dao.insertRow(_config('outbound', subId: providerSource));
      await dao.insertRow(_config('Remnawave', subId: providerSource));
      await dao.insertRow(_config('raw'));
      await dao.insertRow(
        _config('outbound').copyWith(data: const Value(null)),
      );
      final manual = await dao.insertRow(_config('outbound'));
      final orphan = await dao.insertRow(_config('outbound', subId: 999));
      expect(
        await dao.unmeasuredOutboundIds,
        unorderedEquals([appNode, manual, orphan]),
      );
      expect(await dao.allOutboundRowsWithDataBySubId(providerSource), isEmpty);
      expect(
        (await dao.allOutboundRowsWithDataBySubId(appSource))
            .map((row) => row.id),
        unorderedEquals([appNode, measured]),
      );
      final source = (await database.subscriptionDao.searchRow(appSource))!;
      await database.subscriptionDao.updateRow(
        source.copyWith(mode: 'providerManaged'),
      );
      expect(
        await dao.unmeasuredOutboundIds,
        unorderedEquals([manual, orphan]),
      );
      expect(await dao.allOutboundRowsWithDataBySubId(appSource), isEmpty);
    },
  );

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

SubscriptionCompanion _subscription(
  String name, {
  String mode = 'appManaged',
}) => SubscriptionCompanion.insert(
  name: name,
  url: 'https://example.test/$name',
  panel: const Value('generic'),
  mode: Value(mode),
  timestamp: DateTime(2026, 10, 12),
);
