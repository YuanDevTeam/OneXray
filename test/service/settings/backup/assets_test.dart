import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/backup/codec.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/state_db.dart';
import 'package:onexray/service/settings/backup/assets.dart';

void main() {
  test(
    'manual grouping survives capture and restore with new database identities',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final parent = await Directory('../references/onexray-tests').absolute
          .create(recursive: true);
      final root = await parent.createTemp('backup-manual-groups-');
      addTearDown(() => root.delete(recursive: true));
      final geodata = GeoDataService.forTesting(
        database: db,
        directory: '${root.path}/dat',
        download: (_, _) async => fail('Restore must stay offline'),
        count: (_, _, _) async => fail('Restore must not index resources'),
        copyBundled: (_) async => fail('No resource replacement'),
      );
      final assets = BackupAssets(db, geodata);
      final home = await db.manualServerGroupDao.insertRow(
        ManualServerGroupCompanion.insert(
          name: 'Home',
          sortOrder: const Value(2),
        ),
      );
      final empty = await db.manualServerGroupDao.insertRow(
        ManualServerGroupCompanion.insert(
          name: 'Empty',
          sortOrder: const Value(1),
        ),
      );
      final originalNodes = <int>[];
      for (final (name, group, order) in [
        ('Second', home, 2),
        ('First', home, 1),
        ('Ungrouped', null, 4),
      ]) {
        originalNodes.add(
          await db.coreConfigDao.insertRow(
            CoreConfigCompanion.insert(
              name: name,
              type: 'outbound',
              tags: '',
              data: const Value('e30='),
              delay: 100,
              subId: 0,
              favorite: const Value(true),
              manualGroupId: Value(group),
              manualSortOrder: Value(order),
            ),
          ),
        );
      }
      final document = decodeBackup(encodeBackup(await assets.capture()));
      expect(document.manualGroups.map((row) => row.name), ['Empty', 'Home']);
      expect(document.manualGroups.map((row) => row.key), ['g1', 'g2']);
      expect(document.coreConfigs.map((row) => row.manualGroupKey), [
        'g2',
        'g2',
        null,
      ]);
      expect(document.coreConfigs.map((row) => row.manualSortOrder), [2, 1, 4]);
      expect(document.manualGroups.first.toJson(), isNot(contains('id')));
      validateBackupAssets(document);
      await assets.restore(document, await geodata.previewRestore([]));
      final groups = await db.manualServerGroupDao.allRows;
      expect(groups.map((row) => row.name), ['Empty', 'Home']);
      expect(groups.map((row) => row.sortOrder), [1, 2]);
      expect(groups.every((row) => row.id > home && row.id > empty), true);
      final nodes = await db.coreConfigDao.allActiveServerRows();
      expect(nodes.every((row) => !originalNodes.contains(row.id)), true);
      expect(nodes.take(2).map((row) => row.manualGroupId), [
        groups.last.id,
        groups.last.id,
      ]);
      expect(nodes.last.manualGroupId, isNull);
      expect(nodes.map((row) => row.manualSortOrder), [2, 1, 4]);
      expect(nodes.every((row) => !row.favorite), true);
      final recaptured = await assets.capture();
      expect(
        recaptured.manualGroups.map((row) => row.toJson()),
        document.manualGroups.map((row) => row.toJson()),
      );
      expect(
        recaptured.coreConfigs.map((row) => row.toJson()),
        document.coreConfigs.map((row) => row.toJson()),
      );
      final legacyJson = document.toJson()..remove('manualGroups');
      for (final node in legacyJson['coreConfigs'] as List) {
        (node as Map).remove('manualGroupKey');
        node.remove('manualSortOrder');
      }
      final legacy = decodeBackup(
        Uint8List.fromList(utf8.encode(jsonEncode(legacyJson))),
      );
      await assets.restore(legacy, await geodata.previewRestore([]));
      expect(await db.manualServerGroupDao.allRows, isEmpty);
      final legacyNodes = await db.coreConfigDao.allActiveServerRows();
      expect(legacyNodes.map((row) => row.name), [
        'Second',
        'First',
        'Ungrouped',
      ]);
      expect(
        legacyNodes.every(
          (row) => row.manualGroupId == null && row.manualSortOrder == 0,
        ),
        true,
      );
    },
  );

  test('captures only configured assets and restores without IDs, files or network', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final parent = await Directory('../references/onexray-tests').absolute
        .create(recursive: true);
    final root = await parent.createTemp('backup-assets-');
    addTearDown(() => root.delete(recursive: true));
    final geodata = GeoDataService.forTesting(
      database: db,
      directory: '${root.path}/dat',
      download: (_, _) async => fail('No network during restore'),
      count: (_, _, _) async => fail('No resource indexing during restore'),
      copyBundled: (_) async =>
          fail('Startup prepares bundled data separately'),
    );
    final assets = BackupAssets(db, geodata);
    final raw = base64Encode(
      utf8.encode(
        '{\n "outbounds":[], "unknown":true, "dns":'
        '{"serveStale":true,"serveExpiredTTL":60,"enableParallelQuery":true,'
        '"servers":[{"address":"1.1.1.1","expectedIPs":["1.1.1.0/24"],'
        '"expectIPs":["9.9.9.0/24"],"unexpectedIPs":["192.0.2.0/24"],'
        '"serveStale":true,"serveExpiredTTL":60}]},"inbounds":['
        '{"tag":"tunIn","sniffing":{"enabled":true,'
        '"domainsExcluded":["domain:example.com"],"ipsExcluded":["192.168.0.0/16"]}}]\n}',
      ),
    );
    final fragmentOutbound = <String, dynamic>{
      'tag': 'fragment',
      'protocol': 'freedom',
      'settings': {
        'fragment': {
          'packets': 'tlshello',
          'length': '80-120',
          'interval': '1-4',
        },
      },
    };
    final advanced =
        jsonDecode(AdvancedRoutingProfile.defaultText) as Map<String, dynamic>;
    (advanced['outbounds'] as List).add(fragmentOutbound);
    final advancedDns = advanced['dns'] as Map<String, dynamic>;
    advancedDns.addAll(_retiredDnsRoot);
    (advancedDns['servers'] as List).single.addAll(_retiredDnsResolver);
    (advanced['inbounds'] as List).single['sniffing'].addAll(_retiredSniffing);
    final ordinary = RoutingProfileState(
      name: '普通路由',
      dns: const RoutingDnsSettings(
        nonAddressPolicy: NonAddressDnsPolicy.empty,
      ),
      fragmentOutbound: fragmentOutbound,
    );
    final legacyOrdinary = ordinary.toJson();
    final ordinaryDns = legacyOrdinary['dns'] as Map<String, dynamic>;
    ordinaryDns.addAll(_retiredDnsRoot);
    for (final server in (ordinaryDns['servers'] as List)) {
      server.addAll(_retiredDnsResolver);
    }
    (legacyOrdinary['inbounds'] as List).single['sniffing'].addAll(
      _retiredSniffing,
    );
    final routeData = [
      base64Encode(utf8.encode(jsonEncode(legacyOrdinary))),
      base64Encode(utf8.encode(jsonEncode(advanced))),
    ];
    for (var i = 0; i < routeData.length; i++) {
      await db.routingProfileDao.insertRow(
        RoutingProfileCompanion.insert(
          name: '路由 $i',
          advanced: Value(i == 1),
          data: routeData[i],
        ),
      );
    }
    for (var i = 0; i < 4; i++) {
      await db.coreConfigDao.insertRow(
        CoreConfigCompanion.insert(
          name: 'Raw $i',
          type: 'raw',
          tags: '',
          data: Value(raw),
          delay: 100,
          subId: 0,
          favorite: const Value(true),
        ),
      );
    }
    await db.coreConfigDao.insertRow(
      CoreConfigCompanion.insert(
        name: 'Cached',
        type: 'outbound',
        tags: '',
        data: Value(raw),
        delay: 100,
        subId: 42,
      ),
    );
    await db.coreConfigDao.insertRow(
      CoreConfigCompanion.insert(
        name: 'Old',
        type: 'setting',
        tags: '',
        data: Value(raw),
        delay: 0,
        subId: 0,
      ),
    );
    final outbound = base64Encode(
      utf8.encode('{ "tag":"手动节点", "protocol":"socks", "settings":{} }'),
    );
    await db.coreConfigDao.insertRow(
      CoreConfigCompanion.insert(
        name: '手动节点',
        type: 'outbound',
        tags: 'local',
        data: Value(outbound),
        delay: 100,
        subId: 0,
      ),
    );
    await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'Source',
        url: 'https://example.com/sub',
        userAgent: const Value('Example/test'),
        panel: const Value('remnawave'),
        mode: const Value('providerManaged'),
        ageSecretKey: const Value('secret-fixture'),
        agePublicKey: const Value('public-fixture'),
        hwid: const Value('keep'),
        hwidEnabled: const Value(false),
        timestamp: DateTime.now(),
        uploadBytes: const Value(100),
        downloadBytes: const Value(200),
        totalBytes: const Value(1000),
        expireTimestamp: const Value(1900000000),
        userInfoUpdatedAt: Value(DateTime.utc(2026, 9, 22)),
      ),
    );
    await db.geoDataDao.insertRow(
      GeoDataCompanion.insert(
        name: 'blocked',
        type: 'domain',
        url: 'https://example.com/blocked.dat',
        timestamp: DateTime.now(),
        categoryCount: 0,
        ruleCount: 0,
        installed: const Value(false),
      ),
    );
    final original = ConnectionConfiguration(
      connection: ConnectionSettings(
        expert: true,
        rawId: 1,
        smart: SmartRoutingSettings(
          finalExitId: 2,
          fragment: true,
          entryCount: 2,
          dns: const RoutingDnsSettings(
            proxyResolvers: [
              RoutingDnsResolver(address: '1.1.1.1'),
              RoutingDnsResolver(address: '9.9.9.9'),
            ],
            sameExitOnly: true,
            nonAddressPolicy: NonAddressDnsPolicy.direct,
          ),
          sniffing: const RoutingSniffingSettings(metadataOnly: true),
          selection: const RoutingSelectionSettings(
            type: 'leastPing',
            probeInterval: '30s',
          ),
        ),
      ),
      policy: PlatformPolicy.fromJson({
        'ipv6Enabled': false,
        'dialing': {'domainStrategy': 'ipv6First', 'happyEyeballs': true},
      }),
    );
    final legacySettings = original.toJson();
    final legacySmartDns = legacySettings['connection']['smart']['dns'] as Map;
    legacySmartDns.addAll(_retiredDnsRoot);
    (legacySmartDns['proxyResolvers'] as List).first.addAll(
      _retiredDnsResolver,
    );
    legacySettings['connection']['smart']['sniffing'].addAll(_retiredSniffing);
    await db.connectionConfigDao.commit(
      configurationJson: jsonEncode(legacySettings),
    );
    final document = await assets.capture();
    validateBackupAssets(document);
    expect(document.version, 1);
    expect(document.coreConfigs.length, 5);
    expect(document.coreConfigs.last.data, outbound);
    expect(document.routingProfiles.map((row) => row.data), routeData);
    expect(document.smartRouting.fragment, true);
    expect(document.smartRouting.dns, original.connection.smart.dns.toJson());
    expect(
      document.smartRouting.sniffing,
      original.connection.smart.sniffing.toJson(),
    );
    expect(jsonEncode(document.toJson()), isNot(contains('finalExitId')));
    expect(document.toJson(), isNot(contains('dialing')));
    expect(document.smartRouting.toJson(), isNot(contains('dialing')));
    expect(document.subscriptions.single.toJson(), {
      'name': 'Source',
      'panel': 'remnawave',
      'mode': 'providerManaged',
      'url': 'https://example.com/sub',
      'userAgent': 'Example/test',
      'ageSecretKey': 'secret-fixture',
      'agePublicKey': 'public-fixture',
      'hwidEnabled': false,
      'hwid': 'keep',
    });
    final legacyUserAgent = document.toJson();
    ((legacyUserAgent['subscriptions'] as List).single as Map).remove(
      'userAgent',
    );
    final decodedLegacy = decodeBackup(
      Uint8List.fromList(utf8.encode(jsonEncode(legacyUserAgent))),
    );
    expect(decodedLegacy.subscriptions.single.userAgent, isNull);
    validateBackupAssets(decodedLegacy);
    final invalidUserAgent = document.toJson();
    ((invalidUserAgent['subscriptions'] as List).single as Map)['userAgent'] =
        'Example/test\r\nX-Test: value';
    expect(
      () => validateBackupAssets(
        decodeBackup(
          Uint8List.fromList(utf8.encode(jsonEncode(invalidUserAgent))),
        ),
      ),
      throwsFormatException,
    );
    for (final key in ['panel', 'mode']) {
      final invalid = document.toJson();
      ((invalid['subscriptions'] as List).single as Map<String, dynamic>)[key] =
          'unsupported';
      final decodedInvalid = decodeBackup(
        Uint8List.fromList(utf8.encode(jsonEncode(invalid))),
      );
      expect(() => validateBackupAssets(decodedInvalid), throwsFormatException);
    }
    expect(document.geoData.single.name, 'blocked');
    final legacySnapshot =
        jsonDecode(utf8.decode(encodeBackup(document))) as Map<String, dynamic>;
    final backupDns = legacySnapshot['smartRouting']['dns'] as Map;
    backupDns.addAll(_retiredDnsRoot);
    (backupDns['proxyResolvers'] as List).first.addAll(_retiredDnsResolver);
    legacySnapshot['smartRouting']['sniffing'].addAll(_retiredSniffing);
    final decoded = decodeBackup(
      Uint8List.fromList(utf8.encode(jsonEncode(legacySnapshot))),
    );
    validateBackupAssets(decoded);
    final preview = await geodata.previewRestore(backupSources(decoded));
    await assets.restore(decoded, preview);
    final restored = await db.coreConfigDao.allRawRowsWithData;
    expect(restored.length, 4);
    expect(
      restored.every((row) => row.id > 6 && row.data == raw && !row.favorite),
      true,
    );
    final connection = ConnectionConfiguration.fromJson(
      jsonDecode((await db.connectionConfigDao.read()).configurationJson)
          as Map<String, dynamic>,
    );
    expect(connection.connection.expert, false);
    expect(connection.connection.smart.finalExitId, null);
    expect(connection.connection.smart.fragment, true);
    expect(
      connection.connection.smart.dns.toJson(),
      original.connection.smart.dns.toJson(),
    );
    expect(
      connection.connection.smart.sniffing.toJson(),
      original.connection.smart.sniffing.toJson(),
    );
    expect(
      connection.connection.smart.selection.toJson(),
      original.connection.smart.selection.toJson(),
    );
    expect(document.smartRouting.directDnsAddress, isNull);
    expect(connection.policy.toJson(), original.policy.toJson());
    expect(
      connection.policy.dialing.toJson(),
      original.policy.dialing.toJson(),
    );
    final subscription = (await db.subscriptionDao.allRows).single;
    expect(subscription.hwid, 'keep');
    expect(subscription.ageSecretKey, 'secret-fixture');
    expect(subscription.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
    expect(subscription.uploadBytes, isNull);
    expect(subscription.downloadBytes, isNull);
    expect(subscription.totalBytes, isNull);
    expect(subscription.expireTimestamp, isNull);
    expect(subscription.userInfoUpdatedAt, isNull);
    final routes = await db.routingProfileDao.allRows;
    expect(routes.map((row) => row.data), routeData);
    expect(routes.map((row) => row.advanced), [false, true]);
    expect(
      RoutingProfileStateDb.read(routes.first).toJson(),
      ordinary.toJson(),
    );
    expect(
      RoutingProfileStateDb.read(routes.first).dns.nonAddressPolicy,
      NonAddressDnsPolicy.empty,
    );
    expect(
      RoutingProfileStateDb.readConfiguration(routes.last).toJson(),
      advanced,
    );
    expect(routes.every((row) => row.id > 2), true);
    expect((await db.geoDataDao.allRows).single.installed, false);
    final restoredSource = (await db.subscriptionDao.allRows).single;
    expect(restoredSource.panel, 'remnawave');
    expect(restoredSource.userAgent, 'Example/test');
    expect(restoredSource.mode, 'providerManaged');
    final recaptured = await assets.capture();
    expect(recaptured.geoData.single.name, 'blocked');
    expect(recaptured.smartRouting.dns, original.connection.smart.dns.toJson());
    expect(
      recaptured.smartRouting.sniffing,
      original.connection.smart.sniffing.toJson(),
    );
    expect(recaptured.routingProfiles.map((row) => row.data), routeData);
  });

  group('platform-scoped settings', () {
    late AppDatabase db;
    late GeoDataService geodata;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final parent = await Directory('../references/onexray-tests').absolute
          .create(recursive: true);
      final root = await parent.createTemp('backup-platform-settings-');
      addTearDown(() => root.delete(recursive: true));
      geodata = GeoDataService.forTesting(
        database: db,
        directory: '${root.path}/dat',
        download: (_, _) async => fail('Restore must stay offline'),
        count: (_, _, _) async => fail('No indexing during restore'),
        copyBundled: (_) async => fail('No default resource replacement'),
      );
    });

    Future<void> savePolicy(PlatformPolicy policy) =>
        db.connectionConfigDao.commit(
          configurationJson: ConnectionConfiguration(policy: policy).encode(),
        );

    Future<PlatformPolicy> readPolicy() async =>
        ConnectionConfiguration.fromJson(
          jsonDecode((await db.connectionConfigDao.read()).configurationJson)
              as Map<String, dynamic>,
        ).policy;

    for (final scope in ['included', 'excluded']) {
      test(
        'Android $scope capture restores both package lists and portable settings',
        () async {
          final source = PlatformPolicy.fromJson({
            'ipv6Enabled': false,
            'dnsIpv4Address': '1.1.1.1',
            'dnsIpv6Address': '2606:4700:4700::1111',
            'dnsServerName': 'cloudflare-dns.com',
            'dialing': {'domainStrategy': 'ipv4First', 'happyEyeballs': true},
            'lanProxy': {'enabled': true, 'port': 12044},
            'log': {
              'enabled': true,
              'level': 'debug',
              'recordDns': false,
              'maskIp': false,
            },
            'xrayOutboundInterfaceName': 'Source interface',
            'android': {
              'appScope': scope,
              'includedAppPackageNames': [
                'net.example.included',
                'net.example.notInstalled',
              ],
              'excludedAppPackageNames': ['net.example.excluded'],
            },
            'apple': {'alwaysOn': true},
            'windows': {'alwaysOn': true},
          });
          await savePolicy(source);
          final assets = BackupAssets(
            db,
            geodata,
            platform: ConnectionPlatform.android,
          );
          final document = decodeBackup(encodeBackup(await assets.capture()));
          expect(document.platformSettings!.keys, ['android']);
          final platform = document.platformSettings!['android'] as Map;
          expect(platform['android'], source.toJson()['android']);
          expect(platform, isNot(contains('xrayOutboundInterfaceName')));
          expect(platform, isNot(contains('apple')));
          expect(platform, isNot(contains('windows')));

          final target = PlatformPolicy.fromJson({
            'xrayOutboundInterfaceName': 'Target interface',
            'android': {
              'appScope': 'all',
              'includedAppPackageNames': ['net.example.oldIncluded'],
              'excludedAppPackageNames': ['net.example.oldExcluded'],
            },
            'apple': {'captureAllTraffic': true},
            'windows': {'allowLocalNetwork': false},
          });
          await savePolicy(target);
          await assets.restore(document, await geodata.previewRestore([]));
          expect((await readPolicy()).toJson(), {
            ...source.toJson(),
            'xrayOutboundInterfaceName': 'Target interface',
            'apple': target.toJson()['apple'],
            'windows': target.toJson()['windows'],
          });
          expect(
            (await assets.capture()).platformSettings,
            document.platformSettings,
          );
        },
      );
    }

    for (final (sourcePlatform, targetPlatform) in [
      (ConnectionPlatform.android, ConnectionPlatform.windows),
      (ConnectionPlatform.ios, ConnectionPlatform.macos),
      (ConnectionPlatform.macos, ConnectionPlatform.ios),
    ]) {
      test(
        '$sourcePlatform settings do not replace $targetPlatform policy',
        () async {
          await savePolicy(
            PlatformPolicy.fromJson({
              'ipv6Enabled': false,
              'android': {
                'appScope': 'excluded',
                'excludedAppPackageNames': ['net.example.source'],
              },
              'apple': {'alwaysOn': true},
              'windows': {'alwaysOn': true},
            }),
          );
          final id = await db.coreConfigDao.insertRow(
            CoreConfigCompanion.insert(
              name: 'Shared asset',
              type: 'raw',
              tags: '',
              data: const Value('e30='),
              delay: 0,
              subId: 0,
            ),
          );
          final sourceAssets = BackupAssets(
            db,
            geodata,
            platform: sourcePlatform,
          );
          final document = decodeBackup(
            encodeBackup(await sourceAssets.capture()),
          );
          final target = PlatformPolicy.fromJson({
            'xrayOutboundInterfaceName': 'Target interface',
            'android': {
              'appScope': 'included',
              'includedAppPackageNames': ['net.example.target'],
            },
            'apple': {'captureAllTraffic': true},
            'windows': {'allowLocalNetwork': false},
          });
          await savePolicy(target);
          await BackupAssets(
            db,
            geodata,
            platform: targetPlatform,
          ).restore(document, await geodata.previewRestore([]));
          expect((await readPolicy()).toJson(), target.toJson());
          final restored = (await db.coreConfigDao.allRawRowsWithData).single;
          expect(restored.name, 'Shared asset');
          expect(restored.id, greaterThan(id));
        },
      );
    }

    test('legacy v1 without platform settings preserves the complete target policy', () async {
      final assets = BackupAssets(
        db,
        geodata,
        platform: ConnectionPlatform.android,
      );
      final snapshot = (await assets.capture()).toJson()
        ..remove('platformSettings');
      final legacy = decodeBackup(
        Uint8List.fromList(utf8.encode(jsonEncode(snapshot))),
      );
      final target = PlatformPolicy.fromJson({
        'ipv6Enabled': false,
        'xrayOutboundInterfaceName': 'Target interface',
        'android': {
          'appScope': 'excluded',
          'excludedAppPackageNames': ['net.example.target'],
        },
      });
      await savePolicy(target);
      await assets.restore(legacy, await geodata.previewRestore([]));
      expect((await readPolicy()).toJson(), target.toJson());
    });

    test('partial matching settings recursively preserve fields absent from the backup', () async {
      final target = PlatformPolicy.fromJson({
        'ipv6Enabled': false,
        'android': {
          'appScope': 'excluded',
          'includedAppPackageNames': ['net.example.keepIncluded'],
          'excludedAppPackageNames': ['net.example.keepExcluded'],
        },
      });
      await savePolicy(target);
      final assets = BackupAssets(
        db,
        geodata,
        platform: ConnectionPlatform.android,
      );
      final snapshot = (await assets.capture()).toJson();
      snapshot['platformSettings'] = {
        'android': {
          'android': {'appScope': 'included'},
        },
      };
      final document = decodeBackup(
        Uint8List.fromList(utf8.encode(jsonEncode(snapshot))),
      );
      await assets.restore(document, await geodata.previewRestore([]));
      final expected = target.toJson();
      (expected['android'] as Map)['appScope'] = 'included';
      expect((await readPolicy()).toJson(), expected);
    });
  });
}

const _retiredDnsRoot = {
  'serveStale': true,
  'serveExpiredTTL': 60,
  'enableParallelQuery': true,
};
const _retiredDnsResolver = {
  'timeoutMs': 4000,
  'disableCache': false,
  'expectedIPs': ['1.1.1.0/24'],
  'expectIPs': ['9.9.9.0/24'],
  'unexpectedIPs': ['192.0.2.0/24'],
  'serveStale': true,
  'serveExpiredTTL': 60,
};

const _retiredSniffing = {
  'domainsExcluded': ['domain:example.com'],
  'ipsExcluded': ['192.168.0.0/16'],
};
