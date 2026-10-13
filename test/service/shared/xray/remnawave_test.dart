import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/xray/remnawave.dart';

Map<String, dynamic> _source({bool dns = true}) => {
  'remarks': 'Provider graph',
  'inbounds': <dynamic>[
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
  'outbounds': <dynamic>[
    {
      'tag': 'entry',
      'protocol': 'socks',
      'streamSettings': {
        'sockopt': {'dialerProxy': 'exit'},
      },
    },
    {'tag': 'exit', 'protocol': 'freedom'},
    {'tag': 'direct', 'protocol': 'freedom'},
    {'tag': 'block', 'protocol': 'blackhole'},
  ],
  if (dns)
    'dns': {
      'servers': ['1.1.1.1'],
      'tag': 'provider-dns',
    },
  'routing': {
    'domainStrategy': 'IPIfNonMatch',
    'rules': <dynamic>[
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
    'injects tunnel and DNS while preserving the provider graph and source',
    () {
      final source = _source();
      final before = jsonEncode(source);
      final adapted = RemnawaveAdapter.adapt(source);
      final inbounds = adapted['inbounds'] as List;
      expect(inbounds.first['tag'], 'tunIn');
      expect(inbounds.first['protocol'], 'tun');
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
      expect(rules[1]['ip'], source['routing']['rules'][0]['ip']);
      expect(rules.last, source['routing']['rules'][1]);
      expect(adapted['routing']['domainStrategy'], 'IPIfNonMatch');
      expect(adapted['routing']['balancers'], source['routing']['balancers']);
      expect(adapted['observatory'], source['observatory']);
      expect(
        (adapted['outbounds'] as List).take(4).toList(),
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

  test('injects DNS even without a provider DNS section or routing rules', () {
    final source = _source(dns: false)..remove('routing');
    final result = RemnawaveAdapter.adapt(source);
    expect(result.containsKey('dns'), isFalse);
    expect(result['routing']['rules'], hasLength(1));
    expect(result['routing']['rules'][0]['outboundTag'], 'app-remna-dns');
    expect((result['outbounds'] as List).last['protocol'], 'dns');
  });

  test('reuses provider TUN and DNS while adapting only tunnel references', () {
    final source = _source();
    final tunnel = {
      'tag': 'provider-tun',
      'protocol': 'tun',
      'settings': {'name': 'Provider tunnel', 'mtu': 1200},
      'sniffing': {'enabled': false},
    };
    source['inbounds'].add(tunnel);
    source['routing']['rules'].insert(0, {
      'inboundTag': ['provider-tun', 'tunIn', 'provider-socks', 'other'],
      'outboundTag': 'entry',
    });
    (source['outbounds'] as List).addAll([
      {
        'tag': 'provider-query',
        'protocol': 'dns',
        'settings': {'address': '9.9.9.9'},
        'proxySettings': {'tag': 'entry'},
      },
      {'tag': 'backup-query', 'protocol': 'dns'},
    ]);
    final original = jsonEncode(source);
    final result = RemnawaveAdapter.adapt(source);
    final tunnels = (result['inbounds'] as List)
        .where((value) => value['protocol'] == 'tun')
        .toList();
    expect(tunnels, hasLength(1));
    expect(tunnels.single['tag'], 'tunIn');
    expect(tunnels.single, {...tunnel, 'tag': 'tunIn'});
    expect(result['inbounds'][0], source['inbounds'][0]);
    expect(result['inbounds'][1], tunnels.single);
    final dnsOutbounds = (result['outbounds'] as List)
        .where((value) => value['protocol'] == 'dns')
        .toList();
    expect(dnsOutbounds, (source['outbounds'] as List).skip(4).toList());
    expect(result['routing']['rules'][0]['outboundTag'], 'provider-query');
    expect(result['routing']['rules'][1]['inboundTag'], [
      'tunIn',
      'provider-socks',
      'other',
    ]);
    expect(jsonEncode(source), original);
  });

  test(
    'retains declared DNS routing and its outbound without coverage inference',
    () {
      final source = _source();
      final originalRule = <String, dynamic>{
        'inboundTag': ['provider-socks'],
        'network': 'udp',
        'port': '53',
        'ip': ['9.9.9.9/32'],
        'outboundTag': 'provider-query',
      };
      source['routing']['rules'].insert(0, originalRule);
      (source['outbounds'] as List).add({
        'tag': 'provider-query',
        'protocol': 'dns',
        'settings': {'address': '9.9.9.9'},
      });
      final result = RemnawaveAdapter.adapt(source);
      expect(result['routing']['rules'], hasLength(3));
      expect(result['routing']['rules'][0], {
        ...originalRule,
        'inboundTag': ['provider-socks', 'tunIn'],
      });
      expect(
        (result['outbounds'] as List).any(
          (value) => value['tag'] == 'provider-query',
        ),
        isTrue,
      );
      expect(result['outbounds'], source['outbounds']);
    },
  );

  test(
    'retains managed TUN settings and sniffing at the original position',
    () {
      final source = _source();
      source['inbounds'].add({
        'tag': 'tunIn',
        'protocol': 'tun',
        'settings': {'mtu': 1200, 'autoSystemDnsToGateway': true},
        'sniffing': {'enabled': false},
      });
      final result = RemnawaveAdapter.adapt(source);
      expect(result['inbounds'], source['inbounds']);
    },
  );

  for (final emptyTags in [false, true]) {
    test(
      'respects a global DNS rule with ${emptyTags ? 'empty' : 'absent'} ingress tags',
      () {
        final source = _source();
        final rule = {
          'port': emptyTags ? 53 : '53',
          if (emptyTags) 'inboundTag': <String>[],
          'outboundTag': 'entry',
          'domain': ['example.com'],
        };
        source['routing']['rules'].add(rule);
        final result = RemnawaveAdapter.adapt(source);
        expect(result['routing']['rules'], hasLength(3));
        expect(result['routing']['rules'].last, rule);
        expect(result['outbounds'], source['outbounds']);
        expect(
          (result['outbounds'] as List).any(
            (value) => value['protocol'] == 'dns',
          ),
          false,
        );
      },
    );
  }

  test(
    'supplements tunnel DNS when an existing rule only handles internal DNS',
    () {
      final source = _source();
      final internalRule = {
        'port': '53',
        'inboundTag': ['provider-dns'],
        'outboundTag': 'direct',
      };
      source['routing']['rules'].add(internalRule);
      final result = RemnawaveAdapter.adapt(source);
      expect(result['routing']['rules'], hasLength(4));
      expect(result['routing']['rules'][0]['outboundTag'], 'app-remna-dns');
      expect(result['routing']['rules'].last, internalRule);
    },
  );

  test('assigns a missing DNS tag without replacing the provided outbound', () {
    final source = _source();
    final dns = {
      'protocol': 'dns',
      'settings': {'address': '9.9.9.9', 'port': 5353},
      'streamSettings': {
        'sockopt': {'dialerProxy': 'entry'},
      },
    };
    source['outbounds'].add(dns);
    final result = RemnawaveAdapter.adapt(source);
    expect((result['outbounds'] as List).last, {
      ...dns,
      'tag': 'app-remna-dns',
    });
    expect(result['routing']['rules'][0]['outboundTag'], 'app-remna-dns');
    expect(source['outbounds'].last.containsKey('tag'), false);
  });

  test(
    'copies the first proxy sniffing without checking other ingress policies',
    () {
      final source = _source();
      source['inbounds'][0]['sniffing'] = {'enabled': false};
      source['inbounds'].add({
        'tag': 'provider-http',
        'protocol': 'http',
        'sniffing': {'enabled': true, 'routeOnly': false},
      });
      final result = RemnawaveAdapter.adapt(source);
      expect(result['inbounds'][0]['sniffing'], {'enabled': false});
      expect(result['inbounds'][2], source['inbounds'][1]);
    },
  );

  test(
    'new tunnel uses shared FakeDNS defaults when no sniffing is supplied',
    () {
      final source = _source();
      source['inbounds'][0].remove('sniffing');
      source['dns']['servers'] = ['fakedns', '1.1.1.1'];
      source['fakedns'] = [
        {'ipPool': '198.19.0.0/16', 'poolSize': 1024},
      ];
      final result = RemnawaveAdapter.adapt(source);
      expect(
        result['inbounds'][0]['sniffing']['destOverride'],
        contains('fakedns'),
      );
      expect(result['fakedns'], source['fakedns']);
    },
  );

  for (final present in [
    <String>[],
    ['direct'],
    ['block'],
    ['direct', 'block'],
  ]) {
    test(
      'fills missing direct/block and retains existing definitions: $present',
      () {
        final source = _source();
        source['outbounds'] = [
          {'tag': 'proxy', 'protocol': 'freedom'},
          if (present.contains('direct'))
            {
              'tag': 'direct',
              'protocol': 'freedom',
              'settings': {'domainStrategy': 'UseIPv4'},
            },
          if (present.contains('block'))
            {
              'tag': 'block',
              'protocol': 'blackhole',
              'settings': {
                'response': {'type': 'http'},
              },
            },
        ];
        final original = source['outbounds'] as List;
        final outbounds = RemnawaveAdapter.adapt(source)['outbounds'] as List;
        expect(outbounds.take(original.length).toList(), original);
        for (final tag in ['direct', 'block']) {
          final actual = outbounds.singleWhere((value) => value['tag'] == tag);
          expect(
            actual,
            present.contains(tag)
                ? original.singleWhere((value) => value['tag'] == tag)
                : {
                    'tag': tag,
                    'protocol': tag == 'direct' ? 'freedom' : 'blackhole',
                  },
          );
        }
        expect(outbounds.last['tag'], 'app-remna-dns');
      },
    );
  }

  test('preserves unsupported fields and members for native validation', () {
    final source = _source();
    source['inbounds'].add('invalid inbound');
    source['outbounds'].add({'tag': 'unknown', 'protocol': 'unknown-protocol'});
    source['routing']['rules'].add({'inboundTag': 'invalid tags'});
    source['routing']['balancers'][0]['selector'] = [''];
    source['dns']['tag'] = 'tunIn';
    final result = RemnawaveAdapter.adapt(source);
    expect(result['inbounds'].last, 'invalid inbound');
    expect(
      (result['outbounds'] as List).singleWhere(
        (value) => value['tag'] == 'unknown',
      ),
      {'tag': 'unknown', 'protocol': 'unknown-protocol'},
    );
    expect(result['routing']['rules'].last, {'inboundTag': 'invalid tags'});
    expect(result['routing']['balancers'], source['routing']['balancers']);
    expect(result['dns'], source['dns']);
  });
}
