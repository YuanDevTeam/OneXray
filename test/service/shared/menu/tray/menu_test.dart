import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/l10n/localizations/app_localizations_en.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/menu/tray/menu.dart';
import 'package:onexray/service/shared/menu/tray/service.dart';
import 'package:onexray/service/shared/menu/tray/entry.dart';

Iterable<TrayMenuEntry> _descendants(List<TrayMenuEntry> items) sync* {
  for (final item in items) {
    yield item;
    if (item.children != null) yield* _descendants(item.children!);
  }
}

TrayMenuEntry _item(List<TrayMenuEntry> items, String key) =>
    _descendants(items).singleWhere((item) => item.key == key);

CoreConfigCompanion _node(String name, {int source = 0, int delay = 10}) =>
    CoreConfigCompanion.insert(
      name: name,
      type: 'outbound',
      tags: '',
      data: Value(
        base64Encode(
          utf8.encode(
            jsonEncode({
              'outbounds': [
                {
                  'tag': name,
                  'protocol': 'socks',
                  'settings': {'address': '127.0.0.1', 'port': 1080},
                },
              ],
            }),
          ),
        ),
      ),
      delay: delay,
      subId: source,
    );

TrayMenuData _menuData(int count) {
  final ids = const [12, 3, 11, 4, 10, 5, 9, 6, 8, 7, 2, 1].take(count);
  final nodes = [
    for (final id in ids)
      CoreConfigData(
        manualSortOrder: 0,
        id: id,
        name: 'Node $id',
        type: 'outbound',
        tags: '',
        data: _node('Node $id').data.value,
        delay: 10,
        subId: id == 1 ? 0 : id,
        favorite: false,
      ),
  ];
  return TrayMenuData()
    ..catalog = ServerCatalog(
      servers: nodes,
      sources: [
        for (final id in ids)
          SubscriptionData(
            panel: 'generic',
            mode: 'appManaged',
            id: id,
            name: 'Source $id',
            url: 'https://example.com/$id',
            hwidEnabled: false,
            timestamp: DateTime(2026),
          ),
      ],
    )
    ..raws = [for (final node in nodes) node.copyWith(type: 'raw')]
    ..routes = [
      for (final id in ids)
        RoutingProfileData(
          id: id,
          name: 'Route $id',
          data: 'e30=',
          advanced: false,
        ),
    ]
    ..geodata = [
      for (final id in ids)
        GeoDataData(
          installed: true,
          id: id,
          name: 'File $id',
          type: 'domain',
          url: 'https://example.com/$id.dat',
          timestamp: DateTime(2026),
          categoryCount: 0,
          ruleCount: 0,
        ),
    ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppEventBus();
  final l = AppLocalizationsEn();
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  test('provider sources expose individual configurations and keep App traffic inactive', () async {
    final sourceId = await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'Provider source',
        url: 'https://example.com/provider',
        timestamp: DateTime(2026),
        mode: Value(SubscriptionMode.providerManaged.name),
      ),
    );
    final id = await db.coreConfigDao.insertAssetRow(
      _node('Provider profile', source: sourceId).copyWith(
        type: Value(CoreConfigType.Remnawave.name),
        delay: Value(PingDelayConstants.unknown),
        data: Value(
          base64Encode(
            utf8.encode('{"outbounds":[{"tag":"first","protocol":"freedom"}]}'),
          ),
        ),
      ),
    );
    final row = (await db.coreConfigDao.searchRow(id))!;
    final data = TrayMenuData()
      ..configuration = ConnectionSettings(
        selection: ServerSelection.server(id),
      )
      ..catalog = ServerCatalog(
        servers: await db.coreConfigDao.allActiveServerRows(),
        sources: await db.subscriptionDao.allRows,
      );
    final items = data.selectionItems(l, busy: false);
    expect(
      _descendants(items).where((item) => item.key == 'source:$sourceId'),
      isEmpty,
    );
    expect(_item(items, 'server:$id').checked, isTrue);
    expect(_item(items, 'server:$id').disabled, isFalse);
    expect(_item(items, 'traffic:smart').disabled, isTrue);
    expect(_item(items, 'traffic:allVpn').disabled, isTrue);
    final profile = ResolvedProfile.fromRow(row);
    final runtime = _providerRuntime(profile);
    for (final selection in [
      const ServerSelection.automatic(),
      ServerSelection.source(sourceId),
    ]) {
      data.configuration = ConnectionSettings(selection: selection);
      final automatic = data.selectionItems(
        l,
        busy: false,
        runningProfile: runtime.profile,
      );
      expect(
        _item(automatic, 'automatic').checked,
        selection.kind == SelectionKind.automatic,
      );
      expect(_item(automatic, 'traffic:smart').disabled, isTrue);
      expect(
        _descendants(automatic).where((item) => item.key == 'source:$sourceId'),
        isEmpty,
      );
      expect(data.configuration.selection.toJson(), selection.toJson());
    }
    await db.subscriptionDao.updateRow(
      (await db.subscriptionDao.searchRow(sourceId))!
          .copyWith(mode: SubscriptionMode.appManaged.name),
    );
    data.catalog = ServerCatalog(
      servers: await db.coreConfigDao.allActiveServerRows(),
      sources: await db.subscriptionDao.allRows,
    );
    final hidden = data.selectionItems(
      l,
      busy: false,
      runningProfile: runtime.profile,
    );
    expect(
      _descendants(hidden)
          .any((item) => item.label.contains('Provider profile')),
      isTrue,
    );
    expect(_item(hidden, 'traffic:allVpn').disabled, isTrue);
  });

  test(
    'tray revalidates provider modes, sources and traffic actions',
    () async {
      final sourceId = await db.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: 'Provider source',
          url: 'https://example.com/provider',
          timestamp: DateTime(2026),
          mode: Value(SubscriptionMode.providerManaged.name),
        ),
      );
      final id = await db.coreConfigDao.insertAssetRow(
        _node('Provider profile', source: sourceId).copyWith(
          type: Value(CoreConfigType.Remnawave.name),
          delay: Value(PingDelayConstants.unknown),
          data: Value(
            base64Encode(
              utf8.encode(
                '{"outbounds":[{"tag":"first","protocol":"freedom"}]}',
              ),
            ),
          ),
        ),
      );
      final row = (await db.coreConfigDao.searchRow(id))!;
      final configuration = ConnectionConfiguration(
        connection: ConnectionSettings(selection: ServerSelection.server(id)),
      );
      await db.connectionConfigDao.commit(
        configurationJson: configuration.encode(),
      );
      final coordinator = ConnectionCoordinator(database: db);
      addTearDown(coordinator.dispose);
      coordinator.state.value = ConnectionView(
        phase: ConnectionPhase.connected,
        runtime: _providerRuntime(ResolvedProfile.fromRow(row)),
      );
      final changes = <Map<String, dynamic>>[];
      final notices = <String>[];
      Future<void> Function()? recheck;
      final tray =
          TrayService.forTesting(
              database: db,
              coordinator: coordinator,
              connect: () async =>
                  fail('A selection must not directly connect'),
              notify: (message) async => notices.add(message),
              showMainWindow: () async =>
                  fail('Selection must not require a window'),
            )
            ..onConfigurationChange = (values, label, validate) async {
              await validate();
              recheck = validate;
              changes.add(values);
            };
      await tray.onMenuAction(TrayMenuEntry(key: 'server:$id'));
      expect(changes.single['selection'], {'kind': 'server', 'id': id});
      final recheckServer = recheck!;
      await tray.onMenuAction(TrayMenuEntry(key: 'source:$sourceId'));
      expect(changes.last['selection'], {'kind': 'source', 'id': sourceId});
      await tray.onMenuAction(TrayMenuEntry(key: 'traffic:allVpn'));
      await tray.onMenuAction(TrayMenuEntry(key: 'custom:100'));
      expect(changes, hasLength(2));
      expect(notices, isEmpty);
      await db.subscriptionDao.updateRow(
        (await db.subscriptionDao.searchRow(sourceId))!
            .copyWith(mode: SubscriptionMode.appManaged.name),
      );
      await expectLater(recheckServer(), throwsA(isA<AppFailure>()));
      await tray.onMenuAction(TrayMenuEntry(key: 'traffic:smart'));
      expect(
        changes,
        hasLength(2),
        reason:
            'The actual provider runtime remains active after a mode change.',
      );
      await db.subscriptionDao.deleteRow(sourceId);
      await tray.onMenuAction(TrayMenuEntry(key: 'source:$sourceId'));
      expect(changes, hasLength(2));
      expect(notices, isNotEmpty);
    },
  );

  for (final count in [0, 10, 12]) {
    test(
      'tray limits sorted servers and other data to ten choices ($count rows)',
      () {
        final data = _menuData(count);
        final expectedIds = count == 0
            ? <int>[]
            : [12, 3, 11, 4, 10, 5, 9, 6, 8, 7];
        final selections = data.selectionItems(l, busy: false);
        final updates = data.updateItems(l, {});
        for (final prefix in [
          'source:',
          'server:',
          'raw:',
          'custom:',
          'updateSubscription:',
          'updateGeodata:',
        ]) {
          final items = _descendants([...selections, ...updates])
              .where((item) => item.key?.startsWith(prefix) ?? false);
          expect(items.map((item) => item.key), [
            if (prefix == 'source:' && count == 12) 'source:0',
            for (final id
                in prefix == 'server:'
                    ? (count == 12
                            ? List<int>.generate(10, (index) => index + 1)
                            : [...expectedIds]
                        ..sort())
                    : expectedIds)
              '$prefix$id',
          ], reason: prefix);
        }
        expect(_item(selections, 'automatic').checked, isTrue);
        expect(_item(selections, 'traffic:smart').checked, isTrue);
        expect(_item(selections, 'traffic:allVpn').disabled, isFalse);
        expect(
          _item(updates, 'updateSubscriptions').label,
          l.prototypeUpdateAll,
        );
        expect(
          _item(updates, 'updateDefaultGeodata').label,
          l.prototypeDefaultRoutingData,
        );
        expect(updates.first.children, hasLength(expectedIds.length + 2));
        expect(updates.last.children, hasLength(expectedIds.length + 3));
        expect(data.catalog.servers, hasLength(count));
        expect(data.catalog.sources, hasLength(count));
        expect(data.raws, hasLength(count));
        expect(data.routes, hasLength(count));
        expect(data.geodata, hasLength(count));
      },
    );
  }

  test(
    'tray keeps selection, disabled and pending state within the data prefix',
    () {
      final data = _menuData(12);
      data.catalog = data.catalog.copyWith(
        servers: [
          data.catalog.servers.first.copyWith(delay: PingDelayConstants.error),
          ...data.catalog.servers.skip(1),
        ],
      );
      for (final configuration in [
        ConnectionSettings(selection: const ServerSelection.source(1)),
        ConnectionSettings(selection: const ServerSelection.server(12)),
        ConnectionSettings(expert: true, rawId: 1),
        ConnectionSettings(trafficMode: TrafficMode.custom, customId: 1),
      ]) {
        data.configuration = configuration;
        final items = data.selectionItems(l, busy: false);
        for (final prefix in ['source:', 'server:', 'raw:', 'custom:']) {
          final choices = _descendants(items)
              .where((item) => item.key?.startsWith(prefix) ?? false);
          final excludedId = prefix == 'server:' ? 12 : 1;
          expect(
            choices.any((item) => item.key == '$prefix$excludedId'),
            isFalse,
          );
          expect(choices.any((item) => item.checked == true), isFalse);
        }
        expect(data.configuration, same(configuration));
      }
      data.configuration = ConnectionSettings(
        selection: const ServerSelection.server(3),
      );
      final items = data.selectionItems(l, busy: false);
      expect(_item(items, 'server:3').checked, isTrue);
      expect(_item(items, 'server:3').disabled, isFalse);
      expect(_item(items, 'server:1').disabled, isTrue);
      expect(
        _descendants(data.selectionItems(l, busy: true))
            .every((item) => item.disabled),
        isTrue,
      );

      final updates = data.updateItems(l, {
        'updateSubscription:12',
        'updateGeodata:12',
      });
      expect(_item(updates, 'updateSubscription:12').disabled, isTrue);
      expect(
        _item(updates, 'updateSubscription:12').label,
        contains(l.prototypePleaseWait),
      );
      expect(_item(updates, 'updateSubscription:3').disabled, isFalse);
      expect(_item(updates, 'updateGeodata:12').disabled, isTrue);
      expect(_item(updates, 'updateGeodata:3').disabled, isFalse);
      expect(_item(updates, 'updateSubscriptions').disabled, isFalse);
      expect(_item(updates, 'updateGeodata').disabled, isFalse);
      expect(_item(updates, 'updateDefaultGeodata').disabled, isFalse);
    },
  );

  test(
    'tray streams retain legacy Raw rows beyond the displayed prefix',
    () async {
      for (var i = 0; i < 12; i++) {
        await db.coreConfigDao.insertRow(
          _node('Raw $i')
              .copyWith(type: const Value('raw'), data: const Value('e30=')),
        );
      }
      final data = await TrayMenuData.watch(db)
          .firstWhere((data) => data.raws.length == 12);
      final items = data.selectionItems(l, busy: false);
      expect(
        _descendants(items)
            .where((item) => item.key?.startsWith('raw:') ?? false)
            .map((item) => item.key),
        [for (var id = 1; id <= 10; id++) 'raw:$id'],
      );
      expect(data.raws, hasLength(12));
      expect(await db.coreConfigDao.allRawRowsWithData, hasLength(12));
    },
  );

  test('desktop choices retain legacy Raw rows, normal selection and grouped updates', () async {
    final source = await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'Source',
        url: 'https://example.com/sub',
        timestamp: DateTime.now(),
      ),
    );
    final local = await db.coreConfigDao.insertRow(_node('Local'));
    await db.coreConfigDao.insertRow(_node('Remote', source: source));
    for (var i = 1; i <= 4; i++) {
      await db.coreConfigDao.insertRow(
        CoreConfigCompanion.insert(
          name: 'Raw $i',
          type: 'raw',
          tags: '',
          delay: 0,
          subId: 0,
          data: Value(base64Encode(utf8.encode('{}'))),
        ),
      );
    }
    await db.routingProfileDao.insertRow(
      RoutingProfileCompanion.insert(
        name: 'Work',
        data: base64Encode(utf8.encode('{}')),
      ),
    );
    final data = TrayMenuData()
      ..catalog = ServerCatalog(
        servers: await db.coreConfigDao.watchOutbounds().first,
        sources: await db.subscriptionDao.allRows,
      )
      ..raws = await db.coreConfigDao.allRawRowsWithDataStream.first
      ..routes = await db.routingProfileDao.allRows
      ..configuration = ConnectionSettings(
        selection: ServerSelection.server(local),
      );
    var items = data.selectionItems(l, busy: false);
    expect(_item(items, 'server:$local').checked, isTrue);
    expect(_item(items, 'source:0').label, l.prototypeManualAdditions);
    expect(
      _descendants(items)
          .where((item) => item.key?.startsWith('raw:') ?? false),
      hasLength(4),
    );
    expect(items.last.disabled, isFalse);

    data.configuration = ConnectionSettings(
      expert: true,
      rawId: data.raws.last.id,
    );
    items = data.selectionItems(l, busy: false);
    expect(_item(items, 'server:$local').checked, isFalse);
    expect(_item(items, 'raw:${data.raws.last.id}').checked, isTrue);
    expect(items.last.disabled, isTrue);
    expect(items.first.disabled, isFalse);
    expect(
      data.selectionItems(l, busy: true).every((item) => item.disabled),
      isTrue,
    );

    final updates = data.updateItems(l, {'updateSubscriptions'});
    expect(_item(updates, 'updateSubscription:$source').disabled, isTrue);
    expect(_item(updates, 'updateGeodata').disabled, isFalse);
    expect(_item(updates, 'updateDefaultGeodata').disabled, isFalse);
    expect(
      _descendants(updates)
          .any((item) => item.key?.contains('geosite') ?? false),
      isFalse,
    );

    await db.coreConfigDao.deleteRow(
      (await db.coreConfigDao.searchRow(local))!,
    );
    data.catalog = ServerCatalog(
      servers: await db.coreConfigDao.watchOutbounds().first,
    );
    expect(
      _descendants(data.selectionItems(l, busy: false))
          .any((item) => item.key == 'source:0'),
      isFalse,
    );
  });

  test(
    'database changes keep stable tray order and update active configuration',
    () async {
      final snapshots =
          <({List<int> ids, String? firstName, bool expert, int? rawId})>[];
      final subscription = TrayMenuData.watch(db).listen((data) {
        snapshots.add((
          ids: data.catalog.servers.map((row) => row.id).toList(),
          firstName: data.catalog.servers.firstOrNull?.name,
          expert: data.configuration.expert,
          rawId: data.configuration.rawId,
        ));
      });
      addTearDown(subscription.cancel);
      final slow = await db.coreConfigDao.insertRow(_node('Slow', delay: 900));
      final fast = await db.coreConfigDao.insertRow(_node('Fast', delay: 50));
      await db.connectionConfigDao.commit(
        configurationJson: ConnectionConfiguration(
          connection: ConnectionSettings(expert: true, rawId: 99),
        ).encode(),
      );
      await pumpEventQueue();
      expect(snapshots.last.ids, [slow, fast]);
      expect(snapshots.last.firstName, 'Slow');
      expect((snapshots.last.expert, snapshots.last.rawId), (true, 99));
      await db.coreConfigDao.deleteRow(
        (await db.coreConfigDao.searchRow(fast))!,
      );
      await pumpEventQueue();
      expect(snapshots.last.ids, [slow]);
    },
  );

  test('tray dispatch shares configuration application and revalidates a deleted choice', () async {
    final id = await db.coreConfigDao.insertRow(_node('Local'));
    final notifications = <String>[];
    final choices = <Map<String, dynamic>>[];
    Future<void> Function()? validate;
    final tray =
        TrayService.forTesting(
            database: db,
            connect: () async => fail('Selection must not directly start VPN'),
            notify: (message) async => notifications.add(message),
            showMainWindow: () async =>
                fail('Disconnected selection needs no window'),
          )
          ..onConfigurationChange = (values, label, check) async {
            choices.add(values);
            validate = check;
            await check();
          };
    await tray.onMenuAction(TrayMenuEntry(key: 'server:$id'));
    expect(choices.single, {
      'expert': false,
      'selection': {'kind': 'server', 'id': id},
    });
    await db.coreConfigDao.deleteRow((await db.coreConfigDao.searchRow(id))!);
    await expectLater(
      validate!(),
      throwsA(isA<AppFailure>().having((e) => e.code, 'code', 'notFound')),
    );
    await tray.onMenuAction(TrayMenuEntry(key: 'server:$id'));
    expect(choices, hasLength(1));
    expect(notifications, hasLength(1));
    await tray.onMenuAction(TrayMenuEntry(key: 'traffic:allVpn'));
    expect(choices.last, {'expert': false, 'trafficMode': 'allVpn'});
    await tray.onMenuAction(TrayMenuEntry(key: 'region:JP', disabled: true));
    expect(choices, hasLength(2));
  });
}

ConnectionRuntime _providerRuntime(ResolvedProfile profile) {
  final configuration = ConnectionConfiguration(
    connection: ConnectionSettings(
      selection: ServerSelection.server(profile.id),
    ),
  );
  const json = '{}';
  return ConnectionRuntime.create(
    configuration: configuration,
    compiled: CompiledConnection(
      xrayJson: json,
      entries: const [],
      finalExit: null,
      nodeTags: const {},
      profile: profile,
    ),
    platform: ConnectionPlatform.android,
    request: StartVpnRequest(
      configuration.policy.toTun(ConnectionPlatform.android),
      null,
      '18003',
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(json).toJson(),
        ).toJson(),
      ),
    ),
  );
}
