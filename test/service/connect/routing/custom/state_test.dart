import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/routing/custom/document.dart';
import 'package:onexray/service/connect/routing/custom/editor.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/state_db.dart';

void main() {
  test('fragment helper persists and shares its imported parameters', () {
    final legacy = RoutingProfileDocument.parse(jsonEncode(_document())).state;
    expect(legacy.fragment, false);
    expect(legacy.fragmentOutbound, isNull);
    for (final count in [1, 2, 3]) {
      final helper = _fragment();
      final document = _document(count);
      (document['outbounds'] as List).add(helper);
      final state = RoutingProfileDocument.parse(jsonEncode(document)).state;
      expect(state.entryCount, count);
      expect(state.fragment, true);
      expect(state.fragmentOutbound, helper);
      expect(state.xrayJson.outbounds, [
        for (var i = 0; i < count; i++) <String, dynamic>{},
        helper,
      ]);

      final persisted = RoutingProfileStateDb.readData(
        id: 7,
        name: 'Saved route',
        data: state.databaseData,
      );
      expect(persisted.id, 7);
      expect(persisted.entryCount, count);
      expect(persisted.fragmentOutbound, helper);
      final encoded = jsonDecode(persisted.encode()) as Map<String, dynamic>;
      expect(encoded.containsKey('fragment'), false);
      expect(encoded.containsKey('fragmentEnabled'), false);
      final shared = RoutingProfileDocument.parse(
        jsonEncode({...encoded, 'name': 'Shared route'}),
      ).state;
      expect(shared.name, 'Shared route');
      expect(shared.entryCount, count);
      expect(shared.fragmentOutbound, helper);
    }
  });

  test('fragment copies retain parameters without exposing mutable state', () {
    final helper = _fragment();
    final state = RoutingProfileState(name: 'Route', fragmentOutbound: helper);
    final expected = _fragment();
    (helper['settings'] as Map).clear();
    expect(state.fragmentOutbound, expected);
    final exposed = state.fragmentOutbound!;
    (exposed['settings'] as Map).clear();
    final encoded = state.xrayJson;
    (encoded.outbounds!.last['settings'] as Map).clear();
    expect(state.fragmentOutbound, expected);
    expect(state.copyWith(name: 'Renamed').fragmentOutbound, expected);
    expect(state.copyWith(entryCount: 3).fragmentOutbound, expected);
    final disabled = state.copyWith(clearFragment: true);
    expect(disabled.fragment, false);
    expect(disabled.xrayJson.outbounds, [{}]);
    expect(
      disabled.copyWith(fragmentOutbound: expected).fragmentOutbound,
      expected,
    );
    expect(CustomRoutingEditorService.sameRouting(state, disabled), false);
    expect(
      CustomRoutingEditorService.sameRouting(
        state,
        state.copyWith(name: 'Renamed'),
      ),
      true,
    );
    final changed = _fragment();
    ((changed['settings'] as Map)['fragment'] as Map)['length'] = '90-120';
    expect(
      CustomRoutingEditorService.sameRouting(
        state,
        state.copyWith(fragmentOutbound: changed),
      ),
      false,
    );
  });

  test('fragment requires leading slots and the freedom tag identity', () {
    for (final outbounds in [
      [_fragment()],
      [{}, _fragment(), {}],
      [{}, _fragment(), _fragment()],
      [{}, {}, {}, {}, _fragment()],
      [
        {},
        {..._fragment(), 'protocol': 'blackhole'},
      ],
      [
        {},
        {..._fragment(), 'tag': 'other'},
      ],
    ]) {
      _reject({..._document(), 'outbounds': outbounds});
    }
    final helper = _fragment()
      ..['settings'] = {'fragment': 'Core validates this'};
    final state = RoutingProfileDocument.parse(
      jsonEncode({
        ..._document(),
        'outbounds': [{}, helper],
      }),
    ).state;
    expect(state.fragmentOutbound, helper);
  });

  test('FakeDNS round trips as an optional standard tagged DNS server', () {
    final base = RoutingProfileState(name: 'Route');
    expect(base.fakeDns, false);
    expect(
      RoutingProfileDocument.parse(jsonEncode(_document())).state.fakeDns,
      false,
    );
    final enabled = base.copyWith(fakeDns: true);
    final document = jsonDecode(enabled.encode()) as Map<String, dynamic>;
    expect(document['dns'], _storedDns(fakeDns: true));
    expect(document.containsKey('fakedns'), false);
    expect(document.containsKey('fakeDns'), false);
    (document['dns'] as Map)['servers'] = (document['dns']['servers'] as List)
        .reversed
        .toList();
    final decoded = RoutingProfileDocument.parse(
      jsonEncode({...document, 'name': 'Shared route'}),
    ).state;
    expect(decoded.fakeDns, true);
    expect(decoded.name, 'Shared route');
    expect(decoded.copyWith(name: 'Edited').fakeDns, true);
    expect(
      decoded.copyWith(fakeDns: false).xrayJson.dns!.servers,
      hasLength(2),
    );
    for (final extra in [
      {'tag': 'app-dns-fake', 'address': '9.9.9.9'},
      {'tag': 'unknown', 'address': 'fakedns'},
      {'tag': 'app-dns-fake', 'address': 'fakedns', 'domains': []},
    ]) {
      _reject({
        ...document,
        'dns': {
          'servers': [
            {'tag': 'app-dns-direct', 'address': '8.8.8.8'},
            extra,
          ],
        },
      });
    }
    _reject({
      ...document,
      'dns': {
        'servers': [
          {'tag': 'app-dns-direct', 'address': '8.8.8.8'},
          for (var i = 0; i < 2; i++)
            {'tag': 'app-dns-fake', 'address': 'fakedns'},
        ],
      },
    });
    _reject({...document, 'fakedns': []});
  });

  test('tagged direct DNS round trips with only native editable fields', () {
    final source = _document();
    source['dns'] = {
      'servers': [
        {'address': '1.1.1.1', 'tag': 'app-dns-direct'},
      ],
    };
    final state = RoutingProfileDocument.parse(jsonEncode(source)).state;
    expect(state.directDnsAddress, '1.1.1.1');
    final edited = state.copyWith(directDnsAddress: '9.9.9.9');
    expect(jsonDecode(edited.encode())['dns'], _storedDns(direct: '9.9.9.9'));
    expect(
      RoutingProfileDocument.parse(
        edited.encode(),
        allowMetadata: false,
      ).state.directDnsAddress,
      '9.9.9.9',
    );
    expect(
      RoutingProfileDocument.parse(jsonEncode(_document()))
          .state
          .directDnsAddress,
      '8.8.8.8',
    );
    for (final (tag, addresses) in [
      ('app-dns-proxy', ['1.1.1.1']),
      ('app-dns-direct', ['1.1.1.1', '9.9.9.9']),
    ]) {
      final decoded = RoutingProfileDocument.parse(
        jsonEncode({
          ..._document(),
          'dns': {
            'servers': [
              for (final address in addresses) {'tag': tag, 'address': address},
            ],
          },
        }),
      ).state;
      final resolvers = tag == 'app-dns-proxy'
          ? decoded.dns.effectiveProxyResolvers
          : decoded.dns.effectiveDirectResolvers;
      expect(resolvers.map((resolver) => resolver.address), addresses);
      expect(
        RoutingProfileDocument.parse(decoded.encode()).state.dns.toJson(),
        decoded.dns.toJson(),
      );
    }
    for (final servers in [
      [],
      ['1.1.1.1'],
      [
        {'address': '1.1.1.1'},
      ],
      [
        {'tag': 'app-dns-direct', 'address': '1.1.1.1', 'domains': []},
      ],
      [
        {'tag': 'app-dns-direct', 'address': '1.1.1.1', 'port': 53},
      ],
    ]) {
      _reject({
        ..._document(),
        'dns': {'servers': servers},
      });
    }
  });

  test('projects the supported Xray routing fields into editable state', () {
    final source = _document(2);
    source['name'] = '  My routes  ';
    final first = <String, dynamic>{
      'ruleTag': '  Duplicate label  ',
      'domain': ['domain:example.com', 'geosite:cn'],
      'ip': ['192.0.2.0/24', 'geoip:cn'],
      'port': '80,443,8000-8080',
      'network': 'tcp,udp',
      'protocol': ['http', 'quic'],
      'localOS': ['android', 'darwin'],
      'balancerTag': 'proxy',
    };
    final second = <String, dynamic>{
      'ruleTag': '  Duplicate label  ',
      'domain': ['ext:other.dat:private'],
      'outboundTag': 'direct',
    };
    final third = <String, dynamic>{
      'port': 53,
      'network': ['tcp', 'udp'],
      'outboundTag': 'block',
    };
    (source['routing'] as Map)['rules'] = [first, second, third];
    (source['routing'] as Map)['domainStrategy'] = 'IPIfNonMatch';

    final state = RoutingProfileDocument.parse(jsonEncode(source)).state;

    expect(state.name, '  My routes  ');
    expect(state.entryCount, 2);
    expect(state.xrayJson.routing!.domainStrategy, 'IPIfNonMatch');
    expect(state.rules.map((rule) => rule.toJson()), [first, second, third]);
    expect(jsonDecode(state.encode()), {
      'dns': _storedDns(),
      'inbounds': [_storedSniffing()],
      'observatory': _storedObservatory,
      'routing': {
        'balancers': _storedBalancers,
        'domainStrategy': 'IPIfNonMatch',
        'rules': [first, second, third],
      },
      'outbounds': [{}, {}],
    });
  });

  test('state owns immutable rule values and writes a minimal XrayJson', () {
    final domain = ['domain:example.com'];
    final rule = RoutingRuleState(domain: domain);
    final state = RoutingProfileState(name: 'Route', rules: [rule]);
    domain.clear();

    expect(state.rules.single.domain, ['domain:example.com']);
    expect(XrayJson.fromJson(jsonDecode(state.encode())).toJson(), {
      'dns': _storedDns(),
      'inbounds': [_storedSniffing()],
      'observatory': _storedObservatory,
      'routing': {
        'balancers': _storedBalancers,
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {
            'domain': ['domain:example.com'],
            'balancerTag': 'proxy',
          },
        ],
      },
      'outbounds': [{}],
    });
  });

  test('supports one to three entry slots and only supported actions', () {
    for (final count in [1, 2, 3]) {
      final state = RoutingProfileDocument.parse(
        jsonEncode(_document(count)..remove('name')),
      ).state;
      expect(state.entryCount, count);
      expect(state.name, isEmpty);
      expect(state.xrayJson.routing!.domainStrategy, 'IPIfNonMatch');
      expect(state.rules, isEmpty);
    }
    for (final action in RoutingRuleAction.values) {
      final rule = RoutingRuleState(
        domain: const ['domain:example.com'],
        action: action,
      );
      expect(RoutingRuleState.fromXrayJson(rule.xrayJson).action, action);
    }
  });

  test('uses typed geodata only as separated import metadata', () {
    final source = _document();
    source['geodata'] = {
      'assets': [
        {'file': 'other.dat', 'url': 'https://example.com/other.dat?version=2'},
      ],
    };
    (source['routing'] as Map)['rules'] = [
      {
        ..._rule(),
        'domain': ['ext:other.dat:cn'],
      },
    ];

    final document = RoutingProfileDocument.parse(jsonEncode(source));

    expect(document.assets, [
      {'file': 'other.dat', 'url': 'https://example.com/other.dat?version=2'},
    ]);
    expect(document.state.xrayJson.geodata, isNull);
    expect(
      (jsonDecode(document.state.encode()) as Map).containsKey('geodata'),
      false,
    );
  });

  test(
    'rejects unknown roots, routing fields and rule fields before XrayJson',
    () {
      for (final root in [
        'dns',
        'inbounds',
        'policy',
        'version',
        'entryCount',
      ]) {
        _reject({..._document(), root: {}});
      }
      for (final field in ['balancers', 'domainMatcher', 'rulesEnabled']) {
        _reject({
          ..._document(),
          'routing': {'rules': [], field: []},
        });
      }
      for (final field in [
        'source',
        'sourceIP',
        'sourcePort',
        'attrs',
        'inboundTag',
        'localIP',
        'localPort',
        'process',
        'user',
        'vlessRoute',
        'webhook',
        'enabled',
        'disabled',
        'name',
        'id',
        'uuid',
        'type',
      ]) {
        _rejectRule({..._rule(), field: 'hidden'});
      }
      _rejectRule({
        ..._rule(),
        'attrs': {':path': '['},
      });
      _rejectRule({
        ..._rule(),
        'sourceIP': ['192.0.2.0/24'],
      });
      _rejectRule({..._rule(), 'sourcePort': 1024});
      _rejectRule({
        'domain': ['example.com'],
      });
      _rejectRule({..._rule(), 'balancerTag': 'custom'});
      _rejectRule({..._rule(), 'outboundTag': 'direct'});
    },
  );

  test(
    'rejects invalid names and shapes the ordinary editor cannot represent',
    () {
      for (final name in [null, '', '   ', 12, List.filled(33, 'a').join()]) {
        _reject({..._document(), 'name': name});
      }
      for (final count in [0, 4]) {
        _reject(_document(count));
      }
      for (final outbound in [
        {'tag': 'node', 'protocol': 'socks'},
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
        {'tag': 'direct', 'protocol': 'blackhole'},
        {'tag': 'direct', 'protocol': 'freedom', 'settings': null},
        {
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': {'redirect': 'example.com:80'},
        },
      ]) {
        _reject({
          ..._document(),
          'outbounds': [{}, outbound],
        });
      }
      for (final key in ['domain', 'ip']) {
        for (final value in [
          'example.com',
          [1],
        ]) {
          _rejectRule({..._rule(), key: value});
        }
      }
    },
  );

  test('rule values pass through for libXray with a fixed domain strategy', () {
    for (final rule in [
      {'balancerTag': 'proxy'},
      {
        ..._rule(),
        'domain': [''],
        'ip': ['  '],
      },
      for (final port in [[], '', 'abc', '3-2', 0, 65536, 1.5])
        {..._rule(), 'port': port},
      for (final network in [
        '',
        [],
        [1],
        'unix',
        'TCP',
        'tcp,other',
      ])
        {..._rule(), 'network': network},
    ]) {
      final document = _document();
      (document['routing'] as Map)
        ..['domainStrategy'] = 'IPOnDemand'
        ..['rules'] = [rule];
      final state = RoutingProfileDocument.parse(jsonEncode(document)).state;
      expect(state.xrayJson.routing!.domainStrategy, 'IPIfNonMatch');
      expect(state.rules.single.toJson(), rule);
    }
  });

  test('rejects unsafe geodata assets', () {
    for (final file in [
      '../other.dat',
      r'..\other.dat',
      '/other.dat',
      r'C:\other.dat',
      'geosite.dat',
      'GEOIP.DAT',
      '.dat',
      'other.json',
      ' other.dat',
      'CON.dat',
    ]) {
      _rejectAssets([
        {'file': file, 'url': 'https://example.com/other.dat'},
      ]);
    }
    for (final url in [
      'http://example.com/other.dat',
      'file:///other.dat',
      'https:///other.dat',
      'https://user:secret@example.com/other.dat',
      'https://example.com/other.dat#fragment',
      null,
    ]) {
      _rejectAssets([
        {'file': 'other.dat', 'url': url},
      ]);
    }
  });
}

Map<String, dynamic> _document([int count = 1]) => {
  'name': 'Custom',
  'outbounds': List.generate(count, (_) => <String, dynamic>{}),
  'routing': <String, dynamic>{'rules': <dynamic>[]},
};

Map<String, dynamic> _rule() => {
  'ruleTag': 'A rule',
  'domain': ['domain:example.com'],
  'balancerTag': 'proxy',
};

Map<String, dynamic> _fragment() => {
  'tag': 'fragment',
  'protocol': 'freedom',
  'settings': {
    'fragment': {
      'packets': 'tlshello',
      'length': '40-80',
      'interval': '2-3',
      'maxSplit': '3-5',
    },
    'futureSetting': true,
  },
  'streamSettings': {
    'sockopt': {'tcpNoDelay': true},
  },
};

void _reject(Map<String, dynamic> document) {
  expect(
    () => RoutingProfileDocument.parse(jsonEncode(document)),
    throwsFormatException,
    reason: jsonEncode(document),
  );
}

void _rejectRule(Map<String, dynamic> rule) {
  final document = _document();
  (document['routing'] as Map)['rules'] = [rule];
  _reject(document);
}

void _rejectAssets(Object? assets) => _reject({
  ..._document(),
  'geodata': {'assets': assets},
});

Map<String, dynamic> _storedDns({
  String direct = '8.8.8.8',
  bool fakeDns = false,
}) => {
  'disableCache': false,
  'serveStale': false,
  'serveExpiredTTL': 300,
  'disableFallbackIfMatch': false,
  'enableParallelQuery': false,
  'servers': [
    {'tag': 'app-dns-proxy', 'address': '8.8.8.8', 'timeoutMs': 4000},
    {'tag': 'app-dns-direct', 'address': direct, 'timeoutMs': 4000},
    if (fakeDns) {'tag': 'app-dns-fake', 'address': 'fakedns'},
  ],
};

Map<String, dynamic> _storedSniffing() => {
  'tag': 'tunIn',
  'sniffing': {
    'enabled': true,
    'routeOnly': false,
    'destOverride': ['http', 'tls', 'quic'],
  },
};

const _storedObservatory = {
  'probeURL': 'https://www.google.com/generate_204',
  'probeInterval': '60s',
  'enableConcurrency': true,
};
const _storedBalancers = [
  {
    'tag': 'proxy',
    'strategy': {'type': 'roundRobin'},
  },
];
