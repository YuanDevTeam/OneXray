import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';
import 'package:onexray/service/shared/xray/runtime_inbounds.dart';
import 'package:onexray/service/shared/xray/runtime_outbounds.dart';

/// Portable VPN ingress supplements for complete Raw and provider graphs.
/// Device settings and runtime resources belong to ConnectionCompiler.
abstract final class VpnConfigAdapter {
  static const tunnelTag = 'tunIn';
  static const dnsTag = 'app-vpn-dns';
  static const defaultDnsTag = 'app-vpn-default-dns';
  static const defaultDnsDirectTag = 'app-vpn-dns-direct';

  static Map<String, dynamic> adapt(
    Map<String, dynamic> source, {
    String dnsOutboundTag = dnsTag,
  }) {
    final config = JsonTool.copyMap(source);
    // Leave malformed containers intact for Core validation. This adapter only
    // supplements absent containers; it does not repair invalid native JSON.
    if ((config['inbounds'] != null && config['inbounds'] is! List) ||
        (config['outbounds'] != null && config['outbounds'] is! List) ||
        (config['routing'] != null &&
            config['routing'] is! Map<String, dynamic>)) {
      return config;
    }
    final inbounds = config['inbounds'] as List? ?? <dynamic>[];
    final outbounds = config['outbounds'] as List? ?? <dynamic>[];
    final routing = config['routing'] as Map<String, dynamic>? ?? {};
    if (routing['rules'] != null && routing['rules'] is! List) return config;
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
      if (dnsOutbound == null ||
          dnsOutbound['tag'] == null ||
          dnsOutbound['tag'] == '') {
        if (outbounds.whereType<Map>().any(
          (outbound) => outbound['tag'] == dnsOutboundTag,
        )) {
          throw FormatException(
            'The $dnsOutboundTag outbound tag is App-managed',
          );
        }
      }
      if (dnsOutbound == null) {
        _ensureDnsDirect(outbounds);
        dnsOutbound = createDnsOutbound(
          tag: dnsOutboundTag,
          dialerProxy: defaultDnsDirectTag,
        ).toJson();
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

  /// Runtime-only fallback. Never persist device DNS in imported/shared JSON.
  static Map<String, dynamic> withDefaultDns(
    Map<String, dynamic> source, {
    required String ipv4Address,
    String? ipv6Address,
  }) {
    final config = JsonTool.copyMap(source);
    final existing = config['dns'];
    if (existing != null && existing is! Map<String, dynamic>) return config;
    final dns = existing as Map<String, dynamic>? ?? <String, dynamic>{};
    final servers = dns['servers'];
    // Malformed values remain Core errors, not an invitation to replace them.
    if (servers != null && (servers is! List || servers.isNotEmpty)) {
      return config;
    }

    final outbounds = config['outbounds'] as List? ?? <dynamic>[];
    final inbounds = config['inbounds'] as List? ?? <dynamic>[];
    if (inbounds.whereType<Map>().any(
      (inbound) => inbound['tag'] == defaultDnsTag,
    )) {
      throw const FormatException('Default VPN DNS tags are App-managed');
    }
    dns['servers'] = [
      for (final address in [ipv4Address, ?ipv6Address])
        {'address': address, 'tag': defaultDnsTag},
    ];
    config['dns'] = dns;
    _ensureDnsDirect(outbounds);
    config['outbounds'] = outbounds;
    final routing = config['routing'] as Map<String, dynamic>? ?? {};
    final rules = routing['rules'] as List? ?? <dynamic>[];
    rules.insert(0, {
      'type': 'field',
      'inboundTag': [defaultDnsTag],
      'outboundTag': defaultDnsDirectTag,
    });
    config['routing'] = {...routing, 'rules': rules};
    return config;
  }

  static void _ensureDnsDirect(List<dynamic> outbounds) {
    for (final outbound in outbounds.whereType<Map>()) {
      if (outbound['tag'] != defaultDnsDirectTag) continue;
      if (outbound['protocol'] != 'freedom' || outbound.length != 2) {
        throw const FormatException(
          'The VPN DNS direct outbound is App-managed',
        );
      }
      return;
    }
    outbounds.add(createFreedomOutbound(tag: defaultDnsDirectTag).toJson());
  }
}
