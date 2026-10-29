import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/document.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/import.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/shared/share/app_link_model.dart';
import 'package:onexray/service/shared/share/app_link_parser.dart';

import '../../compiler_test.dart' show catalog, node, options;

Map<String, dynamic> template([int entries = 2]) => {
  'outbounds': [
    for (var i = 0; i < entries; i++) <String, dynamic>{},
    {
      'tag': 'reject',
      'protocol': 'blackhole',
      'settings': {
        'response': {'type': 'http'},
      },
    },
  ],
  'inbounds': [
    {
      'tag': 'tunIn',
      'sniffing': {
        'enabled': true,
        'routeOnly': true,
        'destOverride': ['http', 'tls'],
      },
    },
    {
      'tag': 'local-socks',
      'protocol': 'socks',
      'listen': '127.0.0.1',
      'port': 12080,
      'settings': {
        'auth': 'password',
        'users': [
          {'user': 'one', 'pass': 'one'},
          {'user': 'two', 'pass': 'two'},
        ],
        'udp': true,
      },
      'sniffing': {'enabled': false},
    },
  ],
  'dns': {
    'hosts': {
      'domain:example.test': ['192.0.2.1'],
    },
    'disableCache': true,
    'tag': 'dns',
    'servers': [
      {
        'tag': 'dns',
        'address': '1.1.1.1',
        'finalQuery': true,
        'timeoutMs': 1500,
      },
      '8.8.8.8',
    ],
  },
  'routing': {
    'domainStrategy': 'AsIs',
    'rules': [
      {
        'ruleTag': 'Keep this tag',
        'inboundTag': ['dns', 'local-socks'],
        'balancerTag': 'proxy',
      },
      {
        'domain': ['domain:example.test'],
        'localIP': ['127.0.0.1'],
        'localPort': 12080,
        'outboundTag': 'reject',
      },
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('advanced remains JSON, normal rejects its fields', () {
    final source = template();
    final state = AdvancedRoutingDocument.parse(
      jsonEncode(source),
      name: 'Custom',
    ).state;
    expect(state.advanced, true);
    expect(state.entryCount, 2);
    expect(state.ruleCount, 2);
    expect(state.toJson(), source);
    expect(jsonDecode(state.copyWith(name: 'Renamed').encode()), source);
    state.toJson()['outbounds'].clear();
    expect(state.toJson(), source);
    expect(
      () => RoutingProfileDocument.parse(jsonEncode(source)),
      throwsFormatException,
    );
  });

  test('node slots must be leading, empty and within 1–3', () {
    for (final slots in [
      [],
      [{}, {}, {}, {}],
      [
        {'protocol': 'vless'},
      ],
      [
        {},
        {'tag': 'a', 'protocol': 'freedom'},
        {},
      ],
    ]) {
      expect(
        () => AdvancedRoutingDocument.parse(jsonEncode({'outbounds': slots})),
        throwsFormatException,
      );
    }
    for (var i = 1; i <= 3; i++) {
      expect(
        AdvancedRoutingDocument.parse(jsonEncode(template(i))).state.entryCount,
        i,
      );
    }
  });

  test('Freedom FinalMask helpers retain native settings and entry links', () {
    final helper = <String, dynamic>{
      'tag': 'fragment',
      'protocol': 'freedom',
      'streamSettings': {
        'sockopt': {'dialerProxy': 'direct'},
        'finalmask': {
          'tcp': [
            {
              'type': 'fragment',
              'settings': {
                'packets': 'tlshello',
                'lengths': ['40-60', '100-200'],
                'delays': ['0-2', '10-20'],
                'maxSplit': '4-8',
              },
            },
          ],
          'udp': [
            {
              'type': 'noise',
              'settings': {
                'noise': [
                  {
                    'type': 'str',
                    'packet': 'controlled-fixture',
                    'delay': '1-2',
                  },
                ],
              },
            },
          ],
        },
      },
    };
    final source = template()..['outbounds'].add(helper);
    final original = JsonTool.copyMap(source);
    final state = AdvancedRoutingDocument.parse(jsonEncode(source)).state;
    expect(state.toJson(), original);
    expect(jsonDecode(state.encode()), original);
    final runtime = ConnectionCompiler.compile(
      settings: ConnectionSettings(trafficMode: TrafficMode.custom),
      custom: state,
      entries: [node(1), node(2)],
      regions: catalog,
      options: options(),
    ).config;
    final validation = jsonDecode(
      CustomRoutingService.validationJson(state),
    ) as Map<String, dynamic>;
    for (final config in [runtime, validation]) {
      final outbounds = (config['outbounds'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        outbounds.singleWhere((value) => value['tag'] == 'fragment'),
        helper,
      );
      for (final entry in outbounds.take(2)) {
        expect(entry['streamSettings']['sockopt']['dialerProxy'], 'fragment');
      }
    }
    expect(state.toJson(), original);
    expect(source, original);
  });

  test('advanced FinalMask ownership stays limited to Freedom helpers', () {
    for (final protocol in ['blackhole', 'dns']) {
      expect(
        () => AdvancedRoutingDocument.parse(
          jsonEncode({
            'outbounds': [
              {},
              {
                'tag': 'user-helper',
                'protocol': protocol,
                'streamSettings': {
                  'finalmask': {'tcp': []},
                },
              },
            ],
          }),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => AdvancedRoutingDocument.parse(
        jsonEncode({
          'outbounds': [
            {},
            {
              'tag': 'user-helper',
              'protocol': 'freedom',
              'streamSettings': {
                'network': 'tcp',
                'finalmask': {'tcp': []},
              },
            },
          ],
        }),
      ),
      throwsFormatException,
    );

    final delegated = {
      'outbounds': [
        {},
        {
          'tag': 'user-helper',
          'protocol': 'freedom',
          'streamSettings': {
            'finalmask': {
              'tcp': [
                {
                  'type': 'native-mask',
                  'settings': {'nativeParameter': true},
                },
              ],
            },
          },
        },
      ],
    };
    expect(
      AdvancedRoutingDocument.parse(jsonEncode(delegated)).state.toJson(),
      delegated,
    );
  });

  test('App-owned and excluded fields fail with their path', () {
    for (final key in ['env', 'log', 'policy', 'stats', 'metrics']) {
      expect(
        () =>
            AdvancedRoutingDocument.parse(jsonEncode({...template(), key: {}})),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'path',
            contains(key),
          ),
        ),
      );
    }
    for (final key in [
      'process',
      'sourceIP',
      'source',
      'sourcePort',
      'attrs',
      'user',
    ]) {
      final json = template();
      json['routing']['rules'][0][key] = [];
      expect(
        () => AdvancedRoutingDocument.parse(jsonEncode(json)),
        throwsFormatException,
      );
    }
    for (final tag in [
      'proxy',
      'direct',
      'block',
      'tunIn',
      'app-entry-0',
      'app-exit-1',
    ]) {
      final json = template();
      json['outbounds'][2]['tag'] = tag;
      expect(
        () => AdvancedRoutingDocument.parse(jsonEncode(json)),
        throwsFormatException,
      );
    }
    for (final patch in [
      (Map<String, dynamic> j) => j['observatory'] = {
        'subjectSelector': ['app-entry-0'],
      },
      (Map<String, dynamic> j) => j['dns']['queryStrategy'] = 'UseIP',
      (Map<String, dynamic> j) =>
          j['dns']['servers'][0]['queryStrategy'] = 'UseIPv6',
      (Map<String, dynamic> j) => j['routing']['balancers'] = [],
      (Map<String, dynamic> j) =>
          j['routing']['rules'][0]['balancerTag'] = 'other',
      (Map<String, dynamic> j) =>
          j['routing']['rules'][0]['outboundTag'] = 'app-entry-0',
      (Map<String, dynamic> j) => j['inbounds'][0]['settings'] = {},
      (Map<String, dynamic> j) => j['inbounds'][1]['protocol'] = 'tun',
      (Map<String, dynamic> j) =>
          j['inbounds'][1]['settings']['allowTransparent'] = true,
    ]) {
      final json = template();
      patch(json);
      expect(
        () => AdvancedRoutingDocument.parse(jsonEncode(json)),
        throwsFormatException,
      );
    }
  });

  test(
    'runtime preserves DNS, rules, accounts and sniffing on each platform',
    () {
      for (final platform in ConnectionPlatform.values) {
        final modes = platform == ConnectionPlatform.windows
            ? WindowsMode.values
            : [WindowsMode.exe];
        for (final windowsMode in modes) {
          for (final ipv6 in [false, true]) {
            final source = template(3);
            final state = AdvancedRoutingDocument.parse(jsonEncode(source))
                .state;
            final entries = [node(1), node(2), node(3)];
            final result = ConnectionCompiler.compile(
              settings: ConnectionSettings(trafficMode: TrafficMode.custom),
              custom: state,
              entries: entries,
              regions: catalog,
              options: options(
                platform: platform,
                windowsMode: windowsMode,
                ipv6: ipv6,
                interfaceName: 'Ethernet',
              ),
            );
            final runtime = result.config;
            expect(runtime['outbounds'].map((e) => e['tag']).toList(), [
              'app-entry-0',
              'app-entry-1',
              'app-entry-2',
              'reject',
              'direct',
              'block',
            ]);
            expect(runtime['routing']['rules'], source['routing']['rules']);
            expect(runtime['routing']['domainStrategy'], 'AsIs');
            expect(runtime['routing']['balancers'][0]['selector'], [
              'app-entry-0',
              'app-entry-1',
              'app-entry-2',
            ]);
            expect(runtime['routing']['balancers'][0]['fallbackTag'], 'direct');
            expect(
              runtime['inbounds'][0]['sniffing'],
              source['inbounds'][0]['sniffing'],
            );
            expect(runtime['inbounds'][1], source['inbounds'][1]);
            final expectedDns = JsonTool.copyMap(source['dns']);
            expectedDns['queryStrategy'] = ipv6 ? 'UseIP' : 'UseIPv4';
            expectedDns['servers'][0]['queryStrategy'] = ipv6
                ? 'UseIP'
                : 'UseIPv4';
            expect(runtime['dns'], expectedDns);
            expect(state.toJson(), source);
            expect(entries[0].outbound['tag'], 'Same user tag');
          }
        }
      }
    },
  );

  test('fixed node replaces the complete slot region without duplicating', () {
    final result = ConnectionCompiler.compile(
      settings: ConnectionSettings(
        trafficMode: TrafficMode.custom,
        selection: const ServerSelection.server(1),
      ),
      custom: AdvancedRoutingDocument.parse(jsonEncode(template(3))).state,
      entries: [node(1)],
      regions: catalog,
      options: options(),
    ).config;
    expect(result['outbounds'].length, 4);
    expect(result['routing']['balancers'][0]['selector'], ['app-entry-0']);
  });

  test('FakeDNS root aliases preserve pools and runtime recovery', () {
    for (final poolKey in ['fakeDns', 'fakedns']) {
      for (final pools in <dynamic>[
        {'ipPool': '198.19.0.0/16', 'poolSize': 1024},
        [
          {'ipPool': '198.19.0.0/16', 'poolSize': 1024},
        ],
      ]) {
        for (final explicit in [false, true]) {
          final source = <String, dynamic>{
            'outbounds': [{}],
            'dns': {
              'servers': ['9.9.9.9'],
            },
            poolKey: pools,
            if (explicit)
              'inbounds': [
                {
                  'tag': 'tunIn',
                  'sniffing': {'enabled': false},
                },
              ],
          };
          final original = jsonEncode(source);
          final state = AdvancedRoutingDocument.parse(original).state;
          expect(state.toJson(), source);
          expect(jsonDecode(state.encode()), source);

          final compiled = ConnectionCompiler.compile(
            settings: ConnectionSettings(trafficMode: TrafficMode.custom),
            custom: state,
            entries: [node(1)],
            regions: catalog,
            options: options(),
          ).config;
          expect(compiled[poolKey], pools);
          expect(
            compiled.containsKey(poolKey == 'fakeDns' ? 'fakedns' : 'fakeDns'),
            false,
          );
          if (explicit) {
            expect(compiled['inbounds'][0]['sniffing'], {'enabled': false});
          } else {
            expect(
              compiled['inbounds'][0]['sniffing']['destOverride'],
              contains('fakedns'),
            );
          }
          expect(state.toJson(), source);
          expect(jsonEncode(source), original);
        }
      }
    }
  });

  test(
    'FakeDNS preserves explicit pools and sniffing; defaults only when absent',
    () {
      for (final explicit in [false, true]) {
        final source = <String, dynamic>{
          'outbounds': [{}],
          'dns': {
            'servers': ['fakedns'],
          },
          'fakedns': [
            {'ipPool': '198.19.0.0/16', 'poolSize': 32768},
            {'ipPool': 'fc00:1::/64', 'poolSize': 32768},
          ],
          if (explicit)
            'inbounds': [
              {
                'tag': 'tunIn',
                'sniffing': {'enabled': false},
              },
            ],
        };
        final state = AdvancedRoutingDocument.parse(jsonEncode(source)).state;
        final compiled = ConnectionCompiler.compile(
          settings: ConnectionSettings(trafficMode: TrafficMode.custom),
          custom: state,
          entries: [node(1)],
          regions: catalog,
          options: options(),
        ).config;
        expect(compiled['fakedns'], source['fakedns']);
        expect(compiled['routing'].containsKey('rules'), false);
        if (explicit) {
          expect(compiled['inbounds'][0]['sniffing'], {'enabled': false});
        } else {
          expect(
            compiled['inbounds'][0]['sniffing']['destOverride'],
            contains('fakedns'),
          );
        }
        expect(state.toJson(), source);
      }
    },
  );

  test('validation fills slots, keeps advanced fields and uses harmless tun surrogate', () async {
    final source = template();
    final state = AdvancedRoutingDocument.parse(jsonEncode(source)).state;
    await CustomRoutingService.validate(
      state,
      testXray: (text) async {
        final json = jsonDecode(text);
        expect(json['routing']['rules'], source['routing']['rules']);
        expect(json['dns'], source['dns']);
        expect(json['inbounds'][0]['protocol'], 'socks');
        expect(
          json['inbounds'][0]['sniffing'],
          source['inbounds'][0]['sniffing'],
        );
        expect(json['inbounds'][1], source['inbounds'][1]);
        return '';
      },
    );
  });

  test(
    'advanced links round-trip and import into the shared routing table',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final transfers = ConfigurationTransferService(lookup: (_) async => null);
      final text = await transfers.shareLinks(
        kind: ConfigurationKind.customAdvanced,
        name: 'Advanced',
        text: jsonEncode(template()),
      );
      expect(
        (OneXrayAppLinkParser.parse(Uri.parse(text)) as OneXrayConfigLink).type,
        OneXrayConfigLinkType.customAdvanced,
      );
      expect(
        () => ConfigurationTransferService.read(text, ConfigurationKind.custom),
        throwsFormatException,
      );
      final imported = ConfigurationTransferService.read(
        text,
        ConfigurationKind.customAdvanced,
      );
      expect(jsonDecode(imported.text), template());
      final importer = ServerImportService(
        database: db,
        transfer: transfers,
        validate: (_) async => '',
        schedule: (_) {},
      );
      final preview = await importer.preview(text);
      addTearDown(preview.dispose);
      expect((await importer.commit(preview)).customCount, 1);
      final row = (await db.routingProfileDao.allRows).single;
      expect(row.advanced, true);
      expect(CustomRoutingService.readConfiguration(row).toJson(), template());
      final service = CustomRoutingService(db);
      await service.save(RoutingProfileState(name: 'Normal'));
      await service.save(
        AdvancedRoutingDocument.parse(
          jsonEncode(template()),
          name: 'Third',
        ).state,
      );
      await expectLater(
        service.save(RoutingProfileState(name: 'Fourth')),
        throwsA(anything),
      );
    },
  );

  test('Geodata scanning covers semantic fields, not account strings', () {
    final source = template();
    source['inbounds'][0]['sniffing']['domainsExcluded'] = [
      'ext:sniff-domains.dat:cn',
    ];
    source['inbounds'][0]['sniffing']['ipsExcluded'] = [
      '!ext:sniff-ip.dat:private',
    ];
    source['inbounds'][1]['settings']['users'][0]['pass'] =
        'ext:not-a-dependency.dat:cn';
    source['dns']['hosts'] = {
      'ext:hosts.dat:cn': ['192.0.2.1'],
    };
    source['outbounds'].add({
      'tag': 'dnsOut',
      'protocol': 'dns',
      'settings': {
        'rules': [
          {'action': 'hijack', 'domain': 'ext:dns.dat:cn'},
        ],
      },
    });
    expect(geoDataReferences(source), {
      'sniff-domains.dat': GeoDataType.domain,
      'sniff-ip.dat': GeoDataType.ip,
      'hosts.dat': GeoDataType.domain,
      'dns.dat': GeoDataType.domain,
    });
  });
}
