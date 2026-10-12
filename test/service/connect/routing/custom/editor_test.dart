import 'package:onexray/core/errors/failure.dart';

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/shared/share/configuration_source.dart';

import '../../../../support/fake_geodata_import.dart';

import 'package:onexray/service/connect/routing/custom/editor.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';

RoutingProfileState _state(
  String name, {
  int entries = 1,
  RoutingRuleAction action = RoutingRuleAction.direct,
}) => RoutingProfileState(
  name: name,
  entryCount: entries,
  rules: [
    RoutingRuleState(
      ruleTag: 'Example',
      domain: const ['domain:example.com'],
      action: action,
    ),
  ],
);

void main() {
  test(
    'direct DNS changes are runtime changes independent of profile naming',
    () {
      final before = _state('Route');
      expect(
        CustomRoutingEditorService.sameRouting(
          before,
          before.copyWith(name: 'Renamed'),
        ),
        true,
      );
      expect(
        CustomRoutingEditorService.sameRouting(
          before,
          before.copyWith(directDnsAddress: '1.1.1.1'),
        ),
        false,
      );
    },
  );

  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  test('advanced active edits preserve the template on rejected changes and compare full JSON', () async {
    final state = AdvancedRoutingDocument.parse(
      AdvancedRoutingProfile.defaultText,
      name: 'Advanced',
    ).state;
    final id = await CustomRoutingService(db).save(state);
    final configuration = ConnectionConfiguration(
      connection: ConnectionSettings(
        trafficMode: TrafficMode.custom,
        customId: id,
      ),
    );
    await db.connectionConfigDao.commit(
      configurationJson: configuration.encode(),
    );
    final runtime = _runtime('advanced', configuration);
    var host = HostConnection(VpnStatus.connected, runtime: runtime);
    final actions = <String>[];
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        inspect: (_, {observedStatus}) async => host,
        start: (_) async {
          actions.add('start');
          throw const ConnectionHostException('startFailed');
        },
        stop: () async {
          actions.add('stop');
          return host = const HostConnection(VpnStatus.disconnected);
        },
      ),
    );
    final service = CustomRoutingEditorService(
      database: db,
      coordinator: coordinator,
      testXray: (_) async => '',
      prepare: (next, _, _) async => _runtime('new', next),
    );
    final draft = await service.load(id);
    await service.save(
      CustomRoutingEditorDraft(
        original: draft.original,
        state: draft.state.copyWith(name: 'Renamed'),
      ),
      confirmReconnect: () async =>
          throw StateError('Name is not a runtime edit'),
    );
    expect(actions, isEmpty);
    final renamed = await service.load(id);
    final json = renamed.state.toJson();
    json['inbounds'][0]['sniffing']['routeOnly'] = false;
    json['routing']['rules'][0]['ruleTag'] = 'User label';
    final changed = CustomRoutingEditorDraft(
      original: renamed.original,
      state: AdvancedRoutingDocument.parse(
        jsonEncode(json),
        name: renamed.state.name,
      ).state,
    );
    expect(
      CustomRoutingEditorService.sameRouting(renamed.state, changed.state),
      isFalse,
    );
    expect(
      await service.save(changed, confirmReconnect: () async => false),
      isNull,
    );
    expect(actions, isEmpty);
    await expectLater(
      service.save(changed, confirmReconnect: () async => true),
      throwsA(isA<ConnectionHostException>()),
    );
    expect(actions, [
      'stop',
      'start',
      'stop',
    ]); // Failed-start cleanup, never restart old.
    final stored = (await db.routingProfileDao.searchRow(id))!;
    expect(stored, renamed.original);
    expect(stored.advanced, isTrue);
    expect(
      CustomRoutingService.readConfiguration(stored).toJson(),
      state.toJson(),
    );
    expect(coordinator.state.value.phase, ConnectionPhase.failed);
  });

  test(
    'libXray rejection preserves the existing profile without activation',
    () async {
      final id = await CustomRoutingService(db).save(_state('Work'));
      final original = (await db.routingProfileDao.searchRow(id))!;
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          inspect: (_, {observedStatus}) async =>
              const HostConnection(VpnStatus.disconnected),
          start: (_) async => throw StateError('Unexpected start'),
          stop: () async => throw StateError('Unexpected stop'),
        ),
      );
      var calls = 0;
      final service = CustomRoutingEditorService(
        database: db,
        coordinator: coordinator,
        testXray: (text) async {
          calls++;
          expect(
            jsonDecode(text)['routing']['rules'].single['port'],
            'invalid',
          );
          return 'Core rejected port';
        },
      );
      await expectLater(
        service.save(
          CustomRoutingEditorDraft(
            original: original,
            state: _state('Renamed')
                .copyWith(rules: [RoutingRuleState(port: 'invalid')]),
          ),
          confirmReconnect: () async =>
              throw StateError('Unexpected confirmation'),
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.cause,
            'core reason',
            'Core rejected port',
          ),
        ),
      );
      expect(calls, 1);
      expect(await db.routingProfileDao.searchRow(id), original);
    },
  );

  test('new templates save without servers or activation; names and three-item cap are enforced', () async {
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
        start: (_) async => throw StateError('Unexpected start'),
        stop: () async => throw StateError('Unexpected stop'),
      ),
    );
    final service = CustomRoutingEditorService(
      database: db,
      coordinator: coordinator,
      testXray: (_) async => '',
    );
    final before = (await coordinator.configuration).encode();
    final id = await service.save(
      CustomRoutingEditorDraft(state: _state('  Work  ', entries: 3)),
      confirmReconnect: () async => throw StateError('Unexpected confirmation'),
    );
    final row = (await db.routingProfileDao.searchRow(id!))!;
    expect(row.name, 'Work');
    final json = jsonDecode(utf8.decode(base64Decode(row.data))) as Map;
    expect(json.containsKey('name'), false);
    expect(json.containsKey('geodata'), false);
    expect(CustomRoutingService.read(row).entryCount, 3);
    expect((json['routing'] as Map)['rules'], [
      {
        'ruleTag': 'Example',
        'domain': ['domain:example.com'],
        'outboundTag': 'direct',
      },
    ]);
    expect((await coordinator.configuration).encode(), before);
    await expectLater(
      service.save(
        CustomRoutingEditorDraft(state: _state('work')),
        confirmReconnect: () async => false,
      ),
      throwsA(
        isA<CustomRoutingEditorException>().having(
          (e) => e.reason,
          'reason',
          'duplicate',
        ),
      ),
    );
    for (final name in ['Two', 'Three']) {
      await service.save(
        CustomRoutingEditorDraft(state: _state(name)),
        confirmReconnect: () async => false,
      );
    }
    await expectLater(
      service.save(
        CustomRoutingEditorDraft(state: _state('Four')),
        confirmReconnect: () async => false,
      ),
      throwsA(
        isA<CustomRoutingEditorException>().having(
          (e) => e.reason,
          'reason',
          'limit',
        ),
      ),
    );
    expect(await service.rows, hasLength(3));
  });

  test(
    'active edit failure keeps the asset and does not restore the runtime',
    () async {
      final id = await CustomRoutingService(db).save(_state('Work'));
      final configuration = ConnectionConfiguration(
        connection: ConnectionSettings(
          trafficMode: TrafficMode.custom,
          customId: id,
        ),
      );
      final old = _runtime('a', configuration);
      await db.connectionConfigDao.commit(
        configurationJson: configuration.encode(),
      );
      var host = HostConnection(VpnStatus.connected, runtime: old);
      final calls = <String>[];
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          inspect: (_, {observedStatus}) async => host,
          start: (runtime) async {
            calls.add(
              runtime.identity == old.identity ? 'start:old' : 'start:new',
            );
            throw const ConnectionHostException('startFailed');
          },
          stop: () async {
            calls.add('stop');
            return host = const HostConnection(VpnStatus.disconnected);
          },
        ),
      );
      final service = CustomRoutingEditorService(
        database: db,
        coordinator: coordinator,
        testXray: (_) async => '',
        prepare: (next, _, _) async => _runtime('b', next),
      );
      final initial = await service.load(id);
      await service.save(
        CustomRoutingEditorDraft(
          original: initial.original,
          state: initial.state.copyWith(name: 'Renamed'),
        ),
        confirmReconnect: () async =>
            throw StateError('Rename must not reconnect'),
      );
      expect(calls, isEmpty);
      final renamed = await service.load(id);
      final changed = CustomRoutingEditorDraft(
        original: renamed.original,
        state: _state(renamed.state.name, entries: 2),
      );
      final importEvents = <String>[];
      final imported = ConfigurationImportDraft(
        ConfigurationContent(
          kind: ConfigurationKind.custom,
          source: ConfigurationSource.parse(changed.state.encode()),
          name: changed.state.name,
        ),
        FakeGeoDataImport(events: importEvents),
      );
      expect(
        await service.save(
          changed,
          imported: imported,
          confirmReconnect: () async {
            expect(importEvents, isEmpty);
            await coordinator.pauseForDataClear().timeout(
              const Duration(seconds: 1),
            );
            coordinator.resumeAfterDataClear();
            return false;
          },
        ),
        isNull,
      );
      expect(importEvents, isEmpty);
      expect(calls, isEmpty);
      final before = (await db.connectionConfigDao.read()).toJson();
      await expectLater(
        service.save(changed, confirmReconnect: () async => true),
        throwsA(isA<ConnectionHostException>()),
      );
      expect(
        (await db.routingProfileDao.searchRow(id))!.data,
        renamed.original!.data,
      );
      expect((await db.connectionConfigDao.read()).toJson(), before);
      expect(calls, ['stop', 'start:new', 'stop']);
      expect(coordinator.state.value.phase, ConnectionPhase.failed);
      expect(coordinator.state.value.runtime, isNull);
    },
  );

  test('active delete confirms and reconnects with Smart routing', () async {
    final id = await CustomRoutingService(db).save(_state('Work'));
    final configuration = ConnectionConfiguration(
      connection: ConnectionSettings(
        trafficMode: TrafficMode.custom,
        customId: id,
      ),
    );
    final old = _runtime('a', configuration);
    await db.connectionConfigDao.commit(
      configurationJson: configuration.encode(),
    );
    var host = HostConnection(VpnStatus.connected, runtime: old);
    final calls = <String>[];
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        inspect: (_, {observedStatus}) async => host,
        prepare: (next, _) async => _runtime('b', next),
        start: (runtime) async {
          calls.add(
            runtime.identity == old.identity ? 'start:old' : 'start:new',
          );
          return host = HostConnection(VpnStatus.connected, runtime: runtime);
        },
        stop: () async {
          calls.add('stop');
          return host = const HostConnection(VpnStatus.disconnected);
        },
      ),
    );
    final service = CustomRoutingEditorService(
      database: db,
      coordinator: coordinator,
      testXray: (_) async => '',
    );
    final original = (await service.load(id)).original!;
    expect(
      await service.delete(
        original,
        confirm: (selected, reconnect) async {
          expect(selected, true);
          expect(reconnect, true);
          return true;
        },
      ),
      true,
    );
    expect(await db.routingProfileDao.searchRow(id), isNull);
    expect(calls, ['stop', 'start:new']);
    expect(
      (await coordinator.configuration).connection.trafficMode,
      TrafficMode.smart,
    );
    expect(
      coordinator.state.value.runtime!.configuration.connection.trafficMode,
      TrafficMode.smart,
    );
  });

  for (final connected in [false, true]) {
    test(
      'provider ${connected ? 'runtime' : 'selection'} saves and deletes selected Custom preferences without reconnecting',
      () async {
        final id = await CustomRoutingService(db).save(_state('Work'));
        final profile = await _providerRow(db);
        final configuration = ConnectionConfiguration(
          connection: ConnectionSettings(
            selection: ServerSelection.server(profile.id),
            trafficMode: TrafficMode.custom,
            customId: id,
          ),
        );
        await db.connectionConfigDao.commit(
          configurationJson: configuration.encode(),
        );
        final runtime = connected
            ? _runtime(
                'provider',
                configuration,
                profile: ResolvedProfile.fromRow(profile),
              )
            : null;
        final host = HostConnection(
          connected ? VpnStatus.connected : VpnStatus.disconnected,
          runtime: runtime,
        );
        final coordinator = await _initialize(
          ConnectionCoordinator(
            database: db,
            readRuntime: () async => runtime,
            inspect: (_, {observedStatus}) async => host,
            prepare: (_, _) async => throw StateError(
              'Custom preferences must not prepare a provider',
            ),
            start: (_) async => throw StateError(
              'Custom preferences must not start a provider',
            ),
            stop: () async =>
                throw StateError('Custom preferences must not stop a provider'),
          ),
        );
        var validations = 0;
        final service = CustomRoutingEditorService(
          database: db,
          coordinator: coordinator,
          testXray: (_) async {
            validations++;
            return '';
          },
          prepare: (_, _, _) async =>
              throw StateError('Custom drafts must not prepare a provider'),
        );
        final draft = await service.load(id);
        expect(
          await service.save(
            CustomRoutingEditorDraft(
              original: draft.original,
              state: _state(
                'Updated',
                entries: 2,
                action: RoutingRuleAction.proxy,
              ),
            ),
            confirmReconnect: () async => throw StateError(
              'Provider Custom preferences do not require reconnects',
            ),
          ),
          id,
        );
        expect(validations, 1);
        final updated = (await service.load(id)).original!;
        final state = CustomRoutingService.read(updated);
        expect(state.name, 'Updated');
        expect(state.entryCount, 2);
        expect(state.rules.single.action, RoutingRuleAction.proxy);
        expect(
          (await coordinator.configuration).encode(),
          configuration.encode(),
        );
        expect(coordinator.state.value.runtime, same(runtime));

        expect(
          await service.delete(
            updated,
            confirm: (selected, reconnect) async {
              expect(selected, isTrue);
              expect(reconnect, isFalse);
              return true;
            },
          ),
          isTrue,
        );
        expect(await db.routingProfileDao.searchRow(id), isNull);
        final saved = await coordinator.configuration;
        expect(saved.connection.trafficMode, TrafficMode.smart);
        expect(saved.connection.customId, isNull);
        expect(saved.connection.selection.id, profile.id);
        expect(saved.connection.expert, isFalse);
        expect(coordinator.state.value.runtime, same(runtime));
        expect(
          coordinator.state.value.phase,
          connected ? ConnectionPhase.connected : ConnectionPhase.disconnected,
        );
        if (runtime != null) {
          expect(runtime.configuration.connection.customId, id);
        }
        expect(await db.coreConfigDao.searchRow(profile.id), profile);
      },
    );
  }

  test(
    'a provider runtime old Custom ID does not block inactive preference edits',
    () async {
      final id = await CustomRoutingService(db).save(_state('Old preference'));
      final profile = await _providerRow(db);
      final runningConfiguration = ConnectionConfiguration(
        connection: ConnectionSettings(
          selection: ServerSelection.server(profile.id),
          trafficMode: TrafficMode.custom,
          customId: id,
        ),
      );
      final runtime = _runtime(
        'provider',
        runningConfiguration,
        profile: ResolvedProfile.fromRow(profile),
      );
      final configuration = ConnectionConfiguration(
        connection: ConnectionSettings(
          selection: ServerSelection.server(profile.id),
        ),
      );
      await db.connectionConfigDao.commit(
        configurationJson: configuration.encode(),
      );
      final host = HostConnection(VpnStatus.connected, runtime: runtime);
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          readRuntime: () async => runtime,
          inspect: (_, {observedStatus}) async => host,
          prepare: (_, _) async => throw StateError(
            'Inactive preferences must not prepare a provider',
          ),
          start: (_) async => throw StateError(
            'Inactive preferences must not start a provider',
          ),
          stop: () async =>
              throw StateError('Inactive preferences must not stop a provider'),
        ),
      );
      final service = CustomRoutingEditorService(
        database: db,
        coordinator: coordinator,
        testXray: (_) async => '',
        prepare: (_, _, _) async => throw StateError(
          'Inactive Custom drafts must not prepare a provider',
        ),
      );
      final draft = await service.load(id);
      expect(
        await service.save(
          CustomRoutingEditorDraft(
            original: draft.original,
            state: _state('Updated preference', entries: 2),
          ),
          confirmReconnect: () async => throw StateError(
            'Inactive preferences do not require reconnects',
          ),
        ),
        id,
      );
      final updated = (await service.load(id)).original!;
      expect(
        await service.delete(
          updated,
          confirm: (selected, reconnect) async {
            expect(selected, isFalse);
            expect(reconnect, isFalse);
            return true;
          },
        ),
        isTrue,
      );
      expect(await db.routingProfileDao.searchRow(id), isNull);
      expect(
        (await coordinator.configuration).encode(),
        configuration.encode(),
      );
      expect(coordinator.state.value.runtime, same(runtime));
      expect(coordinator.state.value.phase, ConnectionPhase.connected);
      expect(runtime.configuration.connection.customId, id);
      expect(await db.coreConfigDao.searchRow(profile.id), profile);
    },
  );

  test(
    'unselected edits and stale drafts do not overwrite newer assets',
    () async {
      final id = await CustomRoutingService(db).save(_state('Work'));
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          inspect: (_, {observedStatus}) async =>
              const HostConnection(VpnStatus.disconnected),
          start: (_) async => throw StateError('Unexpected start'),
          stop: () async => throw StateError('Unexpected stop'),
        ),
      );
      final service = CustomRoutingEditorService(
        database: db,
        coordinator: coordinator,
        testXray: (_) async => '',
      );
      final original = await service.load(id);
      await service.save(
        CustomRoutingEditorDraft(
          original: original.original,
          state: _state('New name', entries: 2),
        ),
        confirmReconnect: () async =>
            throw StateError('Unexpected confirmation'),
      );
      await expectLater(
        service.save(original, confirmReconnect: () async => false),
        throwsA(isA<CustomRoutingEditorException>()),
      );
      expect((await db.routingProfileDao.searchRow(id))!.name, 'New name');
      expect(
        (await coordinator.configuration).connection.trafficMode,
        TrafficMode.smart,
      );
    },
  );

  test('failed Custom database save rolls staged Geodata back', () async {
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
      ),
    );
    final service = CustomRoutingEditorService(
      database: db,
      coordinator: coordinator,
      testXray: (_) async => '',
    );
    await db.customStatement('''
      CREATE TRIGGER fail_custom_save BEFORE INSERT ON routing_profile
      BEGIN SELECT RAISE(FAIL, 'fixture'); END
    ''');
    final lifecycle = <String>[];
    final imported = ConfigurationImportDraft(
      ConfigurationContent(
        kind: ConfigurationKind.custom,
        source: ConfigurationSource.parse(_state('Work').encode()),
        name: 'Work',
      ),
      FakeGeoDataImport(events: lifecycle),
    );

    await expectLater(
      service.save(
        CustomRoutingEditorDraft(state: _state('Work')),
        confirmReconnect: () async => false,
        imported: imported,
      ),
      throwsA(anything),
    );

    expect(lifecycle, ['publish', 'commit', 'rollback']);
    expect(await db.routingProfileDao.allRows, isEmpty);
  });
}

Future<ConnectionCoordinator> _initialize(
  ConnectionCoordinator coordinator,
) async {
  addTearDown(coordinator.dispose);
  await coordinator.initialize(observe: false, registerReferences: false);
  return coordinator;
}

ConnectionRuntime _runtime(
  String digit,
  ConnectionConfiguration configuration, {
  ResolvedProfile? profile,
}) {
  const text = '{"outbounds":[{"protocol":"freedom"}]}';
  final invoke = LibXrayInvokeRequest(
    method: LibXrayMethod.runXray,
    payload: RunXrayRequest(text).toJson(),
  );
  return ConnectionRuntime.create(
    configuration: configuration,
    compiled: CompiledConnection(
      xrayJson: text,
      entries: [],
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

Future<CoreConfigData> _providerRow(AppDatabase db) async {
  final sourceId = await db.subscriptionDao.insertRow(
    SubscriptionCompanion.insert(
      name: 'Provider',
      url: 'https://example.com/provider',
      timestamp: DateTime(2026, 10, 12),
      mode: Value(SubscriptionMode.providerManaged.name),
    ),
  );
  final id = await db.coreConfigDao.insertRow(
    CoreConfigCompanion.insert(
      name: 'Provider profile',
      type: CoreConfigType.Remnawave.name,
      tags: '',
      delay: PingDelayConstants.unknown,
      subId: sourceId,
      data: Value(
        base64Encode(utf8.encode('{"outbounds":[{"protocol":"freedom"}]}')),
      ),
    ),
  );
  return (await db.coreConfigDao.searchRow(id))!;
}
