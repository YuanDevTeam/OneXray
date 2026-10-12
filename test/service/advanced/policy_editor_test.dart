import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/raw/db.dart';

void main() {
  test('reconnect comparisons include only effective DNS settings', () {
    final original = PlatformPolicy.fromJson({
      'xrayOutboundInterfaceName': 'Ethernet',
    });
    for (final platform in ConnectionPlatform.values) {
      for (final field in ['dnsIpv4Address', 'dnsIpv6Address']) {
        final changed = PlatformPolicy.fromJson({
          ...original.toJson(),
          field: field == 'dnsIpv4Address' ? '1.1.1.1' : '2606:4700:4700::1111',
        });
        expect(
          PolicyEditorService.sameRuntime(original, changed, platform),
          false,
        );
      }
      final renamed = PlatformPolicy.fromJson({
        ...original.toJson(),
        'dnsServerName': 'cloudflare-dns.com',
      });
      expect(
        PolicyEditorService.sameRuntime(original, renamed, platform),
        true,
      );
      final off = PlatformPolicy.fromJson({
        ...original.toJson(),
        'ipv6Enabled': false,
      });
      final offChanged = PlatformPolicy.fromJson({
        ...off.toJson(),
        'dnsIpv6Address': '2606:4700:4700::1111',
      });
      expect(
        PolicyEditorService.sameRuntime(
          off,
          offChanged,
          platform,
          windowsMode: WindowsMode.exe,
        ),
        true,
      );
      if (platform == ConnectionPlatform.windows) {
        expect(
          PolicyEditorService.sameRuntime(
            off,
            offChanged,
            platform,
            windowsMode: WindowsMode.msix,
          ),
          false,
        );
      }
      if (platform == ConnectionPlatform.ios ||
          platform == ConnectionPlatform.macos) {
        final dot = PlatformPolicy.fromJson({
          ...original.toJson(),
          'apple': {'dnsOverTls': true},
        });
        final changed = PlatformPolicy.fromJson({
          ...dot.toJson(),
          'dnsServerName': 'cloudflare-dns.com',
        });
        expect(PolicyEditorService.sameRuntime(dot, changed, platform), false);
      }
    }
  });

  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late HostConnection host;
  late int stops;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    host = const HostConnection(VpnStatus.disconnected);
    stops = 0;
    coordinator = ConnectionCoordinator(
      database: db,
      inspect: (_, {observedStatus}) async => host,
      prepare: (_, _) async => throw StateError('Must not prepare'),
      start: (_) async => throw StateError('Must not start'),
      stop: () async {
        stops++;
        return host = const HostConnection(VpnStatus.disconnected);
      },
    );
    await coordinator.initialize(observe: false, registerReferences: false);
    addTearDown(() async {
      coordinator.dispose();
      await db.close();
    });
  });

  test('LAN sharing changes apply only on the next App start', () {
    final off = PlatformPolicy.fromJson({
      'xrayOutboundInterfaceName': 'Ethernet',
    });
    final changedPort = PlatformPolicy.fromJson({
      ...off.toJson(),
      'lanProxy': {'enabled': false, 'port': 11026},
    });
    final on = PlatformPolicy.fromJson({
      ...off.toJson(),
      'lanProxy': {'enabled': true, 'port': 11024},
    });
    final onChangedPort = PlatformPolicy.fromJson({
      ...on.toJson(),
      'lanProxy': {'enabled': true, 'port': 11026},
    });
    for (final platform in ConnectionPlatform.values) {
      expect(
        PolicyEditorService.sameRuntime(off, changedPort, platform),
        isTrue,
      );
      expect(PolicyEditorService.sameRuntime(off, on, platform), isTrue);
      expect(
        PolicyEditorService.sameRuntime(on, onChangedPort, platform),
        isTrue,
      );
    }
  });

  test('offline sharing saves without starting VPN', () async {
    final service = PolicyEditorService(
      coordinator: coordinator,
      platform: ConnectionPlatform.android,
      reservedApiPort: () async => null,
    );
    var draft = await service.load();
    expect(draft.original.policy.lanProxyEnabled, isFalse);
    expect(draft.original.policy.lanProxyPort, 11024);
    draft.policy['lanProxy']['enabled'] = true;
    expect(
      await service.save(
        draft: draft,
        confirm: (_) async => throw StateError('Must not confirm'),
      ),
      isTrue,
    );
    expect((await coordinator.configuration).policy.lanProxyEnabled, isTrue);
    expect(stops, 0);
    draft = await service.load();
    draft.policy['lanProxy']['enabled'] = false;
    expect(
      await service.save(draft: draft, confirm: (_) async => false),
      isTrue,
    );
    expect((await coordinator.configuration).policy.lanProxyEnabled, isFalse);
    expect(stops, 0);
  });

  test('connected sharing saves without confirmation or changing the active policy', () async {
    final service = PolicyEditorService(
      coordinator: coordinator,
      platform: ConnectionPlatform.android,
      reservedApiPort: () async => null,
    );
    var draft = await service.load();
    final active = _runtime(draft.original);
    host = HostConnection(VpnStatus.connected, runtime: active);
    for (final sharing in [
      {'enabled': true, 'port': 11024},
      {'enabled': true, 'port': 11026},
      {'enabled': false, 'port': 11026},
    ]) {
      draft.policy['lanProxy'] = sharing;
      expect(
        await service.save(
          draft: draft,
          confirm: (_) async => throw StateError('Must not confirm'),
        ),
        isTrue,
      );
      expect(
        (await coordinator.configuration).policy.toJson()['lanProxy'],
        sharing,
      );
      expect(host.runtime, same(active));
      expect(coordinator.state.value.phase, ConnectionPhase.connected);
      draft = await service.load();
    }
    expect(stops, 0);
  });

  test('shared port cannot take the saved local HTTP API port', () async {
    final service = PolicyEditorService(
      coordinator: coordinator,
      platform: ConnectionPlatform.android,
      reservedApiPort: () async => 11024,
    );
    final draft = await service.load();
    draft.policy['lanProxy']['enabled'] = true;
    await expectLater(
      service.save(draft: draft, confirm: (_) async => true),
      throwsFormatException,
    );
    expect((await coordinator.configuration).policy.lanProxyEnabled, isFalse);
  });

  for (final connected in [false, true]) {
    test(
      'Raw saves future sharing policy without affecting VPN: $connected',
      () async {
        final rawId = await db.coreConfigDao.insertAssetRow(
          XrayRawDb.configCompanion(
            'Raw',
            jsonEncode({
              'inbounds': [
                {'tag': 'app-lan-proxy', 'protocol': 'socks', 'port': 11024},
              ],
              'outbounds': [
                {'protocol': 'freedom'},
              ],
            }),
          ),
        );
        final configuration = ConnectionConfiguration(
          connection: ConnectionSettings(expert: true, rawId: rawId),
        );
        await db.connectionConfigDao.commit(
          configurationJson: configuration.encode(),
        );
        if (connected) {
          host = HostConnection(
            VpnStatus.connected,
            runtime: _runtime(configuration),
          );
        }
        final service = PolicyEditorService(
          coordinator: coordinator,
          platform: ConnectionPlatform.android,
          reservedApiPort: () async => 11024,
        );
        var draft = await service.load();
        draft.policy['lanProxy']['enabled'] = true;
        expect(
          await service.save(
            draft: draft,
            confirm: (_) async => throw StateError('Raw must not restart'),
          ),
          isTrue,
        );
        draft = await service.load();
        draft.policy['lanProxy']['port'] = 11026;
        expect(
          await service.save(
            draft: draft,
            confirm: (_) async => throw StateError('Raw must not restart'),
          ),
          isTrue,
        );
        expect(
          (await coordinator.configuration).policy.lanProxyEnabled,
          isTrue,
        );
        expect((await coordinator.configuration).policy.lanProxyPort, 11026);
        expect(stops, 0);
        expect(
          host.status,
          connected ? VpnStatus.connected : VpnStatus.disconnected,
        );
      },
    );
  }

  for (final connected in [false, true]) {
    test(
      'provider ${connected ? 'runtime' : 'selection'} stores LAN preferences without checking inactive Custom listeners',
      () async {
        final sourceId = await db.subscriptionDao.insertRow(
          SubscriptionCompanion.insert(
            name: 'Provider',
            url: 'https://example.test/provider',
            mode: Value(SubscriptionMode.providerManaged.name),
            timestamp: DateTime(2026, 10, 12),
          ),
        );
        const providerText = '{"outbounds":[{"protocol":"freedom"}]}';
        final profileId = await db.coreConfigDao.insertAssetRow(
          CoreConfigCompanion.insert(
            name: 'Provider profile',
            type: CoreConfigType.Remnawave.name,
            tags: '',
            subId: sourceId,
            delay: PingDelayConstants.unknown,
            data: Value(base64Encode(utf8.encode(providerText))),
          ),
        );
        final profile = (await db.coreConfigDao.searchRow(profileId))!;
        final template = base64Encode(
          utf8.encode(
            jsonEncode({
              'inbounds': [
                {'tag': 'custom-listener', 'protocol': 'socks', 'port': 11024},
              ],
              'outbounds': [
                {'protocol': 'freedom'},
              ],
            }),
          ),
        );
        final customId = await db.routingProfileDao.insertRow(
          RoutingProfileCompanion.insert(
            name: 'Inactive advanced route',
            advanced: const Value(true),
            data: template,
          ),
        );
        final configuration = ConnectionConfiguration(
          connection: ConnectionSettings(
            selection: ServerSelection.server(profileId),
            trafficMode: TrafficMode.custom,
            customId: customId,
            smart: SmartRoutingSettings(blockAds: true, entryCount: 3),
          ),
        );
        await db.connectionConfigDao.commit(
          configurationJson: configuration.encode(),
        );
        final active = connected
            ? _runtime(configuration, profile: ResolvedProfile.fromRow(profile))
            : null;
        if (connected) {
          host = HostConnection(VpnStatus.connected, runtime: active);
          await coordinator.refresh();
          // A mode change may hide the old profile, while its complete session
          // continues to own the runtime graph and keeps App routes inactive.
          final source = (await db.subscriptionDao.searchRow(sourceId))!;
          await db.subscriptionDao.updateRow(
            source.copyWith(mode: SubscriptionMode.appManaged.name),
          );
          expect(
            await db.coreConfigDao.searchActiveServerRow(profileId),
            isNull,
          );
        }
        var apiChecks = 0;
        var confirmations = 0;
        final service = PolicyEditorService(
          coordinator: coordinator,
          platform: ConnectionPlatform.android,
          reservedApiPort: () async {
            apiChecks++;
            return 11024;
          },
        );
        final draft = await service.load();
        draft.policy['lanProxy'] = {'enabled': true, 'port': 11024};
        expect(
          await service.save(
            draft: draft,
            confirm: (_) async {
              confirmations++;
              return false;
            },
          ),
          isTrue,
        );
        final saved = await coordinator.configuration;
        expect(saved.policy.lanProxyEnabled, isTrue);
        expect(saved.policy.lanProxyPort, 11024);
        expect(saved.connection.toJson(), configuration.connection.toJson());
        expect(
          (await db.routingProfileDao.searchRow(customId))!.data,
          template,
        );
        expect(
          (await db.coreConfigDao.searchRow(profileId))!.data,
          profile.data,
        );
        expect(apiChecks, 0);
        expect(confirmations, 0);
        expect(stops, 0);
        expect(host.runtime, same(active));
        expect(
          host.status,
          connected ? VpnStatus.connected : VpnStatus.disconnected,
        );
      },
    );
  }

  for (final platform in [
    ConnectionPlatform.windows,
    ConnectionPlatform.linux,
  ]) {
    test(
      'sharing can be configured before selecting an interface: $platform',
      () async {
        final service = PolicyEditorService(
          coordinator: coordinator,
          platform: platform,
          windowsMode: WindowsMode.exe,
          validateInterface: false,
          reservedApiPort: () async => null,
        );
        final draft = await service.load();
        draft.policy['lanProxy']['enabled'] = true;
        expect(
          await service.save(draft: draft, confirm: (_) async => false),
          isTrue,
        );
        expect(
          (await coordinator.configuration).policy.lanProxyEnabled,
          isTrue,
        );
        expect(stops, 0);
      },
    );
  }

  test('EXE ignores hidden MSIX settings for validation and reconnection', () {
    final service = PolicyEditorService(
      coordinator: coordinator,
      platform: ConnectionPlatform.windows,
      windowsMode: WindowsMode.exe,
    );
    final original = ConnectionConfiguration(
      policy: PlatformPolicy.fromJson({
        'xrayOutboundInterfaceName': 'Ethernet',
        'ipv6Enabled': false,
      }),
    );
    final draft = PolicyEditorDraft(original);
    draft.policy['windows']['alwaysOn'] = true;
    draft.policy['windows']['excludedCidrs'] = ['invalid', 'fd00::/64'];
    final policy = service.prepare(draft).policy;
    expect(service.supportsWindowsSystemVpn, false);
    expect(
      () => policy.toTun(
        ConnectionPlatform.windows,
        windowsMode: WindowsMode.exe,
      ),
      returnsNormally,
    );
    expect(
      PolicyEditorService.sameRuntime(
        original.policy,
        policy,
        ConnectionPlatform.windows,
        windowsMode: WindowsMode.exe,
      ),
      true,
    );
    expect(
      PolicyEditorService.sameRuntime(
        original.policy,
        policy,
        ConnectionPlatform.windows,
        windowsMode: WindowsMode.msix,
      ),
      false,
    );
    final controller = PolicyEditorController(draft: draft, service: service);
    addTearDown(controller.close);
    expect(controller.supportsWindowsSystemVpn, false);
    expect(controller.ipv6Conflict, false);
  });

  test('tunnel save does not wait for a paused connection queue', () async {
    final service = PolicyEditorService(
      coordinator: coordinator,
      platform: ConnectionPlatform.ios,
    );
    final draft = await service.load();
    draft.policy['ipv6Enabled'] = false;
    await coordinator.pauseForDataClear();
    try {
      await expectLater(
        service
            .save(draft: draft, confirm: (_) async => false)
            .timeout(const Duration(seconds: 1)),
        throwsStateError,
      );
      expect((await coordinator.configuration).policy.ipv6Enabled, isTrue);
    } finally {
      coordinator.resumeAfterDataClear();
    }
    expect(
      await service.save(draft: draft, confirm: (_) async => false),
      isTrue,
    );
    expect((await coordinator.configuration).policy.ipv6Enabled, isFalse);
    expect(stops, 0);
  });

  test('tunnel save rechecks the draft after data was cleared', () async {
    final service = PolicyEditorService(
      coordinator: coordinator,
      platform: ConnectionPlatform.ios,
    );
    final draft = await service.load();
    await coordinator.pauseForDataClear();
    await db.connectionConfigDao.commit(
      configurationJson: ConnectionConfiguration(
        policy: PlatformPolicy.fromJson({
          'log': {'enabled': true},
        }),
      ).encode(),
    );
    coordinator.resumeAfterDataClear();
    await expectLater(
      service.save(draft: draft, confirm: (_) async => false),
      throwsA(
        isA<ConnectionHostException>().having(
          (error) => error.reason,
          'reason',
          'configurationChanged',
        ),
      ),
    );
  });
  test(
    'restoring defaults changes only the draft, not storage or VPN',
    () async {
      final service = PolicyEditorService(
        coordinator: coordinator,
        platform: ConnectionPlatform.android,
      );
      final seed = await service.load();
      seed.policy['ipv6Enabled'] = false;
      seed.policy['dnsIpv4Address'] = '1.1.1.1';
      seed.policy['dnsIpv6Address'] = '2606:4700:4700::1111';
      seed.policy['dnsServerName'] = 'cloudflare-dns.com';
      seed.policy['android']['appScope'] = 'excluded';
      seed.policy['android']['excludedAppPackageNames'] = [
        'com.example.bypass',
      ];
      seed.policy['log']['enabled'] = true;
      await service.save(
        draft: seed,
        confirm: (_) async => throw StateError('Must not confirm'),
      );
      final original = await service.load();
      final stored = (await db.connectionConfigDao.read()).configurationJson;
      final controller = PolicyEditorController(
        draft: original,
        service: service,
      );
      addTearDown(controller.close);

      controller.restoreDefaults();

      expect(controller.value, PlatformPolicy.defaults().toJson());
      expect(controller.draft!.original, same(original.original));
      expect(original.policy, original.original.policy.toJson());
      expect(controller.error, isNull);
      expect((await db.connectionConfigDao.read()).configurationJson, stored);
      expect(stops, 0);
      expect(host.status, VpnStatus.disconnected);
    },
  );

  test(
    'drafts are isolated and both Android lists survive empty included saves',
    () async {
      final service = PolicyEditorService(
        coordinator: coordinator,
        platform: ConnectionPlatform.android,
      );
      final original = await service.load();
      final changed = original.copy();
      changed.policy['android']['appScope'] = 'included';
      changed.policy['android']['excludedAppPackageNames'] = [
        'com.example.excluded',
      ];
      expect(original.policy['android']['appScope'], 'all');
      expect(
        await service.save(
          draft: changed,
          confirm: (_) async => throw StateError('No confirmation'),
        ),
        true,
      );
      final stored = await coordinator.configuration;
      expect(stored.connection.toJson(), original.original.connection.toJson());
      expect(stored.policy.toJson()['android'], {
        'appScope': 'included',
        'includedAppPackageNames': [],
        'excludedAppPackageNames': ['com.example.excluded'],
      });
      expect(
        () => stored.policy.toTun(ConnectionPlatform.android),
        throwsFormatException,
      );
      await expectLater(
        service.save(draft: original, confirm: (_) async => true),
        throwsA(isA<ConnectionHostException>()),
      );
      expect(stops, 0);
    },
  );

  test(
    'empty included scope needs explicit disconnect approval and never starts',
    () async {
      final service = PolicyEditorService(
        coordinator: coordinator,
        platform: ConnectionPlatform.android,
      );
      final draft = await service.load();
      draft.policy['android']['appScope'] = 'included';
      host = HostConnection(
        VpnStatus.connected,
        runtime: _runtime(draft.original),
      );
      expect(
        await service.save(
          draft: draft,
          confirm: (disconnect) async {
            expect(disconnect, true);
            return false;
          },
        ),
        false,
      );
      expect(stops, 0);
      expect(
        (await coordinator.configuration).encode(),
        draft.original.encode(),
      );
      expect(
        await service.save(
          draft: draft,
          confirm: (disconnect) async {
            expect(disconnect, true);
            return true;
          },
        ),
        true,
      );
      expect(stops, 1);
      expect(host.status, VpnStatus.disconnected);
      expect(
        PolicyEditorService.emptyAndroidScope(
          (await coordinator.configuration).policy,
        ),
        true,
      );
    },
  );

  test(
    'runtime comparison ignores inactive lists and the other Apple network',
    () {
      final a = PlatformPolicy.defaults();
      final json = a.toJson();
      json['android']['includedAppPackageNames'] = ['com.example.included'];
      json['android']['excludedAppPackageNames'] = ['com.example.excluded'];
      final b = PlatformPolicy.fromJson(json);
      expect(
        PolicyEditorService.sameRuntime(a, b, ConnectionPlatform.android),
        true,
      );
      json['android']['appScope'] = 'included';
      expect(
        PolicyEditorService.sameRuntime(
          a,
          PlatformPolicy.fromJson(json),
          ConnectionPlatform.android,
        ),
        false,
      );

      final apple = a.toJson();
      apple['apple']['onDemandEnabled'] = true;
      final ios = PlatformPolicy.fromJson(apple);
      apple['apple']['ethernetAction'] = 'disconnect';
      final macChange = PlatformPolicy.fromJson(apple);
      expect(
        PolicyEditorService.sameRuntime(ios, macChange, ConnectionPlatform.ios),
        true,
      );
      expect(
        PolicyEditorService.sameRuntime(
          ios,
          macChange,
          ConnectionPlatform.macos,
        ),
        false,
      );
    },
  );

  test('VPN icon changes require reconnect only while effective on iOS', () {
    for (final captureAll in [false, true]) {
      final original = PlatformPolicy.fromJson({
        'xrayOutboundInterfaceName': 'en0',
        'apple': {'captureAllTraffic': captureAll},
      });
      final changed = original.toJson();
      changed['apple']['hideVpnIcon'] = true;
      for (final platform in ConnectionPlatform.values) {
        expect(
          PolicyEditorService.sameRuntime(
            original,
            PlatformPolicy.fromJson(changed),
            platform,
          ),
          platform != ConnectionPlatform.ios || captureAll,
        );
      }
    }
  });

  test('VPN icon preference saves and survives capture-all mode', () async {
    final service = PolicyEditorService(
      coordinator: coordinator,
      platform: ConnectionPlatform.ios,
    );
    var draft = await service.load();
    draft.policy['apple']['hideVpnIcon'] = true;
    expect(
      await service.save(draft: draft, confirm: (_) async => false),
      isTrue,
    );
    draft = await service.load();
    expect(draft.policy['apple']['hideVpnIcon'], isTrue);
    expect(
      draft.original.policy.toTun(ConnectionPlatform.ios).hideVpnIcon,
      isTrue,
    );
    draft.policy['apple']['captureAllTraffic'] = true;
    expect(
      await service.save(draft: draft, confirm: (_) async => false),
      isTrue,
    );
    draft = await service.load();
    expect(draft.policy['apple']['hideVpnIcon'], isTrue);
    expect(
      draft.original.policy.toTun(ConnectionPlatform.ios).hideVpnIcon,
      isNull,
    );
    expect(stops, 0);
  });

  test('active VPN icon changes ask before reconnecting', () async {
    final service = PolicyEditorService(
      coordinator: coordinator,
      platform: ConnectionPlatform.ios,
    );
    final draft = await service.load();
    draft.policy['apple']['hideVpnIcon'] = true;
    host = HostConnection(
      VpnStatus.connected,
      runtime: _runtime(draft.original),
    );
    var confirmations = 0;
    expect(
      await service.save(
        draft: draft,
        confirm: (disconnect) async {
          confirmations++;
          expect(disconnect, isFalse);
          return false;
        },
      ),
      isFalse,
    );
    expect(confirmations, 1);
    expect(stops, 0);
    expect(
      (await coordinator.configuration).policy.toJson()['apple']['hideVpnIcon'],
      isFalse,
    );
  });

  test(
    'Apple exclusions save, trim fields and retain disabled lists',
    () async {
      final service = PolicyEditorService(
        coordinator: coordinator,
        platform: ConnectionPlatform.macos,
      );
      final draft = await service.load();
      draft.policy['apple']['excludedCidrs'] = [
        ' 10.250.0.0/16 ',
        '',
        '2001:db8::/64',
      ];
      final originalDraft = jsonEncode(draft.policy);
      expect(
        await service.save(draft: draft, confirm: (_) async => false),
        true,
      );
      expect(jsonEncode(draft.policy), originalDraft);
      var saved = await service.load();
      expect(saved.policy['apple']['excludedCidrs'], [
        '10.250.0.0/16',
        '2001:db8::/64',
      ]);
      saved.policy['apple']['captureAllTraffic'] = true;
      expect(
        await service.save(draft: saved, confirm: (_) async => false),
        true,
      );
      saved = await service.load();
      expect(saved.policy['apple']['excludedCidrs'], [
        '10.250.0.0/16',
        '2001:db8::/64',
      ]);
      expect(
        saved.original.policy.toTun(ConnectionPlatform.macos).excludedRoutes,
        isNull,
      );
      expect(stops, 0);
    },
  );

  test(
    'Apple exclusion changes require reconnect approval only when effective',
    () async {
      final service = PolicyEditorService(
        coordinator: coordinator,
        platform: ConnectionPlatform.ios,
      );
      final draft = await service.load();
      draft.policy['apple']['excludedCidrs'] = ['10.250.0.0/16'];
      final changed = service.prepare(draft).policy;
      expect(
        PolicyEditorService.sameRuntime(
          draft.original.policy,
          changed,
          ConnectionPlatform.ios,
        ),
        false,
      );
      host = HostConnection(
        VpnStatus.connected,
        runtime: _runtime(draft.original),
      );
      var confirmations = 0;
      expect(
        await service.save(
          draft: draft,
          confirm: (disconnect) async {
            confirmations++;
            expect(disconnect, false);
            return false;
          },
        ),
        false,
      );
      expect(confirmations, 1);
      expect(stops, 0);
      expect(
        (await coordinator.configuration).policy
            .toJson()['apple']['excludedCidrs'],
        isEmpty,
      );

      final inactive = PlatformPolicy.fromJson({
        'apple': {'captureAllTraffic': true},
      });
      final disabledDraft = PolicyEditorDraft(
        ConnectionConfiguration(policy: inactive),
      );
      disabledDraft.policy['apple']['excludedCidrs'] = ['invalid hidden draft'];
      expect(
        PolicyEditorService.sameRuntime(
          inactive,
          service.prepare(disabledDraft).policy,
          ConnectionPlatform.ios,
        ),
        true,
      );
      disabledDraft.policy['apple']['captureAllTraffic'] = false;
      expect(() => service.prepare(disabledDraft), throwsFormatException);
    },
  );

  test(
    'Windows uses full existing CIDR policy and never removes IPv6 conflicts',
    () {
      final service = PolicyEditorService(
        coordinator: coordinator,
        platform: ConnectionPlatform.windows,
        windowsMode: WindowsMode.msix,
      );
      final original = ConnectionConfiguration(
        policy: PlatformPolicy.fromJson({
          'xrayOutboundInterfaceName': 'Ethernet',
        }),
      );
      final draft = PolicyEditorDraft(original);
      draft.policy['windows']['excludedCidrs'] = [' 192.168.1.0/24 ', ''];
      expect(
        service
            .prepare(draft)
            .policy
            .toWindowsPolicy()
            .toJson()['excludedCidrs'],
        ['192.168.1.0/24'],
      );
      draft.policy['windows']['excludedCidrs'] = ['fd00::/64'];
      draft.policy['ipv6Enabled'] = false;
      expect(() => service.prepare(draft), throwsFormatException);
      expect(draft.policy['windows']['excludedCidrs'], ['fd00::/64']);
      draft.policy['windows']['excludedCidrs'] = ['192.168.1.1/24'];
      expect(() => service.prepare(draft), throwsFormatException);
    },
  );
}

ConnectionRuntime _runtime(
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
