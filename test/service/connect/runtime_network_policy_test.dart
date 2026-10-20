import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/runtime_network_policy.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';

CompiledConnection compileRaw(
  Map<String, dynamic> source, {
  bool ipv6 = false,
}) => ConnectionCompiler.compile(
  settings: ConnectionSettings(expert: true),
  entries: [],
  raw: source,
  regions: RegionCatalog.fromJson(
    {'geosite': <String, dynamic>{}, 'geoip': <String, dynamic>{}},
    geositeCodes: [],
    geoipCodes: [],
  ),
  options: RuntimeOptions(
    platform: ConnectionPlatform.android,
    sessionDirectory: '/fixture/session',
    metricsPort: 18002,
    socksPort: 18003,
    ipv6: ipv6,
  ),
);

void main() {
  test('Raw IPv6 policy changes only DNS query strategies', () {
    final source = <String, dynamic>{
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'socks',
          'settings': {
            'servers': [
              {'address': '2001:db8::1', 'port': 1080},
            ],
          },
        },
        {
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': {'domainStrategy': 'UseIPv6'},
          'streamSettings': {
            'sockopt': {'domainStrategy': 'UseIPv6'},
          },
        },
        {'tag': 'app-ipv6-block', 'protocol': 'blackhole'},
        {
          'tag': 'wg',
          'protocol': 'wireguard',
          'settings': {
            'peers': [
              {'endpoint': 'node.test:51820'},
              {'endpoint': '[2001:db8::2]:51820'},
            ],
          },
        },
      ],
      'routing': {
        'rules': [
          {
            'ip': ['::/0'],
            'outboundTag': 'proxy',
          },
          {'network': 'tcp,udp', 'outboundTag': 'direct'},
        ],
      },
      'dns': {
        'hosts': {
          'node.test': ['2001:db8::2'],
        },
        'queryStrategy': 'UseIPv6',
        'servers': [
          '2001:4860:4860::8888',
          {
            'address': 'https://dns.google/dns-query',
            'queryStrategy': 'UseIPv6',
          },
        ],
      },
    };
    final original = jsonEncode(source);
    final disabled = compileRaw(source).config;
    final enabled = compileRaw(source, ipv6: true).config;

    expect(
      (disabled['outbounds'] as List)
          .take((source['outbounds'] as List).length)
          .toList(),
      source['outbounds'],
    );
    expect(
      (disabled['routing']['rules'] as List).skip(1).toList(),
      source['routing']['rules'],
    );
    expect(disabled['dns']['hosts'], source['dns']['hosts']);
    expect(disabled['dns']['queryStrategy'], 'UseIPv4');
    expect(disabled['dns']['servers'], [
      '2001:4860:4860::8888',
      {'address': 'https://dns.google/dns-query', 'queryStrategy': 'UseIPv4'},
    ]);
    expect(enabled['dns']['queryStrategy'], 'UseIP');
    expect(enabled['dns']['servers'].last['queryStrategy'], 'UseIP');
    expect(disabled..remove('dns'), enabled..remove('dns'));
    expect(jsonEncode(source), original);
  });

  test('IPv6-off Raw preserves its proxy and supplements DNS without bootstrap hosts', () {
    final source = {
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'socks',
          'settings': {
            'servers': [
              {'address': 'node.test', 'port': 1080},
            ],
          },
        },
      ],
    };
    final config = compileRaw(source).config;
    expect(config['outbounds'].first, source['outbounds']!.single);
    expect(config['dns']['hosts'], isNull);
    expect(config['dns']['queryStrategy'], 'UseIPv4');
    expect(config['dns']['servers'].single['address'], '8.8.8.8');
    expect(config['routing']['rules'], everyElement(contains('inboundTag')));
  });

  test(
    'IPv6 DNS endpoints remain unchanged while query strategies use IPv4',
    () {
      for (final address in [
        '2001:4860:4860::8888',
        '[2001:db8::1]',
        'https://[2001:db8::1]/dns-query',
        'tcp://[2001:db8::1]:53',
        'https+local://[2001:db8::1]/dns-query',
      ]) {
        for (final objectServer in [false, true]) {
          final config = compileRaw({
            'outbounds': [
              {'tag': 'direct', 'protocol': 'freedom'},
            ],
            'dns': {
              'servers': [
                objectServer ? {'address': address} : address,
              ],
            },
          }).config;
          expect(config['dns']['queryStrategy'], 'UseIPv4');
          expect(config['dns']['servers'], [
            objectServer
                ? {'address': address, 'queryStrategy': 'UseIPv4'}
                : address,
          ]);
        }
      }
    },
  );

  test('local DNS still requires the selected outbound interface', () {
    for (final scheme in [
      'https+local',
      'h2c+local',
      'tcp+local',
      'quic+local',
    ]) {
      for (final host in ['192.0.2.1', '[2001:db8::1]', 'dns.example.test']) {
        final config = {
          'dns': {
            'servers': ['$scheme://$host:443'],
          },
        };
        expect(
          () => validateLocalDnsNetworkPolicy(config, requiresInterface: true),
          throwsFormatException,
        );
        validateLocalDnsNetworkPolicy(config, requiresInterface: false);
      }
    }
  });

  test('permitted DNS modes remain untouched including ordinary localhost', () {
    final config = {
      'dns': {
        'servers': [
          'localhost',
          'fakedns',
          '8.8.8.8',
          '2001:4860:4860::8888',
          'https://dns.google/dns-query',
        ],
      },
    };
    final source = jsonEncode(config);
    validateLocalDnsNetworkPolicy(config, requiresInterface: true);
    expect(jsonEncode(config), source);
  });
}
