import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';

abstract final class RoutingDns {
  static const defaultAddress = RoutingDnsSettings.defaultAddress;
  static const proxyTag = RoutingDnsSettings.proxyTag;
  static const directTag = RoutingDnsSettings.directTag;

  /// DNS only knows the queried domain, not the later connection's conditions.
  static List<String> directDomains(Iterable<XrayRoutingRule> rules) => {
    for (final rule in rules)
      if (rule.outboundTag == 'direct' && _pureDomainRule(rule))
        ...?rule.domain,
  }.toList();

  static XrayDns compile({
    String? directAddress,
    Iterable<String> directDomains = const [],
    bool ipv6 = true,
    bool fakeDns = false,
    Iterable<XrayRoutingRule>? rules,
    RoutingDnsSettings? settings,
    bool directEnabled = true,
  }) {
    final queryStrategy = ipv6 ? 'UseIP' : 'UseIPv4';
    final options =
        settings ??
        const RoutingDnsSettings().withDirectAddress(
          directAddress ?? defaultAddress,
        );
    final hasDirect =
        directEnabled && (settings != null || directAddress != null);
    final orderedRules =
        rules ??
        [
          if (directDomains.isNotEmpty)
            XrayRoutingRule(
              domain: directDomains.toSet().toList(),
              outboundTag: 'direct',
            ),
        ];
    final blocks = <({bool direct, List<String> domains})>[
      for (final rule in orderedRules)
        if (_pureDomainRule(rule) &&
            (rule.domain?.isNotEmpty ?? false) &&
            ((hasDirect && rule.outboundTag == 'direct') ||
                rule.balancerTag == 'proxy' ||
                rule.outboundTag == 'proxy'))
          (
            direct: rule.outboundTag == 'direct',
            domains: rule.domain!.toSet().toList(),
          ),
    ];
    final hasDirectBlock = blocks.any((block) => block.direct);
    XrayDnsServer fakeServer({List<String>? domains, bool? skipFallback}) =>
        XrayDnsServer(
          address: FakeDns.address,
          tag: FakeDns.tag,
          domains: domains,
          skipFallback: skipFallback,
          queryStrategy: queryStrategy,
        );

    List<XrayDnsServer> realServers({
      required bool direct,
      List<String>? domains,
      bool? skipFallback,
      bool finalQuery = false,
    }) {
      final resolvers = direct
          ? options.effectiveDirectResolvers
          : options.effectiveProxyResolvers;
      return [
        for (final (index, resolver) in resolvers.indexed)
          resolver.toXrayDnsServer(
            tag: direct ? directTag : proxyTag,
            domains: domains,
            skipFallback: skipFallback,
            finalQuery: finalQuery && index == resolvers.length - 1
                ? true
                : null,
            queryStrategy: queryStrategy,
          ),
      ];
    }

    return XrayDns(
      disableCache: options.disableCache,
      disableFallbackIfMatch: options.sameExitOnly,
      servers: [
        for (final block in blocks) ...[
          if (fakeDns && !block.direct)
            fakeServer(domains: block.domains, skipFallback: true),
          ...realServers(
            direct: block.direct,
            domains: block.domains,
            skipFallback: true,
            finalQuery: !block.direct || options.sameExitOnly,
          ),
        ],
        // Keep unused direct resolvers in construction validation, but never
        // let them become the generic fallback for unmatched domains.
        if (hasDirect && !hasDirectBlock)
          ...realServers(direct: true, domains: [], skipFallback: true),
        if (fakeDns) fakeServer(),
        ...realServers(direct: false),
      ],
    );
  }

  static bool _pureDomainRule(XrayRoutingRule rule) =>
      (rule.ip?.isEmpty ?? true) &&
      rule.port == null &&
      rule.network == null &&
      (rule.protocol?.isEmpty ?? true) &&
      (rule.localOS?.isEmpty ?? true) &&
      (rule.inboundTag?.isEmpty ?? true);
}
