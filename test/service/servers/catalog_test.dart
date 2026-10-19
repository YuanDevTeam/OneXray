import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/sort.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  final storage = InMemorySharedPreferencesAsync.empty();
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = storage);
  setUp(() async {
    await SharedPreferencesAsync().clear();
    final bus = AppEventBus();
    addTearDown(bus.close);
  });

  test('default order is stable across types and delay updates', () {
    final ordinary = _outbound(id: 8, delay: 0);
    final provider = _provider(id: 1);
    final slower = _outbound(id: 3, delay: 100);
    final rows = [ordinary, provider, slower];
    final catalog = ServerCatalog(servers: rows, sources: [_source()]);
    expect(catalog.servers.map((row) => row.id), [1, 3, 8]);
    expect(rows.map((row) => row.id), [8, 1, 3]);
    final updated = catalog.copyWith(
      servers: [
        ordinary.copyWith(delay: 200),
        provider,
        slower.copyWith(delay: 0),
      ],
    );
    expect(updated.servers.map((row) => row.id), [1, 3, 8]);
    expect(updated.servers.last.delay, 200);
    expect(catalog.servers.last.delay, 0);
  });

  test(
    'name order uses displayed names across types with stable same-name IDs',
    () {
      final catalog = ServerCatalog(
        servers: [
          _outbound(id: 8, name: 'Zulu'),
          _provider(id: 5, name: 'beta'),
          _outbound(id: 7, name: ' alpha ', databaseName: 'A metadata alias'),
          _outbound(id: 2, name: 'Alpha', databaseName: 'Zulu metadata alias'),
        ],
        sources: [_source()],
        sortOrder: ServerSortOrder.name,
      );
      expect(catalog.servers.map((row) => row.id), [2, 7, 5, 8]);
      final changed = catalog.copyWith(
        servers: catalog.servers
            .map((row) => row.copyWith(delay: row.id == 8 ? 0 : 500))
            .toList(),
      );
      expect(changed.sortOrder, ServerSortOrder.name);
      expect(changed.servers.map((row) => row.id), [2, 7, 5, 8]);
      expect(
        changed
            .copyWith(sortOrder: ServerSortOrder.defaultOrder)
            .servers
            .map((row) => row.id),
        [2, 5, 7, 8],
      );
    },
  );

  test('delay order places successful probes before untested, failed and complete configs', () {
    final catalog = ServerCatalog(
      servers: [
        _provider(id: 1, delay: 0),
        _outbound(id: 2, delay: PingDelayConstants.timeout),
        _outbound(id: 3),
        _outbound(id: 4, delay: 200),
        _outbound(id: 5, delay: PingDelayConstants.error),
        _outbound(id: 7, delay: 10),
        _outbound(id: 8, delay: 0),
      ],
      sources: [_source()],
      sortOrder: ServerSortOrder.delay,
    );
    expect(catalog.servers.map((row) => row.id), [8, 7, 4, 3, 2, 5, 1]);
  });

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

  test('a provider row with unreadable JSON remains unavailable', () {
    final provider = _provider().copyWith(
      data: Value(base64Encode(utf8.encode('{'))),
    );
    final catalog = ServerCatalog(servers: [provider], sources: [_source()]);
    expect(catalog.servers, [provider]);
    expect(catalog.display(provider).readable, isFalse);
    expect(catalog.selectable(provider), isFalse);
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

  test('catalog streams share persisted display order changes without rewriting nodes', () async {
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
    final slowId = await insert(_outbound(delay: 100, name: 'Z slow'));
    final firstId = await insert(_provider(subId: sourceId));
    final laterId = await insert(_provider(subId: sourceId));
    final fastId = await insert(_outbound(delay: 10, name: 'A fast'));
    final events = <ServerCatalog>[];
    final ready = Completer<void>();
    final subscription = ServerCatalog.watch(db).listen((catalog) {
      events.add(catalog);
      if (catalog.servers.length == 4 && !ready.isCompleted) ready.complete();
    });
    addTearDown(subscription.cancel);
    await ready.future;
    await Future<void>.delayed(Duration.zero);
    expect(events.last.servers.map((row) => row.id), [
      slowId,
      firstId,
      laterId,
      fastId,
    ]);
    final eventCount = events.length;
    AppEventBus.instance.updatePinging(true);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(eventCount));

    await AppEventBus.instance.setServerSort(ServerSortOrder.name);
    await Future<void>.delayed(Duration.zero);
    expect(events.last.sortOrder, ServerSortOrder.name);
    expect(events.last.servers.map((row) => row.id), [
      fastId,
      firstId,
      laterId,
      slowId,
    ]);
    final slow = (await db.coreConfigDao.searchRow(slowId))!;
    final updated = Completer<void>();
    final updates = ServerCatalog.watch(db).listen((catalog) {
      if (catalog.servers.any((row) => row.id == slowId && row.delay == 0) &&
          !updated.isCompleted) {
        updated.complete();
      }
    });
    addTearDown(updates.cancel);
    await db.coreConfigDao.updateRow(slow.copyWith(delay: 0));
    await updated.future;
    await Future<void>.delayed(Duration.zero);
    expect(events.last.servers.map((row) => row.id), [
      fastId,
      firstId,
      laterId,
      slowId,
    ]);

    await AppEventBus.instance.setServerSort(ServerSortOrder.delay);
    await Future<void>.delayed(Duration.zero);
    expect(events.last.servers.map((row) => row.id), [
      slowId,
      fastId,
      firstId,
      laterId,
    ]);
    expect(await PreferencesKey().readServerSort(), 'delay');
    expect((await db.select(db.coreConfig).get()).map((row) => row.id), [
      slowId,
      firstId,
      laterId,
      fastId,
    ]);
    expect((await db.coreConfigDao.searchRow(fastId))!.delay, 10);
  });
}

CoreConfigData _provider({
  int id = 2,
  String name = 'Provider metadata',
  int subId = 7,
  int delay = PingDelayConstants.unknown,
}) => CoreConfigData(
  id: id,
  name: name,
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
  int id = 1,
  String name = 'Ordinary',
  String? databaseName,
  int subId = 0,
  int delay = PingDelayConstants.unknown,
}) => CoreConfigData(
  id: id,
  name: databaseName ?? name,
  type: 'outbound',
  tags: '',
  delay: delay,
  subId: subId,
  favorite: false,
  data: base64Encode(
    utf8.encode(
      jsonEncode({
        'outbounds': [
          {'tag': name, 'protocol': 'socks'},
        ],
      }),
    ),
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
