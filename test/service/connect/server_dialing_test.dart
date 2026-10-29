import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/connect/dialing.dart';
import 'package:onexray/service/shared/xray/server_dialing.dart';

const dualStack = EffectiveServerDialing(
  domainStrategy: 'UseIP',
  happyEyeballs: true,
);

void main() {
  test('system default clears only physical HE without enabling DNS', () {
    final values = [
      _node(
        'entry.example',
        sockopt: {
          'domainStrategy': 'UseIPv6',
          'interface': 'kept0',
          'happyEyeballs': {'tryDelayMs': 99},
        },
      ),
      _fragment(),
      {'tag': 'direct', 'protocol': 'freedom'},
    ];
    final before = [for (final value in values) JsonTool.copyMap(value)];
    expect(
      ManagedServerDialing.apply(
        outbounds: values,
        settings: const EffectiveServerDialing(domainStrategy: 'AsIs'),
        interfaceName: 'eth0',
      ),
      isEmpty,
    );
    _sockopt(before.first).remove('happyEyeballs');
    expect(values, before);
  });

  test('system default leaves a plain endpoint unchanged', () {
    final value = _node('entry.example')..remove('streamSettings');
    final before = JsonTool.copyMap(value);
    expect(
      ManagedServerDialing.apply(
        outbounds: [value],
        settings: const EffectiveServerDialing(domainStrategy: 'AsIs'),
      ),
      isEmpty,
    );
    expect(value, before);
  });

  test('WireGuard peers use endpoint hosts without TCP Happy Eyeballs', () {
    final value = _wireguard([
      'Peer.Example.:51820',
      'peer.example:51821',
      '192.0.2.1:51820',
      '[2001:db8::1]:51820',
    ]);
    value['streamSettings'] = <String, dynamic>{
      'sockopt': <String, dynamic>{
        'happyEyeballs': {'tryDelayMs': 99},
        'mark': 3,
      },
    };
    final originalSettings = JsonTool.copyMap(value['settings']);
    expect(
      ManagedServerDialing.apply(outbounds: [value], settings: dualStack),
      ['peer.example'],
    );
    expect(_sockopt(value), {'domainStrategy': 'UseIP', 'mark': 3});
    expect(value['settings'], originalSettings);

    final literal = _wireguard(['[2001:db8::2]:51820']);
    expect(
      ManagedServerDialing.apply(outbounds: [literal], settings: dualStack),
      isEmpty,
    );
    expect(_sockopt(literal), {'domainStrategy': 'UseIP'});
  });

  test('shared Fragment keeps TCP HE regardless of WireGuard entry order', () {
    for (final reverse in [false, true]) {
      final tcp = _node('entry.example', sockopt: {'dialerProxy': 'fragment'});
      final wg = _wireguard(['peer.example:51820']);
      wg['streamSettings'] = <String, dynamic>{
        'sockopt': <String, dynamic>{'dialerProxy': 'fragment'},
      };
      final helper = _fragment();
      final entries = reverse ? [wg, tcp] : [tcp, wg];
      expect(
        ManagedServerDialing.apply(
          outbounds: [...entries, helper],
          settings: dualStack,
        ),
        unorderedEquals(['entry.example', 'peer.example']),
      );
      expect(_sockopt(wg), {
        'dialerProxy': 'fragment',
        'domainStrategy': 'UseIP',
      });
      expect(_sockopt(helper)['happyEyeballs'], {'tryDelayMs': 250});
    }

    final wg = _wireguard(['peer.example:51820']);
    wg['streamSettings'] = <String, dynamic>{
      'sockopt': <String, dynamic>{'dialerProxy': 'fragment'},
    };
    final helper = _fragment(
      sockopt: {
        'happyEyeballs': {'tryDelayMs': 99},
      },
    );
    ManagedServerDialing.apply(outbounds: [wg, helper], settings: dualStack);
    expect(_sockopt(helper), {'domainStrategy': 'UseIP'});
  });

  test(
    'physical socket receives only managed fields and exact endpoint DNS',
    () {
      final value = _node(
        'Entry.Example.',
        sockopt: {
          'mark': 7,
          'interface': 'old0',
          'tcpFastOpen': true,
          'happyEyeballs': {'tryDelayMs': 99, 'prioritizeIPv6': true},
        },
      );
      value['streamSettings']['tlsSettings'] = {'serverName': 'sni.example'};
      value['streamSettings']['wsSettings'] = {'host': 'header.example'};
      expect(
        ManagedServerDialing.apply(
          outbounds: [value],
          settings: dualStack,
          interfaceName: 'eth0',
        ),
        ['entry.example'],
      );
      expect(_sockopt(value), {
        'mark': 7,
        'interface': 'eth0',
        'tcpFastOpen': true,
        'domainStrategy': 'UseIP',
        'happyEyeballs': {'tryDelayMs': 250},
      });
      expect(value['streamSettings']['tlsSettings'], {
        'serverName': 'sni.example',
      });
    },
  );

  test(
    'explicit strategy without HE removes old HE and preserves interface',
    () {
      final value = _node(
        'entry.example',
        sockopt: {
          'interface': 'kept0',
          'happyEyeballs': {'tryDelayMs': 99},
        },
      );
      expect(
        ManagedServerDialing.apply(
          outbounds: [value],
          settings: const EffectiveServerDialing(domainStrategy: 'UseIPv6v4'),
        ),
        ['entry.example'],
      );
      expect(_sockopt(value), {
        'interface': 'kept0',
        'domainStrategy': 'UseIPv6v4',
      });
    },
  );

  test('legacy endpoints exclude IPs and deduplicate physical domains', () {
    final values = <Map<String, dynamic>>[
      {
        'protocol': 'vless',
        'settings': {
          'vnext': [
            {'address': 'Entry.Example'},
          ],
        },
      },
      {
        'protocol': 'socks',
        'settings': {
          'servers': [
            {'address': 'other.example'},
            {'address': '192.0.2.1'},
            {'address': '2001:db8::1'},
            {'address': '[2001:db8::2]'},
          ],
        },
        'streamSettings': <String, dynamic>{'address': 'inactive.example'},
      },
      _node('192.0.2.2'),
    ];
    expect(ManagedServerDialing.apply(outbounds: values, settings: dualStack), [
      'entry.example',
      'other.example',
    ]);
    expect(_sockopt(values.last)['domainStrategy'], 'UseIP');
  });

  test(
    'flat settings address takes precedence over inactive legacy fields',
    () {
      final value = _node('current.example');
      value['settings']['vnext'] = [
        {'address': 'unused.example'},
      ];
      expect(
        ManagedServerDialing.apply(outbounds: [value], settings: dualStack),
        ['current.example'],
      );
    },
  );

  test('TCP and main XHTTP keep their actual protocol endpoint', () {
    final plain = _node('entry.example');
    plain['streamSettings']['address'] = 'unused.example';
    expect(
      ManagedServerDialing.apply(outbounds: [plain], settings: dualStack),
      ['entry.example'],
    );
    final xhttp = _xhttp(_download('download.example'));
    xhttp['streamSettings']['address'] = 'unused.example';
    expect(
      ManagedServerDialing.apply(outbounds: [xhttp], settings: dualStack),
      ['entry.example', 'download.example'],
    );
  });

  test('XDrive fronting replaces the shadowed protocol endpoint for DNS', () {
    for (final fronting in ['fronting.example', '192.0.2.1']) {
      final value = _node('shadowed.example');
      value['streamSettings']['network'] = 'xdrive';
      value['streamSettings']['address'] = fronting;
      expect(
        ManagedServerDialing.apply(outbounds: [value], settings: dualStack),
        fronting == 'fronting.example' ? ['fronting.example'] : isEmpty,
      );
      expect(_sockopt(value)['domainStrategy'], 'UseIP');
    }
  });

  test(
    'S3 storage host replaces the logical endpoint for both transport aliases',
    () {
      for (final field in ['network', 'method']) {
        for (final pathStyle in <bool?>[null, true, false]) {
          final value = _s3(pathStyle: pathStyle, sockopt: {'mark': 7});
          final stream = value['streamSettings'] as Map<String, dynamic>;
          stream.remove('network');
          stream[field] = 'XDRIVE';
          stream['tlsSettings'] = {'serverName': 'certificate.example'};
          final settingsBefore = JsonTool.copyMap(value['settings']);
          final storageBefore = JsonTool.copyMap(stream['xdriveSettings']);
          expect(
            ManagedServerDialing.apply(
              outbounds: [value],
              settings: dualStack,
              interfaceName: 'eth0',
            ),
            [pathStyle == false ? 'tunnel.storage.example' : 'storage.example'],
          );
          expect(_sockopt(value), {
            'mark': 7,
            'domainStrategy': 'UseIP',
            'happyEyeballs': {'tryDelayMs': 250},
            'interface': 'eth0',
          });
          expect(value['settings'], settingsBefore);
          expect(stream['xdriveSettings'], storageBefore);
          expect(stream['tlsSettings'], {'serverName': 'certificate.example'});
        }
      }
    },
  );

  test(
    'S3 fronting overrides the virtual storage host and IPs need no DNS',
    () {
      for (final fronting in ['fronting.example', '192.0.2.3', '2001:db8::3']) {
        final value = _s3(pathStyle: false, fronting: fronting);
        expect(
          ManagedServerDialing.apply(outbounds: [value], settings: dualStack),
          fronting == 'fronting.example' ? ['fronting.example'] : isEmpty,
        );
        expect(_sockopt(value)['domainStrategy'], 'UseIP');
        expect(value['streamSettings']['address'], fronting);
      }
      for (final endpoint in [
        'http://192.0.2.4:9000/base/',
        'https://[2001:db8::4]:9443/base/',
      ]) {
        final value = _s3(endpoint: endpoint);
        expect(
          ManagedServerDialing.apply(outbounds: [value], settings: dualStack),
          isEmpty,
        );
        expect(_sockopt(value)['happyEyeballs'], {'tryDelayMs': 250});
        expect(
          value['streamSettings']['xdriveSettings']['s3']['endpoint'],
          endpoint,
        );
      }
    },
  );

  test(
    'S3 routed through another proxy keeps its remote storage resolution',
    () {
      final value = _s3(pathStyle: false, sockopt: {'dialerProxy': 'entry'});
      final before = JsonTool.copyMap(value);
      final entry = _node('entry.example');
      expect(
        ManagedServerDialing.apply(
          outbounds: [value, entry],
          settings: dualStack,
        ),
        ['entry.example'],
      );
      expect(value, before);
    },
  );

  test('S3 via Fragment applies physical policy on the helper without replacing masks', () {
    final value = _s3(pathStyle: false, sockopt: {'dialerProxy': 'fragment'});
    final helper = _fragment()..remove('settings');
    helper['streamSettings'] = <String, dynamic>{
      'finalmask': {
        'tcp': [
          {
            'type': 'fragment',
            'settings': {
              'packets': 'tlshello',
              'length': '100-200',
              'delay': '10-20',
            },
          },
        ],
      },
    };
    final maskBefore = JsonTool.copyMap(helper['streamSettings']['finalmask']);
    final entryBefore = JsonTool.copyMap(value);
    expect(
      ManagedServerDialing.apply(
        outbounds: [value, helper],
        settings: dualStack,
        interfaceName: 'eth0',
      ),
      ['tunnel.storage.example'],
    );
    expect(value, entryBefore);
    expect(_sockopt(helper), {
      'domainStrategy': 'UseIP',
      'happyEyeballs': {'tryDelayMs': 250},
      'interface': 'eth0',
    });
    expect(helper['streamSettings']['finalmask'], maskBefore);
  });

  test('S3 with system dialing only clears racing and preserves service configuration', () {
    final value = _s3(
      pathStyle: false,
      sockopt: {
        'domainStrategy': 'UseIPv6',
        'happyEyeballs': {'tryDelayMs': 99},
        'mark': 7,
      },
    );
    final before = JsonTool.copyMap(value);
    _sockopt(before).remove('happyEyeballs');
    expect(
      ManagedServerDialing.apply(
        outbounds: [value],
        settings: const EffectiveServerDialing(domainStrategy: 'AsIs'),
      ),
      isEmpty,
    );
    expect(value, before);
  });

  test(
    'inactive S3 settings and other XDrive services retain endpoint behavior',
    () {
      final inactive = _s3();
      inactive['streamSettings']['network'] = 'tcp';
      final otherService = _s3();
      otherService['streamSettings']['xdriveSettings']['service'] =
          'google-drive';
      for (final value in [inactive, otherService]) {
        expect(
          ManagedServerDialing.apply(outbounds: [value], settings: dualStack),
          ['logical.example'],
        );
      }
    },
  );

  test('transport names follow Core case-insensitive network and method', () {
    for (final field in ['network', 'method']) {
      final xhttp = _xhttp(_download('download.example'));
      xhttp['streamSettings'][field] = 'XHTTP';
      expect(
        ManagedServerDialing.apply(outbounds: [xhttp], settings: dualStack),
        ['entry.example', 'download.example'],
      );
      final xdrive = _node('shadowed.example');
      xdrive['streamSettings'][field] = 'XDRIVE';
      xdrive['streamSettings']['address'] = 'fronting.example';
      expect(
        ManagedServerDialing.apply(outbounds: [xdrive], settings: dualStack),
        ['fronting.example'],
      );
    }
  });

  test(
    'intermediate chain keeps remote resolution while physical entry changes',
    () {
      final exit = _node(
        'remote-exit.example',
        sockopt: {'dialerProxy': 'entry'},
      );
      final beforeExit = JsonTool.copyMap(exit);
      final entry = _node('entry.example');
      expect(
        ManagedServerDialing.apply(
          outbounds: [exit, entry],
          settings: dualStack,
        ),
        ['entry.example'],
      );
      expect(exit, beforeExit);
      expect(_sockopt(entry)['happyEyeballs'], {'tryDelayMs': 250});
    },
  );

  test(
    'generated Fragment owns the physical socket and both entry domains',
    () {
      final first = _node(
        'first.example',
        sockopt: {'dialerProxy': 'fragment'},
      );
      final second = _node(
        'second.example',
        sockopt: {'dialerProxy': 'fragment'},
      );
      final helper = _fragment();
      helper['settings']['domainStrategy'] = 'ForceIPv6';
      helper['settings']['targetStrategy'] = 'UseIPv4';
      final direct = {'tag': 'direct', 'protocol': 'freedom'};
      expect(
        ManagedServerDialing.apply(
          outbounds: [first, second, helper, direct],
          settings: dualStack,
          interfaceName: 'eth0',
        ),
        ['first.example', 'second.example'],
      );
      expect(_sockopt(first), {'dialerProxy': 'fragment'});
      expect(_sockopt(second), {'dialerProxy': 'fragment'});
      expect(_sockopt(helper), {
        'domainStrategy': 'UseIP',
        'happyEyeballs': {'tryDelayMs': 250},
        'interface': 'eth0',
      });
      expect(helper['settings'], {
        'fragment': {
          'packets': 'tlshello',
          'length': '100-200',
          'interval': '10-20',
        },
      });
      expect(direct, {'tag': 'direct', 'protocol': 'freedom'});
    },
  );

  test(
    'unreferenced Fragment helper and nonphysical helper stay unchanged',
    () {
      final helper = _fragment(sockopt: {'dialerProxy': 'other'});
      final entry = _node(
        'entry.example',
        sockopt: {'dialerProxy': 'fragment'},
      );
      final before = [JsonTool.copyMap(entry), JsonTool.copyMap(helper)];
      expect(
        ManagedServerDialing.apply(
          outbounds: [entry, helper],
          settings: dualStack,
        ),
        isEmpty,
      );
      expect([entry, helper], before);
      final unused = _fragment();
      unused['settings']['targetStrategy'] = 'ForceIPv6';
      expect(
        ManagedServerDialing.apply(outbounds: [unused], settings: dualStack),
        isEmpty,
      );
      expect(unused.containsKey('streamSettings'), isFalse);
      expect(unused['settings']['targetStrategy'], 'ForceIPv6');
    },
  );

  test('independent XHTTP download socket has its own DNS and interface', () {
    for (final alias in ['xhttp', 'splithttp']) {
      final download = _download('download.example', sockopt: {'mark': 9});
      final value = _xhttp(download, alias: alias);
      expect(
        ManagedServerDialing.apply(
          outbounds: [value],
          settings: dualStack,
          interfaceName: 'eth0',
        ),
        ['entry.example', 'download.example'],
      );
      expect(_streamSockopt(download), {
        'mark': 9,
        'domainStrategy': 'UseIP',
        'happyEyeballs': {'tryDelayMs': 250},
        'interface': 'eth0',
      });
      expect(download['address'], 'download.example');
    }
  });

  test('XHTTP extra replaces outer settings instead of merging downloads', () {
    final outer = _download('unused.example');
    final effective = _download('download.example');
    final value = _xhttp(outer);
    value['streamSettings']['xhttpSettings']['extra'] = {
      'downloadSettings': effective,
    };
    expect(
      ManagedServerDialing.apply(outbounds: [value], settings: dualStack),
      ['entry.example', 'download.example'],
    );
    expect(outer.containsKey('sockopt'), isFalse);
    expect(_streamSockopt(effective)['happyEyeballs'], {'tryDelayMs': 250});

    final inactive = _download('inactive.example');
    final extraWithoutDownload = _xhttp(inactive);
    extraWithoutDownload['streamSettings']['xhttpSettings']['extra'] = {};
    expect(
      ManagedServerDialing.apply(
        outbounds: [extraWithoutDownload],
        settings: dualStack,
      ),
      ['entry.example'],
    );
    expect(inactive.containsKey('sockopt'), isFalse);
  });

  test(
    'penetrate uses parent socket without changing ignored download sockopt',
    () {
      final download = _download(
        'download.example',
        sockopt: {'dialerProxy': 'ignored', 'mark': 9},
      );
      final beforeDownload = JsonTool.copyMap(download);
      final value = _xhttp(download, sockopt: {'penetrate': true});
      expect(
        ManagedServerDialing.apply(outbounds: [value], settings: dualStack),
        ['entry.example', 'download.example'],
      );
      expect(download, beforeDownload);
      expect(_sockopt(value)['penetrate'], isTrue);
      expect(_sockopt(value)['happyEyeballs'], {'tryDelayMs': 250});
    },
  );

  test('penetrated Fragment downloads resolve at the same final helper', () {
    final download = _download('download.example');
    final value = _xhttp(
      download,
      sockopt: {'dialerProxy': 'fragment', 'penetrate': true},
    );
    final helper = _fragment();
    expect(
      ManagedServerDialing.apply(
        outbounds: [value, helper],
        settings: dualStack,
      ),
      ['entry.example', 'download.example'],
    );
    expect(_sockopt(value), {'dialerProxy': 'fragment', 'penetrate': true});
    expect(download.containsKey('sockopt'), isFalse);
    expect(_sockopt(helper)['happyEyeballs'], {'tryDelayMs': 250});
  });

  test('independent download can use Fragment or another remote chain', () {
    final fragmentDownload = _download(
      'download.example',
      sockopt: {'dialerProxy': 'fragment'},
    );
    final helper = _fragment();
    expect(
      ManagedServerDialing.apply(
        outbounds: [_xhttp(fragmentDownload), helper],
        settings: dualStack,
      ),
      ['entry.example', 'download.example'],
    );
    expect(_streamSockopt(fragmentDownload), {'dialerProxy': 'fragment'});
    expect(_sockopt(helper)['domainStrategy'], 'UseIP');

    final remote = _download(
      'remote.example',
      sockopt: {'dialerProxy': 'entry'},
    );
    final original = JsonTool.copyMap(remote);
    expect(
      ManagedServerDialing.apply(
        outbounds: [_xhttp(remote)],
        settings: dualStack,
      ),
      ['entry.example'],
    );
    expect(remote, original);
  });

  test(
    'unrecognized nested objects and inactive transport fields are untouched',
    () {
      final download = _download('unused.example');
      final value = _node('entry.example');
      value['streamSettings']['xhttpSettings'] = {'downloadSettings': download};
      value['extension'] = {
        'address': 'credential.example',
        'sockopt': {'mark': 3},
      };
      final extension = JsonTool.copyMap(value['extension']);
      expect(
        ManagedServerDialing.apply(outbounds: [value], settings: dualStack),
        ['entry.example'],
      );
      expect(download.containsKey('sockopt'), isFalse);
      expect(value['extension'], extension);
    },
  );

  test(
    'dual bootstrap tries two physical DNS families and stops at the last',
    () {
      final domains = ['entry.example', 'download.example', 'entry.example'];
      final before = List.of(domains);
      final servers = ManagedServerDialing.bootstrapServers(
        domains: domains,
        ipv4Address: '192.0.2.53',
        ipv6Address: '2001:db8::53',
        ipv6: true,
      );
      expect(servers.map((server) => server.toJson()), [
        {
          'address': '192.0.2.53',
          'tag': 'app-dns-bootstrap',
          'domains': ['full:entry.example', 'full:download.example'],
          'skipFallback': true,
          'queryStrategy': 'UseIP',
        },
        {
          'address': '2001:db8::53',
          'tag': 'app-dns-bootstrap',
          'domains': ['full:entry.example', 'full:download.example'],
          'skipFallback': true,
          'queryStrategy': 'UseIP',
          'finalQuery': true,
        },
      ]);
      expect(domains, before);
    },
  );

  test(
    'IPv6-off bootstrap uses only IPv4 and empty endpoint set adds nothing',
    () {
      final servers = ManagedServerDialing.bootstrapServers(
        domains: ['entry.example'],
        ipv4Address: '192.0.2.53',
        ipv6Address: '2001:db8::53',
        ipv6: false,
      );
      expect(servers.single.toJson(), {
        'address': '192.0.2.53',
        'tag': 'app-dns-bootstrap',
        'domains': ['full:entry.example'],
        'skipFallback': true,
        'queryStrategy': 'UseIPv4',
        'finalQuery': true,
      });
      expect(
        ManagedServerDialing.bootstrapServers(
          domains: [],
          ipv4Address: '192.0.2.53',
          ipv6Address: '2001:db8::53',
          ipv6: true,
        ),
        isEmpty,
      );
    },
  );
}

Map<String, dynamic> _node(String address, {Map<String, dynamic>? sockopt}) => {
  'tag': 'entry',
  'protocol': 'socks',
  'settings': <String, dynamic>{'address': address, 'port': 1080},
  'streamSettings': <String, dynamic>{'sockopt': ?sockopt},
};

Map<String, dynamic> _fragment({Map<String, dynamic>? sockopt}) => {
  'tag': 'fragment',
  'protocol': 'freedom',
  'settings': <String, dynamic>{
    'fragment': {
      'packets': 'tlshello',
      'length': '100-200',
      'interval': '10-20',
    },
  },
  if (sockopt != null) 'streamSettings': <String, dynamic>{'sockopt': sockopt},
};

Map<String, dynamic> _wireguard(List<String> endpoints) => {
  'tag': 'wireguard',
  'protocol': 'wireguard',
  'settings': <String, dynamic>{
    'secretKey': 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
    'address': ['10.0.0.2/32', 'fd00::2/128'],
    'peers': [
      for (final endpoint in endpoints)
        {
          'publicKey': 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=',
          'endpoint': endpoint,
        },
    ],
  },
};

Map<String, dynamic> _download(
  String address, {
  Map<String, dynamic>? sockopt,
}) => {
  'address': address,
  'port': 443,
  'network': 'xhttp',
  'xhttpSettings': <String, dynamic>{'path': '/test/'},
  'sockopt': ?sockopt,
};

Map<String, dynamic> _xhttp(
  Map<String, dynamic> download, {
  String alias = 'xhttp',
  Map<String, dynamic>? sockopt,
}) {
  final value = _node('entry.example', sockopt: sockopt);
  value['streamSettings']['network'] = alias;
  value['streamSettings']['${alias}Settings'] = <String, dynamic>{
    'downloadSettings': download,
  };
  return value;
}

Map<String, dynamic> _s3({
  String endpoint = 'https://Storage.Example.:9443/base/',
  bool? pathStyle,
  String? fronting,
  Map<String, dynamic>? sockopt,
}) {
  final value = _node('logical.example', sockopt: sockopt);
  final stream = value['streamSettings'] as Map<String, dynamic>;
  stream['network'] = 'xdrive';
  if (fronting != null) stream['address'] = fronting;
  stream['xdriveSettings'] = <String, dynamic>{
    'service': 's3',
    'remoteFolder': 'sessions/client',
    'secrets': ['test-access', 'test-secret'],
    's3': <String, dynamic>{
      'endpoint': endpoint,
      'bucket': 'tunnel',
      'pathStyle': ?pathStyle,
    },
  };
  return value;
}

Map<String, dynamic> _sockopt(Map<String, dynamic> outbound) =>
    _streamSockopt(outbound['streamSettings'] as Map<String, dynamic>);

Map<String, dynamic> _streamSockopt(Map<String, dynamic> stream) =>
    stream['sockopt'] as Map<String, dynamic>;
