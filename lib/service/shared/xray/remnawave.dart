import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';
import 'package:onexray/service/shared/xray/runtime_inbounds.dart';

/// Adds the App tunnel and DNS ingress on a disposable provider configuration.
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

    inbounds.removeWhere((value) => value is Map && value['protocol'] == 'tun');
    outbounds.removeWhere(
      (value) => value is Map && value['protocol'] == 'dns',
    );

    final tunnel = createTunInbound(fakeDns: FakeDns.usedByRaw(config))
        .toJson();
    Map<String, dynamic>? firstIngress;
    final ingressTags = <String>{};
    for (final inbound in inbounds) {
      if (inbound is! Map<String, dynamic> ||
          !const ['socks', 'http'].contains(inbound['protocol'])) {
        continue;
      }
      firstIngress ??= inbound;
      final tag = inbound['tag'];
      if (tag is String) ingressTags.add(tag);
    }
    final sniffing = firstIngress?['sniffing'];
    if (sniffing != null) {
      tunnel['sniffing'] = sniffing is Map<String, dynamic>
          ? JsonTool.copyMap(sniffing)
          : sniffing;
    }
    inbounds.insert(0, tunnel);

    for (final rule in rules) {
      if (rule is! Map<String, dynamic>) continue;
      final tags = rule['inboundTag'];
      if (tags is List &&
          tags.any(ingressTags.contains) &&
          !tags.contains(tunnelTag)) {
        rule['inboundTag'] = [...tags, tunnelTag];
      }
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
    outbounds.add({
      'tag': dnsTag,
      'protocol': 'dns',
      'settings': <String, dynamic>{},
    });
    rules.insert(0, {
      'type': 'field',
      'inboundTag': [tunnelTag],
      'network': 'tcp,udp',
      'port': '53',
      'outboundTag': dnsTag,
    });
    config['inbounds'] = inbounds;
    config['outbounds'] = outbounds;
    config['routing'] = {...routing, 'rules': rules};
    return config;
  }
}
