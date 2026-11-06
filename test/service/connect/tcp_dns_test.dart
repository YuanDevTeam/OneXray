import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/settings.dart';

import 'compiler_test.dart' show catalog, options;

ResolvedServer httpNode([int id = 266]) => ResolvedServer(
  id: id,
  sourceId: 0,
  outbound: {
    'tag': 'HTTPS proxy',
    'protocol': 'http',
    'settings': {
      'servers': [
        {'address': '192.0.2.1', 'port': 443},
      ],
    },
    'streamSettings': {'security': 'tls'},
  },
);

void main() {
  test('HTTP proxy uses TCP for default resolvers and forwarded DNS', () {
    for (final mode in TrafficMode.values) {
      final plan = ConnectionCompiler.compile(
        settings: ConnectionSettings(
          trafficMode: mode,
          smart: SmartRoutingSettings(
            directRegions: [],
            directPrivate: false,
            directApple: false,
            directWindows: false,
          ),
        ),
        custom: mode == TrafficMode.custom
            ? RoutingProfileState(name: 'Default DNS')
            : null,
        entries: [httpNode()],
        regions: catalog,
        options: options(platform: ConnectionPlatform.ios),
      );
      final config = plan.config;
      expect(
        (config['dns']['servers'] as List).map((server) => server['address']),
        everyElement('tcp://8.8.8.8'),
      );
      final forwarding = (config['outbounds'] as List).singleWhere(
        (outbound) => outbound['tag'] == 'dnsOut',
      );
      expect(forwarding['settings'], {
        'rewriteNetwork': 'tcp',
        'rules': [
          {'action': 'hijack', 'qType': '1,28'},
          {'action': 'direct'},
        ],
      });
      expect(
        forwarding['streamSettings']['sockopt']['dialerProxy'],
        mode == TrafficMode.allVpn ? 'app-entry-0' : 'app-dns-forward',
      );
      const target = String.fromEnvironment('P2_FIXTURES');
      if (target.isNotEmpty) {
        Directory(target).createSync(recursive: true);
        File('$target/default-http-${mode.name}.json')
            .writeAsStringSync(plan.xrayJson);
      }
    }
  });

  test(
    'new advanced template forwards other DNS over TCP through a helper',
    () {
      final template = jsonDecode(AdvancedRoutingProfile.defaultText);
      expect(template['dns']['servers'].single['address'], 'tcp://8.8.8.8');
      final forwarding = (template['outbounds'] as List).singleWhere(
        (outbound) => outbound['tag'] == 'dnsOut',
      );
      expect(forwarding['settings']['rewriteNetwork'], 'tcp');
      expect(forwarding['settings']['rules'].last, {'action': 'direct'});
      expect(
        forwarding['streamSettings']['sockopt']['dialerProxy'],
        'dns-forward',
      );
    },
  );

  test(
    'stored ordinary resolver addresses retain their explicit transport',
    () {
      final stored = {
        'proxyResolvers': [
          {'address': '8.8.8.8'},
          {'address': 'https://1.1.1.1/dns-query'},
        ],
        'directResolvers': [
          {'address': '192.168.1.1'},
        ],
        'disableCache': false,
        'sameExitOnly': false,
        'nonAddressPolicy': 'proxy',
      };
      final before = jsonEncode(stored);
      final settings = RoutingDnsSettings.fromJson(stored);
      expect(settings.toJson(), stored);
      final oldSmart = SmartRoutingSettings.fromJson({'dns': stored});
      expect(oldSmart.dns.toJson(), stored);
      final custom = RoutingProfileState(name: 'Existing', dns: settings);
      final document = custom.toJson();
      final restored = RoutingProfileState.fromXrayJson(
        name: 'Existing',
        xrayJson: XrayJson.fromJson(document),
      );
      expect(restored.toJson(), document);
      for (final mode in [TrafficMode.smart, TrafficMode.custom]) {
        final compiled = ConnectionCompiler.compile(
          settings: ConnectionSettings(trafficMode: mode, smart: oldSmart),
          custom: mode == TrafficMode.custom ? restored : null,
          entries: [httpNode()],
          regions: catalog,
          options: options(),
        ).config;
        final addresses = (compiled['dns']['servers'] as List)
            .map((server) => server['address'])
            .toSet();
        expect(addresses, contains('8.8.8.8'));
        expect(addresses, contains('https://1.1.1.1/dns-query'));
        expect(addresses, isNot(contains('tcp://8.8.8.8')));
      }
      expect(jsonEncode(stored), before);
    },
  );

  test('Raw and provider DNS definitions are not rewritten', () {
    final source = <String, dynamic>{
      'dns': {
        'servers': ['8.8.8.8'],
      },
      'outbounds': [
        {'tag': 'proxy', 'protocol': 'freedom'},
        {
          'tag': 'user-dns',
          'protocol': 'dns',
          'settings': {
            'rewriteNetwork': 'udp',
            'rewriteAddress': '8.8.4.4',
            'rules': [
              {'action': 'direct'},
            ],
          },
        },
      ],
      'routing': {
        'rules': [
          {'port': '53', 'outboundTag': 'user-dns'},
        ],
      },
    };
    final before = jsonEncode(source);
    for (final provider in [false, true]) {
      final plan = ConnectionCompiler.compile(
        settings: ConnectionSettings(expert: !provider),
        entries: const [],
        raw: provider ? null : source,
        profile: provider
            ? ResolvedProfile(
                id: 266,
                sourceId: 1,
                name: 'Provider',
                config: source,
              )
            : null,
        regions: catalog,
        options: options(),
      ).config;
      expect(plan['dns']['servers'], source['dns']['servers']);
      expect(
        (plan['outbounds'] as List).singleWhere(
          (outbound) => outbound['tag'] == 'user-dns',
        ),
        (source['outbounds'] as List).last,
      );
    }
    expect(jsonEncode(source), before);
  });
}
