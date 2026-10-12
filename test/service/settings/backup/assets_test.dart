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
          ),
          sniffing: const RoutingSniffingSettings(metadataOnly: true),
          selection: const RoutingSelectionSettings(
            type: 'leastPing',
            probeInterval: '30s',
          ),
        ),
      ),
      policy: PlatformPolicy.fromJson({'ipv6Enabled': false}),
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
    expect(document.subscriptions.single.toJson(), {
      'name': 'Source',
      'panel': 'remnawave',
      'mode': 'providerManaged',
      'url': 'https://example.com/sub',
      'ageSecretKey': 'secret-fixture',
      'agePublicKey': 'public-fixture',
      'hwidEnabled': false,
      'hwid': 'keep',
    });
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
      RoutingProfileStateDb.readConfiguration(routes.last).toJson(),
      advanced,
    );
    expect(routes.every((row) => row.id > 2), true);
    expect((await db.geoDataDao.allRows).single.installed, false);
    final restoredSource = (await db.subscriptionDao.allRows).single;
    expect(restoredSource.panel, 'remnawave');
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
