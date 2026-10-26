import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/shared/xray/runtime_outbounds.dart';

/// The ordinary runtime and save validation use the same forwarding graph.
/// Complete configurations retain their own DNS adapters and never use this.
final class RoutingDnsForwarding {
  static const outboundTag = 'dnsOut';
  static const proxyTag = 'app-dns-forward';

  final List<Map<String, dynamic>> outbounds;
  final List<XrayRoutingRule> rules;

  RoutingDnsForwarding._(this.outbounds, this.rules);

  factory RoutingDnsForwarding.compile({
    required NonAddressDnsPolicy policy,
    String? fixedProxyTag,
  }) {
    final useBalancer =
        policy == NonAddressDnsPolicy.proxy && fixedProxyTag == null;
    return RoutingDnsForwarding._(
      [
        createDnsOutbound(
          tag: outboundTag,
          dialerProxy: switch (policy) {
            NonAddressDnsPolicy.proxy => fixedProxyTag ?? proxyTag,
            NonAddressDnsPolicy.direct => 'direct',
            NonAddressDnsPolicy.empty => null,
          },
          returnNonAddress: policy == NonAddressDnsPolicy.empty,
        ).toJson(),
        if (useBalancer)
          {
            'tag': proxyTag,
            'protocol': 'loopback',
            'settings': {'inboundTag': proxyTag},
          },
      ],
      [
        if (useBalancer)
          XrayRoutingRule(
            ruleTag: proxyTag,
            inboundTag: [proxyTag],
            balancerTag: 'proxy',
          ),
      ],
    );
  }
}
