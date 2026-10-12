import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/servers/server.dart';
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
}

ConnectionRuntime _runtime(
  String digit,
  ConnectionConfiguration configuration,
  List<ResolvedServer> entries,
) {
  final text = jsonEncode({
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
