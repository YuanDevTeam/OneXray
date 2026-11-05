import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/ordinary_plan.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late int ordinary, source, provider, otherProvider;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    ordinary = await db.coreConfigDao.insertRow(
      _row('ordinary', 'outbound', 0),
    );
    source = await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'provider',
        url: 'https://example.com/provider',
        timestamp: DateTime(2026),
        mode: const Value('providerManaged'),
      ),
    );
    provider = await db.coreConfigDao.insertRow(
      _row('provider', 'Remnawave', source),
    );
    otherProvider = await db.coreConfigDao.insertRow(
      _row('other provider', 'Remnawave', source),
    );
  });

  test(
    'optional memory is compatible with old configuration and malformed hints',
    () {
      expect(
        ConnectionSettings.fromJson({}).rememberedOrdinarySelection,
        isNull,
      );
      for (final value in [
        null,
        'invalid',
        {'kind': 'server', 'id': '7'},
        {'kind': 'source', 'id': -1},
        {'kind': 'future'},
      ]) {
        expect(
          ConnectionSettings.fromJson({'rememberedOrdinarySelection': value})
              .rememberedOrdinarySelection,
          isNull,
        );
      }
      final original = ConnectionSettings(
        rememberedOrdinarySelection: const ServerSelection.source(0),
      );
      expect(
        ConnectionSettings.fromJson(original.toJson())
            .rememberedOrdinarySelection
            ?.toJson(),
        {'kind': 'source', 'id': 0},
      );
    },
  );

  test('provider switches capture ordinary intent once and returning is read-only until applied', () async {
    final coordinator = _coordinator(db);
    addTearDown(coordinator.dispose);
    await coordinator.initialize(observe: false, registerReferences: false);
    final original = ConnectionConfiguration(
      connection: ConnectionSettings(
        selection: ServerSelection.server(ordinary),
        trafficMode: TrafficMode.allVpn,
      ),
    );
    await db.connectionConfigDao.commit(configurationJson: original.encode());
    Future<void> choose(int id) async {
      final current = await coordinator.configuration;
      await coordinator.apply(
        ConnectionConfiguration(
          connection: ConnectionSettings.fromJson({
            ...current.connection.toJson(),
            'selection': ServerSelection.server(id).toJson(),
          }),
          policy: current.policy,
        ),
      );
    }

    await choose(provider);
    expect(
      (await coordinator.configuration)
          .connection
          .rememberedOrdinarySelection
          ?.id,
      ordinary,
    );
    await choose(otherProvider);
    final stored = await coordinator.configuration;
    expect(stored.connection.rememberedOrdinarySelection?.id, ordinary);
    final restored = await coordinator.restoreOrdinaryPlan();
    expect(restored.requiresSelection, isFalse);
    expect(restored.configuration.connection.selection.id, ordinary);
    expect(restored.configuration.connection.trafficMode, TrafficMode.allVpn);
    expect((await coordinator.configuration).encode(), stored.encode());
    await coordinator.apply(restored.configuration);
    expect((await coordinator.configuration).connection.selection.id, ordinary);
  });

  test('failed prepare or asset commit never saves a provider intent or its new memory', () async {
    final coordinator = _coordinator(db);
    addTearDown(coordinator.dispose);
    await coordinator.initialize(observe: false, registerReferences: false);
    final original = ConnectionConfiguration(
      connection: ConnectionSettings(
        selection: ServerSelection.server(ordinary),
      ),
    );
    await db.connectionConfigDao.commit(configurationJson: original.encode());
    final next = ConnectionConfiguration(
      connection: ConnectionSettings(
        selection: ServerSelection.server(provider),
      ),
    );
    await expectLater(
      coordinator.apply(next, connect: true),
      throwsFormatException,
    );
    expect((await coordinator.configuration).encode(), original.encode());
    await expectLater(
      coordinator.apply(
        next,
        writeAssets: () async {
          throw StateError('write');
        },
      ),
      throwsStateError,
    );
    expect((await coordinator.configuration).encode(), original.encode());
    await coordinator.apply(next);
    expect(
      (await coordinator.configuration)
          .connection
          .rememberedOrdinarySelection
          ?.id,
      ordinary,
    );
  });

  test(
    'Raw retains its ordinary selection and existing provider memory',
    () async {
      final service = OrdinaryPlanService(db);
      final normal = ConnectionConfiguration(
        connection: ConnectionSettings(
          selection: ServerSelection.server(ordinary),
        ),
      );
      final raw = await service.retain(
        normal,
        ConnectionConfiguration(
          connection: ConnectionSettings(
            expert: true,
            rawId: 99,
            selection: normal.connection.selection,
          ),
        ),
      );
      final restored = await service.restore(raw);
      expect(restored.requiresSelection, isFalse);
      expect(restored.configuration.connection.expert, isFalse);
      expect(restored.configuration.connection.selection.id, ordinary);
      final providerPlan = await service.retain(
        raw,
        ConnectionConfiguration(
          connection: ConnectionSettings(
            selection: ServerSelection.server(provider),
          ),
        ),
      );
      final providerRaw = await service.retain(
        providerPlan,
        ConnectionConfiguration(
          connection: ConnectionSettings(
            expert: true,
            rawId: 99,
            selection: ServerSelection.server(provider),
          ),
        ),
      );
      expect(
        (await service.restore(providerRaw))
            .configuration
            .connection
            .selection
            .id,
        ordinary,
      );
    },
  );

  test('legacy providers and stale or incompatible memory return automatic with reselect state', () async {
    final service = OrdinaryPlanService(db);
    for (final remembered in [
      null,
      const ServerSelection.server(999),
      const ServerSelection.source(999),
      ServerSelection.source(source),
      ServerSelection.server(provider),
    ]) {
      final result = await service.restore(
        ConnectionConfiguration(
          connection: ConnectionSettings(
            selection: ServerSelection.server(provider),
            rememberedOrdinarySelection: remembered,
          ),
        ),
      );
      expect(result.requiresSelection, isTrue);
      expect(
        result.configuration.connection.selection.kind,
        SelectionKind.automatic,
      );
      expect(
        result.configuration.connection.rememberedOrdinarySelection,
        isNull,
      );
    }
    final manual = await service.restore(
      ConnectionConfiguration(
        connection: ConnectionSettings(
          selection: ServerSelection.server(provider),
          rememberedOrdinarySelection: const ServerSelection.source(0),
        ),
      ),
    );
    expect(manual.requiresSelection, isFalse);
    expect(manual.configuration.connection.selection.toJson(), {
      'kind': 'source',
      'id': 0,
    });
    await db.connectionConfigDao.commit(
      configurationJson: manual.configuration.encode(),
    );
    await db.connectionConfigDao.reset();
    final fresh = ConnectionConfiguration.fromJson(
      jsonDecode((await db.connectionConfigDao.read()).configurationJson)
          as Map<String, dynamic>,
    );
    expect(fresh.connection.rememberedOrdinarySelection, isNull);
  });
}

ConnectionCoordinator _coordinator(AppDatabase db) => ConnectionCoordinator(
  database: db,
  readRuntime: () async => null,
  inspect: (_, {observedStatus}) async =>
      const HostConnection(VpnStatus.disconnected),
  prepare: (_, _) async => throw const FormatException('prepare failed'),
  start: (_) async => throw StateError('must not start'),
  stop: () async => const HostConnection(VpnStatus.disconnected),
  disposeStatus: () {},
);

CoreConfigCompanion _row(String name, String type, int source) =>
    CoreConfigCompanion.insert(
      name: name,
      type: type,
      tags: '',
      delay: 10000,
      subId: source,
      data: Value(
        base64Encode(
          utf8.encode('{"outbounds":[{"tag":"proxy","protocol":"freedom"}]}'),
        ),
      ),
    );
