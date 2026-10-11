import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/routing/dns.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';

void main() {
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
        enableParallelQuery: true,
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
      expect(dns.enableParallelQuery, true);
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

  test('parallel DNS cannot query cross-exit fallback or race FakeDNS', () {
    const settings = RoutingDnsSettings(
      enableParallelQuery: true,
      proxyResolvers: [
        RoutingDnsResolver(address: '8.8.8.8'),
        RoutingDnsResolver(address: '1.1.1.1'),
      ],
    );
    final direct = XrayRoutingRule(
      domain: ['geosite:cn'],
      outboundTag: 'direct',
    );
    expect(
      RoutingDns.compile(
        settings: settings,
        rules: [direct],
      ).enableParallelQuery,
      false,
    );
    expect(
      RoutingDns.compile(
        settings: settings.copyWith(sameExitOnly: true),
        fakeDns: true,
        rules: [direct],
      ).enableParallelQuery,
      false,
    );
    expect(settings.enableParallelQuery, true);
    expect(
      RoutingDns.compile(
        settings: const RoutingDnsSettings(
          sameExitOnly: true,
          enableParallelQuery: true,
        ),
      ).enableParallelQuery,
      false,
    );
  });

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

  test('ordinary DNS exchange preserves options and canonicalizes expected IP alias', () {
    final legacy = XrayDns(
      servers: [
        XrayDnsServer(
          tag: RoutingDns.directTag,
          address: '223.5.5.5',
          expectIPs: ['geoip:cn'],
          disableCache: false,
          serveStale: false,
          serveExpiredTTL: 0,
          timeoutMs: 0,
        ),
      ],
    );
    final settings = RoutingDnsSettings.fromXrayDns(legacy);
    expect(settings.effectiveProxyResolvers.first.address, '8.8.8.8');
    expect(settings.directAddress, '223.5.5.5');
    final stored = settings.toStoredXrayDns(fakeDns: true);
    final direct = stored.servers!.singleWhere(
      (server) => server.tag == RoutingDns.directTag,
    );
      expect(direct.expectedIPs, ['geoip:cn']);
      expect(RoutingDnsResolver.fromXrayDnsServer(XrayDnsServer(address: '8.8.8.8',
        expectedIPs: [], expectIPs: ['geoip:cn'])).expectedIPs, ['geoip:cn']);
    expect(direct.expectIPs, isNull);
    expect(direct.disableCache, false);
    expect(direct.serveStale, false);
    expect(direct.serveExpiredTTL, 0);
    expect(direct.timeoutMs, 0);
    expect(
      stored.servers!.every(
        (server) =>
            server.domains == null &&
            server.finalQuery == null &&
            server.queryStrategy == null,
      ),
      true,
    );
    expect(RoutingDnsSettings.fromXrayDns(stored).toJson(), settings.toJson());
    expect(
      RoutingDnsSettings.fromJson(settings.toJson()).toJson(),
      settings.toJson(),
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
    'stale cache inheritance keeps finite expiry and explicit disabled values',
    () {
      expect(
        () => const RoutingDnsSettings(serveStale: true).validate(),
        returnsNormally,
      );
      expect(
        () => const RoutingDnsSettings(
          serveStale: true,
          serveExpiredTTL: 0,
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => const RoutingDnsSettings(
          serveStale: true,
          proxyResolvers: [
            RoutingDnsResolver(address: '8.8.8.8', serveExpiredTTL: 0),
          ],
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => const RoutingDnsSettings(
          serveStale: true,
          proxyResolvers: [
            RoutingDnsResolver(
              address: '8.8.8.8',
              serveStale: false,
              serveExpiredTTL: 0,
            ),
          ],
        ).validate(),
        returnsNormally,
      );
      final inherited = const RoutingDnsResolver(
        address: '8.8.8.8',
        disableCache: false,
      ).copyWith(clearDisableCache: true);
      expect(inherited.toJson().containsKey('disableCache'), false);
    },
  );

  test(
    'sniffing preserves editable options and retains managed FakeDNS recovery',
    () {
      const settings = RoutingSniffingSettings(
        routeOnly: true,
        metadataOnly: true,
        domainsExcluded: ['domain:internal.test'],
        ipsExcluded: ['192.168.0.0/16'],
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
      for (final excluded in [
        '198.19.1.1',
        '198.18.0.0/15',
        '0.0.0.0/0',
        'fc00:1::1',
        'fc00::/7',
        '::/0',
      ]) {
        expect(
          () =>
              RoutingSniffingSettings(ipsExcluded: [excluded])
                  .validate(fakeDns: true),
          throwsFormatException,
          reason: excluded,
        );
      }
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
