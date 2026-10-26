import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/routing/dns.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';

void main() {
  test('non-address DNS policy defaults to proxy and survives preferences', () {
    expect(
      RoutingDnsSettings.fromJson({}).nonAddressPolicy,
      NonAddressDnsPolicy.proxy,
    );
    for (final policy in NonAddressDnsPolicy.values) {
      final settings = const RoutingDnsSettings().copyWith(
        nonAddressPolicy: policy,
      );
      expect(settings.toJson()['nonAddressPolicy'], policy.name);
      expect(
        RoutingDnsSettings.fromJson(settings.toJson()).nonAddressPolicy,
        policy,
      );
      expect(settings.copyWith(disableCache: true).nonAddressPolicy, policy);
    }
    for (final value in ['unknown', '', 1, true, []]) {
      expect(
        () => RoutingDnsSettings.fromJson({'nonAddressPolicy': value}),
        throwsFormatException,
      );
    }
  });

  test('non-address policy stays effective with direct DNS disabled', () {
    const settings = RoutingDnsSettings(
      directResolvers: [RoutingDnsResolver(address: '223.5.5.5')],
    );
    for (final policy in NonAddressDnsPolicy.values) {
      final effective = settings
          .copyWith(nonAddressPolicy: policy)
          .effectiveJson(directEnabled: false);
      expect(effective['nonAddressPolicy'], policy.name);
      expect(effective, isNot(contains('directResolvers')));
      expect(
        effective,
        settings
            .copyWith(
              nonAddressPolicy: policy,
              directResolvers: const [RoutingDnsResolver(address: '9.9.9.9')],
            )
            .effectiveJson(directEnabled: false),
      );
    }
    expect(
      settings.effectiveJson(directEnabled: false),
      isNot(
        settings
            .copyWith(nonAddressPolicy: NonAddressDnsPolicy.direct)
            .effectiveJson(directEnabled: false),
      ),
    );
  });

  test('only unconditional direct domain rules contribute to local DNS', () {
    final extraConditions = <XrayRoutingRule>[
      XrayRoutingRule(ip: ['192.0.2.0/24']),
      XrayRoutingRule(port: '443'),
      XrayRoutingRule(network: 'tcp'),
      XrayRoutingRule(protocol: ['http']),
      XrayRoutingRule(localOS: ['darwin']),
      XrayRoutingRule(inboundTag: ['tunIn']),
    ];
    for (final rule in extraConditions) {
      rule.domain = ['domain:conditional.test'];
      rule.outboundTag = 'direct';
    }
    expect(
      RoutingDns.directDomains([
        XrayRoutingRule(domain: ['domain:proxy.test'], balancerTag: 'proxy'),
        XrayRoutingRule(domain: ['domain:block.test'], outboundTag: 'block'),
        ...extraConditions,
        XrayRoutingRule(
          domain: ['domain:direct.test', 'geosite:cn'],
          outboundTag: 'direct',
        ),
        XrayRoutingRule(domain: ['domain:direct.test'], outboundTag: 'direct'),
      ]),
      ['domain:direct.test', 'geosite:cn'],
    );
    for (final rule in extraConditions) {
      expect(rule.domain, ['domain:conditional.test']);
      expect(rule.outboundTag, 'direct');
    }
  });

  test('ordered proxy exception truncates a broader direct DNS match', () {
    final dns = RoutingDns.compile(
      settings: const RoutingDnsSettings(),
      rules: [
        XrayRoutingRule(domain: ['geosite:github'], balancerTag: 'proxy'),
        XrayRoutingRule(
          domain: ['geosite:microsoft', 'geosite:cn'],
          outboundTag: 'direct',
        ),
      ],
    );
    final servers = dns.servers!;
    expect(servers[0].domains, ['geosite:github']);
    expect(servers[0].tag, RoutingDns.proxyTag);
    expect(servers[0].skipFallback, true);
    expect(servers[0].finalQuery, true);
    expect(servers[1].domains, ['geosite:microsoft', 'geosite:cn']);
    expect(servers[1].tag, RoutingDns.directTag);
    expect(servers[1].finalQuery, isNull);
    expect(servers.last.domains, isNull);
    expect(servers.last.tag, RoutingDns.proxyTag);
  });

  test(
    'conditional proxy and block rules do not become global DNS policies',
    () {
      final dns = RoutingDns.compile(
        settings: const RoutingDnsSettings(),
        rules: [
          XrayRoutingRule(
            domain: ['domain:conditional.test'],
            port: '443',
            balancerTag: 'proxy',
          ),
          XrayRoutingRule(
            domain: ['domain:blocked.test'],
            outboundTag: 'block',
          ),
          XrayRoutingRule(
            domain: ['domain:direct.test'],
            outboundTag: 'direct',
          ),
        ],
      );
      expect(
        dns.servers!
            .where((server) => server.domains?.isNotEmpty == true)
            .map((server) => server.domains),
        [
          ['domain:direct.test'],
        ],
      );
    },
  );

  test(
    'same-exit fallback caps each ordered block at its last real resolver',
    () {
      const settings = RoutingDnsSettings(
        sameExitOnly: true,
        proxyResolvers: [
          RoutingDnsResolver(address: '8.8.8.8'),
          RoutingDnsResolver(address: '1.1.1.1'),
        ],
        directResolvers: [
          RoutingDnsResolver(address: '223.5.5.5'),
          RoutingDnsResolver(address: '119.29.29.29'),
        ],
      );
      final dns = RoutingDns.compile(
        settings: settings,
        rules: [
          XrayRoutingRule(
            domain: ['domain:direct.test'],
            outboundTag: 'direct',
          ),
          XrayRoutingRule(domain: ['domain:proxy.test'], balancerTag: 'proxy'),
        ],
      );
      expect(dns.disableFallbackIfMatch, true);
      expect(dns.servers!.map((server) => server.tag), [
        RoutingDns.directTag,
        RoutingDns.directTag,
        RoutingDns.proxyTag,
        RoutingDns.proxyTag,
        RoutingDns.proxyTag,
        RoutingDns.proxyTag,
      ]);
      expect(dns.servers!.map((server) => server.finalQuery), [
        null,
        true,
        null,
        true,
        null,
        null,
      ]);
      expect(
        dns.servers!.take(4).every((server) => server.skipFallback == true),
        true,
      );
    },
  );

  test(
    'FakeDNS proxy policy leaves a real resolver before the final boundary',
    () {
      final dns = RoutingDns.compile(
        settings: const RoutingDnsSettings(sameExitOnly: true),
        fakeDns: true,
        ipv6: false,
        rules: [
          XrayRoutingRule(domain: ['geosite:github'], balancerTag: 'proxy'),
          XrayRoutingRule(domain: ['geosite:cn'], outboundTag: 'direct'),
        ],
      );
      expect(dns.servers![0].address, FakeDns.address);
      expect(dns.servers![0].domains, ['geosite:github']);
      expect(dns.servers![0].finalQuery, isNull);
      expect(dns.servers![1].tag, RoutingDns.proxyTag);
      expect(dns.servers![1].domains, ['geosite:github']);
      expect(dns.servers![1].finalQuery, true);
      expect(dns.servers![2].tag, RoutingDns.directTag);
      expect(dns.servers![3].address, FakeDns.address);
      expect(dns.servers![3].domains, isNull);
      expect(
        dns.servers!.every((server) => server.queryStrategy == 'UseIPv4'),
        true,
      );
      expect(FakeDns.poolsFor(dns), hasLength(2));
    },
  );

  test('disabling direct DNS omits direct domains and resolver overrides', () {
    final dns = RoutingDns.compile(
      settings: const RoutingDnsSettings(
        directResolvers: [RoutingDnsResolver(address: '223.5.5.5')],
      ),
      directEnabled: false,
      rules: [
        XrayRoutingRule(domain: ['geosite:cn'], outboundTag: 'direct'),
      ],
    );
    expect(dns.servers, hasLength(1));
    expect(dns.servers!.single.tag, RoutingDns.proxyTag);
    expect(dns.servers!.single.domains, isNull);
  });

  test('old DNS preferences ignore retired options on read and write', () {
    final settings = RoutingDnsSettings.fromJson({
      'disableCache': true,
      'sameExitOnly': true,
      'serveStale': true,
      'serveExpiredTTL': 0,
      'enableParallelQuery': true,
      'proxyResolvers': [
        {
          'address': '1.1.1.1',
          'timeoutMs': 1500,
          'disableCache': false,
          'expectedIPs': ['geoip:US'],
          'expectIPs': ['geoip:JP'],
          'unexpectedIPs': ['geoip:CN'],
          'serveStale': true,
          'serveExpiredTTL': 0,
        },
        {'address': '9.9.9.9'},
      ],
      'directResolvers': [
        {'address': '223.5.5.5'},
      ],
    });
    settings.validate();
    expect(settings.toJson(), {
      'disableCache': true,
      'sameExitOnly': true,
      'nonAddressPolicy': 'proxy',
      'proxyResolvers': [
        {'address': '1.1.1.1'},
        {'address': '9.9.9.9'},
      ],
      'directResolvers': [
        {'address': '223.5.5.5'},
      ],
    });
    expect(settings.effectiveJson()['disableCache'], true);
    expect(
      settings.copyWith(disableCache: false).effectiveJson()['disableCache'],
      false,
    );
    final compiled = RoutingDns.compile(
      settings: settings,
      rules: [
        XrayRoutingRule(domain: ['geosite:cn'], outboundTag: 'direct'),
      ],
    ).toJson();
    expect(
      compiled.keys,
      containsAll(['disableCache', 'disableFallbackIfMatch']),
    );
    expect(compiled.keys, isNot(contains('serveStale')));
    expect(compiled.keys, isNot(contains('serveExpiredTTL')));
    expect(compiled.keys, isNot(contains('enableParallelQuery')));
    expect(
      (compiled['servers'] as List).whereType<Map>().every(
        (server) => !server.keys.any(
          const {
            'expectedIPs',
            'expectIPs',
            'unexpectedIPs',
            'serveStale',
            'serveExpiredTTL',
            'timeoutMs',
            'disableCache',
          }.contains,
        ),
      ),
      true,
    );
  });

  test('ordinary DNS rejects unrepresentable server tags and fake markers', () {
    for (final server in [
      XrayDnsServer(tag: 'user-dns', address: '8.8.8.8'),
      XrayDnsServer(tag: FakeDns.tag, address: '8.8.8.8'),
      XrayDnsServer(tag: RoutingDns.proxyTag, address: FakeDns.address),
      XrayDnsServer(
        tag: RoutingDns.directTag,
        address: '8.8.8.8',
        domains: ['geosite:cn'],
      ),
    ]) {
      expect(
        () => RoutingDnsSettings.fromXrayDns(XrayDns(servers: [server])),
        throwsFormatException,
      );
    }
  });

  test('ordinary resolvers cannot bypass the routed DNS role', () {
    for (final address in [
      'localhost',
      'https+local://dns.example/query',
      'h2c+local://dns.example/query',
      'quic+local://dns.example',
      'tcp+local://1.1.1.1',
      '127.0.0.1',
      'tcp://127.0.0.1',
      '::1',
      'fakedns',
    ]) {
      expect(
        () => RoutingDnsResolver(address: address).validate(),
        throwsFormatException,
        reason: address,
      );
    }
    for (final address in [
      '8.8.8.8',
      'tcp://1.1.1.1',
      'https://dns.example/query',
      '192.168.1.1',
    ]) {
      expect(
        () => RoutingDnsResolver(address: address).validate(),
        returnsNormally,
        reason: address,
      );
    }
  });

  test(
    'sniffing preserves editable options and retains managed FakeDNS recovery',
    () {
      const settings = RoutingSniffingSettings(
        routeOnly: true,
        metadataOnly: true,
      );
      final sniffing = settings.toXraySniffing(fakeDns: true);
      expect(sniffing.destOverride, ['http', 'tls', 'quic', 'fakedns']);
      expect(
        RoutingSniffingSettings.fromXraySniffing(sniffing).toJson(),
        settings.toJson(),
      );
      expect(
        RoutingSniffingSettings.fromJson(settings.toJson()).toJson(),
        settings.toJson(),
      );
      expect(() => settings.validate(fakeDns: true), returnsNormally);
      expect(
        () =>
            const RoutingSniffingSettings(enabled: false)
                .validate(fakeDns: true),
        throwsFormatException,
      );
      expect(
        () => RoutingSniffingSettings.fromXraySniffing(
          XrayInboundSniffing(destOverride: ['http']),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'automatic selection observes only multiple current full-chain tags',
    () {
      const settings = RoutingSelectionSettings(type: 'leastPing');
      final compiled = settings.compile(selector: ['app-exit-0', 'app-exit-1']);
      expect(compiled.automatic, true);
      expect(compiled.balancer.selector, ['app-exit-0', 'app-exit-1']);
      expect(compiled.balancer.fallbackTag, 'app-exit-0');
      expect(compiled.observatory.subjectSelector, [
        'app-exit-0',
        'app-exit-1',
      ]);
      expect(compiled.observatory.probeInterval, '60s');
      final single = settings.compile(selector: ['app-entry-0']);
      expect(single.automatic, false);
      expect(single.balancer.strategy?.type, 'roundRobin');
      expect(single.observatory.subjectSelector, isEmpty);
      expect(
        RoutingSelectionSettings.fromXray(
          routing: settings.toStoredRouting(),
          observatory: settings.toStoredObservatory(),
        ).toJson(),
        settings.toJson(),
      );
    },
  );

  test('probe URL normalization matches the effective runtime policy', () {
    const settings = RoutingSelectionSettings(
      type: 'leastPing',
      probeURL: ' https://example.com/probe ',
    );
    settings.validate();
    expect(
      settings
          .compile(selector: ['app-entry-0', 'app-entry-1'])
          .observatory
          .probeURL,
      'https://example.com/probe',
    );
    expect(
      settings.toStoredObservatory().probeURL,
      'https://example.com/probe',
    );
  });

  test('least-ping probe parameters validate before constructing Core', () {
    for (final interval in ['10s', '30s', '1m', '1h2m3s', '0.5m', '+60s']) {
      expect(
        () => RoutingSelectionSettings(
          type: 'leastPing',
          probeInterval: interval,
        ).validate(),
        returnsNormally,
        reason: interval,
      );
    }
    for (final interval in [
      '0',
      '0s',
      '9.999s',
      '-60s',
      '10',
      'NaNs',
      '1d',
      '10s trailing',
      '99999999999999999999h',
    ]) {
      expect(
        () => RoutingSelectionSettings(
          type: 'leastPing',
          probeInterval: interval,
        ).validate(),
        throwsFormatException,
        reason: interval,
      );
    }
    expect(
      () => const RoutingSelectionSettings(
        type: 'leastPing',
        probeURL: 'file:///tmp/probe',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const RoutingSelectionSettings(
        probeURL: '',
        probeInterval: '0s',
      ).validate(),
      returnsNormally,
    );
  });
}
