import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/routing/smart/editor.dart';
import 'package:onexray/service/connect/routing/options.dart';

RegionCatalog _regions() => RegionCatalog.fromJson(
  {
    'geosite': {
      'CN': ['CN'],
      'RU': ['CATEGORY-RU'],
    },
    'geoip': {
      'CN': ['CN'],
      'RU': ['RU'],
      'IR': ['IR'],
    },
  },
  geositeCodes: ['CN', 'CATEGORY-RU'],
  geoipCodes: ['CN', 'RU'],
);

void main() {
  test(
    'non-address DNS policy changes runtime even with direct DNS disabled',
    () {
      final before = SmartRoutingSettings(directDns: false);
      for (final policy in [
        NonAddressDnsPolicy.direct,
        NonAddressDnsPolicy.empty,
      ]) {
        final after = SmartRoutingSettings.fromJson({
          ...before.toJson(),
          'dns': before.dns.copyWith(nonAddressPolicy: policy).toJson(),
        });
        expect(
          SmartRoutingEditorService.sameRuntime(
            ConnectionSettings(smart: before),
            after,
            _regions(),
          ),
          isFalse,
        );
      }
    },
  );

  test('Fragment defaults off, persists and changes Smart runtime', () {
    final before = SmartRoutingSettings.fromJson({});
    expect(before.fragment, false);
    final after = SmartRoutingSettings.fromJson({
      ...before.toJson(),
      'fragment': true,
    });
    expect(SmartRoutingSettings.fromJson(after.toJson()).fragment, true);
    expect(
      SmartRoutingEditorService.sameRuntime(
        ConnectionSettings(smart: before),
        after,
        _regions(),
      ),
      false,
    );
  });

  test(
    'FakeDNS defaults off, persists and affects Smart runtime comparison',
    () {
      final before = SmartRoutingSettings.fromJson({});
      expect(before.fakeDns, false);
      final after = SmartRoutingSettings.fromJson({
        ...before.toJson(),
        'fakeDns': true,
      });
      expect(SmartRoutingSettings.fromJson(after.toJson()).fakeDns, true);
      expect(
        SmartRoutingEditorService.sameRuntime(
          ConnectionSettings(smart: before),
          after,
          _regions(),
        ),
        false,
      );
      expect(
        SmartRoutingEditorService.sameRuntime(
          ConnectionSettings(smart: after),
          after,
          _regions(),
        ),
        true,
      );
    },
  );

  test(
    'Smart keeps legacy defaults and reconnects only for effective DNS changes',
    () {
      expect(SmartRoutingSettings.fromJson({}).directDnsAddress, '8.8.8.8');
      for (final enabled in [false, true]) {
        final before = SmartRoutingSettings(
          directDns: enabled,
          directDnsAddress: '1.1.1.1',
        );
        final after = SmartRoutingSettings.fromJson({
          ...before.toJson(),
          'dns': before.dns.withDirectAddress('9.9.9.9').toJson(),
        });
        expect(after.directDnsAddress, '9.9.9.9');
        expect(
          SmartRoutingEditorService.sameRuntime(
            ConnectionSettings(smart: before),
            after,
            _regions(),
          ),
          !enabled,
        );
      }
    },
  );

  test(
    'inactive sniffing and probe preferences persist without changing runtime',
    () {
      final before = SmartRoutingSettings(
        sniffing: const RoutingSniffingSettings(enabled: false),
      );
      final after = SmartRoutingSettings.fromJson({
        ...before.toJson(),
        'sniffing': before.sniffing.copyWith(metadataOnly: true).toJson(),
        'selection': before.selection
            .copyWith(
              probeURL: 'https://example.com/probe',
              probeInterval: '30s',
              enableConcurrency: false,
            )
            .toJson(),
      });
      expect(
        SmartRoutingEditorService.sameRuntime(
          ConnectionSettings(smart: before),
          after,
          _regions(),
        ),
        true,
      );
      expect(after.sniffing.metadataOnly, true);
      expect(after.selection.probeInterval, '30s');
      final automaticBefore = SmartRoutingSettings(
        entryCount: 2,
        selection: const RoutingSelectionSettings(type: 'leastPing'),
      );
      final automaticAfter = SmartRoutingSettings.fromJson({
        ...automaticBefore.toJson(),
        'selection': automaticBefore.selection
            .copyWith(probeInterval: '1m')
            .toJson(),
      });
      expect(
        SmartRoutingEditorService.sameRuntime(
          ConnectionSettings(smart: automaticBefore),
          automaticAfter,
          _regions(),
        ),
        true,
      );
    },
  );

  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  test(
    'saving FakeDNS validates the same pools and persists without servers',
    () async {
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          inspect: (_, {observedStatus}) async =>
              const HostConnection(VpnStatus.disconnected),
        ),
      );
      final original = await coordinator.configuration;
      var validations = 0;
      final service = SmartRoutingEditorService(
        database: db,
        coordinator: coordinator,
        loadRegions: () async => _regions(),
        testXray: (text) async {
          validations++;
          final config = jsonDecode(text);
          expect(
            (config['dns']['servers'] as List).where(
              (server) => server['address'] == 'fakedns',
            ),
            isNotEmpty,
          );
          expect(config['fakedns'], [
            {'ipPool': '198.19.0.0/16', 'poolSize': 32768},
            {'ipPool': '2001:2::/48', 'poolSize': 32768},
          ]);
          expect(config['inbounds'].single['protocol'], 'socks');
          expect(config['inbounds'].single['sniffing']['destOverride'], [
            'http',
            'tls',
            'quic',
            'fakedns',
          ]);
          return '';
        },
      );
      expect(
        await service.save(
          original: original,
          smart: SmartRoutingSettings.fromJson({
            ...original.connection.smart.toJson(),
            'fakeDns': true,
          }),
          confirmReconnect: () async =>
              throw StateError('Unexpected reconnect'),
        ),
        true,
      );
      expect(validations, 1);
      expect((await coordinator.configuration).connection.smart.fakeDns, true);
    },
  );

  test(
    'saving Fragment validates its chain and persists without servers',
    () async {
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          inspect: (_, {observedStatus}) async =>
              const HostConnection(VpnStatus.disconnected),
        ),
      );
      final original = await coordinator.configuration;
      String? validated;
      final service = SmartRoutingEditorService(
        database: db,
        coordinator: coordinator,
        loadRegions: () async => _regions(),
        testXray: (text) async {
          validated = text;
          return '';
        },
      );
      expect(
        await service.save(
          original: original,
          smart: SmartRoutingSettings.fromJson({
            ...original.connection.smart.toJson(),
            'fragment': true,
          }),
          confirmReconnect: () async => throw StateError('No VPN is running'),
        ),
        true,
      );
      final outbounds = (jsonDecode(validated!)['outbounds'] as List)
          .cast<Map>();
      expect(
        outbounds.first['streamSettings']['sockopt']['dialerProxy'],
        'fragment',
      );
      expect(
        outbounds[1]['streamSettings']['finalmask']['tcp'].single['settings'],
        {'packets': 'tlshello', 'length': '100-200', 'delay': '10-20'},
      );
      expect((await coordinator.configuration).connection.smart.fragment, true);
      expect(await db.coreConfigDao.watchHasOutbounds().first, false);
    },
  );

  test(
    'Smart validates an edited DNS address with libXray before saving',
    () async {
      final coordinator = await _initialize(
        ConnectionCoordinator(
          database: db,
          inspect: (_, {observedStatus}) async =>
              const HostConnection(VpnStatus.disconnected),
        ),
      );
      final original = await coordinator.configuration;
      var coreError = 'Invalid DNS address';
      var calls = 0;
      final service = SmartRoutingEditorService(
        database: db,
        coordinator: coordinator,
        loadRegions: () async => _regions(),
        testXray: (text) async {
          calls++;
          final json = jsonDecode(text);
          final direct = (json['dns']['servers'] as List).singleWhere(
            (server) => server['tag'] == 'app-dns-direct',
          );
          expect(direct['address'], '1.1.1.1');
          expect(json['inbounds'].single['protocol'], 'socks');
          return coreError;
        },
      );
      Future<bool> save() => service.save(
        original: original,
        smart: SmartRoutingSettings(directDnsAddress: ' 1.1.1.1 '),
        confirmReconnect: () async => throw StateError('Must not reconnect'),
      );
      await expectLater(
        save(),
        throwsA(isA<AppFailure>().having((e) => e.cause, 'cause', coreError)),
      );
      expect((await coordinator.configuration).encode(), original.encode());
      coreError = '';
      expect(await save(), true);
      expect(
        (await coordinator.configuration).connection.smart.directDnsAddress,
        '1.1.1.1',
      );
      expect(calls, 2);
    },
  );

  test('Smart saving validates multi-chain strategy and managed sniffing placeholders', () async {
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
      ),
    );
    final original = await coordinator.configuration;
    var calls = 0;
    final service = SmartRoutingEditorService(
      database: db,
      coordinator: coordinator,
      loadRegions: () async => _regions(),
      testXray: (text) async {
        calls++;
        final json = jsonDecode(text);
        expect(
          json['routing']['balancers'].single['strategy']['type'],
          'leastPing',
        );
        expect(
          json['routing']['balancers'].single['fallbackTag'],
          'app-entry-0',
        );
        expect(json['observatory']['subjectSelector'], [
          'app-entry-0',
          'app-entry-1',
        ]);
        expect(json['observatory']['probeInterval'], '30s');
        expect(json['inbounds'].single['protocol'], 'socks');
        expect(json['inbounds'].single['sniffing']['metadataOnly'], true);
        return '';
      },
    );
    final smart = SmartRoutingSettings(
      entryCount: 2,
      selection: const RoutingSelectionSettings(
        type: 'leastPing',
        probeInterval: '30s',
      ),
      sniffing: const RoutingSniffingSettings(metadataOnly: true),
    );
    expect(
      await service.save(
        original: original,
        smart: smart,
        confirmReconnect: () async => throw StateError('No active VPN'),
      ),
      true,
    );
    expect(calls, 1);
    expect(
      (await coordinator.configuration).connection.smart.selection.toJson(),
      smart.selection.toJson(),
    );
  });

  test('unselected Smart saves without activation or servers; stale settings are rejected', () async {
    final original = ConnectionConfiguration(
      connection: ConnectionSettings(
        expert: true,
        rawId: 9,
        trafficMode: TrafficMode.custom,
        customId: 7,
      ),
    );
    await db.connectionConfigDao.commit(configurationJson: original.encode());
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
        start: (_) async => throw StateError('Unexpected start'),
        stop: () async => throw StateError('Unexpected stop'),
      ),
    );
    final service = SmartRoutingEditorService(
      database: db,
      coordinator: coordinator,
      loadRegions: () async => _regions(),
    );
    final smart = SmartRoutingSettings(
      entryCount: 3,
      directRegions: [],
      directWindows: true,
      blockAds: true,
    );
    expect(
      await service.save(
        original: original,
        smart: smart,
        confirmReconnect: () async =>
            throw StateError('Unexpected confirmation'),
      ),
      true,
    );
    final saved = await coordinator.configuration;
    expect(saved.connection.expert, true);
    expect(saved.connection.rawId, 9);
    expect(saved.connection.trafficMode, TrafficMode.custom);
    expect(saved.connection.customId, 7);
    expect(saved.connection.smart.toJson(), smart.toJson());
    expect(saved.policy.toJson(), original.policy.toJson());
    await expectLater(
      service.save(
        original: original,
        smart: SmartRoutingSettings(),
        confirmReconnect: () async => false,
      ),
      throwsA(isA<ConnectionHostException>()),
    );
    expect((await coordinator.configuration).encode(), saved.encode());
  });

  for (final connected in [false, true]) {
    test(
      'provider ${connected ? 'session' : 'selection'} saves Smart preferences without reconnecting',
      () async {
        final sourceId = await db.subscriptionDao.insertRow(
          SubscriptionCompanion.insert(
            name: 'Provider',
            url: 'https://example.com/provider',
            timestamp: DateTime(2026, 10, 12),
            mode: Value(SubscriptionMode.providerManaged.name),
          ),
        );
        final profileId = await db.coreConfigDao.insertRow(
          CoreConfigCompanion.insert(
            name: 'Provider profile',
            type: CoreConfigType.Remnawave.name,
            tags: '',
            delay: PingDelayConstants.unknown,
            subId: sourceId,
            data: Value(
              base64Encode(
                utf8.encode('{"outbounds":[{"protocol":"freedom"}]}'),
              ),
            ),
          ),
        );
        final profile = (await db.coreConfigDao.searchRow(profileId))!;
        final original = ConnectionConfiguration(
          connection: ConnectionSettings(
            selection: ServerSelection.server(profileId),
          ),
        );
        await db.connectionConfigDao.commit(
          configurationJson: original.encode(),
        );
        final runtime = connected
            ? _runtime(
                'provider',
                original,
                profile: ResolvedProfile.fromRow(profile),
              )
            : null;
        if (connected) {
          // A mode-only edit keeps the current provider session running even
          // though its old cache is no longer in the active server list.
          final source = (await db.subscriptionDao.searchRow(sourceId))!;
          await db.subscriptionDao.updateRow(
            source.copyWith(mode: SubscriptionMode.appManaged.name),
          );
        }
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
              'Smart preferences must not prepare a provider',
            ),
            start: (_) async =>
                throw StateError('Smart preferences must not start a provider'),
            stop: () async =>
                throw StateError('Smart preferences must not stop a provider'),
          ),
        );
        var validations = 0;
        final service = SmartRoutingEditorService(
          database: db,
          coordinator: coordinator,
          loadRegions: () async =>
              throw StateError('Provider sessions do not use Smart rules'),
          testXray: (_) async {
            validations++;
            return '';
          },
        );
        final smart = SmartRoutingSettings(fragment: true, blockAds: true);
        expect(
          await service.save(
            original: original,
            smart: smart,
            confirmReconnect: () async => throw StateError(
              'Provider sessions do not require Smart reconnects',
            ),
          ),
          isTrue,
        );
        expect(validations, 1);
        final saved = await coordinator.configuration;
        expect(saved.connection.smart.toJson(), smart.toJson());
        expect(saved.connection.selection.id, profileId);
        expect(saved.connection.expert, isFalse);
        expect(coordinator.state.value.runtime, same(runtime));
        expect(
          coordinator.state.value.phase,
          connected ? ConnectionPhase.connected : ConnectionPhase.disconnected,
        );
        expect(await db.coreConfigDao.searchRow(profileId), profile);
        expect(
          (await db.subscriptionDao.searchRow(sourceId))!.mode,
          connected
              ? SubscriptionMode.appManaged.name
              : SubscriptionMode.providerManaged.name,
        );
      },
    );
  }

  test(
    'active save cancels without writes and failed reconnect is not restored',
    () async {
      final original = ConnectionConfiguration();
      final old = _runtime('a', original);
      await db.connectionConfigDao.commit(configurationJson: original.encode());
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
            throw const ConnectionHostException('startFailed');
          },
          stop: () async {
            calls.add('stop');
            return host = const HostConnection(VpnStatus.disconnected);
          },
        ),
      );
      final service = SmartRoutingEditorService(
        database: db,
        coordinator: coordinator,
        loadRegions: () async => _regions(),
        testXray: (_) async => '',
      );
      final smart = SmartRoutingSettings(
        dns: const RoutingDnsSettings(
          nonAddressPolicy: NonAddressDnsPolicy.direct,
        ),
      );
      expect(
        await service.save(
          original: original,
          smart: smart,
          confirmReconnect: () async => false,
        ),
        false,
      );
      expect(calls, isEmpty);
      final before = (await db.connectionConfigDao.read()).toJson();
      await expectLater(
        service.save(
          original: original,
          smart: smart,
          confirmReconnect: () async => true,
        ),
        throwsA(isA<ConnectionHostException>()),
      );
      expect((await db.connectionConfigDao.read()).toJson(), before);
      expect(calls, ['stop', 'start:new', 'stop']);
      expect(coordinator.state.value.phase, ConnectionPhase.failed);
      expect(coordinator.state.value.runtime, isNull);
    },
  );

  test('a connection that appears after refresh cannot bypass reconnect confirmation', () async {
    final original = ConnectionConfiguration();
    final old = _runtime('a', original);
    var host = const HostConnection(VpnStatus.disconnected);
    final coordinator = await _initialize(
      ConnectionCoordinator(
        database: db,
        inspect: (_, {observedStatus}) async => host,
        prepare: (_, _) async => throw StateError('Must not prepare'),
        start: (_) async => throw StateError('Must not start'),
        stop: () async => throw StateError('Must not stop'),
      ),
    );
    final service = SmartRoutingEditorService(
      database: db,
      coordinator: coordinator,
      loadRegions: () async {
        host = HostConnection(VpnStatus.connected, runtime: old);
        return _regions();
      },
    );
    await expectLater(
      service.save(
        original: original,
        smart: SmartRoutingSettings(blockAds: true),
        confirmReconnect: () async =>
            throw StateError('No earlier connected state'),
      ),
      throwsA(
        isA<ConnectionHostException>().having(
          (e) => e.reason,
          'reason',
          'reconnectRequired',
        ),
      ),
    );
    expect((await coordinator.configuration).encode(), original.encode());
    expect(host.runtime?.identity, old.identity);
  });

  test('Smart preview shares native rules and ignores non-semantic region/count changes', () {
    final regions = _regions();
    final smart = SmartRoutingSettings(
      directRegions: ['RU', 'CN'],
      blockAds: true,
    );
    final rules = ConnectionCompiler.smartRules(smart, regions);
    expect(rules.map((rule) => rule.ruleTag), [
      'app-smart-ads',
      'app-smart-github',
      'app-smart-direct-domain',
      'app-smart-direct-ip',
    ]);
    expect(rules[0].outboundTag, 'block');
    expect(rules[1].toJson(), {
      'ruleTag': 'app-smart-github',
      'domain': ['geosite:GITHUB'],
      'balancerTag': 'proxy',
    });
    expect(rules[2].toJson(), {
      'ruleTag': 'app-smart-direct-domain',
      'domain': [
        'geosite:PRIVATE',
        'geosite:APPLE',
        'geosite:MICROSOFT',
        'geosite:BING',
        'geosite:CATEGORY-RU',
        'geosite:CN',
      ],
      'outboundTag': 'direct',
    });
    expect(rules[3].toJson(), {
      'ruleTag': 'app-smart-direct-ip',
      'ip': ['geoip:PRIVATE', 'geoip:RU', 'geoip:CN'],
      'outboundTag': 'direct',
    });
    expect(regions.regionCodes, ['CN', 'RU']);
    final original = ConnectionSettings(
      selection: const ServerSelection.server(8),
      smart: smart,
    );
    expect(
      SmartRoutingEditorService.sameRuntime(
        original,
        SmartRoutingSettings.fromJson({
          ...smart.toJson(),
          'directWindows': false,
        }),
        regions,
      ),
      false,
    );
    expect(
      SmartRoutingEditorService.sameRuntime(
        original,
        SmartRoutingSettings(
          entryCount: 3,
          directRegions: ['CN', 'RU'],
          blockAds: true,
        ),
        regions,
      ),
      true,
    );
    expect(
      SmartRoutingEditorService.sameRuntime(
        original,
        SmartRoutingSettings(
          directRegions: ['CN', 'RU'],
          blockAds: true,
          directDns: false,
        ),
        regions,
      ),
      false,
    );
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
      jsonEncode(
        LibXrayInvokeRequest(
          method: LibXrayMethod.runXray,
          payload: RunXrayRequest(text).toJson(),
        ).toJson(),
      ),
    ),
  );
}
