import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';

import 'compiler_test.dart' show catalog, node, options;

const _ruleTag = 'app-smart-google-play';
const _domains = ['full:services.googleapis.cn', 'domain:xn--ngstr-lra8j.com'];
const _customDns = RoutingDnsSettings(
  proxyResolvers: [
    RoutingDnsResolver(address: 'tcp://1.1.1.1'),
    RoutingDnsResolver(address: 'https://dns.google/dns-query'),
  ],
  directResolvers: [
    RoutingDnsResolver(address: '223.5.5.5'),
    RoutingDnsResolver(address: '119.29.29.29'),
  ],
);

void main() {
  for (final (label, regions, enabled) in [
    ('empty regions', <String>[], false),
    ('Russia only', ['RU'], false),
    ('other historical regions', ['RU', 'US'], false),
    ('China', ['CN'], true),
    ('lowercase China', ['cn'], true),
    ('mixed historical and duplicate China', ['RU', 'cN', 'CN'], true),
  ]) {
    test('Google Play proxy exception follows CN intent: $label', () {
      final config = _compileSmart(
        SmartRoutingSettings(directRegions: regions),
      );
      expect(
        _rules(config).where((rule) => rule['ruleTag'] == _ruleTag),
        enabled
            ? [
                {
                  'ruleTag': _ruleTag,
                  'domain': _domains,
                  'balancerTag': 'proxy',
                },
              ]
            : isEmpty,
      );
      expect(_targetServers(config).isNotEmpty, enabled);
      if (enabled) {
        expect(
          _rules(config).singleWhere(
            (rule) => rule['ruleTag'] == 'app-smart-direct-domain',
          )['domain'],
          contains('geosite:CN'),
        );
      }
    });
  }

  test(
    'CN intent keeps literal exceptions when installed categories are absent',
    () {
      final config = _compileSmart(
        SmartRoutingSettings(
          directPrivate: false,
          directApple: false,
          directWindows: false,
        ),
        regions: const RegionCatalog.empty(),
      );
      expect(_rules(config).where((rule) => rule['ruleTag'] == _ruleTag), [
        {'ruleTag': _ruleTag, 'domain': _domains, 'balancerTag': 'proxy'},
      ]);
      expect(
        _rules(config).where(
          (rule) =>
              rule['outboundTag'] == 'direct' &&
              (rule['domain'] != null || rule['ip'] != null),
        ),
        isEmpty,
      );
      expect(
        _targetServers(config)
            .where((server) => server['tag'] == RoutingDnsSettings.proxyTag),
        hasLength(1),
      );
    },
  );

  for (final blockAds in [false, true]) {
    for (final directWindows in [false, true]) {
      test(
        'Google Play rule order with ads=$blockAds Windows=$directWindows',
        () {
          final config = _compileSmart(
            SmartRoutingSettings(
              blockAds: blockAds,
              directWindows: directWindows,
            ),
          );
          final rules = _rules(config);
          expect(
            rules
                .where(
                  (rule) => (rule['ruleTag'] as String? ?? '').startsWith(
                    'app-smart-',
                  ),
                )
                .map((rule) => rule['ruleTag']),
            [
              if (blockAds) 'app-smart-ads',
              if (directWindows) 'app-smart-github',
              _ruleTag,
              'app-smart-direct-domain',
              'app-smart-direct-ip',
            ],
          );
          expect(
            rules.singleWhere(
              (rule) => rule['ruleTag'] == 'app-smart-direct-domain',
            )['domain'],
            [
              'geosite:PRIVATE',
              'geosite:APPLE',
              if (directWindows) ...['geosite:MICROSOFT', 'geosite:BING'],
              'geosite:CN',
            ],
          );
          expect(
            rules.singleWhere(
              (rule) => rule['ruleTag'] == 'app-smart-direct-ip',
            )['ip'],
            ['geoip:PRIVATE', 'geoip:CN'],
          );
        },
      );
    }
  }

  for (final (label, dns, directDns, fakeDns, ipv6) in [
    ('default resolvers', const RoutingDnsSettings(), true, false, true),
    ('configured resolver order', _customDns, true, false, true),
    (
      'same-exit fallback',
      _customDns.copyWith(sameExitOnly: true),
      true,
      false,
      true,
    ),
    ('FakeDNS with IPv4 queries', _customDns, true, true, false),
    ('direct DNS disabled', _customDns, false, false, true),
  ]) {
    test('Google Play DNS uses ordered proxy resolvers: $label', () {
      final config = _compileSmart(
        SmartRoutingSettings(dns: dns, directDns: directDns, fakeDns: fakeDns),
        ipv6: ipv6,
      );
      final servers = _dnsServers(config);
      final targetServers = _targetServers(config);
      final proxyServers = targetServers
          .where((server) => server['tag'] == RoutingDnsSettings.proxyTag)
          .toList();
      expect(
        proxyServers.map((server) => server['address']),
        dns.effectiveProxyResolvers.map((resolver) => resolver.address),
      );
      expect(targetServers.map((server) => server['tag']), [
        if (fakeDns) FakeDns.tag,
        for (final _ in dns.effectiveProxyResolvers)
          RoutingDnsSettings.proxyTag,
      ]);
      for (final server in targetServers) {
        expect(server['domains'], _domains);
        expect(server['skipFallback'], true);
      }
      final githubServers = servers.where(
        (server) =>
            (server['domains'] as List?)?.contains('geosite:GITHUB') ?? false,
      );
      expect(
        servers.indexOf(githubServers.last),
        lessThan(servers.indexOf(targetServers.first)),
      );
      expect(proxyServers.map((server) => server['finalQuery']), [
        for (var i = 0; i < proxyServers.length - 1; i++) null,
        true,
      ]);
      final directServers = servers
          .where((server) => server['tag'] == RoutingDnsSettings.directTag)
          .toList();
      if (directDns) {
        expect(
          directServers.map((server) => server['address']),
          dns.effectiveDirectResolvers.map((resolver) => resolver.address),
        );
        expect(directServers.first['domains'], contains('geosite:CN'));
        expect(
          servers.indexOf(targetServers.last),
          lessThan(servers.indexOf(directServers.first)),
        );
        expect(
          directServers.last['finalQuery'],
          dns.sameExitOnly ? true : isNull,
        );
      } else {
        expect(directServers, isEmpty);
      }
      expect(config['dns']['disableFallbackIfMatch'], dns.sameExitOnly);
      expect(servers.map((server) => server['queryStrategy']).toSet(), {
        ipv6 ? 'UseIP' : 'UseIPv4',
      });
      expect(servers.last['tag'], RoutingDnsSettings.proxyTag);
      expect(servers.last['domains'], isNull);
      expect(servers.last['finalQuery'], isNull);
      if (fakeDns) {
        expect(targetServers.first['address'], FakeDns.address);
        expect(targetServers.first['finalQuery'], isNull);
        expect(
          servers
              .where((server) => server['tag'] == FakeDns.tag)
              .last['domains'],
          isNull,
        );
        expect(config['fakedns'], hasLength(2));
      }
    });
  }

  test(
    'compiling old settings leaves their input and encoded settings unchanged',
    () {
      for (final input in <Map<String, dynamic>>[
        {},
        {
          'trafficMode': 'smart',
          'smart': {
            'directRegions': ['RU', 'cN', 'CN'],
            'directPrivate': false,
            'directApple': false,
            'directWindows': false,
            'directDnsAddress': '223.5.5.5',
          },
        },
      ]) {
        final originalInput = jsonEncode(input);
        final settings = ConnectionSettings.fromJson(input);
        final originalSettings = jsonEncode(settings.toJson());
        for (final regions in [catalog, const RegionCatalog.empty()]) {
          final config = ConnectionCompiler.compile(
            settings: settings,
            entries: [node(1)],
            regions: regions,
            options: options(),
          ).config;
          expect(
            _rules(config).where((rule) => rule['ruleTag'] == _ruleTag),
            hasLength(1),
          );
          expect(jsonEncode(input), originalInput);
          expect(jsonEncode(settings.toJson()), originalSettings);
        }
      }
    },
  );

  test('Custom retains an explicit direct target rule and its direct DNS', () {
    final custom = RoutingProfileState(
      name: 'Explicit direct',
      rules: [
        RoutingRuleState(domain: _domains, action: RoutingRuleAction.direct),
      ],
    );
    final before = custom.encode();
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(trafficMode: TrafficMode.custom),
      custom: custom,
      entries: [node(1)],
      regions: catalog,
      options: options(),
    ).config;
    expect(
      _rules(config).where((rule) => rule['ruleTag'] == _ruleTag),
      isEmpty,
    );
    expect(_rules(config).singleWhere(_matchesTargets), {
      'ruleTag': 'app-custom-0',
      'domain': _domains,
      'outboundTag': 'direct',
    });
    expect(_targetServers(config).single['tag'], RoutingDnsSettings.directTag);
    expect(_targetServers(config).single['domains'], _domains);
    expect(custom.encode(), before);
  });

  test('All VPN does not inherit the Smart exception or domain DNS blocks', () {
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(trafficMode: TrafficMode.allVpn),
      entries: [node(1)],
      regions: catalog,
      options: options(),
    ).config;
    expect(
      _rules(config).where((rule) => rule['ruleTag'] == _ruleTag),
      isEmpty,
    );
    expect(_targetServers(config), isEmpty);
  });

  test('Advanced Custom keeps its explicit direct target policy', () {
    final source = _directSource()..['outbounds'] = [<String, dynamic>{}];
    final custom = AdvancedRoutingDocument.fromJson(
      source,
      name: 'Explicit direct',
    ).state;
    final before = custom.encode();
    final config = ConnectionCompiler.compile(
      settings: ConnectionSettings(trafficMode: TrafficMode.custom),
      custom: custom,
      entries: [node(1)],
      regions: catalog,
      options: options(),
    ).config;
    expect(
      _rules(config).where((rule) => rule['ruleTag'] == _ruleTag),
      isEmpty,
    );
    expect(_rules(config).singleWhere(_matchesTargets), {
      'domain': _domains,
      'outboundTag': 'direct',
    });
    expect(config['dns']['servers'], ['9.9.9.9']);
    expect(custom.encode(), before);
  });

  for (final provider in [false, true]) {
    test(
      '${provider ? 'Provider' : 'Raw'} keeps explicit target direct rules and DNS',
      () {
        final source = _directSource();
        final before = jsonEncode(source);
        final config = ConnectionCompiler.compile(
          settings: ConnectionSettings(expert: !provider),
          entries: const [],
          raw: provider ? null : source,
          profile: provider
              ? ResolvedProfile(
                  id: 99,
                  sourceId: 7,
                  name: 'Provider',
                  config: source,
                )
              : null,
          regions: catalog,
          options: options(),
        ).config;
        expect(
          _rules(config).where((rule) => rule['ruleTag'] == _ruleTag),
          isEmpty,
        );
        expect(_rules(config).singleWhere(_matchesTargets), {
          'domain': _domains,
          'outboundTag': 'direct',
        });
        expect(config['dns']['servers'], ['9.9.9.9']);
        expect(jsonEncode(source), before);
      },
    );
  }
}

Map<String, dynamic> _compileSmart(
  SmartRoutingSettings smart, {
  RegionCatalog? regions,
  bool ipv6 = true,
}) => ConnectionCompiler.compile(
  settings: ConnectionSettings(smart: smart),
  entries: [node(1)],
  regions: regions ?? catalog,
  options: options(ipv6: ipv6),
).config;

List<Map<String, dynamic>> _rules(Map<String, dynamic> config) =>
    (config['routing']['rules'] as List).cast<Map<String, dynamic>>();

List<Map<String, dynamic>> _dnsServers(Map<String, dynamic> config) =>
    (config['dns']['servers'] as List).cast<Map<String, dynamic>>();

bool _matchesTargets(Map<String, dynamic> rule) =>
    (rule['domain'] as List?)?.contains(_domains.first) ?? false;

List<Map<String, dynamic>> _targetServers(Map<String, dynamic> config) =>
    _dnsServers(config)
        .where(
          (server) =>
              (server['domains'] as List?)?.contains(_domains.first) ?? false,
        )
        .toList();

Map<String, dynamic> _directSource() => {
  'outbounds': [
    {'tag': 'direct', 'protocol': 'freedom'},
  ],
  'dns': {
    'servers': ['9.9.9.9'],
  },
  'routing': {
    'rules': [
      {'domain': _domains, 'outboundTag': 'direct'},
    ],
  },
};
