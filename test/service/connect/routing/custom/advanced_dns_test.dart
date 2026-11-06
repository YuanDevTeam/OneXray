import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/settings.dart';

import '../../compiler_test.dart' show catalog, options;
import '../../tcp_dns_test.dart' show httpNode;

void main() {
  for (final count in [1, 2, 3]) {
    for (final strategy in ['roundRobin', 'leastPing']) {
      test('new template forwards DNS through $count-entry $strategy', () {
        final source = jsonDecode(
          AdvancedRoutingProfile.defaultText,
        ) as Map<String, dynamic>;
        (source['outbounds'] as List).insertAll(0, [
          for (var i = 1; i < count; i++) <String, dynamic>{},
        ]);
        source['routing']['balancers'] = [
          {
            'tag': 'proxy',
            'strategy': {'type': strategy},
          },
        ];
        source['observatory'] = {
          'probeURL': 'http://198.18.0.2:58162/health',
          'probeInterval': '10s',
        };
        final profile = AdvancedRoutingDocument.fromJson(
          source,
          name: 'Default advanced DNS',
        ).state;
        final before = profile.encode();
        final plan = ConnectionCompiler.compile(
          settings: ConnectionSettings(trafficMode: TrafficMode.custom),
          custom: profile,
          entries: [for (var i = 1; i <= count; i++) httpNode(i)],
          regions: catalog,
          options: options(platform: ConnectionPlatform.ios),
        );
        final config = plan.config;
        final outbounds = (config['outbounds'] as List).cast<Map>();
        final dns = outbounds.singleWhere((o) => o['tag'] == 'dnsOut');
        expect(dns['settings']['rewriteNetwork'], 'tcp');
        expect(dns['settings']['rules'], [
          {'action': 'hijack', 'qType': '1,28'},
          {'action': 'direct'},
        ]);
        expect(dns['streamSettings']['sockopt']['dialerProxy'], 'dns-forward');
        final helper = outbounds.singleWhere((o) => o['tag'] == 'dns-forward');
        expect(helper['protocol'], 'loopback');
        expect(helper['settings'], {'inboundTag': 'dns-forward'});
        expect(config['routing']['rules'].first, {
          'ruleTag': 'Forward DNS',
          'inboundTag': ['dns-forward'],
          'balancerTag': 'proxy',
        });
        final balancer = config['routing']['balancers'].single;
        expect(balancer['selector'], [
          for (var i = 0; i < count; i++) 'app-entry-$i',
        ]);
        expect(
          balancer['strategy']['type'],
          count == 1 ? 'roundRobin' : strategy,
        );
        expect(plan.nodeTags.length, count);
        expect(profile.encode(), before);
        const target = String.fromEnvironment('P2_FIXTURES');
        if (target.isNotEmpty) {
          Directory(target).createSync(recursive: true);
          File('$target/advanced-$strategy-$count.json')
              .writeAsStringSync(plan.xrayJson);
        }
      });
    }
  }

  test(
    'loopback helpers keep virtual inbound tags within their own namespace',
    () {
      for (final settings in [
        <String, dynamic>{},
        {'inboundTag': null},
        {'inboundTag': 42},
        {'inboundTag': ''},
        {'inboundTag': 'proxy'},
        {'inboundTag': 'direct'},
        {'inboundTag': 'block'},
        {'inboundTag': 'tunIn'},
        {'inboundTag': 'app-entry-0'},
        {'inboundTag': 'app-exit-1'},
        {'inboundTag': 'other-helper'},
        {'inboundTag': 'dns-forward', 'unexpected': true},
      ]) {
        expect(
          () => AdvancedRoutingDocument.fromJson({
            'outbounds': [
              <String, dynamic>{},
              {
                'tag': 'dns-forward',
                'protocol': 'loopback',
                'settings': settings,
              },
            ],
          }, name: 'Invalid helper'),
          throwsFormatException,
          reason: '$settings',
        );
      }
    },
  );

  test('existing advanced drop templates keep their DNS graph unchanged', () {
    final source = <String, dynamic>{
      'outbounds': [
        <String, dynamic>{},
        {
          'tag': 'old-dns',
          'protocol': 'dns',
          'settings': {
            'rules': [
              {'action': 'hijack', 'qType': '1,28'},
              {'action': 'drop'},
            ],
          },
        },
      ],
      'dns': {
        'servers': ['8.8.8.8'],
      },
      'routing': {
        'rules': [
          {
            'inboundTag': ['tunIn'],
            'port': 53,
            'outboundTag': 'old-dns',
          },
        ],
      },
    };
    final before = jsonEncode(source);
    final profile = AdvancedRoutingDocument.fromJson(source, name: 'Old').state;
    expect(profile.toJson(), source);
    final plan = ConnectionCompiler.compile(
      settings: ConnectionSettings(trafficMode: TrafficMode.custom),
      custom: profile,
      entries: [httpNode()],
      regions: catalog,
      options: options(),
    ).config;
    expect(plan['dns']['servers'], ['8.8.8.8']);
    expect(
      (plan['outbounds'] as List).singleWhere((o) => o['tag'] == 'old-dns'),
      (source['outbounds'] as List).last,
    );
    expect(
      (plan['outbounds'] as List).any((o) => o['protocol'] == 'loopback'),
      isFalse,
    );
    expect(plan['routing']['rules'], source['routing']['rules']);
    expect(profile.toJson(), source);
    expect(jsonEncode(source), before);
  });
}
