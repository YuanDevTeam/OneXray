import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/service/servers/import.dart';

import '../../../support/fake_geodata_import.dart';
import '../../../support/xdrive_template_fixture.dart';

import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/document.dart';
import 'package:onexray/service/shared/share/app_link_generator.dart';
import 'package:onexray/service/shared/share/app_link_model.dart';
import 'package:onexray/service/shared/share/app_link_parser.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';

String template(String name, {bool assets = false}) => jsonEncode({
  'name': name,
  'outbounds': [{}, {}],
  'dns': {
    'servers': [
      {'tag': 'app-dns-direct', 'address': '1.1.1.1'},
      {'tag': 'app-dns-fake', 'address': 'fakedns'},
    ],
  },
  'routing': {
    'rules': [
      {
        'ruleTag': 'Local websites',
        'domain': [assets ? 'ext:rules.dat:cn' : 'domain:example.com'],
        'balancerTag': 'proxy',
      },
    ],
  },
  if (assets)
    'geodata': {
      'assets': [
        {'file': 'rules.dat', 'url': 'https://example.com/rules.dat'},
      ],
    },
});

void main() {
  test(
    'nameless Raw can enter the editor without rewriting its source',
    () async {
      const text = '  {"outbounds":[],"customRoot":true}\n';
      final content = ConfigurationTransferService.read(
        text,
        ConfigurationKind.raw,
      );
      final draft = await ConfigurationTransferService().prepare(content);
      expect(draft.name, '');
      expect(draft.text, text);
      expect(draft.content, same(content));
      expect(content.source.value, {'outbounds': [], 'customRoot': true});
      await draft.dispose();
    },
  );

  test(
    'IP geodata and extended conditions survive Custom JSON and link sharing',
    () async {
      final rule = {
        'ip': ['!ext:rules.dat:private'],
        'protocol': ['http'],
        'localOS': ['android', 'darwin'],
        'balancerTag': 'proxy',
      };
      final source = jsonEncode({
        'outbounds': [{}, {}],
        'routing': {
          'rules': [rule],
        },
      });
      final service = ConfigurationTransferService(
        lookup: (name) async => GeoDataData(
          installed: true,
          id: 1,
          name: name,
          type: 'ip',
          url: 'https://example.com/rules.dat',
          timestamp: DateTime(2026),
          categoryCount: 1,
          ruleCount: 1,
        ),
        prepare: (_) async => throw StateError('Sharing must not download'),
      );
      final exported = await service.exportJson(
        kind: ConfigurationKind.custom,
        name: 'Custom',
        text: source,
      );
      final decoded = jsonDecode(exported);
      expect(decoded['routing']['rules'], [rule]);
      expect(decoded['geodata']['assets'], [
        {'file': 'rules.dat', 'url': 'https://example.com/rules.dat'},
      ]);
      final link = await service.shareLinks(
        kind: ConfigurationKind.custom,
        name: 'Custom',
        text: source,
      );
      for (final text in [exported, link]) {
        final imported = ConfigurationTransferService.read(
          text,
          ConfigurationKind.custom,
        );
        expect(jsonDecode(imported.text)['routing']['rules'], [rule]);
        expect(jsonDecode(imported.text)['outbounds'], [{}, {}]);
        expect(jsonDecode(imported.text), isNot(contains('geodata')));
        expect(imported.assets.single.type, GeoDataType.ip);
        expect(imported.assets.single.fileName, 'rules.dat');
      }
    },
  );

  test('Raw geodata discovery includes source aliases, local IP and inverse IP rules', () {
    expect(
      geoDataReferences({
        'routing': {
          'rules': [
            {
              'source': ['ext:old-source.dat:private'],
            },
            {
              'sourceIP': ['!ext:source.dat:cn', 'geoip:private'],
              'source': ['ext:ignored-alias.dat:private'],
            },
            {
              'localIP': ['ext:local.dat:private'],
            },
            {
              'ip': ['!ext:target.dat:cn', 'ext:geoip.dat:cn'],
            },
            {
              'attrs': {':path': 'ext:not-data.dat:cn'},
            },
          ],
        },
      }),
      {
        'old-source.dat': GeoDataType.ip,
        'source.dat': GeoDataType.ip,
        'local.dat': GeoDataType.ip,
        'target.dat': GeoDataType.ip,
      },
    );
  });

  test('custom transfer consumes only its manifest and preserves native rule fields', () {
    final content = ConfigurationTransferService.read(
      template('Route', assets: true),
      ConfigurationKind.custom,
    );
    final json = jsonDecode(content.text) as Map<String, dynamic>;
    expect(json, isNot(contains('geodata')));
    expect(content.name, 'Route');
    expect(content.assets.single.fileName, 'rules.dat');
    expect(content.assets.single.type, GeoDataType.domain);
    expect(json['outbounds'], [{}, {}]);
    expect(
      (json['dns']['servers'] as List).singleWhere(
        (server) => server['tag'] == 'app-dns-direct',
      )['address'],
      '1.1.1.1',
    );
    expect(
      (json['dns']['servers'] as List).singleWhere(
        (server) => server['tag'] == 'app-dns-fake',
      )['address'],
      'fakedns',
    );
    expect(
      (json['dns']['servers'] as List).singleWhere(
        (server) => server['tag'] == 'app-dns-proxy',
      )['address'],
      '8.8.8.8',
    );
    expect(
      (json['routing']['rules'] as List).single['ruleTag'],
      'Local websites',
    );
    expect(
      () => ConfigurationTransferService.read(
        template(
          'Route',
        ).replaceFirst('"balancerTag"', '"source":["1.1.1.1"],"balancerTag"'),
        ConfigurationKind.custom,
      ),
      throwsFormatException,
    );
  });

  test('Raw source and independent source links round trip without formatting or double encoding', () async {
    const source =
        '  { "outbounds": [], "dns": {"servers":[{"domains":["ext:rules.dat:cn"]}]}, '
        '"routing":{"rules":[{"sourceIP":["192.0.2.0/24"],"sourcePort":1024,"outboundTag":"direct"}]}, '
        '"future": 123 }\n';
    final service = ConfigurationTransferService(
      lookup: (name) async => GeoDataData(
        installed: true,
        id: 1,
        name: name,
        type: 'domain',
        url: 'https://example.com/rules.dat',
        timestamp: DateTime(2026),
        categoryCount: 1,
        ruleCount: 1,
      ),
      prepare: (_) async => throw StateError('Export must not download'),
    );
    expect(
      await service.exportJson(
        kind: ConfigurationKind.raw,
        name: 'Metadata',
        text: source,
      ),
      source,
    );
    final text = await service.shareLinks(
      kind: ConfigurationKind.raw,
      name: 'Metadata',
      text: source,
    );
    expect(await service.sharingDataCount(source), 1);
    expect(await service.sharingDataCount('{"outbounds":[]}'), 0);
    final links = text
        .split('\n')
        .map(Uri.parse)
        .map(OneXrayAppLinkParser.parse)
        .whereType<OneXrayAppLink>()
        .toList();
    expect(links, hasLength(2));
    expect(links.first, isA<OneXrayGeoDataLink>());
    expect((links.last as OneXrayConfigLink).xrayJson, source);
    final read = ConfigurationTransferService.read(text, ConfigurationKind.raw);
    expect(read.text, source);
    expect(read.name, 'Metadata');
    expect(read.assets.single.fileName, 'rules.dat');
  });

  test(
    'Raw template JSON and source links preserve nested and unknown fields',
    () async {
      final source = jsonEncode({
        'name': 'Template',
        'outbounds': [xdriveTemplateOutbound()],
        'futureRoot': {'keep': true},
      });
      final service = ConfigurationTransferService(
        lookup: (_) async => null,
        prepare: (_) async => throw StateError('No dependencies'),
      );
      final exported = await service.exportJson(
        kind: ConfigurationKind.raw,
        name: 'Template',
        text: source,
      );
      final link = await service.shareLinks(
        kind: ConfigurationKind.raw,
        name: 'Template',
        text: source,
      );
      expect(exported, source);
      for (final input in [exported, link]) {
        final imported = ConfigurationTransferService.read(
          input,
          ConfigurationKind.raw,
        );
        expect(imported.text, source);
        expect(jsonDecode(imported.text), jsonDecode(source));
      }
    },
  );

  test(
    'Custom share uses type=custom with assets but never selected servers',
    () async {
      final service = ConfigurationTransferService(
        lookup: (_) async => null,
        prepare: (_) async => throw StateError('No dependencies'),
      );
      final text = await service.shareLinks(
        kind: ConfigurationKind.custom,
        name: 'Shared',
        text: template('Draft'),
      );
      final link =
          OneXrayAppLinkParser.parse(Uri.parse(text))! as OneXrayConfigLink;
      expect(link.type, OneXrayConfigLinkType.custom);
      expect(link.name, 'Shared');
      expect(jsonDecode(link.xrayJson)['name'], 'Shared');
      expect(jsonDecode(link.xrayJson)['outbounds'], [{}, {}]);
      final servers = jsonDecode(link.xrayJson)['dns']['servers'] as List;
      expect(
        servers.singleWhere(
          (server) => server['tag'] == 'app-dns-direct',
        )['address'],
        '1.1.1.1',
      );
      expect(
        servers.singleWhere(
          (server) => server['tag'] == 'app-dns-fake',
        )['address'],
        'fakedns',
      );
      expect(
        servers.singleWhere(
          (server) => server['tag'] == 'app-dns-proxy',
        )['address'],
        '8.8.8.8',
      );
    },
  );

  test('reference collection ignores arbitrary strings and rejects mixed file types and unsafe manifests', () {
    expect(geoDataReferences({'password': 'ext:secret.dat:cn'}), isEmpty);
    expect(
      () => geoDataReferences({
        'routing': {
          'rules': [
            {
              'domain': ['ext:same.dat:cn'],
              'ip': ['ext:same.dat:cn'],
            },
          ],
        },
      }),
      throwsFormatException,
    );
    for (final file in ['../rules.dat', 'rules.DAT', 'geosite.dat']) {
      expect(
        () => ConfigurationTransferService.read(
          template('Route', assets: true).replaceAll('rules.dat', file),
          ConfigurationKind.custom,
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'editor dependency metadata remains pending until caller commits',
    () async {
      var writes = 0;
      var disposed = 0;
      final service = ConfigurationTransferService(
        lookup: (_) async => null,
        prepare: (inputs) async => FakeGeoDataImport(
          writeMetadata: () async {
            writes++;
          },
          onDispose: () async {
            disposed++;
          },
        ),
      );
      final draft = await service.prepare(
        ConfigurationTransferService.read(
          template('Route', assets: true),
          ConfigurationKind.custom,
        ),
      );
      expect(writes, 0);
      final exported = jsonDecode(
        await service.exportJson(
          kind: ConfigurationKind.custom,
          name: draft.name,
          text: draft.text,
          assets: draft.content.assets,
        ),
      );
      expect(exported['geodata']['assets'].single['file'], 'rules.dat');
      await draft.save((writeMetadata) => writeMetadata());
      await draft.dispose();
      expect(writes, 1);
      expect(disposed, 1);
    },
  );

  test('common import previews Custom rather than nodes; batch limits roll back dependencies and configs', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final lifecycle = <String>[];
    final service = ServerImportService(
      database: db,
      parse: (_) async => throw StateError('Custom must not reach node parser'),
      validate: (_) async => '',
      schedule: (_) => throw StateError('Routes are not nodes'),
      transfer: ConfigurationTransferService(
        lookup: db.geoDataDao.searchRowByName,
        prepare: (inputs) async => FakeGeoDataImport(
          events: lifecycle,
          writeMetadata: () async {
            await db.geoDataDao.insertRow(
              GeoDataCompanion.insert(
                name: 'rules',
                type: 'domain',
                url: inputs.single.url,
                timestamp: DateTime(2026),
                categoryCount: 1,
                ruleCount: 1,
              ),
            );
          },
        ),
      ),
    );
    final first = await service.preview(template('One'));
    expect(first.count, 0);
    expect(first.rawCount, 0);
    expect(first.customRoutes.single.name, 'One');
    expect(await db.routingProfileDao.allRows, isEmpty);
    final result = await service.commit(first);
    expect(result.customCount, 1);
    await CustomRoutingService(db)
        .save(RoutingProfileDocument.parse(template('Two')).state);
    await CustomRoutingService(db)
        .save(RoutingProfileDocument.parse(template('Three')).state);
    final next = await service.preview(template('Fourth', assets: true));
    expect(await db.geoDataDao.allRows, isEmpty);
    await expectLater(
      service.commit(next),
      throwsA(
        isA<CustomRoutingEditorException>().having(
          (e) => e.reason,
          'reason',
          'limit',
        ),
      ),
    );
    expect(lifecycle, ['publish', 'commit', 'rollback']);
    expect(await db.geoDataDao.allRows, isEmpty);
    expect(await db.routingProfileDao.allRows, hasLength(3));
    await next.dispose();
  });

  test('type=custom rejects unsupported rules without falling back to Raw or node import', () async {
    final invalid = template('Route')
        .replaceFirst('"ruleTag"', '"inboundTag":["secret"],"ruleTag"');
    final link = OneXrayAppLinkGenerator.configurationText(
      OneXrayConfigLinkType.custom,
      'Route',
      invalid,
    );
    final service = ServerImportService(
      parse: (_) async => throw StateError('Unexpected fallback'),
    );
    final preview = await service.preview(link.toString());
    expect(preview.hasItems, false);
    await expectLater(service.commit(preview), throwsFormatException);
  });
}
