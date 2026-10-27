import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:onexray/service/servers/manual_groups.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/reader.dart';
import 'package:onexray/service/connect/raw/editor.dart';
import 'package:onexray/service/connect/raw/db.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
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

  ConnectionCoordinator selectionCoordinator() {
    final coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => null,
      inspect: (_, {observedStatus}) async =>
          const HostConnection(VpnStatus.disconnected),
      start: (_) async => throw StateError('No implicit start'),
      stop: () async => throw StateError('No implicit stop'),
      disposeStatus: () {},
    );
    addTearDown(coordinator.dispose);
    return coordinator;
  }

  test('manual group deletion removes only confirmed members and clears fixed references', () async {
    final groups = ManualServerGroupService(database: db);
    final group = await groups.create('AWS');
    final selected = await server();
    final ungrouped = await server();
    final subscriptionNode = await server(subId: 7);
    await groups.move({selected.id}, targetGroupId: group);
    final configuration = ConnectionConfiguration(
      connection: ConnectionSettings(
        selection: ServerSelection.server(selected.id),
        smart: SmartRoutingSettings(finalExitId: selected.id),
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
        start: (_) async => throw StateError('No implicit start'),
        stop: () async => throw StateError('No implicit stop'),
      ),
    );
    final service = ServerAssetService(database: db, coordinator: coordinator);
    final preview = await service.previewRemoval(manualGroupId: group);
    expect(preview.ids, {selected.id});
    expect(preview.sourceId, isNull);
    expect(preview.affectsRuntime, isFalse);
    await service.remove(preview);
    expect(await db.manualServerGroupDao.searchRow(group), isNull);
    expect(await db.coreConfigDao.searchRow(selected.id), isNull);
    expect(await db.coreConfigDao.searchRow(ungrouped.id), ungrouped);
    expect(
      await db.coreConfigDao.searchRow(subscriptionNode.id),
      subscriptionNode,
    );
    expect(
      (await coordinator.configuration).connection.selection.kind,
      SelectionKind.automatic,
    );
    expect(
      (await coordinator.configuration).connection.smart.finalExitId,
      isNull,
    );
  });

  test('moving a running node keeps its session, deleting its last group disconnects', () async {
    final groups = ManualServerGroupService(database: db);
    final group = await groups.create('AWS');
    final selected = await server();
    final configuration = ConnectionConfiguration(
      connection: ConnectionSettings(
        selection: ServerSelection.server(selected.id),
      ),
    );
    await db.connectionConfigDao.commit(
      configurationJson: configuration.encode(),
    );
    final runtime = _runtime('group-session', configuration, [
      ResolvedServer.fromRow(selected),
    ]);
    var host = HostConnection(VpnStatus.connected, runtime: runtime);
    var stopped = 0;
    final coordinator = await initialize(
      ConnectionCoordinator(
        database: db,
        readRuntime: () async => host.runtime,
        inspect: (_, {observedStatus}) async => host,
        start: (_) async => throw StateError('No remaining candidate to start'),
        stop: () async {
          stopped++;
          return host = const HostConnection(VpnStatus.disconnected);
        },
      ),
    );
    final service = ServerAssetService(database: db, coordinator: coordinator);
    await groups.move({selected.id}, targetGroupId: group);
    await groups.reorderServers(
      groupId: group,
      expectedIds: [selected.id],
      orderedIds: [selected.id],
    );
    expect(stopped, 0);
    expect(coordinator.state.value.runtime, same(runtime));
    expect((await coordinator.configuration).encode(), configuration.encode());
    final preview = await service.previewRemoval(manualGroupId: group);
    expect(preview.affectsRuntime, isTrue);
    expect(preview.disconnect, isTrue);
    await service.remove(preview);
    expect(stopped, 1);
    expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
    expect(await db.manualServerGroupDao.searchRow(group), isNull);
    expect(await db.coreConfigDao.searchRow(selected.id), isNull);
  });

  test(
    'manual group deletion rejects a member added after confirmation',
    () async {
      final groups = ManualServerGroupService(database: db);
      final group = await groups.create('AWS');
      final a = await server();
      final b = await server();
      await groups.move({a.id}, targetGroupId: group);
      final coordinator = selectionCoordinator();
      await coordinator.initialize(observe: false, registerReferences: false);
      final service = ServerAssetService(
        database: db,
        coordinator: coordinator,
      );
      final preview = await service.previewRemoval(manualGroupId: group);
      await groups.move({b.id}, targetGroupId: group);
      await expectLater(service.remove(preview), throwsFormatException);
      expect(await db.manualServerGroupDao.searchRow(group), isNotNull);
      expect(await db.coreConfigDao.searchRow(a.id), isNotNull);
      expect(await db.coreConfigDao.searchRow(b.id), isNotNull);
    },
  );

  test(
    'empty manual groups can be deleted without touching ungrouped nodes',
    () async {
      final groups = ManualServerGroupService(database: db);
      final group = await groups.create('Empty');
      final retained = await server();
      final coordinator = selectionCoordinator();
      await coordinator.initialize(observe: false, registerReferences: false);
      final service = ServerAssetService(
        database: db,
        coordinator: coordinator,
      );
      final preview = await service.previewRemoval(manualGroupId: group);
      expect(preview.ids, isEmpty);
      await service.remove(preview);
      expect(await db.manualServerGroupDao.searchRow(group), isNull);
      expect(await db.coreConfigDao.searchRow(retained.id), retained);
    },
  );

  test(
    'editing a stale content draft preserves a concurrent move and measurement',
    () async {
      final groups = ManualServerGroupService(database: db);
      final group = await groups.create('AWS');
      final selected = await server();
      final coordinator = selectionCoordinator();
      await coordinator.initialize(observe: false, registerReferences: false);
      final service = ServerAssetService(
        database: db,
        coordinator: coordinator,
        validate: (_) async => '',
        schedule: (_) {},
      );
      final draft = await service.load(selected.id);
      await groups.move({selected.id}, targetGroupId: group);
      final moved = (await db.coreConfigDao.searchRow(selected.id))!;
      await db.coreConfigDao.updateRow(
        moved.copyWith(delay: 5, favorite: true),
      );
      expect(
        await service.save(
          ServerEditDraft(
            draft.original,
            draft.text.replaceFirst('original', 'renamed'),
          ),
          confirmReconnect: () async => throw StateError('No semantic change'),
        ),
        isTrue,
      );
      final saved = (await db.coreConfigDao.searchRow(selected.id))!;
      expect(saved.name, 'renamed');
      expect(saved.manualGroupId, group);
      expect(saved.manualSortOrder, moved.manualSortOrder);
      expect(saved.delay, 5);
      expect(saved.favorite, isTrue);
    },
  );

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

  for (final mode in SubscriptionMode.values) {
    for (final count in [1, 2]) {
      test(
        'source selection follows the remaining active $mode pool: $count',
        () async {
          final profile = await _provider(db, mode: mode);
          final ordinary = await server(subId: profile.subId);
          final active = [
            mode == SubscriptionMode.appManaged ? ordinary : profile,
          ];
          if (count == 2) {
            final id = await db.coreConfigDao.insertAssetRow(
              active.first
                  .toCompanion(false)
                  .copyWith(id: const Value.absent()),
            );
            active.add((await db.coreConfigDao.searchRow(id))!);
          }
          final inactive = mode == SubscriptionMode.appManaged
              ? profile
              : ordinary;
          final configuration = ConnectionConfiguration(
            connection: ConnectionSettings(
              selection: ServerSelection.source(profile.subId),
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
              start: (_) async => throw StateError('No implicit start'),
              stop: () async => throw StateError('No implicit stop'),
            ),
          );
          final service = ServerAssetService(
            database: db,
            coordinator: coordinator,
          );
          expect(
            (await db.coreConfigDao.allActiveServerRows()).map((row) => row.id),
            active.map((row) => row.id),
          );
          final preview = await service.previewRemoval(ids: {active.first.id});
          final expected = count == 1
              ? const ServerSelection.automatic()
              : ServerSelection.source(profile.subId);
          expect(
            preview.configuration.connection.selection.toJson(),
            expected.toJson(),
          );
          expect(preview.affectsRuntime, isFalse);
          expect(preview.disconnect, isFalse);
          await service.remove(preview);
          expect(
            (await coordinator.configuration).connection.selection.toJson(),
            expected.toJson(),
          );
          expect(await db.coreConfigDao.searchRow(active.first.id), isNull);
          expect(await db.coreConfigDao.searchRow(inactive.id), inactive);
          expect(await db.subscriptionDao.searchRow(profile.subId), isNotNull);
          if (count == 2) {
            expect(
              await db.coreConfigDao.searchRow(active.last.id),
              active.last,
            );
          }
        },
      );
    }
  }

  for (final removeProvider in [false, true]) {
    test(
      'deleting a running ${removeProvider ? 'provider' : 'ordinary node'} reconnects to an available provider',
      () async {
        final removed = removeProvider ? await _provider(db) : await server();
        final remaining = await _provider(db);
        final configuration = ConnectionConfiguration();
        final old = _runtime(
          'a',
          configuration,
          removeProvider ? [] : [ResolvedServer.fromRow(removed)],
          profile: removeProvider ? ResolvedProfile.fromRow(removed) : null,
        );
        final replacement = _runtime(
          'b',
          configuration,
          [],
          profile: ResolvedProfile.fromRow(remaining),
        );
        await db.connectionConfigDao.commit(
          configurationJson: configuration.encode(),
        );
        var host = HostConnection(VpnStatus.connected, runtime: old);
        final calls = <String>[];
        final coordinator = await initialize(
          ConnectionCoordinator(
            database: db,
            readRuntime: () async => old,
            inspect: (_, {observedStatus}) async => host,
            start: (runtime) async {
              calls.add('start');
              return host = HostConnection(
                VpnStatus.connected,
                runtime: runtime,
              );
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
          prepare: (next, _, _, excluded) async {
            expect(excluded, {removed.id});
            expect(next.encode(), configuration.encode());
            return replacement;
          },
        );
        final preview = await service.previewRemoval(ids: {removed.id});
        expect(preview.affectsRuntime, isTrue);
        expect(preview.disconnect, isFalse);
        await service.remove(preview);
        expect(calls, ['stop', 'start']);
        expect(coordinator.state.value.runtime?.profile?.id, remaining.id);
        expect(
          (await coordinator.configuration).connection.selection.kind,
          SelectionKind.automatic,
        );
        expect(await db.coreConfigDao.searchRow(removed.id), isNull);
        expect(await db.coreConfigDao.searchRow(remaining.id), remaining);
      },
    );
  }

  test('mode edits and unrelated deletions retain an unavailable source preference', () async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    final subscriptions = SubscriptionService.forTesting(
      database: db,
      schedulePing: (_) {},
      loadRows: (input) async => SubscriptionLoadResult(
        status: SubscriptionUpdateResult.success,
        mode: input.mode!,
        rows: input.mode == SubscriptionMode.appManaged
            ? [
                outboundCompanion({
                  'tag': 'Ordinary',
                  'protocol': 'socks',
                  'settings': {
                    'servers': [
                      {'address': 'example.com', 'port': 1080},
                    ],
                  },
                }),
              ]
            : [
                CoreConfigCompanion.insert(
                  name: 'Complete only',
                  type: CoreConfigType.Remnawave.name,
                  tags: '',
                  data: Value(
                    base64Encode(
                      utf8.encode(
                        '{"remarks":"Complete only","outbounds":[{"protocol":"freedom"}]}',
                      ),
                    ),
                  ),
                  delay: PingDelayConstants.unknown,
                  subId: 0,
                ),
              ],
      ),
    );
    final inserted = await subscriptions.insertSubscription(
      const SubscriptionInput(
        name: 'Source',
        url: 'https://example.com/source',
        mode: SubscriptionMode.appManaged,
      ),
    );
    expect(inserted.success, isTrue);
    final configuration = ConnectionConfiguration(
      connection: ConnectionSettings(
        selection: ServerSelection.source(inserted.subId),
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
        start: (_) async => throw StateError('No implicit start'),
        stop: () async => throw StateError('No implicit stop'),
      ),
    );
    final service = ServerAssetService(
      database: db,
      coordinator: coordinator,
      subscriptions: subscriptions,
    );
    expect(
      await subscriptions.saveSubscriptionInput(
        inserted.subId,
        const SubscriptionInput(
          name: 'Source',
          url: 'https://example.com/source',
          mode: SubscriptionMode.providerManaged,
        ),
      ),
      SubscriptionUpdateResult.success,
    );
    final unavailable = await subscriptions.modeAvailability(inserted.subId);
    expect(unavailable.hasActiveCache, isFalse);
    expect(unavailable.selectedCompatible, isFalse);
    final unrelated = await server();
    await service.remove(await service.previewRemoval(ids: {unrelated.id}));
    expect((await coordinator.configuration).encode(), configuration.encode());

    final source = (await db.subscriptionDao.searchRow(inserted.subId))!;
    expect(
      (await subscriptions.refreshSubscriptionResult(source)).success,
      isTrue,
    );
    final profile = (await db.coreConfigDao.allActiveServerRows()).single;
    expect(profile.type, CoreConfigType.Remnawave.name);
    expect(
      (await subscriptions.modeAvailability(inserted.subId)).selectedCompatible,
      isTrue,
    );
    await service.remove(await service.previewRemoval(ids: {profile.id}));
    expect(await service.rows(), isEmpty);
    expect(
      (await coordinator.configuration).connection.selection.kind,
      SelectionKind.automatic,
    );

    final another = await server();
    await service.remove(await service.previewRemoval(ids: {another.id}));
    expect(
      (await coordinator.configuration).connection.selection.kind,
      SelectionKind.automatic,
    );
    expect(await db.subscriptionDao.searchRow(inserted.subId), isNotNull);
    await service.remove(
      await service.previewRemoval(sourceId: inserted.subId),
    );
    expect(await db.subscriptionDao.searchRow(inserted.subId), isNull);
    expect(
      (await coordinator.configuration).connection.selection.kind,
      SelectionKind.automatic,
    );
  });

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

  for (final emptyOutbounds in [false, true]) {
    test(
      'an imported provider with ${emptyOutbounds ? 'empty' : 'missing'} original outbounds can be selected',
      () async {
        final original = <String, dynamic>{
          'remarks': 'Complete profile',
          if (emptyOutbounds) 'outbounds': <dynamic>[],
        };
        final validations = <Map<String, dynamic>>[];
        final reader = SubscriptionConfigurationReader(
          decode: (text, {ageSecretKey}) async => text,
          readNodes: (_) async => throw StateError('No node projection'),
          withFiles: (action) => action(),
          validate: (text) async {
            validations.add(jsonDecode(text) as Map<String, dynamic>);
            return '';
          },
        );
        final subscriptions = SubscriptionService.forTesting(
          database: db,
          schedulePing: (_) => throw StateError('No provider measurement'),
          loadRows: (input) async {
            final result = await reader.read(jsonEncode(original), input);
            return SubscriptionLoadResult(
              status: SubscriptionUpdateResult.success,
              mode: result.mode,
              rows: result.rows,
            );
          },
        );
        final inserted = await subscriptions.insertSubscription(
          const SubscriptionInput(
            name: 'Provider',
            url: 'https://example.com/provider',
            panel: SubscriptionPanel.remnawave,
          ),
        );
        expect(inserted.success, isTrue);
        expect(inserted.count, 1);
        expect(validations, hasLength(1));
        expect(
          (validations.single['outbounds'] as List).map(
            (value) => value['tag'],
          ),
          containsAll(['direct', 'block', 'app-remna-dns']),
        );
        final profile = (await db.coreConfigDao.allActiveServerRows()).single;
        final source = (await db.subscriptionDao.searchRow(inserted.subId))!;
        expect(ResolvedProfile.fromRow(profile).config, original);
        expect(profile.type, CoreConfigType.Remnawave.name);
        final catalog = ServerCatalog(servers: [profile], sources: [source]);
        expect(catalog.display(profile).readable, isTrue);
        expect(catalog.selectable(profile), isTrue);
        expect(ServerAssetService.selectable(profile), isTrue);
        final service = ServerAssetService(
          database: db,
          coordinator: selectionCoordinator(),
          subscriptions: subscriptions,
          validate: (_) async =>
              throw StateError('Already validated at import'),
        );
        await service.validateSelection(ServerSelection.server(profile.id));
        final configuration = ConnectionConfiguration(
          connection: ConnectionSettings(
            selection: ServerSelection.server(profile.id),
          ),
        );
        await db.connectionConfigDao.commit(
          configurationJson: configuration.encode(),
        );
        final available = await subscriptions.modeAvailability(source.id);
        expect(available.count, 1);
        expect(available.selectedCompatible, isTrue);

        final appManaged = source.copyWith(mode: 'appManaged');
        await db.subscriptionDao.updateRow(appManaged);
        expect(
          catalog.copyWith(sources: [appManaged]).selectable(profile),
          isFalse,
        );
        await expectLater(
          service.validateSelection(ServerSelection.server(profile.id)),
          throwsFormatException,
        );
        final unavailable = await subscriptions.modeAvailability(source.id);
        expect(unavailable.count, 0);
        expect(unavailable.selectedCompatible, isFalse);
      },
    );
  }

  test('a provider asset with unreadable JSON cannot be selected', () async {
    final profile = await _provider(db);
    final unreadable = profile.copyWith(
      data: Value(base64Encode(utf8.encode('{'))),
    );
    await db.coreConfigDao.updateRow(unreadable);
    expect(ServerAssetService.selectable(unreadable), isFalse);
    await expectLater(
      ServerAssetService(
        database: db,
        coordinator: selectionCoordinator(),
        subscriptions: SubscriptionService.forTesting(
          database: db,
          schedulePing: (_) {},
        ),
      ).validateSelection(ServerSelection.server(profile.id)),
      throwsFormatException,
    );
  });

  test(
    'selection checks use the latest mode rather than a stale server view',
    () async {
      final profile = await _provider(db);
      final derived = await server(subId: profile.subId);
      await server();
      final service = ServerAssetService(
        database: db,
        coordinator: selectionCoordinator(),
        subscriptions: SubscriptionService.forTesting(
          database: db,
          schedulePing: (_) {},
        ),
      );
      await service.validateSelection(const ServerSelection.automatic());
      await service.validateSelection(const ServerSelection.source(0));
      await service.validateSelection(ServerSelection.server(profile.id));
      await service.validateSelection(ServerSelection.source(profile.subId));
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

Future<CoreConfigData> _provider(
  AppDatabase db, {
  SubscriptionMode mode = SubscriptionMode.providerManaged,
}) async {
  final sourceId = await db.subscriptionDao.insertRow(
    SubscriptionCompanion.insert(
      name: 'Provider',
      url: 'https://example.com/provider',
      timestamp: DateTime(2026),
      mode: Value(mode.name),
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
