import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/model/xray_json.dart';

void main() {
  test('round-trips the complete regular configuration model', () {
    final source = <String, dynamic>{
      'env': {'xray.location.asset': '/assets', 'xray.location.cert': '/certs'},
      'geodata': {
        'assets': [
          {'file': 'other.dat', 'url': 'https://example.com/other.dat'},
        ],
      },
      'log': {
        'access': '/logs/access.log',
        'error': '/logs/error.log',
        'loglevel': 'warning',
        'dnsLog': true,
        'maskAddress': 'full',
      },
      'dns': {
        'servers': [
          {
            'address': '8.8.8.8',
            'domains': ['geosite:cn'],
            'skipFallback': true,
            'queryStrategy': 'UseIPv4',
            'tag': 'app-dns-direct',
          },
        ],
      },
      'fakedns': [
        {'ipPool': '198.19.0.0/16', 'poolSize': 32768},
        {'ipPool': 'fc00:1::/64', 'poolSize': 32768},
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {
            'domain': ['geosite:cn'],
            'ip': ['geoip:cn'],
            'port': '80,443',
            'network': ['tcp', 'udp'],
            'protocol': ['http', 'tls'],
            'localOS': ['ios', 'android', 'darwin', 'windows', 'linux'],
            'inboundTag': ['tunIn'],
            'outboundTag': 'direct',
            'ruleTag': 'app-smart-cn',
          },
          {'balancerTag': 'proxy', 'ruleTag': 'app-default'},
        ],
        'balancers': [
          {
            'tag': 'proxy',
            'selector': ['app-entry-0'],
            'strategy': {'type': 'roundRobin'},
            'fallbackTag': 'direct',
          },
        ],
      },
      'inbounds': [
        {
          'listen': '127.0.0.1',
          'protocol': 'tun',
          'settings': {'name': 'OneXrayTun', 'mtu': 9000},
          'tag': 'tunIn',
          'sniffing': {
            'enabled': true,
            'routeOnly': false,
            'destOverride': ['http', 'tls', 'quic'],
          },
        },
        {
          'listen': '127.0.0.1',
          'port': '1080',
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
          'tag': 'socksIn',
        },
      ],
      'outbounds': [
        {'tag': 'app-entry-0', 'protocol': 'freedom'},
      ],
      'policy': {
        'system': {
          'statsInboundUplink': true,
          'statsInboundDownlink': true,
          'statsOutboundUplink': false,
          'statsOutboundDownlink': false,
        },
      },
      'stats': <String, dynamic>{},
      'metrics': {'listen': '127.0.0.1:11111'},
      'observatory': {'subjectSelector': <String>[]},
    };

    expect(XrayJson.fromJson(source).toJson(), source);
  });

  test('ordinary DTOs omit retired optional Core fields', () {
    final dns = XrayDns.fromJson({
      'disableCache': true,
      'disableFallbackIfMatch': true,
      'serveStale': true,
      'serveExpiredTTL': 60,
      'enableParallelQuery': true,
      'servers': [
        {
          'tag': 'app-dns-proxy',
          'address': '1.1.1.1',
          'timeoutMs': 1500,
          'disableCache': false,
          'expectedIPs': ['geoip:US'],
          'expectIPs': ['geoip:JP'],
          'unexpectedIPs': ['geoip:CN'],
          'serveStale': true,
          'serveExpiredTTL': 60,
        },
      ],
    });
    expect(dns.toJson(), {
      'disableCache': true,
      'disableFallbackIfMatch': true,
      'servers': [
        {'tag': 'app-dns-proxy', 'address': '1.1.1.1'},
      ],
    });
  });

  test(
    'ordinary sniffing DTO retains toggles and drops retired exclusions',
    () {
      final sniffing = XrayInboundSniffing.fromJson({
        'enabled': true,
        'routeOnly': true,
        'metadataOnly': true,
        'destOverride': ['http', 'tls', 'quic'],
        'domainsExcluded': ['domain:example.com'],
        'ipsExcluded': ['192.168.0.0/16'],
      });
      expect(sniffing.toJson(), {
        'enabled': true,
        'routeOnly': true,
        'metadataOnly': true,
        'destOverride': ['http', 'tls', 'quic'],
      });
    },
  );

  test('preserves complete proxy outbound maps', () {
    final outbound = <String, dynamic>{
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': 'example.test',
            'port': 443,
            'users': [
              {'id': 'fixture', 'flow': 'xtls-rprx-vision'},
            ],
          },
        ],
      },
      'streamSettings': {
        'network': 'xhttp',
        'xhttpSettings': {
          'path': '/xray',
          'futureTransportField': {'enabled': true},
        },
      },
    };

    expect(
      XrayJson.fromJson({
        'outbounds': [outbound],
      }).toJson(),
      {
        'outbounds': [outbound],
      },
    );
  });

  test('round-trips the App-managed inbound settings', () {
    final tun = {
      'name': 'OneXrayTun',
      'mtu': 9000,
      'gateway': ['198.18.0.1/15', 'fc00::1/64'],
      'dns': ['8.8.8.8', '2001:4860:4860::8888'],
      'autoSystemRoutingTable': ['0.0.0.0/0', '::/0'],
      'autoOutboundsInterface': 'en0',
      'autoSystemDnsToGateway': true,
      'autoSystemWfpBlockLeak': ['dns'],
    };
    final socks = {'auth': 'noauth', 'udp': true};
    expect(XrayInboundTunSettings.fromJson(tun).toJson(), tun);
    expect(XrayInboundSocksSettings.fromJson(socks).toJson(), socks);
  });

  test('round-trips the three App-managed system outbounds', () {
    const direct = {'tag': 'direct', 'protocol': 'freedom'};
    const block = {'tag': 'block', 'protocol': 'blackhole'};
    expect(XrayOutbound.fromJson(direct).toJson(), direct);
    expect(XrayOutbound.fromJson(block).toJson(), block);

    final directWithInterface = XrayOutbound(
      tag: 'direct',
      protocol: 'freedom',
      streamSettings: XrayStreamSettings(
        sockopt: XraySockopt(interface: 'en0'),
      ),
    ).toJson();
    expect(directWithInterface, {
      'tag': 'direct',
      'protocol': 'freedom',
      'streamSettings': {
        'sockopt': {'interface': 'en0'},
      },
    });

    final dns = {
      'tag': 'dnsOut',
      'protocol': 'dns',
      'settings': {
        'rules': [
          {'action': 'hijack', 'qType': '1,28'},
          {'action': 'direct'},
        ],
      },
      'streamSettings': {
        'sockopt': {'dialerProxy': 'direct'},
      },
    };
    expect(XrayOutbound.fromJson(dns).toJson(), dns);
    expect(
      XrayOutboundDnsRule.fromJson({'action': 'hijack', 'qType': '1,28'})
          .toJson(),
      {'action': 'hijack', 'qType': '1,28'},
    );
  });

  test('managed stream settings preserve FinalMask and socket options', () {
    final source = <String, dynamic>{
      'tag': 'fragment',
      'protocol': 'freedom',
      'streamSettings': {
        'sockopt': {'interface': 'selected-interface'},
        'finalmask': {
          'tcp': [
            {
              'type': 'fragment',
              'settings': {
                'packets': 'tlshello',
                'length': '100-200',
                'delay': '10-20',
                'futureOption': {'preserve': true},
              },
            },
          ],
        },
      },
    };

    expect(XrayOutbound.fromJson(source).toJson(), source);
    expect(XrayStreamSettings().toJson(), isEmpty);
  });
}
