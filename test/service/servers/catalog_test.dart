import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/servers/catalog.dart';

void main() {
  test('provider metadata is displayed without a delay or single-outbound projection', () {
    final row = _provider(delay: PingDelayConstants.timeout);
    final catalog = ServerCatalog(servers: [row], sources: [_source()]);
    final display = catalog.display(row);
    expect(display.type, 'Remnawave');
    expect(display.name, 'Provider metadata');
    expect(display.protocol, isEmpty);
    expect(display.readable, isTrue);
    expect(catalog.selectable(row), isTrue);
    expect(catalog.outboundEligible(row), isFalse);
  });

  test('failed ordinary nodes remain measurable and provider rows need an active source', () {
    final ordinary = _outbound(delay: PingDelayConstants.error);
    final provider = _provider();
    final catalog = ServerCatalog(servers: [ordinary, provider]);
    expect(catalog.servers, [ordinary]);
    expect(catalog.outboundEligible(ordinary), isTrue);
    expect(catalog.selectable(ordinary), isFalse);
    expect(catalog.selectable(provider), isFalse);
    final updated = catalog.copyWith(sources: [_source()]);
    expect(updated.servers, [ordinary, provider]);
    expect(updated.selectable(provider), isTrue);
    final appManaged = updated.copyWith(sources: [_source(mode: 'appManaged')]);
    expect(appManaged.servers, [ordinary]);
    expect(appManaged.selectable(provider), isFalse);
  });

  test(
    'catalog watches local source mode changes across both caches',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final sourceId = await db.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: 'Provider',
          url: 'https://example.com/sub',
          timestamp: DateTime(2026),
          mode: const Value('appManaged'),
        ),
      );
      final ordinaryId = await db.coreConfigDao.insertRow(
        _outbound(subId: sourceId)
            .toCompanion(false)
            .copyWith(id: const Value.absent()),
      );
      final providerId = await db.coreConfigDao.insertRow(
        _provider(subId: sourceId)
            .toCompanion(false)
            .copyWith(id: const Value.absent()),
      );
      final appManaged = await ServerCatalog.watch(db).firstWhere(
        (catalog) => catalog.servers.any((row) => row.id == ordinaryId),
      );
      expect(appManaged.servers.map((row) => row.id), [ordinaryId]);
      final source = (await db.subscriptionDao.searchRow(sourceId))!;
      await db.subscriptionDao.updateRow(
        source.copyWith(mode: 'providerManaged'),
      );
      final providerManaged = await ServerCatalog.watch(db).firstWhere(
        (catalog) => catalog.servers.any((row) => row.id == providerId),
      );
      expect(providerManaged.servers.map((row) => row.id), [providerId]);
      expect(
        providerManaged.selectable(providerManaged.servers.single),
        isTrue,
      );
      expect(
        providerManaged.outboundEligible(providerManaged.servers.single),
        isFalse,
      );
      expect(await db.select(db.coreConfig).get(), hasLength(2));
    },
  );

  test(
    'ordinary nodes retain delay ordering and provider graphs retain row order',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final sourceId = await db.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: 'Provider',
          url: 'https://example.com/sub',
          timestamp: DateTime(2026),
          mode: const Value('providerManaged'),
        ),
      );
      Future<int> insert(CoreConfigData row) => db.coreConfigDao.insertRow(
        row.toCompanion(false).copyWith(id: const Value.absent()),
      );
      final slowId = await insert(_outbound(delay: 100));
      final firstId = await insert(_provider(subId: sourceId));
      final laterId = await insert(_provider(subId: sourceId));
      final fastId = await insert(_outbound(delay: 10));
      final catalog = await ServerCatalog.watch(db)
          .firstWhere((value) => value.servers.length == 4);
      expect(catalog.servers.map((row) => row.id), [
        fastId,
        slowId,
        firstId,
        laterId,
      ]);
    },
  );
}

CoreConfigData _provider({
  int subId = 7,
  int delay = PingDelayConstants.unknown,
}) => CoreConfigData(
  id: 2,
  name: 'Provider metadata',
  type: 'Remnawave',
  tags: '',
  delay: delay,
  subId: subId,
  favorite: false,
  data: base64Encode(
    utf8.encode(
      jsonEncode({
        'remarks': 'JSON remarks',
        'outbounds': [
          {'tag': 'proxy-a', 'protocol': 'socks'},
          {'tag': 'proxy-b', 'protocol': 'socks'},
        ],
        'routing': {
          'balancers': [
            {
              'tag': 'provider',
              'selector': ['proxy-'],
            },
          ],
        },
      }),
    ),
  ),
);

CoreConfigData _outbound({
  int subId = 0,
  int delay = PingDelayConstants.unknown,
}) => CoreConfigData(
  id: 1,
  name: 'Ordinary',
  type: 'outbound',
  tags: '',
  delay: delay,
  subId: subId,
  favorite: false,
  data: base64Encode(
    utf8.encode('{"outbounds":[{"tag":"Ordinary","protocol":"socks"}]}'),
  ),
);

SubscriptionData _source({String mode = 'providerManaged'}) => SubscriptionData(
  id: 7,
  name: 'Provider',
  url: 'https://example.com/sub',
  panel: 'generic',
  mode: mode,
  hwidEnabled: false,
  timestamp: DateTime(2026),
);
