import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/shared/xray/validation.dart';
import 'package:onexray/service/shared/xray/remnawave.dart';

void main() {
  test(
    'full validation supplements portable ingress without device defaults',
    () {
      final source = <String, dynamic>{
        'outbounds': [
          {'protocol': 'freedom'},
        ],
        'dns': {
          'hosts': {'example.test': '192.0.2.1'},
        },
      };
      final before = jsonEncode(source);
      final config = jsonDecode(XrayValidation.full(source));
      expect(config['inbounds'].single['protocol'], 'socks');
      expect(config['routing']['rules'].single['inboundTag'], ['tunIn']);
      expect(config['outbounds'].first, source['outbounds'][0]);
      expect(config['dns'], source['dns']);
      expect(config.containsKey('metrics'), false);
      expect(jsonEncode(source), before);
    },
  );

  test('full validation leaves malformed native containers for Core', () {
    for (final source in <Map<String, dynamic>>[
      {'inbounds': false},
      {'outbounds': 'invalid'},
      {'routing': false},
      {
        'routing': {'rules': false},
      },
      {'dns': false},
      {
        'dns': {'servers': 'invalid'},
      },
      {
        'inbounds': [false],
        'outbounds': [false],
      },
    ]) {
      final config = jsonDecode(XrayValidation.full(source));
      for (final key in source.keys) {
        final actual = config[key];
        if (source[key] is List) {
          expect(actual, containsAll(source[key] as List));
        } else {
          expect(actual, source[key]);
        }
      }
    }
  });

  test('provider validation retains adapted graph and replaces only the disposable tunnel', () {
    final source = <String, dynamic>{
      'inbounds': [
        {'tag': 'provider', 'protocol': 'http', 'port': 1080},
      ],
      'outbounds': [
        {'tag': 'first', 'protocol': 'freedom'},
      ],
      'dns': {
        'servers': ['fakedns', '1.1.1.1'],
      },
      'fakedns': [
        {'ipPool': '198.19.0.0/16', 'poolSize': 1024},
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {
            'inboundTag': ['provider'],
            'outboundTag': 'first',
          },
        ],
      },
    };
    final adapted = RemnawaveAdapter.adapt(source);
    final validation = jsonDecode(XrayValidation.raw(adapted));
    expect(validation['routing'], adapted['routing']);
    expect(validation['outbounds'], adapted['outbounds']);
    expect(validation['fakedns'], source['fakedns']);
    final inbounds = validation['inbounds'] as List;
    expect(inbounds.first['protocol'], 'socks');
    expect(inbounds.first['tag'], 'tunIn');
    expect(inbounds.first['sniffing']['destOverride'], contains('fakedns'));
    expect((adapted['inbounds'] as List).first['protocol'], 'tun');
    expect((source['inbounds'] as List).single['tag'], 'provider');
  });

  test(
    'node validation preserves protocol fields without runtime resources',
    () {
      final outbound = {
        'tag': 'Node',
        'protocol': 'vless',
        'settings': {'address': 'example.com', 'port': 443, 'id': 'invalid'},
        'streamSettings': {
          'network': 'xhttp',
          'security': 'tls',
          'xhttpSettings': {
            'path': '/proxy',
            'extra': {'custom': true},
          },
          'sockopt': {'interface': 'App-managed', 'dialerProxy': 'entry'},
        },
      };
      final before = jsonEncode(outbound);
      final config = jsonDecode(XrayValidation.nodes([outbound]));
      final expected = jsonDecode(before);
      expected['streamSettings']['sockopt'].remove('interface');
      expect(config['outbounds'], [expected]);
      expect(config['env']['xray.location.asset'], VpnConstants.datDir);
      expect(config['env']['xray.location.cert'], VpnConstants.datDir);
      expect(config['log']['loglevel'], 'none');
      expect(config.keys.toSet(), {'outbounds', 'env', 'log'});
      expect(jsonEncode(outbound), before);
    },
  );

  test('normal projection retains routing and DNS from the same model', () {
    final config = XrayJson(
      routing: XrayRouting(
        rules: [
          XrayRoutingRule(domain: ['regexp:['], balancerTag: 'missing'),
        ],
      ),
      dns: XrayDns(
        servers: [
          XrayDnsServer(address: '8.8.8.8', domains: ['geosite:CN']),
        ],
      ),
      inbounds: [XrayInbound(protocol: 'tun', tag: 'tunIn')],
      outbounds: [
        {'protocol': 'freedom', 'tag': 'direct'},
      ],
      log: XrayLog(error: '/runtime/error.log'),
      stats: XrayStats(),
      metrics: XrayMetrics(listen: '127.0.0.1:12345'),
      policy: XrayPolicy(system: XrayPolicySystem(statsInboundUplink: true)),
    );
    final before = jsonEncode(config.toJson());
    final actual = jsonDecode(XrayValidation.normal(config));
    expect(actual['routing'], config.routing!.toJson());
    expect(actual['dns'], config.dns!.toJson());
    expect(actual['inbounds'].single['protocol'], 'socks');
    expect(actual['inbounds'].single['listen'], '127.0.0.1');
    expect(actual.keys.toSet(), {
      'env',
      'log',
      'outbounds',
      'routing',
      'dns',
      'inbounds',
    });
    expect(jsonEncode(config.toJson()), before);
  });

  test('Raw removes only App-owned settings and retains user dependencies', () {
    final source = <String, dynamic>{
      'env': {'xray.tun.fd': '7', 'XRAY_TUN_FD': '8', 'custom': 'retained'},
      'inbounds': [
        {
          'tag': 'tunIn',
          'protocol': 'tun',
          'settings': {
            'gateway': ['platform-owned'],
          },
          'sniffing': {
            'enabled': true,
            'routeOnly': true,
            'domainsExcluded': ['ext:missing.dat:cn'],
            'ipsExcluded': ['ext:missing-ip.dat:private'],
          },
        },
        {'tag': 'local', 'protocol': 'socks', 'port': 1080},
      ],
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'freedom',
          'streamSettings': {
            'sockopt': {'interface': 'ignored', 'dialerProxy': 'entry'},
          },
        },
      ],
      'routing': {
        'rules': [
          {
            'domain': ['geosite:CN'],
            'balancerTag': 'missing',
          },
        ],
      },
      'geodata': {
        'cron': 'invalid',
        'assets': [
          {'file': 'missing.dat', 'url': 'invalid'},
        ],
      },
      'metrics': false,
      'stats': false,
      'log': false,
      'policy': {
        'system': {'statsInboundUplink': 'invalid', 'other': true},
        'levels': {
          '0': {
            'connIdle': 123,
            'statsUserUplink': true,
            'statsUserDownlink': true,
          },
        },
      },
      'dns': {
        'hosts': {'example.com': '127.0.0.1'},
        'queryStrategy': 'invalid',
        'servers': [
          'localhost',
          {
            'address': '8.8.8.8',
            'domains': ['geosite:CN'],
            'queryStrategy': 'invalid',
          },
        ],
      },
      'api': {
        'tag': 'api',
        'services': ['StatsService'],
      },
      'observatory': {
        'subjectSelector': ['proxy'],
      },
      'fakeDns': [
        {'ipPool': '198.18.0.0/15'},
      ],
      'customRoot': {'retained': true},
    };
    final before = jsonEncode(source);
    final actual = jsonDecode(XrayValidation.raw(source));
    for (final key in [
      'routing',
      'api',
      'observatory',
      'fakeDns',
      'customRoot',
    ]) {
      expect(actual[key], source[key]);
    }
    expect(actual.containsKey('geodata'), false);
    expect(actual.containsKey('metrics'), false);
    expect(actual['stats'], {});
    expect(actual['log']['loglevel'], 'none');
    expect(actual['inbounds'][0], {
      'tag': 'tunIn',
      'protocol': 'socks',
      'listen': '127.0.0.1',
      'port': 1080,
      'settings': {'auth': 'noauth', 'udp': true},
      'sniffing': source['inbounds'][0]['sniffing'],
    });
    expect(actual['inbounds'][1], source['inbounds'][1]);
    expect(actual['env'], {
      'xray.location.asset': VpnConstants.datDir,
      'xray.location.cert': VpnConstants.datDir,
      'custom': 'retained',
    });
    expect(actual['policy'], {
      'system': {'other': true},
      'levels': {
        '0': {'connIdle': 123},
      },
    });
    expect(actual['dns']['hosts'], source['dns']['hosts']);
    expect(actual['dns'].containsKey('queryStrategy'), false);
    expect(actual['dns']['servers'], [
      'localhost',
      {
        'address': '8.8.8.8',
        'domains': ['geosite:CN'],
      },
    ]);
    expect(actual['outbounds'][0]['streamSettings']['sockopt'], {
      'dialerProxy': 'entry',
    });
    expect(jsonEncode(source), before);
  });

  test('malformed user configuration is left for libXray to reject', () {
    final source = <String, dynamic>{
      'env': false,
      'dns': false,
      'policy': false,
      'outbounds': [false],
      'inbounds': [false],
    };
    final actual = jsonDecode(XrayValidation.raw(source));
    for (final entry in source.entries) {
      expect(actual[entry.key], entry.value);
    }
    expect(jsonDecode(XrayValidation.nodes([false]))['outbounds'], [false]);
  });

  test('advanced and Raw validation preserve native DNS and sniffing maps after DTO reduction', () {
    final dns = <String, dynamic>{
      'serveStale': true,
      'serveExpiredTTL': 300,
      'enableParallelQuery': true,
      'servers': [
        {
          'address': 'tcp://8.8.8.8',
          'timeoutMs': 1200,
          'disableCache': true,
          'expectedIPs': ['geoip:CN'],
          'unexpectedIPs': ['geoip:PRIVATE'],
          'serveStale': false,
          'serveExpiredTTL': 60,
        },
        {
          'address': 'tcp://1.1.1.1',
          'timeoutMs': 4000,
          'disableCache': false,
          'expectIPs': ['!geoip:PRIVATE'],
        },
      ],
    };
    final sniffing = <String, dynamic>{
      'enabled': true,
      'routeOnly': true,
      'destOverride': ['http', 'tls', 'quic'],
      'domainsExcluded': ['domain:private.example'],
      'ipsExcluded': ['192.0.2.0/24'],
    };
    final raw = <String, dynamic>{
      'dns': dns,
      'outbounds': [
        {'protocol': 'freedom'},
      ],
      'inbounds': [
        {'tag': 'tunIn', 'protocol': 'tun', 'sniffing': sniffing},
      ],
    };
    final before = jsonEncode(raw);
    final rawProjection = jsonDecode(XrayValidation.raw(raw));
    expect(rawProjection['dns'], dns);
    expect(rawProjection['inbounds'].single['sniffing'], sniffing);
    final advanced = AdvancedRoutingDocument.fromJson({
      'name': 'Advanced DNS',
      'outbounds': [<String, dynamic>{}],
      'dns': dns,
      'inbounds': [
        {'tag': 'tunIn', 'sniffing': sniffing},
      ],
    }).state;
    final projection = jsonDecode(
      CustomRoutingService.validationJson(advanced),
    );
    expect(projection['dns'], dns);
    expect(projection['inbounds'].single['sniffing'], sniffing);
    expect(advanced.toJson()['dns'], dns);
    expect(advanced.toJson()['inbounds'].single['sniffing'], sniffing);
    expect(jsonEncode(raw), before);
  });
}
