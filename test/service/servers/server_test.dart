import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/connect/raw/editor.dart';
import 'package:onexray/service/connect/raw/db.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  Future<CoreConfigData> server({int subId = 0, bool favorite = false}) async {
    final id = await db.coreConfigDao.insertAssetRow(
      outboundCompanion({'tag': 'original', 'protocol': 'freedom'}).copyWith(
        subId: Value(subId),
        favorite: Value(favorite),
        delay: const Value(20),
      ),
    );
    return (await db.coreConfigDao.searchRow(id))!;
  }

  Future<ConnectionCoordinator> initialize(
    ConnectionCoordinator coordinator,
  ) async {
    addTearDown(coordinator.dispose);
    await coordinator.initialize(observe: false, registerReferences: false);
    return coordinator;
  }

  for (final change in ['entry', 'exit', 'unused', 'rename', 'live-unused']) {
    test(
      'offline or unrelated server edit does not reconnect: $change',
      () async {
        final entry = await server();
        final exit = await server();
        final unused = await server();
        final configuration = ConnectionConfiguration(
          connection: ConnectionSettings(
            selection: ServerSelection.server(entry.id),
            smart: SmartRoutingSettings(finalExitId: exit.id),
          ),
        );
        await db.connectionConfigDao.commit(
          configurationJson: configuration.encode(),
        );
        final live = _runtime('b', configuration, [
          ResolvedServer.fromRow(unused),
        ]);
        final coordinator = await initialize(
          ConnectionCoordinator(
            database: db,
            inspect: (_, {observedStatus}) async => change == 'live-unused'
                ? HostConnection(VpnStatus.connected, runtime: live)
                : const HostConnection(VpnStatus.disconnected),
            start: (_) async => throw StateError('Unexpected start'),
            stop: () async => throw StateError('Unexpected stop'),
          ),
        );
        final service = ServerAssetService(
          database: db,
          coordinator: coordinator,
          validate: (_) async => '',
          schedule: (_) {},
          prepare: (_, _, _, _) async =>
              throw StateError('Unexpected preparation'),
        );
        final row = change == 'exit'
            ? exit
            : change == 'unused'
            ? unused
            : entry;
        final draft = await service.load(row.id);
        final text = change == 'rename'
            ? draft.text.replaceFirst('original', 'renamed')
            : draft.text.replaceFirst('freedom', 'blackhole');
        expect(
          await service.save(
            ServerEditDraft(draft.original, text),
            confirmReconnect: () async =>
                throw StateError('Unexpected confirmation'),
          ),
          true,
        );
        final saved = (await db.coreConfigDao.searchRow(row.id))!;
        expect(
          saved.delay,
          change == 'rename' ? 20 : PingDelayConstants.unknown,
        );
        await service.favorite(row.id, true);
        expect((await db.coreConfigDao.searchRow(row.id))!.favorite, true);
        expect(
          coordinator.state.value.phase,
          change == 'live-unused'
              ? ConnectionPhase.connected
              : ConnectionPhase.disconnected,
        );
      },
    );
  }

  for (final removed in ['entry', 'exit', 'unused']) {
    test('offline deletion clears only affected settings: $removed', () async {
      final entry = await server();
      final exit = await server();
      final unused = await server();
      final configuration = ConnectionConfiguration(
        connection: ConnectionSettings(
          selection: ServerSelection.server(entry.id),
          smart: SmartRoutingSettings(finalExitId: exit.id),
        ),
      );
      await db.connectionConfigDao.commit(
        configurationJson: configuration.encode(),
      );
      final coordinator = await initialize(
        ConnectionCoordinator(
          database: db,
          inspect: (_, {observedStatus}) async =>
              const HostConnection(VpnStatus.disconnected),
          start: (_) async => throw StateError('Unexpected start'),
          stop: () async => throw StateError('Unexpected stop'),
        ),
      );
      final service = ServerAssetService(
        database: db,
        coordinator: coordinator,
        validate: (_) async => '',
        schedule: (_) {},
        prepare: (_, _, _, _) async =>
            throw StateError('Unexpected preparation'),
      );
      final row = removed == 'entry'
          ? entry
          : removed == 'exit'
          ? exit
          : unused;
      final preview = await service.previewRemoval(ids: {row.id});
      expect(preview.affectsRuntime, false);
      expect(preview.disconnect, false);
      await service.remove(preview);
      expect(await db.coreConfigDao.searchRow(row.id), isNull);
      final next = await coordinator.configuration;
      expect(
        next.connection.selection.kind,
        removed == 'entry' ? SelectionKind.automatic : SelectionKind.server,
      );
      expect(
        next.connection.smart.finalExitId,
        removed == 'exit' ? isNull : exit.id,
      );
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
    });
  }

  test(
    'favorite and local copy preserve source identity and do not start VPN',
    () async {
      final original = await server(subId: 7, favorite: true);
      final coordinator = await initialize(
        ConnectionCoordinator(
          database: db,
          inspect: (_, {observedStatus}) async =>
              const HostConnection(VpnStatus.disconnected),
          start: (_) async => throw StateError('Unexpected start'),
          stop: () async => throw StateError('Unexpected stop'),
        ),
      );
      final scheduled = <int>[];
      final service = ServerAssetService(
        database: db,
        coordinator: coordinator,
        schedule: scheduled.addAll,
        validate: (_) async => '',
      );
      final copyId = await service.copyLocal(original, 'Local copy');
      final copy = (await db.coreConfigDao.searchRow(copyId))!;
      expect(copy.subId, 0);
      expect(copy.favorite, false);
      expect(copy.delay, PingDelayConstants.unknown);
      expect(readOutboundFromDbData(copy)['tag'], 'original · Local copy');
      expect(scheduled, [copyId]);
      await service.favorite(original.id, false);
      final source = (await db.coreConfigDao.searchRow(original.id))!;
      expect(source.subId, 7);
      expect(source.data, original.data);
      expect(source.favorite, false);
    },
  );

  test('running rename is metadata-only; cancelled or failed semantic edit keeps original', () async {
    final row = await server(favorite: true);
    final configuration = ConnectionConfiguration(
      connection: ConnectionSettings(selection: ServerSelection.server(row.id)),
    );
    final old = _runtime('a', configuration, [ResolvedServer.fromRow(row)]);
    await db.connectionConfigDao.commit(
      configurationJson: configuration.encode(),
    );
    var host = HostConnection(VpnStatus.connected, runtime: old);
    final calls = <String>[];
    final coordinator = await initialize(
      ConnectionCoordinator(
        database: db,
        inspect: (_, {observedStatus}) async => host,
        start: (_) async {
          calls.add('start');
          throw const ConnectionHostException('startFailed');
        },
        stop: () async {
          calls.add('stop');
          return host = const HostConnection(VpnStatus.disconnected);
        },
      ),
    );
    final service = ServerAssetService(
      database: db,
      coordinator: coordinator,
      validate: (_) async => '',
      schedule: (_) {},
      prepare: (next, _, drafts, _) async =>
          _runtime('b', next, drafts.values.toList()),
    );
    final draft = await service.load(row.id);
    expect(
      await service.save(
        ServerEditDraft(row, draft.text.replaceFirst('original', 'renamed')),
        confirmReconnect: () async =>
            throw StateError('Metadata must not confirm'),
      ),
      true,
    );
    expect(calls, isEmpty);
    final renamed = await service.load(row.id);
    expect(renamed.original.name, 'renamed');
    expect(renamed.original.favorite, true);
    expect(renamed.original.delay, row.delay);
    final changed = ServerEditDraft(
      renamed.original,
      renamed.text.replaceFirst('freedom', 'blackhole'),
    );
    expect(
      await service.save(changed, confirmReconnect: () async => false),
      false,
    );
    expect(calls, isEmpty);
    await expectLater(
      service.save(changed, confirmReconnect: () async => true),
      throwsA(isA<ConnectionHostException>()),
    );
    expect(
      (await db.coreConfigDao.searchRow(row.id))!.data,
      renamed.original.data,
    );
    expect(calls, ['stop', 'start', 'stop']);
    expect(coordinator.state.value.phase, ConnectionPhase.failed);
    expect(coordinator.state.value.runtime, isNull);
  });

  test('deleting an inactive fixed/final node clears references without starting VPN', () async {
    final row = await server(favorite: true);
    final configuration = ConnectionConfiguration(
      connection: ConnectionSettings(
        expert: true,
        rawId: 99,
        selection: ServerSelection.server(row.id),
        smart: SmartRoutingSettings(finalExitId: row.id),
      ),
    );
    await db.connectionConfigDao.commit(
      configurationJson: configuration.encode(),
    );
    final coordinator = await initialize(
      ConnectionCoordinator(
        database: db,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
        start: (_) async => throw StateError('Unexpected start'),
        stop: () async => throw StateError('Unexpected stop'),
      ),
    );
    final service = ServerAssetService(
      database: db,
      coordinator: coordinator,
      validate: (_) async => '',
      schedule: (_) {},
    );
    final preview = await service.previewRemoval(ids: {row.id});
    expect(preview.affectsRuntime, false);
    await service.remove(preview);
    expect(await db.coreConfigDao.searchRow(row.id), isNull);
    final next = await coordinator.configuration;
    expect(next.connection.selection.kind, SelectionKind.automatic);
    expect(next.connection.smart.finalExitId, isNull);
    expect(next.connection.expert, true);
    expect(next.connection.rawId, 99);
  });

  test('complete profile favorites and deletion keep cache ownership and use the coordinator', () async {
    final sourceId = await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'Provider',
        url: 'https://example.com/full',
        timestamp: DateTime(2026),
        mode: const Value('providerManaged'),
      ),
    );
    final profileId = await db.coreConfigDao.insertRow(
      CoreConfigCompanion.insert(
        name: 'Full',
        type: 'Remnawave',
        tags: '',
        data: Value(
          base64Encode(
            utf8.encode(
              '{"remarks":"Full","outbounds":[{"protocol":"freedom"}]}',
            ),
          ),
        ),
        delay: PingDelayConstants.unknown,
        subId: sourceId,
      ),
    );
    final derived = await server(subId: sourceId);
    final configuration = ConnectionConfiguration(
      connection: ConnectionSettings(
        selection: ServerSelection.server(profileId),
      ),
    );
    await db.connectionConfigDao.commit(
      configurationJson: configuration.encode(),
    );
    final coordinator = await initialize(
      ConnectionCoordinator(
        database: db,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
        start: (_) async => throw StateError('No implicit start'),
        stop: () async => throw StateError('No implicit stop'),
      ),
    );
    final service = ServerAssetService(database: db, coordinator: coordinator);
    final original = (await db.coreConfigDao.searchRow(profileId))!;
    await service.favorite(profileId, true);
    expect((await db.coreConfigDao.searchRow(profileId))!.data, original.data);
    expect((await db.coreConfigDao.searchRow(profileId))!.favorite, isTrue);
    final preview = await service.previewRemoval(ids: {profileId});
    expect(
      preview.configuration.connection.selection.kind,
      SelectionKind.automatic,
    );
    expect(preview.affectsRuntime, isFalse);
    await service.remove(preview);
    expect(await db.coreConfigDao.searchRow(profileId), isNull);
    expect(await db.coreConfigDao.searchRow(derived.id), derived);
    expect(await db.subscriptionDao.searchRow(sourceId), isNotNull);
  });

  test('complete JSON views and Raw copies retain the provider graph and running selection', () async {
    final profile = await _provider(db);
    final configuration = ConnectionConfiguration(
      connection: ConnectionSettings(
        selection: ServerSelection.server(profile.id),
      ),
    );
    await db.connectionConfigDao.commit(
      configurationJson: configuration.encode(),
    );
    final runtime = _runtime(
      'provider',
      configuration,
      const [],
      profile: ResolvedProfile.fromRow(profile),
    );
    final coordinator = await initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => runtime,
        inspect: (_, {observedStatus}) async =>
            HostConnection(VpnStatus.connected, runtime: runtime),
        start: (_) async => throw StateError('Copying Raw must not start VPN'),
        stop: () async => throw StateError('Copying Raw must not stop VPN'),
      ),
    );
    var validations = 0;
    final service = ServerAssetService(
      database: db,
      coordinator: coordinator,
      validate: (text) async {
        validations++;
        final config = jsonDecode(text) as Map;
        expect((config['inbounds'] as List).first['tag'], 'tunIn');
        expect((config['inbounds'] as List).first['protocol'], 'socks');
        expect(
          config['routing']['balancers'],
          _providerConfig['routing']['balancers'],
        );
        return '';
      },
      schedule: (_) => throw StateError(
        'Complete configurations and Raw are not node probes',
      ),
    );
    final draft = await service.loadComplete(profile.id);
    expect(draft.text, utf8.decode(base64Decode(profile.data!)));
    expect(draft.original.name, 'Full profile');
    await expectLater(service.load(profile.id), throwsFormatException);
    await expectLater(
      service.save(draft, confirmReconnect: () async => false),
      throwsFormatException,
    );
    final rawId = await service.copyAsRaw(profile.id, name: 'Personal Raw');
    final raw = (await db.coreConfigDao.searchRow(rawId))!;
    final json = jsonDecode(XrayRawDb.readFromDbData(raw)) as Map;
    expect(raw.type, 'raw');
    expect(raw.subId, 0);
    expect(raw.name, 'Personal Raw');
    expect(json['name'], 'Personal Raw');
    expect(json['remarks'], _providerConfig['remarks']);
    expect((json['inbounds'] as List).first['protocol'], 'tun');
    expect((json['outbounds'] as List).take(2), _providerConfig['outbounds']);
    expect(
      json['routing']['balancers'],
      _providerConfig['routing']['balancers'],
    );
    expect((json['routing']['rules'] as List).last['inboundTag'], [
      'provider-socks',
      'tunIn',
    ]);
    expect(validations, 1);
    expect(await db.coreConfigDao.searchRow(profile.id), profile);
    expect((await coordinator.configuration).encode(), configuration.encode());
    expect(coordinator.state.value.runtime, same(runtime));
  });

  test('Raw copy uses the existing validation and three-item quota', () async {
    final profile = await _provider(db);
    final coordinator = await initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
      ),
    );
    var error = 'Core rejected provider';
    final service = ServerAssetService(
      database: db,
      coordinator: coordinator,
      validate: (_) async => error,
      schedule: (_) => throw StateError('Raw must not be measured'),
    );
    await expectLater(
      service.copyAsRaw(profile.id),
      throwsA(
        isA<AppFailure>().having((failure) => failure.cause, 'cause', error),
      ),
    );
    expect(await db.coreConfigDao.allRawRowsWithData, isEmpty);
    error = '';
    for (var index = 0; index < 3; index++) {
      await service.copyAsRaw(profile.id, name: 'Raw $index');
    }
    await expectLater(
      service.copyAsRaw(profile.id),
      throwsA(
        isA<RawEditorException>().having(
          (error) => error.reason,
          'reason',
          'limit',
        ),
      ),
    );
    expect(await db.coreConfigDao.allRawRowsWithData, hasLength(3));
    expect(await db.coreConfigDao.searchRow(profile.id), profile);
  });

  test('source removal clears both complete and derived favorites without orphaning configs', () async {
    final profile = await _provider(db);
    final derived = await server(subId: profile.subId, favorite: true);
    final manual = await server();
    final configuration = ConnectionConfiguration(
      connection: ConnectionSettings(
        selection: ServerSelection.server(profile.id),
      ),
    );
    await db.connectionConfigDao.commit(
      configurationJson: configuration.encode(),
    );
    final coordinator = await initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
      ),
    );
    final service = ServerAssetService(
      database: db,
      coordinator: coordinator,
      subscriptions: SubscriptionService.forTesting(
        database: db,
        schedulePing: (_) {},
      ),
    );
    await service.favorite(profile.id, true);
    final preview = await service.previewRemoval(sourceId: profile.subId);
    expect(preview.ids, {profile.id, derived.id});
    await service.remove(preview);
    expect(await db.subscriptionDao.searchRow(profile.subId), isNull);
    expect(await db.coreConfigDao.searchRow(profile.id), isNull);
    expect(await db.coreConfigDao.searchRow(derived.id), isNull);
    expect(await db.coreConfigDao.searchRow(manual.id), manual);
    expect(
      (await coordinator.configuration).connection.selection.kind,
      SelectionKind.automatic,
    );
  });

  test(
    'selection checks use the latest mode rather than a stale server view',
    () async {
      final profile = await _provider(db);
      final derived = await server(subId: profile.subId);
      await server();
      final service = ServerAssetService(database: db);
      await service.validateSelection(const ServerSelection.automatic());
      await service.validateSelection(const ServerSelection.source(0));
      await service.validateSelection(ServerSelection.server(profile.id));
      await expectLater(
        service.validateSelection(ServerSelection.source(profile.subId)),
        throwsFormatException,
      );
      await expectLater(
        service.validateSelection(ServerSelection.server(derived.id)),
        throwsFormatException,
      );
      final source = (await db.subscriptionDao.searchRow(profile.subId))!;
      await db.subscriptionDao.updateRow(source.copyWith(mode: 'appManaged'));
      await service.validateSelection(ServerSelection.server(derived.id));
      await service.validateSelection(ServerSelection.source(source.id));
      await expectLater(
        service.validateSelection(ServerSelection.server(profile.id)),
        throwsFormatException,
      );
      await db.subscriptionDao.deleteRow(source.id);
      await expectLater(
        service.validateSelection(ServerSelection.source(source.id)),
        throwsFormatException,
      );
      await expectLater(
        service.validateSelection(ServerSelection.server(profile.id)),
        throwsFormatException,
      );
    },
  );
}

ConnectionRuntime _runtime(
  String digit,
  ConnectionConfiguration configuration,
  List<ResolvedServer> entries, {
  ResolvedProfile? profile,
}) {
  final text = jsonEncode({
    if (profile != null)
      ...profile.config
    else
      'outbounds': entries.map((row) => row.outbound).toList(),
  });
  final invoke = LibXrayInvokeRequest(
    method: LibXrayMethod.runXray,
    payload: RunXrayRequest(text).toJson(),
  );
  return ConnectionRuntime.create(
    configuration: configuration,
    compiled: CompiledConnection(
      xrayJson: text,
      entries: entries,
      finalExit: null,
      nodeTags: {},
      profile: profile,
    ),
    platform: ConnectionPlatform.android,
    request: StartVpnRequest(
      configuration.policy.toTun(ConnectionPlatform.android),
      null,
      '18003',
      jsonEncode(invoke.toJson()),
    ),
  );
}

Future<CoreConfigData> _provider(AppDatabase db) async {
  final sourceId = await db.subscriptionDao.insertRow(
    SubscriptionCompanion.insert(
      name: 'Provider',
      url: 'https://example.com/provider',
      timestamp: DateTime(2026),
      mode: const Value('providerManaged'),
    ),
  );
  final id = await db.coreConfigDao.insertAssetRow(
    CoreConfigCompanion.insert(
      name: 'Full profile',
      type: 'Remnawave',
      tags: '',
      subId: sourceId,
      delay: PingDelayConstants.unknown,
      data: Value(base64Encode(utf8.encode(jsonEncode(_providerConfig)))),
    ),
  );
  return (await db.coreConfigDao.searchRow(id))!;
}

const _providerConfig = <String, dynamic>{
  'remarks': 'Provider name',
  'inbounds': [
    {
      'tag': 'provider-socks',
      'protocol': 'socks',
      'port': 1080,
      'sniffing': {
        'enabled': true,
        'destOverride': ['http', 'tls'],
        'routeOnly': true,
      },
    },
  ],
  'outbounds': [
    {
      'tag': 'proxy-a',
      'protocol': 'socks',
      'streamSettings': {
        'sockopt': {'dialerProxy': 'proxy-b'},
      },
    },
    {'tag': 'proxy-b', 'protocol': 'socks'},
  ],
  'dns': {
    'servers': ['1.1.1.1'],
  },
  'routing': {
    'domainStrategy': 'IPIfNonMatch',
    'balancers': [
      {
        'tag': 'provider',
        'selector': ['proxy-'],
        'strategy': {'type': 'roundRobin'},
      },
    ],
    'rules': [
      {
        'inboundTag': ['provider-socks'],
        'domain': ['domain:example.com'],
        'balancerTag': 'provider',
      },
    ],
  },
};
