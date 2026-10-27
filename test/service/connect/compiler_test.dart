import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/shared/xray/runtime_inbounds.dart';
import 'package:onexray/service/shared/xray/remnawave.dart';

import '../../support/xdrive_template_fixture.dart';

final catalog = RegionCatalog.fromJson(
  {
    'geosite': {
      'CN': ['CN'],
      'RU': ['CATEGORY-RU'],
    },
    'geoip': {
      'CN': ['CN'],
      'RU': ['RU'],
      'US': ['US'],
    },
  },
  geositeCodes: ['CN', 'CATEGORY-RU'],
  geoipCodes: ['CN', 'RU', 'US'],
);

RuntimeOptions options({
  ConnectionPlatform platform = ConnectionPlatform.android,
  WindowsMode windowsMode = WindowsMode.exe,
  bool ipv6 = true,
  String interfaceName = '',
  String tunDnsIpv4Address = '8.8.8.8',
  String tunDnsIpv6Address = '2001:4860:4860::8888',
  bool lanProxyEnabled = false,
  int lanProxyPort = defaultLanProxyPort,
}) => RuntimeOptions(
  platform: platform,
  windowsMode: windowsMode,
  sessionDirectory: '/unused-session',
  metricsPort: 18186,
  socksPort: 18187,
  ipv6: ipv6,
  interfaceName: interfaceName,
  tunDnsIpv4Address: tunDnsIpv4Address,
  tunDnsIpv6Address: tunDnsIpv6Address,
  lanProxyEnabled: lanProxyEnabled,
  lanProxyPort: lanProxyPort,
);

ResolvedServer node(int id, {String? address}) => ResolvedServer(
  id: id,
  sourceId: 1,
  outbound: {
    'tag': 'Same user tag',
    'protocol': address == null ? 'freedom' : 'socks',
    if (address != null) 'settings': {'address': address, 'port': 12345},
  },
);

void main() {
  test('copying a provider profile into personal Raw retains its tunnel routing semantics', () {
    final source = <String, dynamic>{
      'inbounds': [
        {'tag': 'provider', 'protocol': 'http', 'port': 1080},
      ],
      'dns': {
        'servers': ['1.1.1.1'],
      },
      'outbounds': [
        {'tag': 'first', 'protocol': 'freedom'},
      ],
      'routing': {
        'rules': [
          {
            'inboundTag': ['provider'],
            'outboundTag': 'first',
          },
        ],
      },
    };
    final profile = ResolvedProfile(
      id: 99,
      sourceId: 7,
      name: 'Provider',
      config: source,
    );
    final copied = RemnawaveAdapter.adapt(source)..['name'] = 'Personal Raw';
    final provider = ConnectionCompiler.compile(
      settings: ConnectionSettings(selection: const ServerSelection.server(99)),
      entries: const [],
      profile: profile,
      regions: catalog,
      options: options(),
    ).config;
    final raw = ConnectionCompiler.compile(
      settings: ConnectionSettings(expert: true),
      entries: const [],
      raw: copied,
      regions: catalog,
      options: options(),
    ).config..remove('name');
    expect(raw, provider);
    expect(copied.containsKey('metrics'), isFalse);
    expect(copied.containsKey('log'), isFalse);
    expect(copied.containsKey('env'), isFalse);
    expect((source['inbounds'] as List).single['tag'], 'provider');
  });

  test('provider profiles bypass App routes and keep the complete graph on every platform', () {
    final source = <String, dynamic>{
      'remarks': 'Provider',
      'inbounds': [
        {
          'tag': 'provider',
          'protocol': 'socks',
          'port': 1080,
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls'],
          },
        },
      ],
      'dns': {
        'servers': ['1.1.1.1'],
        'disableCache': true,
      },
      'fakedns': [
        {'ipPool': 'fc00:1::/64', 'poolSize': 1024},
      ],
      'outbounds': [
        {
          'tag': 'edge',
          'protocol': 'socks',
          'streamSettings': {
            'sockopt': {'dialerProxy': 'last'},
          },
        },
        {'tag': 'last', 'protocol': 'freedom'},
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {
            'inboundTag': ['provider'],
            'ip': ['203.0.113.0/24'],
            'balancerTag': 'provider-pool',
          },
        ],
        'balancers': [
          {
            'tag': 'provider-pool',
            'selector': ['edge'],
            'fallbackTag': 'last',
            'strategy': {'type': 'leastPing'},
          },
        ],
      },
      'observatory': {
        'subjectSelector': ['edge'],
        'probeURL': 'https://example.com/probe',
      },
    };
    final before = jsonEncode(source);
    final profile = ResolvedProfile(
      id: 99,
      sourceId: 7,
      name: 'Row metadata',
      config: source,
    );
    for (final platform in ConnectionPlatform.values) {
      final compiled = ConnectionCompiler.compile(
        settings: ConnectionSettings(
          selection: const ServerSelection.server(99),
          trafficMode: TrafficMode.custom,
          smart: SmartRoutingSettings(
            entryCount: 3,
            finalExitId: 123,
            fakeDns: true,
            fragment: true,
            blockAds: true,
          ),
        ),
        entries: const [],
        profile: profile,
        regions: catalog,
        options: options(
          platform: platform,
          windowsMode: WindowsMode.msix,
          interfaceName: 'Ethernet',
          lanProxyEnabled: true,
        ),
      );
      final actual = compiled.config;
      expect(compiled.profile, same(profile));
      expect(compiled.entries, isEmpty);
      expect(compiled.nodeTags, isEmpty);
      expect(actual['routing']['domainStrategy'], 'IPIfNonMatch');
      expect(actual['routing']['balancers'], source['routing']['balancers']);
      expect(actual['observatory'], source['observatory']);
      final rules = actual['routing']['rules'] as List;
      expect(rules, hasLength(2));
      expect(rules.first['outboundTag'], 'app-remna-dns');
      expect(rules.last['inboundTag'], ['provider', 'tunIn']);
      expect(rules.last['balancerTag'], 'provider-pool');
      final outbounds = actual['outbounds'] as List;
      expect(outbounds.map((value) => value['tag']), [
        'edge',
        'last',
        'direct',
        'block',
        'app-vpn-dns-direct',
        'app-remna-dns',
      ]);
      expect(
        outbounds.first['streamSettings']['sockopt']['dialerProxy'],
        'last',
      );
      expect(actual['dns']['disableCache'], isTrue);
      expect(actual['fakedns'], source['fakedns']);
      expect(actual['metrics']['listen'], '127.0.0.1:18186');
      expect(actual['stats'], isEmpty);
      final inbounds = actual['inbounds'] as List;
      expect(inbounds.where((value) => value['tag'] == 'tunIn'), hasLength(1));
      expect(
        inbounds.where((value) => value['tag'] == lanProxyInboundTag),
        isEmpty,
      );
      expect(
        inbounds.first['protocol'],
        platform == ConnectionPlatform.windows ? 'socks' : 'tun',
      );
      expect(
        inbounds.first['sniffing'],
        (source['inbounds'] as List).single['sniffing'],
      );
    }
    expect(jsonEncode(source), before);
  });

  test('provider tunnel and DNS policies pass through shared Raw platform compilation', () {
    final source = <String, dynamic>{
      'inbounds': [
        {
          'tag': 'provider-http',
          'protocol': 'http',
          'port': 12080,
          'sniffing': {'enabled': true},
        },
        {
          'tag': 'provider-tun',
          'protocol': 'tun',
          'settings': {
            'name': 'ProviderTun',
            'mtu': 1234,
            'gateway': ['192.0.2.1/24'],
            'autoOutboundsInterface': 'ProviderInterface',
            'userLevel': 5,
            'autoSystemDnsToGateway': true,
          },
          'sniffing': {'enabled': false, 'routeOnly': true},
        },
      ],
      'dns': {
        'servers': ['1.1.1.1'],
      },
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'socks',
          'streamSettings': {
            'sockopt': {
              'interface': 'ProviderInterface',
              'dialerProxy': 'direct',
            },
          },
        },
        {
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': {'domainStrategy': 'UseIPv4'},
        },
        {'tag': 'block', 'protocol': 'blackhole'},
        {
          'tag': 'provider-dns',
          'protocol': 'dns',
          'settings': {'address': '9.9.9.9', 'port': 5353},
          'streamSettings': {
            'sockopt': {'interface': 'ProviderDnsInterface'},
          },
        },
      ],
      'routing': {
        'rules': [
          {
            'type': 'field',
            'inboundTag': ['provider-tun'],
            'port': '53',
            'outboundTag': 'provider-dns',
          },
          {
            'type': 'field',
            'inboundTag': ['provider-tun'],
            'network': 'tcp,udp',
            'outboundTag': 'proxy',
          },
        ],
      },
    };
    final before = jsonEncode(source);
    final profile = ResolvedProfile(
      id: 99,
      sourceId: 7,
      name: 'Provider',
      config: source,
    );
    for (final (platform, windowsMode) in [
      (ConnectionPlatform.linux, WindowsMode.exe),
      (ConnectionPlatform.windows, WindowsMode.exe),
      (ConnectionPlatform.windows, WindowsMode.msix),
    ]) {
      final config = ConnectionCompiler.compile(
        settings: ConnectionSettings(
          selection: const ServerSelection.server(99),
        ),
        entries: const [],
        profile: profile,
        regions: catalog,
        options: options(
          platform: platform,
          windowsMode: windowsMode,
          interfaceName: 'Ethernet',
          ipv6: false,
        ),
      ).config;
      final inbounds = config['inbounds'] as List;
      expect(inbounds, hasLength(2));
      expect(inbounds.first, source['inbounds'][0]);
      final tunnel = inbounds.last;
      expect(tunnel['tag'], 'tunIn');
      expect(tunnel['sniffing'], source['inbounds'][1]['sniffing']);
      if (windowsMode == WindowsMode.msix) {
        expect(tunnel['protocol'], 'socks');
        expect(tunnel['port'], '18187');
        expect(tunnel['settings'], {'auth': 'noauth', 'udp': true});
      } else {
        expect(tunnel['protocol'], 'tun');
        expect(tunnel['settings']['name'], 'OneXrayTun');
        expect(tunnel['settings']['mtu'], VpnConstants.tunMtu);
        expect(tunnel['settings']['gateway'], ['198.18.0.1/15']);
        expect(tunnel['settings']['autoOutboundsInterface'], 'Ethernet');
        expect(tunnel['settings']['userLevel'], 5);
        expect(tunnel['settings']['autoSystemDnsToGateway'], true);
      }
      final rules = config['routing']['rules'] as List;
      expect(rules, hasLength(2));
      expect(rules.first, {
        ...source['routing']['rules'][0] as Map<String, dynamic>,
        'inboundTag': ['tunIn'],
      });
      expect(rules.last['inboundTag'], ['tunIn']);
      expect(rules.last['outboundTag'], 'proxy');
      final outbounds = config['outbounds'] as List;
      expect(outbounds.map((value) => value['tag']), [
        'proxy',
        'direct',
        'block',
        'provider-dns',
      ]);
      expect(outbounds.first['streamSettings']['sockopt'], {
        'interface': 'Ethernet',
        'dialerProxy': 'direct',
      });
      expect(
        outbounds[1]['streamSettings']['sockopt']['interface'],
        'Ethernet',
      );
      expect(outbounds[1]['settings'], source['outbounds'][1]['settings']);
      expect(outbounds.last, source['outbounds'][3]);
    }
    expect(jsonEncode(source), before);
  });

  test(
    'provider compilation supports automatic or matching scoped selections',
    () {
      final profile = ResolvedProfile(
        id: 99,
        sourceId: 7,
        name: 'Provider',
        config: {
          'outbounds': [
            {'tag': 'first', 'protocol': 'freedom'},
          ],
        },
      );
      for (final selection in [
        const ServerSelection.automatic(),
        const ServerSelection.source(7),
        const ServerSelection.server(99),
      ]) {
        final compiled = ConnectionCompiler.compile(
          settings: ConnectionSettings(
            selection: selection,
            smart: SmartRoutingSettings(entryCount: 3, finalExitId: 123),
          ),
          entries: const [],
          profile: profile,
          regions: catalog,
          options: options(),
        );
        expect(compiled.profile, same(profile));
        expect(compiled.entries, isEmpty);
        expect(compiled.finalExit, isNull);
        expect(compiled.nodeTags, isEmpty);
      }
      for (final settings in [
        ConnectionSettings(selection: const ServerSelection.source(0)),
        ConnectionSettings(selection: const ServerSelection.source(8)),
        ConnectionSettings(selection: const ServerSelection.server(98)),
        ConnectionSettings(
          expert: true,
          selection: const ServerSelection.server(99),
        ),
      ]) {
        expect(
          () => ConnectionCompiler.compile(
            settings: settings,
            entries: const [],
            profile: profile,
            regions: catalog,
            options: options(),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => ConnectionCompiler.compile(
          settings: ConnectionSettings(
            selection: const ServerSelection.server(99),
          ),
          entries: [node(1)],
          profile: profile,
          regions: catalog,
          options: options(),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'LAN sharing adds one mixed SOCKS inbound without changing selected routes',
    () {
      final raw = <String, dynamic>{
        'inbounds': [
          {
            'tag': 'user-http',
            'protocol': 'http',
            'listen': '127.0.0.1',
            'port': 12080,
            'sniffing': {'enabled': false},
          },
        ],
        'outbounds': [
          {'tag': 'user-direct', 'protocol': 'freedom'},
        ],
        'routing': {
          'rules': [
            {
              'inboundTag': ['user-http'],
              'outboundTag': 'user-direct',
            },
          ],
        },
      };
      final advanced = AdvancedRoutingDocument.fromJson({
        'outbounds': [<String, dynamic>{}],
        'inbounds': raw['inbounds'],
        'routing': {
          'rules': [
            {
              'inboundTag': ['user-http'],
              'balancerTag': 'proxy',
            },
          ],
        },
      }).state;
      final rawBefore = jsonEncode(raw);
      final advancedBefore = advanced.encode();
      for (final platform in ConnectionPlatform.values) {
        for (final kind in ['smart', 'custom', 'allVpn', 'advanced']) {
          final settings = ConnectionSettings(
            trafficMode: switch (kind) {
              'custom' || 'advanced' => TrafficMode.custom,
              'allVpn' => TrafficMode.allVpn,
              _ => TrafficMode.smart,
            },
          );
          Map<String, dynamic> compile(bool enabled) =>
              ConnectionCompiler.compile(
                settings: settings,
                entries: [node(1)],
                custom: kind == 'advanced'
                    ? advanced
                    : RoutingProfileState(name: 'Custom'),
                regions: catalog,
                options: options(
                  platform: platform,
                  windowsMode: WindowsMode.msix,
                  interfaceName: 'Ethernet',
                  lanProxyEnabled: enabled,
                ),
              ).config;
          final disabled = compile(false);
          final shared = compile(true);
          final inbounds = shared['inbounds'] as List;
          expect(
            inbounds.take(inbounds.length - 1).toList(),
            disabled['inbounds'],
          );
          expect(inbounds.last, {
            'tag': lanProxyInboundTag,
            'protocol': 'socks',
            'listen': '0.0.0.0',
            'port': '11024',
            'settings': {'auth': 'noauth', 'udp': true},
            'sniffing': {
              'enabled': true,
              'routeOnly': false,
              'destOverride': ['http', 'tls', 'quic'],
            },
          });
          expect(shared['routing'], disabled['routing']);
          expect(shared['outbounds'], disabled['outbounds']);
          expect(shared['metrics']['listen'], '127.0.0.1:18186');
          if (platform == ConnectionPlatform.windows) {
            expect(inbounds.first['listen'], '127.0.0.1');
            expect(inbounds.first['port'], '18187');
          }
        }
      }
      expect(jsonEncode(raw), rawBefore);
      expect(advanced.encode(), advancedBefore);
    },
  );

  test('sharing uses the saved port and includes managed FakeDNS recovery', () {
    final compiled = ConnectionCompiler.compile(
      settings: ConnectionSettings(smart: SmartRoutingSettings(fakeDns: true)),
      entries: [node(1)],
      regions: catalog,
      options: options(lanProxyEnabled: true, lanProxyPort: 11424),
    ).config;
    final shared = (compiled['inbounds'] as List).last;
    expect(shared['port'], '11424');
    expect(shared['sniffing']['destOverride'], contains('fakedns'));
  });

  test('Raw inbounds and runtime ignore the device LAN sharing setting', () {
    for (final inbound in [
      {'tag': 'user-socks', 'protocol': 'socks', 'port': '11020-11030'},
      {'tag': lanProxyInboundTag, 'protocol': 'http', 'port': 11424},
    ]) {
      final raw = <String, dynamic>{
        'inbounds': [inbound],
        'outbounds': [
          {'protocol': 'freedom'},
        ],
      };
      CompiledConnection compile(bool enabled) => ConnectionCompiler.compile(
        settings: ConnectionSettings(expert: true),
        entries: [],
        raw: raw,
        regions: catalog,
        options: options(lanProxyEnabled: enabled),
      );
      final disabled = compile(false).config;
      expect(disabled['inbounds'].last, inbound);
      expect(compile(true).config, disabled);
      expect(
        ConnectionCompiler.rawSemanticJson(raw, options(lanProxyEnabled: true)),
        ConnectionCompiler.rawSemanticJson(raw, options()),
      );
    }
  });

  test('advanced routing still protects the managed LAN inbound', () {
    final custom = AdvancedRoutingDocument.fromJson({
      'outbounds': [<String, dynamic>{}],
      'inbounds': [
        {'tag': 'user-socks', 'protocol': 'socks', 'port': '11020-11030'},
      ],
    }).state;
    CompiledConnection compile(bool enabled) => ConnectionCompiler.compile(
      settings: ConnectionSettings(trafficMode: TrafficMode.custom),
      entries: [node(1)],
      custom: custom,
      regions: catalog,
      options: options(lanProxyEnabled: enabled),
    );
    expect(compile(false).config['inbounds'].last['tag'], 'user-socks');
    expect(() => compile(true), throwsFormatException);
  });

  test('Raw tunIn updates only owned settings and retains its position and sniffing', () {
    for (final platform in ConnectionPlatform.values) {
      for (final windowsMode in WindowsMode.values) {
        final source = <String, dynamic>{
          'outbounds': [
            {'protocol': 'freedom'},
          ],
          'inbounds': [
            {
              'tag': 'extra',
              'protocol': 'socks',
              'listen': '127.0.0.1',
              'port': 12080,
            },
            {
              'tag': 'tunIn',
              'protocol': 'tun',
              'settings': {
                'desc': 'Keep',
                'userLevel': 5,
                'futureSetting': 'retain',
                'name': 'Old',
                'mtu': 1234,
                'gateway': ['old'],
                'dns': ['old'],
                'autoSystemRoutingTable': ['old'],
                'autoOutboundsInterface': 'Old',
              },
              'sniffing': {
                'enabled': false,
                'routeOnly': true,
                'domainsExcluded': ['domain:example.net'],
                'ipsExcluded': ['192.0.2.0/24'],
              },
            },
          ],
        };
        final before = jsonEncode(source);
        final result = ConnectionCompiler.compile(
          settings: ConnectionSettings(expert: true),
          raw: source,
          entries: [],
          regions: catalog,
          options: options(
            platform: platform,
            windowsMode: windowsMode,
            interfaceName: 'Ethernet',
          ),
        ).config;
        expect(result['inbounds'][0], source['inbounds'][0]);
        final tun = result['inbounds'][1];
        expect(tun['sniffing'], source['inbounds'][1]['sniffing']);
        if (platform == ConnectionPlatform.windows &&
            windowsMode == WindowsMode.msix) {
          expect(tun['protocol'], 'socks');
          expect(tun['settings'], {'auth': 'noauth', 'udp': true});
        } else {
          expect(tun['settings']['desc'], 'Keep');
          expect(tun['settings']['userLevel'], 5);
          expect(tun['settings']['futureSetting'], 'retain');
          expect(tun['settings']['name'], 'OneXrayTun');
          expect(tun['settings']['mtu'], VpnConstants.tunMtu);
          if (platform != ConnectionPlatform.windows &&
              platform != ConnectionPlatform.linux) {
            for (final key in [
              'gateway',
              'dns',
              'autoSystemRoutingTable',
              'autoOutboundsInterface',
            ]) {
              expect(tun['settings'].containsKey(key), false);
            }
          }
        }
        expect(jsonEncode(source), before);
      }
    }
  });

  test(
    'FakeDNS is opt-in per route and paired with managed inbound recovery',
    () {
      for (final platform in ConnectionPlatform.values) {
        for (final mode in TrafficMode.values) {
          for (final enabled in [false, true]) {
            for (final ipv6 in [false, true]) {
              final config = ConnectionCompiler.compile(
                settings: ConnectionSettings(
                  trafficMode: mode,
                  smart: SmartRoutingSettings(fakeDns: enabled),
                ),
                custom: RoutingProfileState(
                  name: 'Custom',
                  fakeDns: enabled,
                  directDnsAddress: '1.1.1.1',
                  rules: [
                    RoutingRuleState(
                      domain: ['domain:direct.test'],
                      action: RoutingRuleAction.direct,
                    ),
                  ],
                ),
                entries: [node(1)],
                regions: catalog,
                options: options(
                  platform: platform,
                  ipv6: ipv6,
                  interfaceName: 'Ethernet',
                ),
              ).config;
              final active = enabled && mode != TrafficMode.allVpn;
              final servers = config['dns']['servers'] as List;
              expect(
                servers.any((server) => server['tag'] == 'app-dns-fake'),
                active,
              );
              expect(servers.last['tag'], 'app-dns-proxy');
              expect(
                servers.every(
                  (server) =>
                      server['queryStrategy'] == (ipv6 ? 'UseIP' : 'UseIPv4'),
                ),
                true,
              );
              final sniffing = config['inbounds'].single['sniffing'];
              expect(sniffing, {
                'enabled': true,
                'routeOnly': false,
                'destOverride': ['http', 'tls', 'quic', if (active) 'fakedns'],
              });
              expect(config.containsKey('fakedns'), active);
              if (active) {
                expect(config['fakedns'], [
                  {'ipPool': '198.19.0.0/16', 'poolSize': 32768},
                  {'ipPool': '2001:2::/48', 'poolSize': 32768},
                ]);
                expect(servers.last['address'], '8.8.8.8');
                final direct = servers.firstWhere(
                  (server) => server['tag'] == 'app-dns-direct',
                );
                expect(direct['skipFallback'], true);
                expect(direct['domains'], isNotEmpty);
              }
              expect(
                config['routing']['domainStrategy'],
                mode == TrafficMode.allVpn ? 'AsIs' : 'IPIfNonMatch',
              );
            }
          }
        }
      }
    },
  );

  test('Windows MSIX SOCKS receives the same FakeDNS recovery', () {
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(smart: SmartRoutingSettings(fakeDns: true)),
      entries: [node(1)],
      regions: catalog,
      options: options(
        platform: ConnectionPlatform.windows,
        windowsMode: WindowsMode.msix,
        interfaceName: 'Ethernet',
      ),
    ).config;
    expect(config['inbounds'].single['protocol'], 'socks');
    expect(
      config['inbounds'].single['sniffing']['destOverride'],
      contains('fakedns'),
    );
  });

  test(
    'FakeDNS uses its dedicated setting instead of a real resolver address',
    () {
      expect(
        () => ConnectionCompiler.compile(
          settings: ConnectionSettings(
            smart: SmartRoutingSettings(directDnsAddress: 'fakedns'),
          ),
          entries: [node(1)],
          regions: catalog,
          options: options(),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Raw FakeDNS preserves explicit sniffing and supplies missing inbounds',
    () {
      for (final dns in [
        {
          'servers': ['fakedns', '9.9.9.9'],
        },
        {
          'servers': [
            {'address': 'fakedns', 'disableCache': true},
          ],
        },
      ]) {
        for (final poolKey in [null, 'fakedns', 'fakeDns']) {
          final source = <String, dynamic>{
            'dns': dns,
            ?poolKey: {'ipPool': 'fc00:1::/64', 'poolSize': 1024},
            'inbounds': [
              {
                'tag': 'tunIn',
                'protocol': 'tun',
                'sniffing': {'enabled': false},
              },
              {
                'tag': 'extra',
                'protocol': 'socks',
                'port': 20000,
                'sniffing': {'enabled': false},
              },
            ],
            'outbounds': [
              {'protocol': 'freedom'},
            ],
          };
          final before = jsonEncode(source);
          final config = ConnectionCompiler.compile(
            settings: ConnectionSettings(expert: true),
            raw: source,
            entries: [],
            regions: catalog,
            options: options(ipv6: false),
          ).config;
          expect(config['inbounds'].first['sniffing'], {'enabled': false});
          expect(config['inbounds'].last, (source['inbounds'] as List).last);
          if (poolKey == null) {
            expect(config.containsKey('fakedns'), false);
          } else {
            expect(config[poolKey], source[poolKey]);
          }
          expect(config['dns']['queryStrategy'], 'UseIPv4');
          expect(jsonEncode(source), before);
        }
      }
      for (final pool in [false, true]) {
        final config = ConnectionCompiler.compile(
          settings: ConnectionSettings(expert: true),
          raw: {
            'dns': {
              'servers': ['8.8.8.8'],
            },
            if (pool)
              'fakedns': [
                {'ipPool': '198.19.0.0/16', 'poolSize': 1024},
              ],
            'outbounds': [
              {'protocol': 'freedom'},
            ],
          },
          entries: [],
          regions: catalog,
          options: options(),
        ).config;
        expect(
          (config['inbounds'].first['sniffing']['destOverride'] as List)
              .contains('fakedns'),
          pool,
        );
      }
    },
  );

  test('routing DNS addresses are independent from proxy and tunnel DNS', () {
    for (final mode in TrafficMode.values) {
      final compiled = ConnectionCompiler.compile(
        settings: ConnectionSettings(
          trafficMode: mode,
          smart: SmartRoutingSettings(directDnsAddress: '1.1.1.1'),
        ),
        entries: [node(1)],
        custom: RoutingProfileState(
          name: 'Custom',
          directDnsAddress: '9.9.9.9',
          rules: [
            RoutingRuleState(
              domain: ['domain:example.com'],
              action: RoutingRuleAction.direct,
            ),
          ],
        ),
        regions: catalog,
        options: options(ipv6: false, tunDnsIpv4Address: '192.0.2.53'),
      );
      final servers = compiled.config['dns']['servers'] as List;
      expect(servers.last['tag'], 'app-dns-proxy');
      expect(servers.last['address'], '8.8.8.8');
      expect(servers.last['queryStrategy'], 'UseIPv4');
      expect(
        servers.length,
        mode == TrafficMode.allVpn ? 1 : (mode == TrafficMode.smart ? 3 : 2),
      );
      if (mode != TrafficMode.allVpn) {
        final direct = servers.singleWhere(
          (server) => server['tag'] == 'app-dns-direct',
        );
        expect(
          direct['address'],
          mode == TrafficMode.smart ? '1.1.1.1' : '9.9.9.9',
        );
        expect(direct['skipFallback'], true);
        expect(direct['queryStrategy'], 'UseIPv4');
        expect(direct['domains'], isNotEmpty);
      }
    }
    final disabled =
        ConnectionCompiler.compile(
              settings: ConnectionSettings(
                smart: SmartRoutingSettings(
                  directDns: false,
                  directDnsAddress: '1.1.1.1',
                ),
              ),
              entries: [node(1)],
              regions: catalog,
              options: options(),
            ).config['dns']['servers']
            as List;
    expect(disabled.last['address'], '8.8.8.8');
    expect(disabled.last['domains'], isNull);
  });

  test('native TUN uses configured DNS in normal and Raw without replacing Raw DNS', () {
    for (final platform in [
      ConnectionPlatform.windows,
      ConnectionPlatform.linux,
    ]) {
      for (final ipv6 in [false, true]) {
        for (final raw in [false, true]) {
          final compiled = ConnectionCompiler.compile(
            settings: ConnectionSettings(expert: raw),
            entries: raw ? [] : [node(1)],
            raw: raw
                ? {
                    'outbounds': [
                      {'protocol': 'freedom'},
                    ],
                    'dns': {
                      'servers': ['9.9.9.9'],
                    },
                  }
                : null,
            regions: catalog,
            options: options(
              platform: platform,
              interfaceName: 'Ethernet',
              ipv6: ipv6,
              tunDnsIpv4Address: '192.0.2.53',
              tunDnsIpv6Address: '2001:db8::53',
            ),
          );
          expect(compiled.config['inbounds'].first['settings']['dns'], [
            '192.0.2.53',
            if (ipv6) '2001:db8::53',
          ]);
          if (raw) expect(compiled.config['dns']['servers'], ['9.9.9.9']);
        }
      }
    }
  });

  test('normal runtime includes real chains and managed resources', () {
    final plan = ConnectionCompiler.compile(
      settings: ConnectionSettings(
        smart: SmartRoutingSettings(entryCount: 2, finalExitId: 9),
      ),
      entries: [node(1), node(2)],
      finalExit: node(9),
      regions: catalog,
      options: options(
        platform: ConnectionPlatform.windows,
        interfaceName: 'Ethernet',
      ),
    );
    final runtime = plan.config;
    expect(runtime['routing']['balancers'].single['selector'], [
      'app-exit-0',
      'app-exit-1',
    ]);
    expect(
      runtime['outbounds'][0]['streamSettings']['sockopt']['dialerProxy'],
      'app-entry-0',
    );
    for (final key in ['inbounds', 'stats', 'metrics', 'policy']) {
      expect(runtime.containsKey(key), true);
    }
    expect(
      runtime['outbounds'][0]['streamSettings']['sockopt']['interface'],
      'Ethernet',
    );
  });

  test('Raw runtime keeps user configuration alongside managed fields', () {
    final source = <String, dynamic>{
      'inbounds': [
        {'tag': 'extra', 'protocol': 'socks', 'port': 10080},
      ],
      'outbounds': [
        {'tag': 'proxy', 'protocol': 'freedom'},
      ],
      'routing': {
        'rules': [
          {
            'domain': ['regexp:['],
            'balancerTag': 'missing',
          },
        ],
      },
    };
    final before = jsonEncode(source);
    final plan = ConnectionCompiler.compile(
      settings: ConnectionSettings(expert: true),
      entries: [],
      raw: source,
      regions: catalog,
      options: options(),
    );
    expect(plan.config['inbounds'].last, source['inbounds'].single);
    expect(plan.config['outbounds'].first, source['outbounds'].single);
    expect(
      plan.config['routing']['rules'].last,
      source['routing']['rules'].single,
    );
    expect(plan.config['inbounds'].first['tag'], 'tunIn');
    expect(plan.config['metrics']['listen'], '127.0.0.1:18186');
    expect(jsonEncode(source), before);
  });

  test(
    'Windows EXE/MSIX select the same managed inbound in normal and Raw',
    () {
      for (final mode in WindowsMode.values) {
        for (final ipv6 in [false, true]) {
          for (final raw in [false, true]) {
            final config = ConnectionCompiler.compile(
              settings: ConnectionSettings(expert: raw),
              entries: raw ? [] : [node(1)],
              raw: raw
                  ? {
                      'inbounds': [
                        {'tag': 'tunIn', 'protocol': 'tun'},
                      ],
                      'outbounds': [
                        {'protocol': 'freedom'},
                      ],
                    }
                  : null,
              regions: catalog,
              options: options(
                platform: ConnectionPlatform.windows,
                windowsMode: mode,
                ipv6: ipv6,
                interfaceName: 'Ethernet 2',
              ),
            ).config;
            final inbound = (config['inbounds'] as List).single;
            expect(inbound['tag'], 'tunIn');
            if (mode == WindowsMode.msix) {
              expect(inbound['protocol'], 'socks');
              expect(inbound['listen'], '127.0.0.1');
              expect(inbound['port'], '18187');
              expect(inbound['settings'], {'auth': 'noauth', 'udp': true});
            } else {
              expect(inbound['protocol'], 'tun');
              expect(inbound.containsKey('port'), false);
              expect(inbound['settings'], {
                'name': 'OneXrayTun',
                'mtu': VpnConstants.tunMtu,
                'gateway': ['198.18.0.1/15', if (ipv6) 'fc00::1/64'],
                'dns': ['8.8.8.8', if (ipv6) '2001:4860:4860::8888'],
                'autoSystemRoutingTable': ['0.0.0.0/0', if (ipv6) '::/0'],
                'autoOutboundsInterface': 'Ethernet 2',
                'autoSystemWfpBlockLeak': ['dns'],
              });
            }
          }
        }
      }
    },
  );

  test(
    'TUN DNS protection defaults follow the actual platform tunnel owner',
    () {
      for (final platform in ConnectionPlatform.values) {
        for (final windowsMode in WindowsMode.values) {
          for (final ipv6 in [false, true]) {
            for (final raw in [false, true]) {
              final config = ConnectionCompiler.compile(
                settings: ConnectionSettings(expert: raw),
                entries: raw ? [] : [node(1)],
                raw: raw
                    ? {
                        'outbounds': [
                          {'protocol': 'freedom'},
                        ],
                      }
                    : null,
                regions: catalog,
                options: options(
                  platform: platform,
                  windowsMode: windowsMode,
                  ipv6: ipv6,
                  interfaceName: 'Ethernet',
                ),
              ).config;
              final settings = config['inbounds'].single['settings'] as Map;
              final windowsTun =
                  platform == ConnectionPlatform.windows &&
                  windowsMode == WindowsMode.exe;
              expect(
                settings['autoSystemWfpBlockLeak'],
                windowsTun ? ['dns'] : null,
              );
              expect(settings.containsKey('autoSystemDnsToGateway'), false);
              if (windowsTun) {
                expect(settings['dns'], isNotEmpty);
                expect(settings['autoSystemRoutingTable'], isNotEmpty);
                expect(
                  settings['autoSystemWfpBlockLeak'],
                  isNot(contains('misconfigtun')),
                );
              }
            }
          }
        }
      }
    },
  );

  test('Raw retains explicit core TUN DNS and WFP options', () {
    for (final platform in [
      ConnectionPlatform.linux,
      ConnectionPlatform.windows,
    ]) {
      for (final filters in <List<String>>[
        [],
        ['dns', 'misconfigtun'],
      ]) {
        final source = <String, dynamic>{
          'inbounds': [
            {
              'tag': 'tunIn',
              'protocol': 'tun',
              'settings': {
                'autoSystemDnsToGateway': true,
                'autoSystemWfpBlockLeak': filters,
              },
            },
          ],
          'outbounds': [
            {'protocol': 'freedom'},
          ],
        };
        final before = jsonEncode(source);
        final config = ConnectionCompiler.compile(
          settings: ConnectionSettings(expert: true),
          entries: [],
          raw: source,
          regions: catalog,
          options: options(
            platform: platform,
            ipv6: false,
            interfaceName: 'Ethernet',
          ),
        ).config;
        final settings = config['inbounds'].single['settings'] as Map;
        expect(settings['autoSystemDnsToGateway'], true);
        expect(settings['autoSystemWfpBlockLeak'], filters);
        expect(jsonEncode(source), before);
      }
    }
  });

  test(
    'normal 1/2/3 nodes always use full selectors and immutable mappings',
    () {
      for (var count = 1; count <= 3; count++) {
        final settings = ConnectionSettings(
          smart: SmartRoutingSettings(entryCount: count),
        );
        final entries = List.generate(count, (index) => node(index + 1));
        final plan = ConnectionCompiler.compile(
          settings: settings,
          entries: entries,
          regions: catalog,
          options: options(),
        );
        final config = plan.config;
        final balancer = config['routing']['balancers'].single as Map;
        expect(balancer['tag'], 'proxy');
        expect(
          balancer['selector'],
          List.generate(count, (i) => 'app-entry-$i'),
        );
        expect(balancer['fallbackTag'], 'app-entry-0');
        expect(config['observatory']['subjectSelector'], isEmpty);
        final outbounds = (config['outbounds'] as List).cast<Map>();
        expect(
          outbounds.take(count).map((outbound) => outbound['tag']),
          List.generate(count, (index) => 'app-entry-$index'),
        );
        expect(outbounds.skip(count).map((outbound) => outbound['tag']), [
          'direct',
          'block',
          'dnsOut',
          'app-dns-forward',
        ]);
        expect(
          outbounds.singleWhere(
            (outbound) => outbound['tag'] == 'dnsOut',
          )['streamSettings']['sockopt']['dialerProxy'],
          'app-dns-forward',
        );
        expect(
          outbounds.any((outbound) => outbound['protocol'] == 'loopback'),
          true,
        );
        expect(jsonEncode(outbounds), isNot(contains('domainStrategy')));
        expect(
          (config['routing']['rules'] as List).any(
            (rule) => (rule as Map).containsKey('type'),
          ),
          false,
        );
        final directRules = (config['routing']['rules'] as List)
            .cast<Map>()
            .where((rule) => rule['outboundTag'] == 'direct');
        final domainRule = directRules.singleWhere(
          (rule) => rule.containsKey('domain'),
        );
        final ipRule = directRules.singleWhere(
          (rule) => rule.containsKey('ip'),
        );
        expect(domainRule['domain'], [
          'geosite:PRIVATE',
          'geosite:APPLE',
          'geosite:MICROSOFT',
          'geosite:BING',
          'geosite:CN',
        ]);
        expect(domainRule.containsKey('ip'), false);
        expect(ipRule['ip'], ['geoip:PRIVATE', 'geoip:CN']);
        expect(ipRule.containsKey('domain'), false);
        expect(
          (config['dns']['servers'] as List).singleWhere(
            (server) => server['tag'] == 'app-dns-direct',
          )['domains'],
          domainRule['domain'],
        );
        expect(plan.nodeTags.values, entries.map((entry) => entry.id));
        expect(entries.first.outbound['tag'], 'Same user tag');
        expect(XrayJson.fromJson(config).toJson(), config);
        final inbounds = (config['inbounds'] as List).cast<Map>();
        expect(
          inbounds.singleWhere(
            (inbound) => inbound['tag'] == 'tunIn',
          )['settings'],
          {'name': 'OneXrayTun', 'mtu': 1500},
        );
        expect(inbounds, hasLength(1));
        config['outbounds'].clear();
        expect(plan.config['outbounds'], isNotEmpty);
        _fixture('normal-$count', plan);
      }
    },
  );

  test(
    'each final exit clone depends on its own entry, with no asset rewrite',
    () {
      for (var count = 1; count <= 3; count++) {
        final entries = List.generate(count, (i) => node(i + 1));
        final finalExit = ResolvedServer(
          id: 9,
          sourceId: 1,
          outbound: {
            'tag': 'Same user tag',
            'protocol': 'freedom',
            'streamSettings': {
              'sockopt': {'tcpFastOpen': true},
            },
          },
        );
        final finalExitBeforeCompile =
            jsonDecode(jsonEncode(finalExit.outbound)) as Map<String, dynamic>;
        final plan = ConnectionCompiler.compile(
          settings: ConnectionSettings(
            smart: SmartRoutingSettings(entryCount: count, finalExitId: 9),
          ),
          entries: entries,
          finalExit: finalExit,
          regions: catalog,
          options: options(),
        );
        final outbounds = (plan.config['outbounds'] as List).cast<Map>();
        final selector = List.generate(count, (i) => 'app-exit-$i');
        expect(
          plan.config['routing']['balancers'].single['selector'],
          selector,
        );
        expect(outbounds.map((outbound) => outbound['tag']), [
          ...selector,
          ...List.generate(count, (i) => 'app-entry-$i'),
          'direct',
          'block',
          'dnsOut',
          'app-dns-forward',
        ]);
        expect(
          outbounds.take(count).map((outbound) => outbound['tag']),
          selector,
        );
        expect(
          outbounds.skip(count).take(count).map((outbound) => outbound['tag']),
          List.generate(count, (index) => 'app-entry-$index'),
        );
        for (var i = 0; i < count; i++) {
          final exit = outbounds.singleWhere(
            (item) => item['tag'] == 'app-exit-$i',
          );
          expect(
            exit['streamSettings']['sockopt']['dialerProxy'],
            'app-entry-$i',
          );
          expect(exit['streamSettings']['sockopt']['tcpFastOpen'], true);
          expect(plan.nodeTags['app-exit-$i'], 9);
          expect(plan.nodeTags['app-entry-$i'], i + 1);
        }
        expect(
          outbounds.map((outbound) => outbound['tag']).toSet(),
          hasLength(outbounds.length),
        );
        expect(
          entries.every((entry) => entry.outbound['tag'] == 'Same user tag'),
          true,
        );
        expect(finalExit.outbound, finalExitBeforeCompile);
        _fixture('chain-$count', plan);
      }
    },
  );

  test('All VPN/fixed server use one node, excluding Smart final exit', () {
    final settings = ConnectionSettings(
      trafficMode: TrafficMode.allVpn,
      smart: SmartRoutingSettings(entryCount: 3, finalExitId: 9),
    );
    final plan = ConnectionCompiler.compile(
      settings: settings,
      entries: [node(1)],
      regions: catalog,
      options: options(),
    );
    expect(plan.finalExit, isNull);
    expect(plan.config['routing']['domainStrategy'], 'AsIs');
    expect(
      ConnectionSettings(
        selection: const ServerSelection.server(1),
        smart: SmartRoutingSettings(entryCount: 3),
      ).requiredEntries(),
      1,
    );
    expect(
      () => ConnectionCompiler.compile(
        settings: settings,
        entries: [node(1)],
        finalExit: node(9),
        regions: catalog,
        options: options(),
      ),
      throwsFormatException,
    );
    _fixture('all-vpn', plan);
  });

  test(
    'missing/duplicate entries and self chains are rejected before runtime',
    () {
      final settings = ConnectionSettings(
        smart: SmartRoutingSettings(entryCount: 2),
      );
      for (final entries in [
        <ResolvedServer>[],
        [node(1)],
        [node(1), node(1)],
      ]) {
        expect(
          () => ConnectionCompiler.compile(
            settings: settings,
            entries: entries,
            regions: catalog,
            options: options(),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => ConnectionCompiler.compile(
          settings: ConnectionSettings(
            smart: SmartRoutingSettings(finalExitId: 1),
          ),
          entries: [node(1)],
          finalExit: node(1),
          regions: catalog,
          options: options(),
        ),
        throwsFormatException,
      );
    },
  );

  test('Custom keeps all native AND conditions/order and derives DNS only from domain-only rules', () {
    final template = RoutingProfileState(
      name: 'Custom',
      entryCount: 2,
      rules: [
        RoutingRuleState(
          ruleTag: 'Same',
          domain: const ['domain:example.test'],
          port: '443',
          network: 'tcp',
          protocol: const ['http'],
          localOS: const ['android', 'darwin'],
          action: RoutingRuleAction.direct,
        ),
        RoutingRuleState(
          ruleTag: 'Same',
          ip: const ['192.0.2.1/32'],
          action: RoutingRuleAction.block,
        ),
        RoutingRuleState(
          domain: const ['domain:direct-only.test'],
          action: RoutingRuleAction.direct,
        ),
      ],
    );
    final original = template.encode();
    expect(jsonDecode(original)['outbounds'], [{}, {}]);
    final plan = ConnectionCompiler.compile(
      settings: ConnectionSettings(
        trafficMode: TrafficMode.custom,
        customId: 4,
        smart: SmartRoutingSettings(finalExitId: 9),
      ),
      entries: [node(1), node(2)],
      custom: template,
      regions: catalog,
      options: options(),
    );
    expect(
      (plan.config['outbounds'] as List).map((outbound) => outbound['tag']),
      [
        'app-entry-0',
        'app-entry-1',
        'direct',
        'block',
        'dnsOut',
        'app-dns-forward',
      ],
    );
    final first = (plan.config['routing']['rules'] as List).singleWhere(
      (rule) => rule['ruleTag'] == 'app-custom-0',
    );
    expect(first['domain'], ['domain:example.test']);
    expect(first['port'], '443');
    expect(first['network'], 'tcp');
    expect(first, {
      ...template.rules.first.toJson(),
      'ruleTag': 'app-custom-0',
    });
    final servers = plan.config['dns']['servers'] as List;
    expect(servers.map((server) => server['address']), ['8.8.8.8', '8.8.8.8']);
    expect(servers.first['domains'], ['domain:direct-only.test']);
    expect(servers.first['skipFallback'], true);
    expect(template.encode(), original);
    _fixture('custom', plan);
  });

  test('Smart enables every switch except ad blocking by default', () {
    for (final smart in [
      SmartRoutingSettings(),
      SmartRoutingSettings.fromJson({}),
      ConnectionSettings.fromJson({}).smart,
    ]) {
      expect(smart.directPrivate, true);
      expect(smart.directApple, true);
      expect(smart.directWindows, true);
      expect(smart.directDns, true);
      expect(smart.blockAds, false);
    }
  });

  test('Windows services keep GitHub on proxy ahead of direct rules', () {
    for (final enabled in [false, true]) {
      for (final directDns in [false, true]) {
        final smart = SmartRoutingSettings.fromJson(
          SmartRoutingSettings(
            directWindows: enabled,
            directDns: directDns,
          ).toJson(),
        );
        expect(smart.directWindows, enabled);
        final config = ConnectionCompiler.compile(
          settings: ConnectionSettings(smart: smart),
          entries: [node(1)],
          regions: catalog,
          options: options(),
        ).config;
        final domains = [
          'geosite:PRIVATE',
          'geosite:APPLE',
          if (enabled) ...['geosite:MICROSOFT', 'geosite:BING'],
          'geosite:CN',
        ];
        final rules = (config['routing']['rules'] as List).cast<Map>();
        final githubRules = rules.where(
          (rule) => rule['ruleTag'] == 'app-smart-github',
        );
        expect(githubRules, [
          if (enabled)
            {
              'ruleTag': 'app-smart-github',
              'domain': ['geosite:GITHUB'],
              'balancerTag': 'proxy',
            },
        ]);
        expect(
          rules
              .where(
                (rule) => (rule['ruleTag'] as String).startsWith('app-smart-'),
              )
              .map((rule) => rule['ruleTag']),
          [
            if (enabled) 'app-smart-github',
            'app-smart-direct-domain',
            'app-smart-direct-ip',
          ],
        );
        expect(
          rules
              .where((rule) => rule['outboundTag'] == 'direct')
              .where((rule) => rule.containsKey('domain'))
              .single['domain'],
          domains,
        );
        expect(
          rules.singleWhere(
            (rule) => rule['ruleTag'] == 'app-smart-direct-ip',
          )['ip'],
          ['geoip:PRIVATE', 'geoip:CN'],
        );
        expect(
          directDns
              ? (config['dns']['servers'] as List).singleWhere(
                  (server) => server['tag'] == 'app-dns-direct',
                )['domains']
              : config['dns']['servers'].last['domains'],
          directDns ? domains : isNull,
        );
      }
    }
  });

  test('Smart omits empty direct rule types', () {
    for (final (smart, expected) in [
      (
        SmartRoutingSettings(
          directPrivate: false,
          directApple: false,
          directWindows: false,
          directRegions: [],
        ),
        <Map<String, dynamic>>[],
      ),
      (
        SmartRoutingSettings(
          directPrivate: false,
          directWindows: false,
          directRegions: [],
        ),
        [
          {
            'ruleTag': 'app-smart-direct-domain',
            'domain': ['geosite:APPLE'],
            'outboundTag': 'direct',
          },
        ],
      ),
      (
        SmartRoutingSettings(
          directPrivate: false,
          directApple: false,
          directWindows: false,
          directRegions: ['US', 'US'],
        ),
        [
          {
            'ruleTag': 'app-smart-direct-ip',
            'ip': ['geoip:US'],
            'outboundTag': 'direct',
          },
        ],
      ),
    ]) {
      expect(
        ConnectionCompiler.smartRules(
          smart,
          catalog,
        ).map((rule) => rule.toJson()),
        expected,
      );
    }
  });

  test('normal IPv6 policy only changes DNS query strategies', () {
    Map<String, dynamic> compile(bool ipv6) => ConnectionCompiler.compile(
      settings: ConnectionSettings(),
      entries: [node(1, address: '2001:db8::1')],
      regions: catalog,
      options: options(ipv6: ipv6),
    ).config;
    final disabled = compile(false);
    final enabled = compile(true);
    expect(
      (disabled['dns']['servers'] as List).every(
        (server) => server['queryStrategy'] == 'UseIPv4',
      ),
      true,
    );
    expect(disabled..remove('dns'), enabled..remove('dns'));
  });

  test('Smart and Custom use IPIfNonMatch without a first-pass catch-all', () {
    for (final mode in [TrafficMode.smart, TrafficMode.custom]) {
      final plan = ConnectionCompiler.compile(
        settings: ConnectionSettings(
          trafficMode: mode,
          smart: SmartRoutingSettings(directDns: false),
        ),
        entries: [node(1)],
        custom: mode == TrafficMode.custom
            ? RoutingProfileState(name: 'Custom')
            : null,
        regions: catalog,
        options: options(),
      );
      expect(plan.config['routing']['domainStrategy'], 'IPIfNonMatch');
      expect(plan.config['dns']['servers'].last['domains'], isNull);
      expect(
        (plan.config['routing']['rules'] as List).any(
          (rule) => ![
            'domain',
            'ip',
            'inboundTag',
            'port',
            'network',
          ].any(rule.containsKey),
        ),
        false,
      );
    }
  });

  test('Raw keeps source/additional inbound/policy/DNS/routing but overrides runtime fields', () {
    const source = ''' {"inbounds":[{"tag":"tunIn","protocol":"tun","settings":{"name":"ignored"}},
      {"tag":"extra","protocol":"socks","listen":"127.0.0.1","port":18185}],
      "outbounds":[{"tag":"custom-direct","protocol":"freedom","streamSettings":{"sockopt":{"domainStrategy":"UseIPv4"}}}],
      "routing":{"domainStrategy":"IPOnDemand","rules":[{"type":"field","domain":["full:example.test"],"outboundTag":"custom-direct","futureRule":{"keep":true}}]},
      "dns":{"hosts":{"example.test":"127.0.0.1"},"servers":["localhost"],"futureDns":{"keep":true}},
      "policy":{"levels":{"0":{"handshake":7,"statsUserUplink":true}},"system":{"statsOutboundUplink":true}},
      "log":{"error":"user-file","loglevel":"debug"},"metrics":{"listen":"0.0.0.0:8080"},
      "fakeDns":[{"ipPool":"198.18.0.0/15","poolSize":1024,"futureFakeDns":true}],
      "api":{"tag":"user-api"},"geodata":{"assets":[]},
      "futureRoot":{"nested":{"keep":true}},
      "env":{"xray.location.asset":"bad"}}
    ''';
    final raw = jsonDecode(source) as Map<String, dynamic>;
    final rawBeforeCompile =
        jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    final plan = ConnectionCompiler.compile(
      settings: ConnectionSettings(expert: true, rawId: 8),
      entries: [],
      raw: raw,
      regions: catalog,
      options: options(),
    );
    final runtime = plan.config;
    expect(runtime['inbounds'][1]['tag'], 'extra');
    expect(runtime['inbounds'].first['settings']['name'], 'OneXrayTun');
    expect(runtime['policy']['levels']['0']['handshake'], 7);
    expect(runtime['policy']['levels']['0']['statsUserUplink'], false);
    expect(runtime['policy']['system']['statsOutboundUplink'], false);
    expect(runtime['dns']['servers'], ['localhost']);
    expect(runtime['fakeDns'], jsonDecode(source)['fakeDns']);
    expect(runtime['api'], jsonDecode(source)['api']);
    expect(runtime['futureRoot'], jsonDecode(source)['futureRoot']);
    expect(runtime['dns']['futureDns'], jsonDecode(source)['dns']['futureDns']);
    expect(runtime.containsKey('geodata'), false);
    expect(runtime['routing']['domainStrategy'], 'IPOnDemand');
    expect(
      runtime['outbounds'].first['streamSettings']['sockopt']['domainStrategy'],
      'UseIPv4',
    );
    expect(
      runtime['routing']['rules'].last,
      jsonDecode(source)['routing']['rules'].single,
    );
    expect(runtime['log']['error'], 'none');
    expect(runtime['metrics']['listen'], '127.0.0.1:18186');
    expect(
      jsonDecode(source)['policy']['levels']['0']['statsUserUplink'],
      true,
    );
    expect(raw, rawBeforeCompile);
    expect(raw['geodata'], jsonDecode(source)['geodata']);
    expect(plan.nodeTags, isEmpty);
    _fixture('raw', plan);
  });

  test('Raw and provider runtime copies preserve XDrive template maps', () {
    final source = <String, dynamic>{
      'outbounds': [xdriveTemplateOutbound()],
      'futureRoot': {'keep': true},
    };
    final before = jsonEncode(source);
    for (final provider in [false, true]) {
      final compiled = ConnectionCompiler.compile(
        settings: ConnectionSettings(
          expert: !provider,
          selection: const ServerSelection.server(99),
        ),
        entries: const [],
        raw: provider ? null : source,
        profile: provider
            ? ResolvedProfile(
                id: 99,
                sourceId: 7,
                name: 'Template',
                config: source,
              )
            : null,
        regions: catalog,
        options: options(),
      ).config;
      expect(
        compiled['outbounds'].first['streamSettings']['xdriveSettings'],
        source['outbounds'][0]['streamSettings']['xdriveSettings'],
      );
      expect(compiled['outbounds'].first['mux'], {
        'enabled': true,
        'concurrency': 8,
      });
      expect(jsonEncode(source), before);
    }
  });

  test('Raw semantic comparison includes fields unknown to the App', () {
    Map<String, dynamic> semantic(String value) =>
        ConnectionCompiler.rawSemanticJson({
          'name': 'Ignored display name',
          'outbounds': [
            {'tag': 'direct', 'protocol': 'freedom'},
          ],
          'futureRoot': {'value': value},
        }, options());

    expect(semantic('one').containsKey('name'), false);
    expect(semantic('one')['futureRoot'], {'value': 'one'});
    expect(semantic('one'), isNot(semantic('two')));
  });

  test('advanced and Raw retain native DNS and sniffing fields retired from ordinary routing', () {
    final dns = <String, dynamic>{
      'serveStale': true,
      'serveExpiredTTL': 300,
      'enableParallelQuery': true,
      'servers': [
        {
          'address': 'tcp://8.8.8.8',
          'timeoutMs': 1200,
          'disableCache': true,
          'expectedIPs': ['geoip:CN'],
          'unexpectedIPs': ['geoip:PRIVATE'],
          'serveStale': false,
          'serveExpiredTTL': 60,
        },
        {
          'address': 'tcp://1.1.1.1',
          'timeoutMs': 4000,
          'disableCache': false,
          'expectIPs': ['!geoip:PRIVATE'],
        },
      ],
    };
    final sniffing = <String, dynamic>{
      'enabled': true,
      'routeOnly': true,
      'destOverride': ['http', 'tls', 'quic'],
      'domainsExcluded': ['domain:private.example'],
      'ipsExcluded': ['192.0.2.0/24'],
    };
    final raw = <String, dynamic>{
      'outbounds': [node(1).outbound],
      'dns': dns,
      'inbounds': [
        {'tag': 'tunIn', 'protocol': 'tun', 'sniffing': sniffing},
      ],
    };
    final advanced = AdvancedRoutingDocument.fromJson({
      'name': 'Advanced DNS',
      'outbounds': [<String, dynamic>{}],
      'dns': dns,
      'inbounds': [
        {'tag': 'tunIn', 'sniffing': sniffing},
      ],
    }).state;
    final rawBefore = jsonEncode(raw);
    final advancedBefore = advanced.encode();
    for (final ipv6 in [false, true]) {
      for (final isRaw in [false, true]) {
        final config = ConnectionCompiler.compile(
          settings: ConnectionSettings(
            expert: isRaw,
            trafficMode: TrafficMode.custom,
          ),
          entries: isRaw ? [] : [node(1)],
          raw: isRaw ? raw : null,
          custom: isRaw ? null : advanced,
          regions: catalog,
          options: options(ipv6: ipv6),
        ).config;
        final strategy = ipv6 ? 'UseIP' : 'UseIPv4';
        expect(config['dns'], {
          ...dns,
          'queryStrategy': strategy,
          'servers': [
            for (final server in dns['servers'] as List)
              {...server as Map<String, dynamic>, 'queryStrategy': strategy},
          ],
        });
        expect(
          (config['inbounds'] as List).singleWhere(
            (inbound) => inbound['tag'] == 'tunIn',
          )['sniffing'],
          sniffing,
        );
      }
    }
    expect(jsonEncode(raw), rawBefore);
    expect(advanced.encode(), advancedBefore);
    expect(advanced.toJson()['dns'], dns);
    expect(advanced.toJson()['inbounds'].single['sniffing'], sniffing);
  });

  test('Raw keeps the default outbound and supplements tunnel DNS routing', () {
    final plan = ConnectionCompiler.compile(
      settings: ConnectionSettings(expert: true),
      entries: [],
      raw: {
        'outbounds': [
          {'protocol': 'freedom'},
        ],
      },
      regions: catalog,
      options: options(),
    );

    expect(plan.config['outbounds'].first.containsKey('tag'), false);
    expect(plan.config['routing']['rules'].last['inboundTag'], ['tunIn']);
    expect(plan.config['routing']['rules'].last['outboundTag'], 'app-vpn-dns');
  });

  test('Raw reserved tags/ports conflict clearly, rather than renaming user references', () {
    for (final inbound in [
      {'tag': 'extra', 'protocol': 'socks', 'port': '18186-18187'},
      {'tag': 'extra-tun', 'protocol': 'tun'},
    ]) {
      expect(
        () => ConnectionCompiler.compile(
          settings: ConnectionSettings(expert: true),
          entries: [],
          raw: {
            'inbounds': [inbound],
            'outbounds': [
              {'protocol': 'freedom'},
            ],
          },
          regions: catalog,
          options: options(),
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'normal runtime models retain platform, DNS, logging and statistics policy',
    () {
      // Representative runtime choices include each platform and macOS SE,
      // without crossing every log option with every platform and IP setting.
      for (final (platform, ipv6, enabled, supported, dnsLog) in [
        (ConnectionPlatform.ios, true, false, true, true),
        (ConnectionPlatform.android, false, true, true, false),
        (ConnectionPlatform.windows, true, true, true, true),
        (ConnectionPlatform.linux, false, true, true, true),
        (ConnectionPlatform.macos, true, true, true, true),
        (ConnectionPlatform.macos, false, true, false, true),
      ]) {
        final desktop =
            platform == ConnectionPlatform.windows ||
            platform == ConnectionPlatform.linux;
        final config = ConnectionCompiler.compile(
          settings: ConnectionSettings(trafficMode: TrafficMode.allVpn),
          entries: [node(1, address: '192.0.2.1')],
          regions: catalog,
          options: RuntimeOptions(
            platform: platform,
            sessionDirectory: '/unused-session',
            metricsPort: 18186,
            socksPort: 18187,
            ipv6: ipv6,
            interfaceName: 'selected-interface',
            logEnabled: enabled,
            logFilesSupported: supported,
            logLevel: 'debug',
            dnsLog: dnsLog,
            maskAddress: 'half',
          ),
        ).config;
        final logging = enabled && supported;
        expect(config['log'], {
          'access': logging ? '/unused-session/access.log' : 'none',
          'error': logging ? '/unused-session/error.log' : 'none',
          'loglevel': logging ? 'debug' : 'none',
          'dnsLog': logging && dnsLog,
          'maskAddress': 'half',
        });
        expect(config['env'], {
          'xray.location.asset': VpnConstants.datDir,
          'xray.location.cert': VpnConstants.datDir,
        });
        expect(config['stats'], isEmpty);
        expect(config['metrics'], {'listen': '127.0.0.1:18186'});
        expect(config['policy'], {
          'system': {
            'statsInboundUplink': true,
            'statsInboundDownlink': true,
            'statsOutboundUplink': false,
            'statsOutboundDownlink': false,
          },
        });
        expect(config['dns']['servers'], [
          {
            'address': '8.8.8.8',
            'tag': ConnectionCompiler.dnsProxy,
            'queryStrategy': ipv6 ? 'UseIP' : 'UseIPv4',
          },
        ]);
        final rules = (config['routing']['rules'] as List).cast<Map>();
        expect(rules.singleWhere((rule) => rule['ruleTag'] == 'app-default'), {
          'ruleTag': 'app-default',
          'inboundTag': [ConnectionCompiler.dnsProxy],
          'balancerTag': 'proxy',
        });
        expect(rules.any((rule) => rule['outboundTag'] == 'direct'), false);
        final dnsOutbound = (config['outbounds'] as List).singleWhere(
          (outbound) => outbound['tag'] == ConnectionCompiler.dnsOutbound,
        );
        expect(
          dnsOutbound['streamSettings']['sockopt']['dialerProxy'],
          'app-entry-0',
        );
        final direct = (config['outbounds'] as List).singleWhere(
          (outbound) => outbound['tag'] == 'direct',
        );
        expect(direct, {
          'tag': 'direct',
          'protocol': 'freedom',
          if (desktop)
            'streamSettings': {
              'sockopt': {'interface': 'selected-interface'},
            },
        });
        if (platform == ConnectionPlatform.linux) {
          expect(config['inbounds'].single['settings'], {
            'name': 'OneXrayTun',
            'mtu': VpnConstants.tunMtu,
            'gateway': ['198.18.0.1/15', if (ipv6) 'fc00::1/64'],
            'dns': ['8.8.8.8', if (ipv6) '2001:4860:4860::8888'],
            'autoSystemRoutingTable': ['0.0.0.0/0', if (ipv6) '::/0'],
            'autoOutboundsInterface': 'selected-interface',
          });
        }
      }
    },
  );

  for (final maskType in ['udphop', 'UDPHOP', 'UdpHop']) {
    test(
      'UDP hopping ($maskType) inherits the outer socket policy without mask rewrites',
      () {
        final source = <String, dynamic>{
          'tag': 'Hysteria2',
          'protocol': 'hysteria',
          'settings': {'version': 2, 'address': 'server.example', 'port': 443},
          'streamSettings': {
            'network': 'hysteria',
            'security': 'tls',
            'hysteriaSettings': {'version': 2, 'auth': 'test'},
            'sockopt': {'interface': 'old-interface', 'mark': 7},
            'finalmask': {
              'udp': [
                {
                  'type': 'salamander',
                  'settings': {'password': 'test'},
                },
                {
                  'type': maskType,
                  'settings': {
                    'mode': 'intervalLocal,intervalRemote',
                    'remotePorts': '443,8443',
                    'interval': 30,
                  },
                },
              ],
            },
          },
        };
        final before = jsonEncode(source);
        for (final platform in ConnectionPlatform.values) {
          for (final raw in [false, true]) {
            final plan = ConnectionCompiler.compile(
              settings: ConnectionSettings(
                expert: raw,
                trafficMode: TrafficMode.allVpn,
              ),
              entries: raw
                  ? []
                  : [ResolvedServer(id: 1, sourceId: 0, outbound: source)],
              raw: raw
                  ? {
                      'outbounds': [source],
                    }
                  : null,
              regions: catalog,
              options: options(
                platform: platform,
                interfaceName: 'selected-interface',
              ),
            );
            final stream = plan.config['outbounds'][0]['streamSettings'];
            expect(stream['finalmask']['udp'][1]['type'], maskType);
            final interface =
                platform == ConnectionPlatform.windows ||
                    platform == ConnectionPlatform.linux
                ? 'selected-interface'
                : null;
            expect(stream['sockopt']['interface'], interface);
            expect(stream['sockopt']['mark'], 7);
            expect(stream['finalmask'], source['streamSettings']['finalmask']);
            expect(jsonEncode(source), before);
          }
        }
      },
    );
  }

  test('Windows/Linux require an interface and stay within XrayJson', () {
    expect(
      () => options(platform: ConnectionPlatform.windows),
      throwsFormatException,
    );
    for (final platform in [
      ConnectionPlatform.windows,
      ConnectionPlatform.linux,
    ]) {
      final plan = ConnectionCompiler.compile(
        settings: ConnectionSettings(trafficMode: TrafficMode.allVpn),
        entries: [node(1, address: 'node.test')],
        regions: catalog,
        options: options(
          platform: platform,
          ipv6: false,
          interfaceName: 'selected-interface',
        ),
      );
      final entry = (plan.config['outbounds'] as List).singleWhere(
        (node) => node['tag'] == 'app-entry-0',
      );
      expect(
        entry['streamSettings']['sockopt']['interface'],
        'selected-interface',
      );
      expect(
        entry['streamSettings']['sockopt'].containsKey('domainStrategy'),
        false,
      );
      expect(
        (plan.config['outbounds'] as List).map((outbound) => outbound['tag']),
        ['app-entry-0', 'direct', 'block', 'dnsOut'],
      );
      expect(
        (plan.config['routing']['rules'] as List).first['ruleTag'],
        'app-default',
      );
      expect(plan.config['dns'].containsKey('hosts'), false);
      expect(plan.config['dns'].containsKey('queryStrategy'), false);
      expect(
        (plan.config['dns']['servers'] as List).every(
          (server) => server['queryStrategy'] == 'UseIPv4',
        ),
        true,
      );
      expect(plan.config['inbounds'].first['protocol'], 'tun');
      final settings = plan.config['inbounds'].first['settings'];
      expect(settings['autoOutboundsInterface'], 'selected-interface');
      expect(settings['autoSystemRoutingTable'], ['0.0.0.0/0']);
      expect(XrayJson.fromJson(plan.config).toJson(), plan.config);
    }
  });
}

void _fixture(String name, CompiledConnection plan) {
  const target = String.fromEnvironment('P2_FIXTURES');
  if (target.isEmpty) return;
  Directory(target).createSync(recursive: true);
  File('$target/$name.json').writeAsStringSync(plan.xrayJson);
}
