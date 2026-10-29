import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/dialing.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/settings.dart';

import 'compiler_test.dart' show catalog;

const _happyEyeballs = ServerDialingSettings(happyEyeballs: true);

void main() {
  test('managed routes resolve the physical server before their routed and FakeDNS resolvers', () {
    for (final mode in TrafficMode.values) {
      final entry = _node(1, 'entry.example');
      final before = entry.outbound;
      final settings = ConnectionSettings(
        trafficMode: mode,
        smart: SmartRoutingSettings(fakeDns: true),
      );
      final custom = mode == TrafficMode.custom
          ? RoutingProfileState(
              name: 'Custom',
              fakeDns: true,
              dns: const RoutingDnsSettings(
                proxyResolvers: [RoutingDnsResolver(address: '9.9.9.9')],
              ),
              rules: [
                RoutingRuleState(domain: ['full:entry.example']),
              ],
            )
          : null;
      CompiledConnection compile(ServerDialingSettings dialing) =>
          ConnectionCompiler.compile(
            settings: settings,
            custom: custom,
            entries: [entry],
            regions: catalog,
            options: _options(dialing: dialing),
          );
      final baseline = compile(const ServerDialingSettings());
      final compiled = compile(_happyEyeballs);
      final config = compiled.config;
      final socket = _socket(_outbound(config, 'app-entry-0'));
      expect(socket['domainStrategy'], 'UseIP');
      expect(socket['happyEyeballs'], {'tryDelayMs': 250});
      expect(_socket(_outbound(config, 'direct'))['happyEyeballs'], isNull);
      expect(compiled.nodeTags, baseline.nodeTags);
      expect(
        config['routing']['balancers'],
        baseline.config['routing']['balancers'],
      );
      _expectBootstrap(config, ['entry.example']);
      expect(
        _dnsServers(config)
            .where((server) => server['tag'] != 'app-dns-bootstrap'),
        _dnsServers(baseline.config),
      );
      expect(
        (config['routing']['rules'] as List).skip(1),
        baseline.config['routing']['rules'],
      );
      if (mode == TrafficMode.allVpn) {
        expect(
          _socket(_outbound(config, 'dnsOut'))['dialerProxy'],
          'app-entry-0',
        );
      } else {
        expect(
          _dnsServers(config).any((server) => server['address'] == 'fakedns'),
          isTrue,
        );
      }
      expect(entry.outbound, before);
    }
  });

  test(
    'managed S3 routes bootstrap storage hosts while preserving the node graph',
    () {
      for (final mode in TrafficMode.values) {
        for (final pathStyle in <bool?>[null, true, false]) {
          for (final ipv6 in [false, true]) {
            final source = _s3(pathStyle: pathStyle);
            final before = jsonEncode(source);
            final entry = ResolvedServer(id: 1, sourceId: 0, outbound: source);
            final config = ConnectionCompiler.compile(
              settings: ConnectionSettings(
                trafficMode: mode,
                smart: SmartRoutingSettings(fakeDns: true),
              ),
              custom: mode == TrafficMode.custom
                  ? RoutingProfileState(name: 'Custom', fakeDns: true)
                  : null,
              entries: [entry],
              regions: catalog,
              options: _options(
                dialing: const ServerDialingSettings(
                  domainStrategy: ServerDomainStrategy.useIp,
                  happyEyeballs: true,
                ),
                ipv6: ipv6,
              ),
            ).config;
            final outbound = _outbound(config, 'app-entry-0');
            _expectBootstrap(config, [
              pathStyle == false ? 'tunnel.storage.example' : 'storage.example',
            ], ipv6: ipv6);
            expect(
              _socket(outbound)['domainStrategy'],
              ipv6 ? 'UseIP' : 'UseIPv4',
            );
            expect(
              _socket(outbound)['happyEyeballs'],
              ipv6 ? {'tryDelayMs': 250} : isNull,
            );
            expect(outbound['settings'], source['settings']);
            expect(outbound['mux'], source['mux']);
            for (final field in ['tlsSettings', 'xdriveSettings']) {
              expect(
                outbound['streamSettings'][field],
                source['streamSettings'][field],
              );
            }
            expect(jsonEncode(source), before);
            expect(entry.outbound, source);
          }
        }
      }
    },
  );

  test(
    'S3 fronting and final exits retain the physical Fragment bootstrap target',
    () {
      for (final fronting in <String?>[
        null,
        'fronting.example',
        '192.0.2.10',
      ]) {
        final source = _s3(pathStyle: false, fronting: fronting);
        final before = jsonEncode(source);
        final entry = ResolvedServer(id: 1, sourceId: 0, outbound: source);
        final exit = _node(9, 'remote-exit.example');
        final compiled = ConnectionCompiler.compile(
          settings: ConnectionSettings(
            smart: SmartRoutingSettings(
              finalExitId: exit.id,
              fragment: true,
              fakeDns: true,
            ),
          ),
          entries: [entry],
          finalExit: exit,
          regions: catalog,
          options: _options(dialing: _happyEyeballs),
        );
        final config = compiled.config;
        final outer = _outbound(config, 'app-exit-0');
        final inner = _outbound(config, 'app-entry-0');
        final helper = _outbound(config, 'fragment');
        expect(_socket(outer)['dialerProxy'], inner['tag']);
        expect(_socket(inner), {'dialerProxy': 'fragment'});
        expect(_socket(helper)['domainStrategy'], 'UseIP');
        expect(_socket(helper)['happyEyeballs'], {'tryDelayMs': 250});
        expect(
          helper['streamSettings']['finalmask']['tcp'].single['type'],
          'fragment',
        );
        if (fronting == '192.0.2.10') {
          expect(
            _dnsServers(config)
                .where((server) => server['tag'] == 'app-dns-bootstrap'),
            isEmpty,
          );
        } else {
          _expectBootstrap(config, [fronting ?? 'tunnel.storage.example']);
        }
        expect(compiled.nodeTags, {'app-entry-0': 1, 'app-exit-0': 9});
        expect(
          inner['streamSettings']['xdriveSettings'],
          source['streamSettings']['xdriveSettings'],
        );
        expect(jsonEncode(source), before);
        expect(entry.outbound, source);
      }
    },
  );

  test('system default retains the existing managed socket and DNS output', () {
    final source = <String, dynamic>{
      'tag': 'Personal entry',
      'protocol': 'socks',
      'settings': {'address': 'entry.example', 'port': 1080},
      'streamSettings': {
        'sockopt': {
          'domainStrategy': 'UseIPv6',
          'happyEyeballs': {'tryDelayMs': 80},
          'tcpFastOpen': true,
        },
      },
    };
    final before = jsonEncode(source);
    final entry = ResolvedServer(id: 1, sourceId: 0, outbound: source);
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(),
      entries: [entry],
      regions: catalog,
      options: _options(),
    ).config;
    expect(_outbound(config, 'app-entry-0'), {
      'tag': 'app-entry-0',
      'protocol': 'socks',
      'settings': {'address': 'entry.example', 'port': 1080},
      'streamSettings': {
        'sockopt': {'tcpFastOpen': true},
      },
    });
    expect(
      _dnsServers(config)
          .where((server) => server['tag'] == 'app-dns-bootstrap'),
      isEmpty,
    );
    expect(
      (config['routing']['rules'] as List)
          .map((rule) => rule['ruleTag'])
          .take(5),
      [
        'app-dns-forward',
        'app-default',
        'app-direct-dns',
        'app-tunnel-dns',
        'app-tunnel-dot',
      ],
    );
    expect(jsonEncode(source), before);
    expect(entry.outbound, source);
  });

  test('system default disables imported XHTTP download racing without imposing DNS policy', () {
    final source = _xhttp(
      settings: {
        'path': '/upload',
        'mode': 'packet-up',
        'downloadSettings': {'address': 'shadowed.example'},
        'extra': {
          'downloadSettings': {
            'address': 'download.example',
            'port': 443,
            'network': 'xhttp',
            'xhttpSettings': {'path': '/download'},
            'sockopt': {
              'domainStrategy': 'UseIP',
              'happyEyeballs': {'tryDelayMs': 80},
              'tcpFastOpen': true,
            },
          },
        },
      },
      sockopt: {
        'domainStrategy': 'UseIP',
        'happyEyeballs': {'tryDelayMs': 80},
        'tcpFastOpen': true,
      },
    );
    final before = jsonEncode(source);
    final entry = ResolvedServer(id: 1, sourceId: 0, outbound: source);
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(),
      entries: [entry],
      regions: catalog,
      options: _options(),
    ).config;
    final outbound = _outbound(config, 'app-entry-0');
    expect(_socket(outbound), {'tcpFastOpen': true});
    final xhttp = outbound['streamSettings']['xhttpSettings'];
    final download = xhttp['extra']['downloadSettings'];
    expect(download['address'], 'download.example');
    expect(download['port'], 443);
    expect(download['xhttpSettings'], {'path': '/download'});
    expect(download['sockopt'], {
      'domainStrategy': 'UseIP',
      'tcpFastOpen': true,
    });
    expect(xhttp['downloadSettings'], {'address': 'shadowed.example'});
    expect(
      _dnsServers(config)
          .where((server) => server['tag'] == 'app-dns-bootstrap'),
      isEmpty,
    );
    expect(
      (config['routing']['rules'] as List).where(
        (rule) => rule['ruleTag'] == 'app-dns-bootstrap',
      ),
      isEmpty,
    );
    expect(jsonEncode(source), before);
    expect(entry.outbound, source);
  });

  test(
    'system default disables imported Fragment racing on the physical helper',
    () {
      final helper = <String, dynamic>{
        'tag': 'fragment',
        'protocol': 'freedom',
        'settings': {
          'fragment': {'packets': 'tlshello', 'length': '100-200'},
        },
        'streamSettings': {
          'sockopt': {
            'domainStrategy': 'UseIP',
            'happyEyeballs': {'tryDelayMs': 80},
            'tcpFastOpen': true,
          },
        },
      };
      final before = jsonEncode(helper);
      final custom = RoutingProfileState(
        name: 'Custom',
        fragmentOutbound: helper,
      );
      final config = ConnectionCompiler.compile(
        settings: ConnectionSettings(trafficMode: TrafficMode.custom),
        custom: custom,
        entries: [_node(1, 'entry.example')],
        regions: catalog,
        options: _options(),
      ).config;
      expect(
        _socket(_outbound(config, 'app-entry-0'))['dialerProxy'],
        'fragment',
      );
      expect(_socket(_outbound(config, 'fragment')), {'tcpFastOpen': true});
      expect(_outbound(config, 'fragment')['settings'], helper['settings']);
      expect(
        _dnsServers(config)
            .where((server) => server['tag'] == 'app-dns-bootstrap'),
        isEmpty,
      );
      expect(jsonEncode(helper), before);
      expect(custom.fragmentOutbound, helper);
    },
  );

  test('Raw and provider graphs retain their own dialing independently of the global preference', () {
    final source = <String, dynamic>{
      'dns': {
        'servers': ['9.9.9.9'],
      },
      'outbounds': [
        {
          'tag': 'personal-proxy',
          'protocol': 'socks',
          'settings': {'address': 'provider.example', 'port': 1080},
          'streamSettings': {
            'sockopt': {
              'domainStrategy': 'UseIPv6',
              'happyEyeballs': {'tryDelayMs': 80, 'maxConcurrentTry': 2},
            },
          },
        },
        {
          'tag': 'wireguard-proxy',
          'protocol': 'wireguard',
          'settings': {
            'secretKey': 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
            'address': ['10.0.0.2/32'],
            'peers': [
              {
                'publicKey': 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=',
                'endpoint': 'provider-wg.example:51820',
              },
            ],
          },
          'streamSettings': {
            'sockopt': {
              'domainStrategy': 'UseIPv6',
              'happyEyeballs': {'tryDelayMs': 80},
            },
          },
        },
        {
          ..._xhttp(
            settings: {
              'mode': 'packet-up',
              'downloadSettings': {
                'address': 'provider-download.example',
                'port': 443,
                'sockopt': {
                  'domainStrategy': 'UseIP',
                  'happyEyeballs': {'tryDelayMs': 80},
                },
              },
            },
          ),
          'tag': 'xhttp-proxy',
        },
        {
          ..._s3(pathStyle: false),
          'tag': 's3-proxy',
          'streamSettings': <String, dynamic>{
            ..._s3(pathStyle: false)['streamSettings'],
            'sockopt': {
              'domainStrategy': 'UseIPv6',
              'happyEyeballs': {'tryDelayMs': 80},
            },
          },
        },
      ],
    };
    final before = jsonEncode(source);
    final profile = ResolvedProfile(
      id: 99,
      sourceId: 7,
      name: 'Provider',
      config: source,
    );
    for (final provider in [false, true]) {
      CompiledConnection compile(ServerDialingSettings dialing) =>
          ConnectionCompiler.compile(
            settings: ConnectionSettings(
              expert: !provider,
              selection: const ServerSelection.server(99),
            ),
            entries: [],
            raw: provider ? null : source,
            profile: provider ? profile : null,
            regions: catalog,
            options: _options(dialing: dialing),
          );
      final baseline = compile(const ServerDialingSettings()).config;
      final config = compile(_happyEyeballs).config;
      expect(config, baseline);
      for (final outbound in source['outbounds'] as List) {
        expect(_outbound(config, outbound['tag'] as String), outbound);
      }
    }
    expect(jsonEncode(source), before);
    expect(profile.config, source);
  });

  test('advanced routes retain their DNS and helper policy without the managed dialing overlay', () {
    final source = <String, dynamic>{
      'outbounds': [
        <String, dynamic>{},
        {
          'tag': 'custom-helper',
          'protocol': 'freedom',
          'settings': {'domainStrategy': 'UseIPv6'},
        },
      ],
      'dns': {
        'servers': [
          {'tag': 'custom-dns', 'address': '9.9.9.9'},
        ],
      },
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          {
            'inboundTag': ['custom-dns'],
            'outboundTag': 'direct',
          },
        ],
      },
    };
    final advanced = AdvancedRoutingDocument.fromJson(source).state;
    final saved = advanced.toJson();
    final sourceBefore = jsonEncode(source);
    final entry = _node(1, 'entry.example');
    CompiledConnection compile(ServerDialingSettings dialing) =>
        ConnectionCompiler.compile(
          settings: ConnectionSettings(trafficMode: TrafficMode.custom),
          entries: [entry],
          custom: advanced,
          regions: catalog,
          options: _options(dialing: dialing),
        );
    final config = compile(_happyEyeballs).config;
    expect(config, compile(const ServerDialingSettings()).config);
    expect(_outbound(config, 'custom-helper')['settings'], {
      'domainStrategy': 'UseIPv6',
    });
    expect(
      config['routing']['rules'],
      contains(equals(source['routing']['rules'][0])),
    );
    expect(advanced.toJson(), saved);
    expect(jsonEncode(source), sourceBefore);
  });

  test('IPv6 off narrows actual server dialing and bootstrap without rewriting the preference', () {
    const preference = ServerDialingSettings(
      domainStrategy: ServerDomainStrategy.ipv6,
      happyEyeballs: true,
    );
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(trafficMode: TrafficMode.allVpn),
      entries: [_node(1, 'entry.example')],
      regions: catalog,
      options: _options(dialing: preference, ipv6: false),
    ).config;
    final socket = _socket(_outbound(config, 'app-entry-0'));
    expect(socket['domainStrategy'], 'UseIPv4');
    expect(socket['happyEyeballs'], isNull);
    _expectBootstrap(config, ['entry.example'], ipv6: false);
    expect(
      _dnsServers(config)
          .every((server) => server['queryStrategy'] == 'UseIPv4'),
      isTrue,
    );
    expect(preference.domainStrategy, ServerDomainStrategy.ipv6);
    expect(preference.happyEyeballs, isTrue);
  });

  test('chained final exits remain remote names while Fragment owns the physical entry socket', () {
    final entry = _node(1, 'entry.example');
    final exit = _node(9, 'exit.example');
    final before = [entry.outbound, exit.outbound];
    final compiled = ConnectionCompiler.compile(
      settings: ConnectionSettings(
        smart: SmartRoutingSettings(
          finalExitId: 9,
          fragment: true,
          fakeDns: true,
        ),
      ),
      entries: [entry],
      finalExit: exit,
      regions: catalog,
      options: _options(dialing: _happyEyeballs),
    );
    final config = compiled.config;
    final outer = _outbound(config, 'app-exit-0');
    final inner = _outbound(config, 'app-entry-0');
    final fragment = _outbound(config, 'fragment');
    expect(outer['settings']['address'], 'exit.example');
    expect(_socket(outer)['dialerProxy'], inner['tag']);
    expect(_socket(inner)['dialerProxy'], fragment['tag']);
    for (final forwarded in [outer, inner]) {
      expect(_socket(forwarded)['domainStrategy'], isNull);
      expect(_socket(forwarded)['happyEyeballs'], isNull);
    }
    expect(fragment['protocol'], 'freedom');
    expect(fragment.containsKey('settings'), false);
    expect(fragment['streamSettings']['finalmask']['tcp'], [
      {
        'type': 'fragment',
        'settings': {
          'packets': 'tlshello',
          'length': '100-200',
          'delay': '10-20',
        },
      },
    ]);
    expect(_socket(fragment)['domainStrategy'], 'UseIP');
    expect(_socket(fragment)['happyEyeballs'], {'tryDelayMs': 250});
    expect(config['routing']['balancers'].single['selector'], [outer['tag']]);
    expect(compiled.nodeTags, {'app-entry-0': 1, 'app-exit-0': 9});
    _expectBootstrap(config, ['entry.example']);
    expect([entry.outbound, exit.outbound], before);
  });

  test('XHTTP independent download sockets join bootstrap using the effective extra object', () {
    for (final extra in [false, true]) {
      final download = <String, dynamic>{
        'address': 'download.example',
        'port': 443,
        'network': 'xhttp',
        'xhttpSettings': {'path': '/download'},
      };
      final source = _xhttp(
        settings: {
          'path': '/upload',
          'mode': 'packet-up',
          if (!extra) 'downloadSettings': download,
          if (extra) ...{
            'downloadSettings': {...download, 'address': 'shadowed.example'},
            'extra': {'downloadSettings': download, 'noGRPCHeader': true},
          },
        },
      );
      final entry = ResolvedServer(id: 1, sourceId: 0, outbound: source);
      final before = entry.outbound;
      final config = ConnectionCompiler.compile(
        settings: ConnectionSettings(),
        entries: [entry],
        regions: catalog,
        options: _options(dialing: _happyEyeballs),
      ).config;
      final outbound = _outbound(config, 'app-entry-0');
      final xhttp = outbound['streamSettings']['xhttpSettings'];
      final effective = extra ? xhttp['extra'] : xhttp;
      final effectiveDownload =
          effective['downloadSettings'] as Map<String, dynamic>;
      expect(effectiveDownload['address'], 'download.example');
      expect(effectiveDownload['xhttpSettings'], download['xhttpSettings']);
      expect(_socket(outbound)['domainStrategy'], 'UseIP');
      expect(effectiveDownload['sockopt']['domainStrategy'], 'UseIP');
      expect(effectiveDownload['sockopt']['happyEyeballs'], {
        'tryDelayMs': 250,
      });
      _expectBootstrap(config, ['entry.example', 'download.example']);
      expect(entry.outbound, before);
      expect(source['streamSettings']['xhttpSettings']['path'], '/upload');
    }
  });

  test('XHTTP penetrate passes upload and download domain targets to the Fragment socket', () {
    final source = _xhttp(
      settings: {
        'path': '/upload',
        'mode': 'packet-up',
        'extra': {
          'downloadSettings': {
            'address': 'download.example',
            'port': 443,
            'network': 'xhttp',
            'xhttpSettings': {'path': '/download'},
          },
        },
      },
      sockopt: {'penetrate': true},
    );
    final entry = ResolvedServer(id: 1, sourceId: 0, outbound: source);
    final before = jsonEncode(source);
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(smart: SmartRoutingSettings(fragment: true)),
      entries: [entry],
      regions: catalog,
      options: _options(dialing: _happyEyeballs),
    ).config;
    final outbound = _outbound(config, 'app-entry-0');
    final socket = _socket(outbound);
    final fragment = _outbound(config, socket['dialerProxy'] as String);
    expect(socket['penetrate'], isTrue);
    expect(socket['domainStrategy'], isNull);
    expect(socket['happyEyeballs'], isNull);
    expect(fragment['tag'], 'fragment');
    expect(_socket(fragment)['domainStrategy'], 'UseIP');
    expect(_socket(fragment)['happyEyeballs'], {'tryDelayMs': 250});
    expect(outbound['settings']['address'], 'entry.example');
    expect(
      outbound['streamSettings']['xhttpSettings']['extra']['downloadSettings']['address'],
      'download.example',
    );
    _expectBootstrap(config, ['entry.example', 'download.example']);
    expect(jsonEncode(source), before);
  });

  test('literal IP entry destinations do not create bootstrap DNS candidates or routes', () {
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(smart: SmartRoutingSettings(entryCount: 2)),
      entries: [_node(1, '192.0.2.10'), _node(2, '2001:db8::10')],
      regions: catalog,
      options: _options(dialing: _happyEyeballs),
    ).config;
    expect(
      _dnsServers(config)
          .where((server) => server['tag'] == 'app-dns-bootstrap'),
      isEmpty,
    );
    expect(
      (config['routing']['rules'] as List).where(
        (rule) => rule['ruleTag'] == 'app-dns-bootstrap',
      ),
      isEmpty,
    );
    expect(config['routing']['balancers'].single['selector'], [
      'app-entry-0',
      'app-entry-1',
    ]);
  });

  test(
    'WireGuard resolves only peer endpoint hosts without enabling TCP racing',
    () {
      final source = <String, dynamic>{
        'tag': 'WireGuard entry',
        'protocol': 'wireguard',
        'settings': {
          'address': ['10.0.0.2/32', 'fd00::2/128'],
          'secretKey': 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
          'peers': [
            {
              'publicKey': 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=',
              'endpoint': 'peer.example:51820',
              'keepAlive': 25,
            },
            {
              'publicKey': 'AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM=',
              'endpoint': '192.0.2.10:51820',
            },
            {
              'publicKey': 'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ=',
              'endpoint': '[2001:db8::10]:51820',
            },
          ],
          'reserved': [0, 0, 0],
          'remoteDNS': ['192.0.2.53'],
        },
        'streamSettings': {
          'sockopt': {
            'domainStrategy': 'UseIPv6',
            'happyEyeballs': {'tryDelayMs': 80},
            'mark': 7,
          },
        },
      };
      final before = jsonEncode(source);
      final entry = ResolvedServer(id: 1, sourceId: 0, outbound: source);
      final config = ConnectionCompiler.compile(
        settings: ConnectionSettings(),
        entries: [entry],
        regions: catalog,
        options: _options(dialing: _happyEyeballs),
      ).config;
      final outbound = _outbound(config, 'app-entry-0');
      expect(_socket(outbound), {'domainStrategy': 'UseIP', 'mark': 7});
      expect(outbound['settings'], source['settings']);
      _expectBootstrap(config, ['peer.example']);
      expect(jsonEncode(source), before);
      expect(entry.outbound, source);
    },
  );

  test('chained WireGuard exits resolve peers locally while retaining their proxy hop', () {
    final entry = _node(1, 'entry.example');
    final exit = ResolvedServer(
      id: 9,
      sourceId: 0,
      outbound: {
        'tag': 'WireGuard exit',
        'protocol': 'wireguard',
        'settings': {
          'secretKey': 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
          'address': ['10.0.0.2/32'],
          'peers': [
            {
              'publicKey': 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=',
              'endpoint': 'exit-peer.example:51820',
            },
          ],
        },
        'streamSettings': {
          'sockopt': {
            'domainStrategy': 'UseIPv6',
            'happyEyeballs': {'tryDelayMs': 80},
          },
        },
      },
    );
    final before = [entry.outbound, exit.outbound];
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(smart: SmartRoutingSettings(finalExitId: 9)),
      entries: [entry],
      finalExit: exit,
      regions: catalog,
      options: _options(dialing: _happyEyeballs),
    ).config;
    final outbound = _outbound(config, 'app-exit-0');
    expect(_socket(outbound), {
      'domainStrategy': 'UseIP',
      'dialerProxy': 'app-entry-0',
    });
    expect(outbound['settings'], exit.outbound['settings']);
    expect(_socket(_outbound(config, 'app-entry-0'))['happyEyeballs'], {
      'tryDelayMs': 250,
    });
    _expectBootstrap(config, ['entry.example', 'exit-peer.example']);
    expect([entry.outbound, exit.outbound], before);
  });
}

RuntimeOptions _options({
  ServerDialingSettings dialing = const ServerDialingSettings(),
  bool ipv6 = true,
}) => RuntimeOptions(
  platform: ConnectionPlatform.android,
  sessionDirectory: '/unused-session',
  metricsPort: 18186,
  socksPort: 18187,
  ipv6: ipv6,
  dialing: dialing,
);

ResolvedServer _node(int id, String address) => ResolvedServer(
  id: id,
  sourceId: 0,
  outbound: {
    'tag': 'Personal $id',
    'protocol': 'socks',
    'settings': {'address': address, 'port': 1080},
  },
);

Map<String, dynamic> _xhttp({
  required Map<String, dynamic> settings,
  Map<String, dynamic>? sockopt,
}) => {
  'tag': 'XHTTP entry',
  'protocol': 'vless',
  'settings': {
    'address': 'entry.example',
    'port': 443,
    'id': '11111111-1111-4111-8111-111111111111',
    'encryption': 'none',
  },
  'streamSettings': {
    'network': 'xhttp',
    'security': 'tls',
    'tlsSettings': {'serverName': 'certificate.example'},
    'sockopt': ?sockopt,
    'xhttpSettings': settings,
  },
};

Map<String, dynamic> _s3({bool? pathStyle, String? fronting}) => {
  'tag': 'S3 entry',
  'protocol': 'vless',
  'settings': {
    'address': 'logical.example',
    'port': 443,
    'id': '11111111-1111-4111-8111-111111111111',
    'encryption': 'none',
  },
  'mux': {'enabled': true, 'concurrency': 8},
  'streamSettings': {
    'network': 'xdrive',
    'security': 'tls',
    'tlsSettings': {'serverName': 'certificate.example'},
    if (fronting != null) ...{'address': fronting, 'port': 9443},
    'xdriveSettings': {
      'service': 's3',
      'remoteFolder': 'sessions/client',
      'secrets': ['test-access', 'test-secret'],
      's3': {
        'endpoint': 'https://Storage.Example.:9443/base/',
        'bucket': 'tunnel',
        'pathStyle': ?pathStyle,
      },
      'future': {'keep': true},
    },
  },
};

Map<String, dynamic> _outbound(Map<String, dynamic> config, String tag) =>
    (config['outbounds'] as List).cast<Map<String, dynamic>>().singleWhere(
      (outbound) => outbound['tag'] == tag,
    );

Map<String, dynamic> _socket(Map<String, dynamic> outbound) =>
    ((outbound['streamSettings'] as Map?)?['sockopt']
        as Map<String, dynamic>?) ??
    {};

List<Map<String, dynamic>> _dnsServers(Map<String, dynamic> config) =>
    (config['dns']['servers'] as List).cast<Map<String, dynamic>>();

void _expectBootstrap(
  Map<String, dynamic> config,
  List<String> domains, {
  bool ipv6 = true,
}) {
  final servers = _dnsServers(config);
  final bootstrap = servers
      .where((server) => server['tag'] == 'app-dns-bootstrap')
      .toList();
  expect(bootstrap.map((server) => server['address']), [
    '8.8.8.8',
    if (ipv6) '2001:4860:4860::8888',
  ]);
  expect(servers.take(bootstrap.length), bootstrap);
  for (final (index, server) in bootstrap.indexed) {
    expect(
      server['domains'],
      unorderedEquals(domains.map((domain) => 'full:$domain')),
    );
    expect(server['skipFallback'], isTrue);
    expect(server['queryStrategy'], ipv6 ? 'UseIP' : 'UseIPv4');
    expect(server['finalQuery'] == true, index == bootstrap.length - 1);
  }
  final first = (config['routing']['rules'] as List).first;
  expect(first['ruleTag'], 'app-dns-bootstrap');
  expect(first['inboundTag'], ['app-dns-bootstrap']);
  expect(first['outboundTag'], 'direct');
  expect(first['balancerTag'], isNull);
  expect(
    _outbound(config, first['outboundTag'] as String)['protocol'],
    'freedom',
  );
}
