import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';
import 'package:onexray/service/shared/xray/runtime_inbounds.dart';

/// Portable VPN ingress supplements for complete Raw and provider graphs.
/// Device settings and runtime resources belong to ConnectionCompiler.
abstract final class VpnConfigAdapter {
  static const tunnelTag = 'tunIn';
  static const dnsTag = 'app-vpn-dns';

  static Map<String, dynamic> adapt(
    Map<String, dynamic> source, {
    String dnsOutboundTag = dnsTag,
  }) {
    final config = JsonTool.copyMap(source);
    final inbounds = config['inbounds'] as List? ?? <dynamic>[];
    final outbounds = config['outbounds'] as List? ?? <dynamic>[];
    final routing = config['routing'] as Map<String, dynamic>? ?? {};
    final rules = routing['rules'] as List? ?? <dynamic>[];
    if (!inbounds.whereType<Map>().any((value) => value['tag'] == tunnelTag)) {
      inbounds.insert(
        0,
        createTunInbound(fakeDns: FakeDns.usedByRaw(config)).toJson(),
      );
    }

    // A port-53 declaration belongs to the user. Do not infer coverage from
    // network/domain/IP conditions, ranges, rule priority or target protocol.
    final hasDnsRule = rules.whereType<Map>().any((rule) {
      final tags = rule['inboundTag'];
      return '${rule['port']}' == '53' &&
          (tags == null ||
              (tags is List && (tags.isEmpty || tags.contains(tunnelTag))));
    });
    if (!hasDnsRule) {
      Map<String, dynamic>? dnsOutbound;
      for (final outbound in outbounds) {
        if (outbound is Map<String, dynamic> && outbound['protocol'] == 'dns') {
          dnsOutbound = outbound;
          break;
        }
      }
      if (dnsOutbound == null) {
        dnsOutbound = {
          'tag': dnsOutboundTag,
          'protocol': 'dns',
          'settings': <String, dynamic>{},
        };
        outbounds.add(dnsOutbound);
      } else if (dnsOutbound['tag'] == null || dnsOutbound['tag'] == '') {
        dnsOutbound['tag'] = dnsOutboundTag;
      }
      rules.insert(0, {
        'type': 'field',
        'inboundTag': [tunnelTag],
        'network': 'tcp,udp',
        'port': '53',
        'outboundTag': dnsOutbound['tag'],
      });
    }
    config['inbounds'] = inbounds;
    config['outbounds'] = outbounds;
    config['routing'] = {...routing, 'rules': rules};
    return config;
  }
}
