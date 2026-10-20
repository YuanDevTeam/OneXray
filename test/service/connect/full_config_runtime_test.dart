import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/xray/vpn_config.dart';

const _ipv4 = '192.0.2.53';
const _ipv6 = '2001:db8::53';

RuntimeOptions _options({
  ConnectionPlatform platform = ConnectionPlatform.android,
  WindowsMode windowsMode = WindowsMode.exe,
  bool ipv6 = true,
}) => RuntimeOptions(
  platform: platform,
  windowsMode: windowsMode,
  sessionDirectory: '/unused-full-config-session',
  metricsPort: 18186,
  socksPort: 18187,
  ipv6: ipv6,
  tunDnsIpv4Address: _ipv4,
  tunDnsIpv6Address: _ipv6,
  interfaceName: 'physical-interface',
);

Map<String, dynamic> _source() => {
  'outbounds': [
    {
      'tag': 'provider-proxy',
      'protocol': 'socks',
      'settings': {'address': 'full-config.example.test', 'port': 1080},
      'streamSettings': {
        'sockopt': {'domainStrategy': 'ForceIP'},
      },
    },
    {'tag': 'provider-block', 'protocol': 'blackhole'},
  ],
  'routing': {
    'domainStrategy': 'IPIfNonMatch',
    'rules': [
      {
        'domain': ['domain:blocked.example.test'],
        'outboundTag': 'provider-block',
      },
    ],
  },
};

CompiledConnection _compile(
  Map<String, dynamic> source, {
  bool provider = false,
  RuntimeOptions? options,
}) => ConnectionCompiler.compile(
  settings: provider
      ? ConnectionSettings(selection: const ServerSelection.server(99))
      : ConnectionSettings(expert: true),
  entries: const [],
  raw: provider ? null : source,
  profile: provider
      ? ResolvedProfile(id: 99, sourceId: 7, name: 'Provider', config: source)
      : null,
  regions: const RegionCatalog.empty(),
  options: options ?? _options(),
);

void main() {
  test('only the native session may supply a TUN descriptor', () {
    for (final provider in [false, true]) {
      for (final platform in ConnectionPlatform.values) {
        final source = _source()
          ..['env'] = {
            'xray.tun.fd': '77',
            'XRAY_TUN_FD': '88',
            'provider.custom': 'preserved',
          };
        final runtime = _compile(
          source,
          provider: provider,
          options: _options(platform: platform),
        ).config;
        expect(runtime['env'].containsKey('xray.tun.fd'), false);
        expect(runtime['env'].containsKey('XRAY_TUN_FD'), false);
        expect(runtime['env']['provider.custom'], 'preserved');
        expect(source['env']['xray.tun.fd'], '77');
        expect(source['env']['XRAY_TUN_FD'], '88');
      }
    }
  });

  for (final provider in [false, true]) {
    final kind = provider ? 'Provider' : 'Raw';
    for (final dnsCase in [
      'missing',
      'null',
      'servers-null',
      'empty',
      'hosts-only',
    ]) {
      test('$kind supplements $dnsCase DNS without changing the source', () {
        final source = _source();
        switch (dnsCase) {
          case 'null':
            source['dns'] = null;
          case 'servers-null':
            source['dns'] = {'servers': null};
          case 'empty':
            source['dns'] = {'servers': <dynamic>[]};
          case 'hosts-only':
            source['dns'] = {
              'hosts': {'full-config.example.test': '192.0.2.10'},
              'disableCache': true,
            };
        }
        final before = jsonEncode(source);
        final runtime = _compile(source, provider: provider).config;
        expect(runtime['dns']['servers'], [
          for (final address in [_ipv4, _ipv6])
            {
              'address': address,
              'tag': VpnConfigAdapter.defaultDnsTag,
              'queryStrategy': 'UseIP',
            },
        ]);
        if (dnsCase == 'hosts-only') {
          expect(runtime['dns']['hosts'], source['dns']['hosts']);
          expect(runtime['dns']['disableCache'], true);
        }
        final rules = runtime['routing']['rules'] as List;
        expect(rules.first, {
          'type': 'field',
          'inboundTag': [VpnConfigAdapter.defaultDnsTag],
          'outboundTag': VpnConfigAdapter.defaultDnsDirectTag,
        });
        expect(rules.last, source['routing']['rules'].single);
        expect(runtime['routing']['domainStrategy'], 'IPIfNonMatch');
        final outbounds = runtime['outbounds'] as List;
        expect(outbounds.take(2).toList(), source['outbounds']);
        expect(
          outbounds.first['settings']['address'],
          'full-config.example.test',
        );
        expect(
          outbounds.first['streamSettings']['sockopt']['domainStrategy'],
          'ForceIP',
        );
        expect(
          outbounds.where(
            (value) => value['tag'] == VpnConfigAdapter.defaultDnsDirectTag,
          ),
          hasLength(1),
        );
        expect(jsonEncode(source), before);
      });
    }
  }

  test('fallback does not coerce explicit or malformed DNS values', () {
    for (final dns in <dynamic>[
      false,
      {'servers': 'invalid'},
      {
        'servers': {'address': 'invalid'},
      },
      {
        'servers': [false],
      },
      {
        'servers': ['localhost'],
      },
      {
        'servers': ['fakedns'],
      },
      {
        'servers': [
          {'address': 'https://dns.example.test/dns-query', 'tag': 'user-dns'},
        ],
      },
    ]) {
      final source = _source()..['dns'] = dns;
      final before = jsonEncode(source);
      final supplemented = VpnConfigAdapter.withDefaultDns(
        source,
        ipv4Address: _ipv4,
        ipv6Address: _ipv6,
      );
      expect(supplemented, source);
      expect(jsonEncode(source), before);
    }
  });

  test(
    'explicit DNS retains its servers and receives no fallback resolver route',
    () {
      for (final provider in [false, true]) {
        final source = _source()
          ..['dns'] = {
            'servers': ['localhost', 'fakedns', '9.9.9.9'],
            'hosts': {'full-config.example.test': '192.0.2.10'},
          };
        final runtime = _compile(source, provider: provider).config;
        expect(runtime['dns']['servers'], source['dns']['servers']);
        expect(runtime['dns']['hosts'], source['dns']['hosts']);
        expect(
          (runtime['routing']['rules'] as List).any(
            (rule) =>
                (rule['inboundTag'] as List?)?.contains(
                  VpnConfigAdapter.defaultDnsTag,
                ) ==
                true,
          ),
          false,
        );
      }
    },
  );

  test(
    'declared tunnel DNS policy is retained alongside bounded fallback routing',
    () {
      for (final provider in [false, true]) {
        final source = _source();
        final rule = {
          'inboundTag': ['tunIn'],
          'port': 53,
          'network': 'udp',
          'outboundTag': 'provider-proxy',
        };
        source['routing']['rules'].insert(0, rule);
        final runtime = _compile(source, provider: provider).config;
        expect(
          (runtime['routing']['rules'] as List).skip(1).toList(),
          source['routing']['rules'],
        );
        expect(
          (runtime['outbounds'] as List).any(
            (outbound) => outbound['protocol'] == 'dns',
          ),
          false,
        );
      }
    },
  );

  test('runtime fallback is stable on repeated adaptation', () {
    final adapted = VpnConfigAdapter.adapt(_source());
    final first = VpnConfigAdapter.withDefaultDns(
      adapted,
      ipv4Address: _ipv4,
      ipv6Address: _ipv6,
    );
    final second = VpnConfigAdapter.withDefaultDns(
      VpnConfigAdapter.adapt(first),
      ipv4Address: _ipv4,
      ipv6Address: _ipv6,
    );
    expect(second, first);
  });

  test('all platforms use the current DNS family and physical interface policy', () {
    for (final platform in ConnectionPlatform.values) {
      for (final ipv6 in [false, true]) {
        for (final windowsMode
            in platform == ConnectionPlatform.windows
                ? WindowsMode.values
                : [WindowsMode.exe]) {
          final runtimeOptions = _options(
            platform: platform,
            windowsMode: windowsMode,
            ipv6: ipv6,
          );
          final compiled = _compile(_source(), options: runtimeOptions);
          final config = compiled.config;
          final servers = config['dns']['servers'] as List;
          expect(servers.map((value) => value['address']).toList(), [
            _ipv4,
            if (ipv6) _ipv6,
          ]);
          expect(
            servers.every(
              (value) => value['queryStrategy'] == (ipv6 ? 'UseIP' : 'UseIPv4'),
            ),
            true,
          );
          final direct = (config['outbounds'] as List).singleWhere(
            (value) => value['tag'] == VpnConfigAdapter.defaultDnsDirectTag,
          );
          final interface = direct['streamSettings']?['sockopt']?['interface'];
          expect(
            interface,
            [
                  ConnectionPlatform.windows,
                  ConnectionPlatform.linux,
                ].contains(platform)
                ? 'physical-interface'
                : null,
          );
          _fixture(
            'raw-${platform.name}-${windowsMode.name}-${ipv6 ? 'dual' : 'ipv4'}',
            compiled,
          );
        }
      }
    }
  });

  test(
    'advanced templates do not acquire complete-configuration DNS defaults',
    () {
      final template = AdvancedRoutingDocument.fromJson({
        'outbounds': [<String, dynamic>{}],
      }).state;
      final compiled = ConnectionCompiler.compile(
        settings: ConnectionSettings(trafficMode: TrafficMode.custom),
        entries: [
          ResolvedServer(id: 1, sourceId: 1, outbound: {'protocol': 'freedom'}),
        ],
        custom: template,
        regions: const RegionCatalog.empty(),
        options: _options(),
      );
      expect(compiled.config['dns']['servers'], null);
      expect(
        (compiled.config['outbounds'] as List).any(
          (value) =>
              value['tag'] == VpnConfigAdapter.defaultDnsDirectTag ||
              value['protocol'] == 'dns',
        ),
        false,
      );
    },
  );

  test('reserved default resolver tags cannot redirect unrelated traffic', () {
    final source = _source();
    source['outbounds'].add({
      'tag': VpnConfigAdapter.defaultDnsDirectTag,
      'protocol': 'freedom',
      'settings': {'domainStrategy': 'UseIPv4'},
    });
    expect(() => _compile(source), throwsFormatException);
    final collision = _source()
      ..['inbounds'] = [
        {
          'tag': VpnConfigAdapter.defaultDnsTag,
          'protocol': 'socks',
          'port': 1080,
        },
      ];
    expect(() => _compile(collision), throwsFormatException);
  });
}

void _fixture(String name, CompiledConnection compiled) {
  const target = String.fromEnvironment('FULL_CONFIG_FIXTURES');
  if (target.isEmpty) return;
  Directory(target).createSync(recursive: true);
  File('$target/$name.json').writeAsStringSync(compiled.xrayJson);
}
