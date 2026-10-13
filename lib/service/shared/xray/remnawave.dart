import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';
import 'package:onexray/service/shared/xray/runtime_inbounds.dart';

/// Supplements the App tunnel and DNS ingress on a disposable provider graph.
/// Platform runtime fields and Core validation use the shared Raw path.
abstract final class RemnawaveAdapter {
  static const tunnelTag = 'tunIn';
  static const dnsTag = 'app-remna-dns';

  static Map<String, dynamic> adapt(Map<String, dynamic> source) {
    final config = JsonTool.copyMap(source);
    final inbounds = config['inbounds'] as List? ?? <dynamic>[];
    final outbounds = config['outbounds'] as List? ?? <dynamic>[];
    final routing = config['routing'] as Map<String, dynamic>? ?? {};
    final rules = routing['rules'] as List? ?? <dynamic>[];

    Map<String, dynamic>? tunnel;
    Map<String, dynamic>? firstIngress;
    final ingressTags = <String>{};
    for (final inbound in inbounds) {
      if (inbound is! Map<String, dynamic>) continue;
      if (inbound['protocol'] == 'tun' &&
          (tunnel == null ||
              (tunnel['tag'] != tunnelTag && inbound['tag'] == tunnelTag))) {
        tunnel = inbound;
      }
      if (const ['socks', 'http'].contains(inbound['protocol'])) {
        firstIngress ??= inbound;
        final tag = inbound['tag'];
        if (tag is String) ingressTags.add(tag);
      }
    }
    final oldTunnelTag = tunnel?['tag'];
    if (tunnel == null) {
      tunnel = createTunInbound(fakeDns: FakeDns.usedByRaw(config)).toJson();
      final sniffing = firstIngress?['sniffing'];
      if (sniffing != null) {
        tunnel['sniffing'] = sniffing is Map<String, dynamic>
            ? JsonTool.copyMap(sniffing)
            : sniffing;
      }
      inbounds.insert(0, tunnel);
    } else {
      tunnel['tag'] = tunnelTag;
    }

    for (final rule in rules) {
      if (rule is! Map<String, dynamic>) continue;
      final tags = rule['inboundTag'];
      if (tags is! List) continue;
      final adaptedTags = <dynamic>[];
      for (final tag in tags) {
        final adapted = oldTunnelTag is String && tag == oldTunnelTag
            ? tunnelTag
            : tag;
        if (adapted != tunnelTag || !adaptedTags.contains(tunnelTag)) {
          adaptedTags.add(adapted);
        }
      }
      if (tags.any(ingressTags.contains) && !adaptedTags.contains(tunnelTag)) {
        adaptedTags.add(tunnelTag);
      }
      rule['inboundTag'] = adaptedTags;
    }
    for (final outbound in const [
      {'tag': 'direct', 'protocol': 'freedom'},
      {'tag': 'block', 'protocol': 'blackhole'},
    ]) {
      if (!outbounds.any(
        (value) => value is Map && value['tag'] == outbound['tag'],
      )) {
        outbounds.add({...outbound});
      }
    }
    // An explicit port-53 rule is a provider policy declaration. Do not infer
    // its coverage or equivalence from network/domain/IP conditions or order.
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
          'tag': dnsTag,
          'protocol': 'dns',
          'settings': <String, dynamic>{},
        };
        outbounds.add(dnsOutbound);
      } else if (dnsOutbound['tag'] == null || dnsOutbound['tag'] == '') {
        dnsOutbound['tag'] = dnsTag;
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
