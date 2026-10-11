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
      utf8.encode('{\n "outbounds":[], "unknown":true\n}'),
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
    final routeData = [
      base64Encode(
        utf8.encode(
          RoutingProfileState(
            name: '普通路由',
            fragmentOutbound: fragmentOutbound,
          ).encode(),
        ),
      ),
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
          countryCode: const Value('CN'),
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
              RoutingDnsResolver(address: '1.1.1.1', expectedIPs: ['geoip:US']),
              RoutingDnsResolver(address: '9.9.9.9'),
            ],
            sameExitOnly: true,
            enableParallelQuery: true,
          ),
          sniffing: const RoutingSniffingSettings(
            metadataOnly: true,
            domainsExcluded: ['domain:example.com'],
          ),
          selection: const RoutingSelectionSettings(
            type: 'leastPing',
            probeInterval: '30s',
          ),
        ),
      ),
      policy: PlatformPolicy.fromJson({'ipv6Enabled': false}),
    );
    await db.connectionConfigDao.commit(configurationJson: original.encode());
    final document = await assets.capture();
    validateBackupAssets(document);
    expect(document.coreConfigs.length, 5);
    expect(document.coreConfigs.last.data, outbound);
    expect(document.routingProfiles.map((row) => row.data), routeData);
    expect(document.smartRouting.fragment, true);
    expect(jsonEncode(document.toJson()), isNot(contains('finalExitId')));
    expect(document.subscriptions.single.toJson(), {
      'name': 'Source',
      'url': 'https://example.com/sub',
      'ageSecretKey': 'secret-fixture',
      'agePublicKey': 'public-fixture',
      'hwidEnabled': false,
      'hwid': 'keep',
    });
    expect(document.geoData.single.name, 'blocked');
    final decoded = decodeBackup(encodeBackup(document));
    final preview = await geodata.previewRestore(backupSources(decoded));
    await assets.restore(decoded, preview);
    final restored = await db.coreConfigDao.allRawRowsWithData;
    expect(restored.length, 4);
    expect(
      restored.every(
        (row) =>
            row.id > 6 &&
            row.data == raw &&
            row.countryCode == null &&
            !row.favorite,
      ),
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
    expect(routes.every((row) => row.id > 2), true);
    expect((await db.geoDataDao.allRows).single.installed, false);
    expect((await assets.capture()).geoData.single.name, 'blocked');
  });
}
