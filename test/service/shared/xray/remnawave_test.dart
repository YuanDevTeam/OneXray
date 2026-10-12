import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/xray/remnawave.dart';

Map<String, dynamic> _source({bool dns = true}) => {
  'remarks': 'Provider graph',
  'inbounds': <Map<String, dynamic>>[
    {
      'tag': 'provider-socks',
      'protocol': 'socks',
      'port': 1080,
      'sniffing': {
        'enabled': true,
        'routeOnly': true,
        'destOverride': ['http', 'tls', 'quic'],
      },
    },
  ],
  'outbounds': <Map<String, dynamic>>[
    {
      'tag': 'entry',
      'protocol': 'socks',
      'streamSettings': {
        'sockopt': {'dialerProxy': 'exit'},
      },
    },
    {'tag': 'exit', 'protocol': 'freedom'},
  ],
  if (dns)
    'dns': {
      'servers': ['1.1.1.1'],
      'tag': 'provider-dns',
    },
  'routing': {
    'domainStrategy': 'IPIfNonMatch',
    'rules': [
      {
        'inboundTag': ['provider-socks'],
        'ip': ['203.0.113.0/24'],
        'balancerTag': 'pool',
      },
      {
        'domain': ['example.com'],
        'outboundTag': 'entry',
      },
    ],
    'balancers': [
      {
        'tag': 'pool',
        'selector': ['entry'],
        'fallbackTag': 'exit',
        'strategy': {'type': 'leastPing'},
      },
    ],
  },
  'observatory': {
    'subjectSelector': ['entry'],
    'probeURL': 'https://example.com/probe',
  },
};

void main() {
  test(
    'tunnel ingress preserves the source graph and limits DNS interception',
    () {
      final source = _source();
      final before = jsonEncode(source);
      final adapted = RemnawaveAdapter.adapt(source);
      final inbounds = adapted['inbounds'] as List;
      expect(inbounds.where((value) => value['tag'] == 'tunIn'), hasLength(1));
      expect(inbounds.first['sniffing'], inbounds.last['sniffing']);
      expect(inbounds.last, (source['inbounds'] as List).single);
      final rules = adapted['routing']['rules'] as List;
      expect(rules.first, {
        'type': 'field',
        'inboundTag': ['tunIn'],
        'network': 'tcp,udp',
        'port': '53',
        'outboundTag': 'app-remna-dns',
      });
      expect(rules[1]['inboundTag'], ['provider-socks', 'tunIn']);
      expect(rules[1]['ip'], (source['routing']['rules'] as List).first['ip']);
      expect(rules.last, (source['routing']['rules'] as List).last);
      expect(adapted['routing']['domainStrategy'], 'IPIfNonMatch');
      expect(adapted['routing']['balancers'], source['routing']['balancers']);
      expect(adapted['observatory'], source['observatory']);
      expect(
        (adapted['outbounds'] as List).take(2).toList(),
        source['outbounds'],
      );
      expect((adapted['outbounds'] as List).last, {
        'tag': 'app-remna-dns',
        'protocol': 'dns',
        'settings': {},
      });
      expect(adapted['dns'], source['dns']);
      expect(adapted.containsKey('metrics'), isFalse);
      expect(jsonEncode(source), before);
    },
  );

  test(
    'without built-in DNS the original rules and default outbound stay intact',
    () {
      final source = _source(dns: false);
      final result = RemnawaveAdapter.adapt(source);
      expect(result['outbounds'], source['outbounds']);
      expect(result['routing']['rules'], [
        {
          ...(source['routing']['rules'] as List).first,
          'inboundTag': ['provider-socks', 'tunIn'],
        },
        (source['routing']['rules'] as List).last,
      ]);
      expect(result.containsKey('dns'), isFalse);
    },
  );

  test(
    'equivalent proxy inbounds share the tunnel, conflicting policies fail',
    () {
      final source = _source(dns: false);
      final inbounds = source['inbounds'] as List;
      inbounds.add(<String, dynamic>{
        ...inbounds.single,
        'tag': 'provider-http',
        'protocol': 'http',
      });
      (source['routing']['rules'] as List).first['inboundTag'] = [
        'provider-socks',
        'provider-http',
      ];
      expect(RemnawaveAdapter.adapt(source)['inbounds'], hasLength(3));
      (source['routing']['rules'] as List).first['inboundTag'] = [
        'provider-socks',
      ];
      expect(() => RemnawaveAdapter.adapt(source), throwsFormatException);
      (source['routing']['rules'] as List).first['inboundTag'] = [
        'provider-socks',
        'provider-http',
      ];
      inbounds.last['sniffing'] = {'enabled': false};
      expect(() => RemnawaveAdapter.adapt(source), throwsFormatException);
    },
  );

  test('FakeDNS restores domains on the tunnel without changing old proxy sniffing', () {
    final source = _source();
    source['dns']['servers'] = ['fakedns', '1.1.1.1'];
    source['fakedns'] = [
      {'ipPool': '198.19.0.0/16', 'poolSize': 1024},
    ];
    final result = RemnawaveAdapter.adapt(source);
    final inbounds = result['inbounds'] as List;
    expect(inbounds.first['sniffing']['destOverride'], [
      'http',
      'tls',
      'quic',
      'fakedns',
    ]);
    expect(inbounds.first['sniffing']['routeOnly'], isTrue);
    expect(inbounds.last['sniffing']['destOverride'], ['http', 'tls', 'quic']);
    expect(result['fakedns'], source['fakedns']);
    (source['inbounds'] as List).first['sniffing'] = {'enabled': false};
    expect(() => RemnawaveAdapter.adapt(source), throwsFormatException);
  });

  test('an existing native DNS ingress is reused and custom forwarding is rejected', () {
    final source = _source();
    (source['outbounds'] as List).add({
      'tag': 'provider-query',
      'protocol': 'dns',
      'settings': <String, dynamic>{},
    });
    (source['routing']['rules'] as List).insert(0, {
      'inboundTag': ['provider-socks'],
      'port': '53',
      'outboundTag': 'provider-query',
    });
    final result = RemnawaveAdapter.adapt(source);
    expect(result['outbounds'], source['outbounds']);
    expect(result['routing']['rules'], hasLength(3));
    (source['outbounds'] as List).last['settings'] = {'address': '1.1.1.1'};
    expect(() => RemnawaveAdapter.adapt(source), throwsFormatException);
  });

  test('reserved DNS tags and prefix selectors cannot capture the bridge', () {
    for (final collision in [
      'outbound',
      'balancer',
      'observatory',
      'dns-tag',
    ]) {
      final source = _source();
      switch (collision) {
        case 'outbound':
          (source['outbounds'] as List).add({
            'tag': 'app-remna-dns',
            'protocol': 'freedom',
          });
        case 'balancer':
          source['routing']['balancers'][0]['selector'] = ['app-'];
        case 'observatory':
          source['observatory']['subjectSelector'] = [''];
        case 'dns-tag':
          source['dns']['tag'] = 'tunIn';
      }
      expect(
        () => RemnawaveAdapter.adapt(source),
        throwsFormatException,
        reason: collision,
      );
    }
  });

  test(
    'an unreachable existing DNS rule cannot bypass tunnel DNS integration',
    () {
      final source = _source();
      (source['outbounds'] as List).add({
        'tag': 'provider-query',
        'protocol': 'dns',
      });
      (source['routing']['rules'] as List).add({
        'port': '53',
        'outboundTag': 'provider-query',
      });
      final result = RemnawaveAdapter.adapt(source);
      expect(result['routing']['rules'][0]['outboundTag'], 'app-remna-dns');
      expect((result['outbounds'] as List).last['tag'], 'app-remna-dns');
      expect(result['routing']['rules'].last['outboundTag'], 'provider-query');
    },
  );

  test(
    'duplicate or unmanaged tunnels are rejected before native construction',
    () {
      for (final additional in [
        {'tag': 'foreign', 'protocol': 'tun'},
        {'tag': 'tunIn', 'protocol': 'socks'},
      ]) {
        final source = _source();
        (source['inbounds'] as List).add(additional);
        expect(() => RemnawaveAdapter.adapt(source), throwsFormatException);
      }
    },
  );
}
