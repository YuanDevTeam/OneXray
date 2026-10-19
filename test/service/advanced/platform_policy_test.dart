import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/dialing.dart';
import 'package:onexray/service/connect/settings.dart';

void main() {
  test('dialing defaults and saved preferences survive platform storage', () {
    final defaults = PlatformPolicy.fromJson({});
    expect(defaults.dialing.toJson(), const ServerDialingSettings().toJson());
    final unknown = PlatformPolicy.fromJson({
      'dialing': {'domainStrategy': 'future-strategy', 'happyEyeballs': true},
    });
    expect(unknown.dialing.domainStrategy, ServerDomainStrategy.system);
    expect(unknown.dialing.happyEyeballs, isTrue);
    expect(unknown.toJson()['dialing']['domainStrategy'], 'system');

    final saved = PlatformPolicy.fromJson({
      'ipv6Enabled': false,
      'dialing': {'domainStrategy': 'ipv6First', 'happyEyeballs': true},
    });
    final restored = PlatformPolicy.fromJson(saved.toJson());
    expect(restored.dialing.domainStrategy, ServerDomainStrategy.ipv6First);
    expect(restored.dialing.happyEyeballs, isTrue);
    expect(restored.dialing.effective(ipv6: restored.ipv6Enabled).toJson(), {
      'domainStrategy': 'UseIPv4',
      'happyEyeballs': false,
    });
    expect(restored.toJson(), saved.toJson());
  });

  test(
    'configured tunnel DNS survives storage and reaches native parameters',
    () {
      for (final platform in ConnectionPlatform.values) {
        final policy = PlatformPolicy.fromJson({
          'xrayOutboundInterfaceName': 'Ethernet',
          'dnsIpv4Address': ' 1.1.1.1 ',
          'dnsIpv6Address': '2606:4700:4700::1111',
          'dnsServerName': 'cloudflare-dns.com',
          'apple': {'dnsOverTls': true},
        });
        final restored = PlatformPolicy.fromJson(policy.toJson());
        final tun = restored.toTun(platform);
        expect(tun.tunDnsIPv4, '1.1.1.1');
        expect(tun.tunDnsIPv6, '2606:4700:4700::1111');
        expect(tun.dnsServerName, 'cloudflare-dns.com');
        expect(restored.dnsIpv4Address, '1.1.1.1');
        expect(tun.tunIPv4, '198.18.0.1');
      }
    },
  );

  test('only effective native DNS fields are validated', () {
    for (final value in [
      '',
      'dns.example.com',
      '::1',
      '1.1.1.1:53',
      'https://1.1.1.1',
    ]) {
      final policy = PlatformPolicy.fromJson({'dnsIpv4Address': value});
      expect(
        () => policy.toTun(ConnectionPlatform.android),
        throwsFormatException,
      );
    }
    for (final value in ['', '1.1.1.1', '[2001:db8::1]', 'fe80::1%en0']) {
      final policy = PlatformPolicy.fromJson({'dnsIpv6Address': value});
      expect(() => policy.toTun(ConnectionPlatform.ios), throwsFormatException);
    }
    final inactive = PlatformPolicy.fromJson({
      'ipv6Enabled': false,
      'dnsIpv6Address': '',
      'dnsServerName': '',
      'xrayOutboundInterfaceName': 'Ethernet',
    });
    expect(inactive.toTun(ConnectionPlatform.ios).tunDnsIPv6, isNull);
    expect(
      () => inactive.toTun(
        ConnectionPlatform.windows,
        windowsMode: WindowsMode.exe,
      ),
      returnsNormally,
    );
    expect(() => inactive.toWindowsPolicy(), throwsFormatException);
    final dot = PlatformPolicy.fromJson({
      ...inactive.toJson(),
      'apple': {'dnsOverTls': true},
    });
    expect(() => dot.toTun(ConnectionPlatform.ios), throwsFormatException);
    expect(() => dot.toTun(ConnectionPlatform.android), returnsNormally);
  });

  test('Windows exclusions protect configured DNS instead of old defaults', () {
    final value = {
      'dnsIpv4Address': '1.1.1.1',
      'dnsIpv6Address': '2606:4700:4700::1111',
      'windows': {
        'excludedCidrs': ['8.8.8.8/32', '2001:4860:4860::8888/128'],
      },
    };
    expect(
      PlatformPolicy.fromJson(value).toWindowsPolicy().excludedCidrs,
      hasLength(2),
    );
    for (final cidr in ['1.1.1.0/24', '2606:4700:4700::/64']) {
      expect(
        () => PlatformPolicy.fromJson({
          ...value,
          'windows': {
            'excludedCidrs': [cidr],
          },
        }).toWindowsPolicy(),
        throwsFormatException,
      );
    }
  });

  test(
    'defaults contain no demo selections and compile fixed runtime values',
    () {
      final policy = PlatformPolicy.defaults();
      expect(policy.ipv6Enabled, true);
      expect(policy.xrayOutboundInterfaceName, '');
      expect(policy.logEnabled, false);
      expect(policy.logLevel, 'warning');
      expect(policy.recordDns, true);
      expect(policy.maskAddress, 'full');
      expect(policy.toJson()['android'], {
        'appScope': 'all',
        'includedAppPackageNames': [],
        'excludedAppPackageNames': [],
      });
      final apple = policy.toJson()['apple'];
      expect(apple['connectWifiSsids'], isEmpty);
      expect(apple['disconnectWifiSsids'], isEmpty);
      expect(apple['cellularAction'], 'connect');
      expect(apple['ethernetAction'], 'connect');
      expect(apple['excludedCidrs'], isEmpty);
      expect(apple['hideVpnIcon'], isFalse);
      final tun = policy.toTun(ConnectionPlatform.ios);
      expect(tun.tunIPv4, '198.18.0.1');
      expect(tun.tunIPv6, 'fc00::1');
      expect(tun.tunDnsIPv4, '8.8.8.8');
      expect(tun.tunDnsIPv6, '2001:4860:4860::8888');
      expect(tun.dnsServerName, 'dns.google');
      expect(tun.enableIPv6, true);
      expect(tun.includeAllNetworks, false);
      expect(tun.excludedRoutes, isEmpty);
      expect(tun.hideVpnIcon, isFalse);
      expect(tun.excludeLocalNetworks, true);
      expect(tun.excludeCellularServices, true);
      expect(tun.excludeAPNs, true);
      expect(tun.excludeDeviceCommunication, true);
      expect(tun.enableDot, false);
      expect(tun.onDemandEnabled, false);
      expect(tun.onDemandRules, isEmpty);
      expect(policy.toWindowsPolicy().toJson(), {
        'alwaysOn': false,
        'allowLocalNetwork': true,
        'excludedCidrs': [],
      });
    },
  );

  test('IPv6-off native TUN configuration omits IPv6 addresses and DNS', () {
    for (final platform in ConnectionPlatform.values) {
      final policy = PlatformPolicy.fromJson({
        'ipv6Enabled': false,
        'xrayOutboundInterfaceName': 'selected-interface',
      });
      final tun = policy.toTun(platform);
      expect(tun.enableIPv6, false);
      expect(tun.tunIPv4, PlatformPolicy.tunIpv4Address);
      expect(tun.tunDnsIPv4, policy.dnsIpv4Address);
      expect(tun.tunIPv6, isNull);
      expect(tun.tunDnsIPv6, isNull);
      expect(tun.toJson(), isNot(contains('tunIPv6')));
      expect(tun.toJson(), isNot(contains('tunDnsIPv6')));
    }
  });

  test(
    'policy and converted native values cannot mutate the stored snapshot',
    () {
      final input = {
        'android': {
          'appScope': 'included',
          'includedAppPackageNames': ['com.example.included'],
          'excludedAppPackageNames': ['com.example.excluded'],
        },
      };
      final policy = PlatformPolicy.fromJson(input);
      input['android']!['includedAppPackageNames'] = ['com.example.changed'];
      final json = policy.toJson();
      json['android']['includedAppPackageNames'].clear();
      final tun = policy.toTun(ConnectionPlatform.android);
      tun.allowAppList!.clear();
      expect(policy.toTun(ConnectionPlatform.android).allowAppList, [
        'com.example.included',
      ]);
      expect(
        PlatformPolicy.fromJson(policy.toJson()).toJson(),
        policy.toJson(),
      );
    },
  );

  test(
    'Android scopes preserve both lists but compile only the active selection',
    () {
      final value = PlatformPolicy.defaults().toJson();
      value['android']['includedAppPackageNames'] = ['com.example.included'];
      value['android']['excludedAppPackageNames'] = ['com.example.excluded'];
      for (final scope in ['all', 'included', 'excluded']) {
        value['android']['appScope'] = scope;
        final policy = PlatformPolicy.fromJson(value);
        final tun = policy.toTun(ConnectionPlatform.android);
        expect(tun.perAppVPNMode, scope == 'included' ? 'allow' : 'disallow');
        expect(
          tun.allowAppList,
          scope == 'included' ? ['com.example.included'] : [],
        );
        expect(
          tun.disallowAppList,
          scope == 'excluded' ? ['com.example.excluded'] : [],
        );
        expect(policy.toJson()['android']['includedAppPackageNames'], [
          'com.example.included',
        ]);
        expect(policy.toJson()['android']['excludedAppPackageNames'], [
          'com.example.excluded',
        ]);
      }
      final emptyIncluded = PlatformPolicy.fromJson({
        'android': {'appScope': 'included'},
      });
      expect(
        emptyIncluded.toJson()['android']['includedAppPackageNames'],
        isEmpty,
      );
      expect(
        () => emptyIncluded.toTun(ConnectionPlatform.android),
        throwsFormatException,
      );
      expect(
        () => emptyIncluded.toTun(ConnectionPlatform.ios),
        returnsNormally,
      );
      expect(
        PlatformPolicy.fromJson({
          'android': {'appScope': 'excluded'},
        }).toTun(ConnectionPlatform.android).disallowAppList,
        isEmpty,
      );
    },
  );

  test(
    'Apple On Demand compiles platform rules in order without changing SSIDs',
    () {
      final policy = PlatformPolicy.fromJson({
        'apple': {
          'onDemandEnabled': true,
          'connectWifiSsids': [' Home Wi-Fi ', 'office', ' \t'],
          'disconnectWifiSsids': ['Office'],
          'cellularAction': 'disconnect',
          'ethernetAction': 'connect',
        },
      });
      for (final platform in [
        ConnectionPlatform.ios,
        ConnectionPlatform.macos,
      ]) {
        final rules = policy.toTun(platform).onDemandRules!;
        expect(rules.map((rule) => rule.toJson()).toList(), [
          {
            'mode': 'disconnect',
            'interfaceType': 'wifi',
            'ssid': ['Office'],
          },
          {
            'mode': 'connect',
            'interfaceType': 'wifi',
            'ssid': [' Home Wi-Fi ', 'office'],
          },
          {
            'mode': platform == ConnectionPlatform.ios
                ? 'disconnect'
                : 'connect',
            'interfaceType': platform == ConnectionPlatform.ios
                ? 'cellular'
                : 'ethernet',
          },
          {'mode': 'ignore', 'interfaceType': 'any'},
        ]);
      }
      final withoutWifi = PlatformPolicy.fromJson({
        'apple': {'onDemandEnabled': true},
      });
      expect(
        withoutWifi.toTun(ConnectionPlatform.ios).onDemandRules!.length,
        2,
      );
      expect(
        () => PlatformPolicy.fromJson({
          'apple': {
            'connectWifiSsids': ['Same'],
            'disconnectWifiSsids': ['Same'],
          },
        }),
        throwsFormatException,
      );
    },
  );

  test('Apple master switches hide runtime rules but retain stored drafts', () {
    final value = PlatformPolicy.defaults().toJson();
    value['apple'].addAll({
      'captureAllTraffic': false,
      'allowLocalNetwork': false,
      'alwaysOn': true,
      'onDemandEnabled': true,
      'connectWifiSsids': ['Saved'],
      'ethernetAction': 'disconnect',
    });
    var policy = PlatformPolicy.fromJson(value);
    expect(
      policy
          .toTun(ConnectionPlatform.macos)
          .onDemandRules!
          .map((rule) => rule.toJson())
          .toList(),
      [
        {'mode': 'connect', 'interfaceType': 'any'},
      ],
    );
    expect(policy.toTun(ConnectionPlatform.macos).excludeLocalNetworks, false);
    expect(policy.toJson()['apple']['connectWifiSsids'], ['Saved']);
    expect(policy.toJson()['apple']['onDemandEnabled'], true);
    value['apple']['alwaysOn'] = false;
    value['apple']['onDemandEnabled'] = false;
    policy = PlatformPolicy.fromJson(value);
    expect(policy.toTun(ConnectionPlatform.macos).onDemandRules, isEmpty);
    expect(policy.toJson()['apple']['connectWifiSsids'], ['Saved']);
    value['apple']['onDemandEnabled'] = true;
    expect(
      PlatformPolicy.fromJson(value)
          .toTun(ConnectionPlatform.macos)
          .onDemandRules![1]
          .mode,
      'disconnect',
    );
  });

  test('VPN icon preference is sent only to iOS outside capture-all mode', () {
    for (final captureAll in [false, true]) {
      for (final ipv6 in [false, true]) {
        final policy = PlatformPolicy.fromJson({
          'ipv6Enabled': ipv6,
          'xrayOutboundInterfaceName': 'en0',
          'apple': {
            'captureAllTraffic': captureAll,
            'hideVpnIcon': true,
            'excludedCidrs': ['10.250.0.0/16', '2001:db8::/64'],
          },
        });
        for (final platform in ConnectionPlatform.values) {
          final tun = policy.toTun(platform);
          final active = platform == ConnectionPlatform.ios && !captureAll;
          expect(tun.hideVpnIcon, active ? isTrue : isNull);
          expect(tun.toJson().containsKey('hideVpnIcon'), active);
          if (active) {
            // The special exclusions belong to Swift, not user configuration.
            expect(tun.excludedRoutes, [
              '10.250.0.0/16',
              if (ipv6) '2001:db8::/64',
            ]);
          }
        }
        expect(policy.toJson()['apple']['hideVpnIcon'], isTrue);
        expect(policy.toJson()['apple']['excludedCidrs'], [
          '10.250.0.0/16',
          '2001:db8::/64',
        ]);
        expect(
          PlatformPolicy.fromJson(policy.toJson()).toJson(),
          policy.toJson(),
        );
      }
    }
  });

  test('Apple exclusions compile only for an active Apple policy', () {
    final value = PlatformPolicy.defaults().toJson();
    value['xrayOutboundInterfaceName'] = 'en0';
    final cidrs = ['10.250.0.0/16', '10.250.0.5/32', '2001:db8::/64'];
    value['apple']['excludedCidrs'] = cidrs;
    for (final platform in [ConnectionPlatform.ios, ConnectionPlatform.macos]) {
      final policy = PlatformPolicy.fromJson(value);
      expect(policy.toTun(platform).excludedRoutes, cidrs);
      expect(policy.toTun(platform).tunDnsIPv4, policy.dnsIpv4Address);
      expect(policy.toJson()['apple']['excludedCidrs'], cidrs);
    }
    for (final platform in [
      ConnectionPlatform.android,
      ConnectionPlatform.windows,
      ConnectionPlatform.linux,
    ]) {
      expect(
        PlatformPolicy.fromJson(value).toTun(platform).excludedRoutes,
        isNull,
      );
    }

    value['apple']['captureAllTraffic'] = true;
    var policy = PlatformPolicy.fromJson(value);
    expect(policy.toTun(ConnectionPlatform.macos).excludedRoutes, isNull);
    expect(policy.toJson()['apple']['excludedCidrs'], cidrs);
    value['apple']['excludedCidrs'] = ['invalid inactive draft'];
    policy = PlatformPolicy.fromJson(value);
    expect(() => policy.toTun(ConnectionPlatform.ios), returnsNormally);
  });

  test('Apple IPv6 exclusions are retained but not applied with IPv6 off', () {
    final policy = PlatformPolicy.fromJson({
      'ipv6Enabled': false,
      'apple': {
        'excludedCidrs': ['10.250.0.0/16', '2001:db8::/64'],
      },
    });
    for (final platform in [ConnectionPlatform.ios, ConnectionPlatform.macos]) {
      expect(policy.toTun(platform).excludedRoutes, ['10.250.0.0/16']);
      expect(policy.toTun(platform).tunIPv6, isNull);
    }
    expect(policy.toJson()['apple']['excludedCidrs'], [
      '10.250.0.0/16',
      '2001:db8::/64',
    ]);
  });

  test(
    'Apple CIDRs validate native route syntax without Windows restrictions',
    () {
      for (final cidr in [
        'example.com/24',
        '10.250.0.0',
        '10.250.0.0/-1',
        '10.250.0.0/33',
        '10.250.0.5/16',
        '2001:db8::/129',
        '2001:db8::5/64',
        '[2001:db8::]/64',
        'fe80::%en0/64',
        '10.250.0.0/16\n',
      ]) {
        expect(
          () => PlatformPolicy.fromJson({
            'apple': {
              'excludedCidrs': [cidr],
            },
          }).toTun(ConnectionPlatform.macos),
          throwsFormatException,
          reason: cidr,
        );
      }
      final routes = [
        '0.0.0.0/0',
        '::/0',
        '8.8.8.8/32',
        '2001:db8::1/128',
        ...List.generate(65, (i) => '192.0.2.$i/32'),
      ];
      expect(
        PlatformPolicy.fromJson({
          'apple': {'excludedCidrs': routes},
        }).toTun(ConnectionPlatform.ios).excludedRoutes,
        routes,
      );
    },
  );

  test(
    'desktop interface selection and Windows policy are explicit and isolated',
    () {
      final defaults = PlatformPolicy.defaults();
      for (final platform in [
        ConnectionPlatform.windows,
        ConnectionPlatform.linux,
      ]) {
        expect(() => defaults.toTun(platform), throwsFormatException);
      }
      final policy = PlatformPolicy.fromJson({
        'xrayOutboundInterfaceName': 'Ethernet 2',
        'windows': {
          'alwaysOn': true,
          'allowLocalNetwork': false,
          'excludedCidrs': ['192.0.2.0/24', '2001:db8::/64'],
        },
      });
      expect(
        policy.toTun(ConnectionPlatform.windows).autoOutboundsInterface,
        'Ethernet 2',
      );
      expect(
        policy.toTun(ConnectionPlatform.linux).autoOutboundsInterface,
        'Ethernet 2',
      );
      for (final platform in [
        ConnectionPlatform.ios,
        ConnectionPlatform.macos,
        ConnectionPlatform.android,
      ]) {
        expect(policy.toTun(platform).autoOutboundsInterface, isNull);
      }
      expect(policy.toTun(ConnectionPlatform.windows).onDemandEnabled, isNull);
      expect(policy.toWindowsPolicy().toJson(), policy.toJson()['windows']);
      final ipv4 = policy.toJson()..['ipv6Enabled'] = false;
      final ipv4Policy = PlatformPolicy.fromJson(ipv4);
      expect(() => ipv4Policy.toWindowsPolicy(), throwsFormatException);
      expect(
        () => ipv4Policy.toTun(
          ConnectionPlatform.windows,
          windowsMode: WindowsMode.msix,
        ),
        throwsFormatException,
      );
      expect(() => ipv4Policy.toTun(ConnectionPlatform.ios), returnsNormally);
      expect(ipv4Policy.toJson()['windows']['excludedCidrs'], [
        '192.0.2.0/24',
        '2001:db8::/64',
      ]);
    },
  );

  test(
    'Windows CIDRs reject broad, duplicate, host-bit and DNS exclusions',
    () {
      for (final cidrs in <List<String>>[
        ['0.0.0.0/0'],
        ['::/0'],
        ['192.0.2.1/24'],
        ['2001:db8::1/64'],
        ['192.0.2.0/33'],
        ['2001:db8::/129'],
        ['192.0.2.0'],
        ['192.0.2.0/24\n'],
        ['192.0.002.0/24'],
        ['[2001:db8::]/64'],
        ['fe80::%en0/64'],
        ['192.0.2.0/24', '192.0.2.0/24'],
        ['2001:0DB8:0:0::/64', '2001:db8::/64'],
        ['8.8.8.8/32'],
        ['8.8.0.0/16'],
        ['2001:4860::/32'],
        List.generate(65, (i) => '192.0.2.$i/32'),
      ]) {
        expect(
          () => PlatformPolicy.fromJson({
            'windows': {'excludedCidrs': cidrs},
          }).toWindowsPolicy(),
          throwsFormatException,
        );
      }
      expect(
        PlatformPolicy.fromJson({
          'windows': {
            'excludedCidrs': ['192.0.2.1/32', '2001:db8::1/128'],
          },
        }).toWindowsPolicy().excludedCidrs.length,
        2,
      );
    },
  );

  test('log choices are preserved by policy serialization', () {
    final policy = PlatformPolicy.fromJson({
      'log': {
        'enabled': true,
        'level': 'debug',
        'recordDns': false,
        'maskIp': false,
      },
    });
    expect(policy.logEnabled, true);
    expect(policy.logLevel, 'debug');
    expect(policy.recordDns, false);
    expect(policy.maskAddress, '');
  });
}
