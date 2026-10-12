import 'package:collection/collection.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';
import 'package:onexray/service/shared/xray/runtime_inbounds.dart';

/// Connects a provider's local proxy ingress to the App tunnel on a disposable
/// copy. No platform FD, listener port, logging or statistics are written here.
/// The same result can be validated, compiled or copied into a personal Raw.
abstract final class RemnawaveAdapter {
  static const tunnelTag = 'tunIn';
  static const dnsTag = 'app-remna-dns';
  static const _equality = DeepCollectionEquality();

  static Map<String, dynamic> adapt(Map<String, dynamic> source) {
    final config = JsonTool.copyMap(source);
    final inbounds = _objects(config['inbounds'], 'inbounds');
    final outbounds = _objects(config['outbounds'], 'outbounds');
    if (outbounds.isEmpty) {
      throw const FormatException('Provider configuration needs outbounds');
    }
    final routing = config['routing'];
    if (routing != null && routing is! Map<String, dynamic>) {
      throw const FormatException('routing must be an object');
    }
    final rules = _objects(routing?['rules'], 'routing.rules');
    final managed = inbounds
        .where((value) => value['tag'] == tunnelTag)
        .toList();
    if (managed.length > 1 ||
        inbounds.any(
          (value) => value['protocol'] == 'tun' && value['tag'] != tunnelTag,
        )) {
      throw const FormatException(
        'Only the App-managed tunIn tunnel is allowed',
      );
    }
    if (managed.isNotEmpty && managed.single['protocol'] != 'tun') {
      throw const FormatException('Provider tunIn must use the tun protocol');
    }
    final ingress = inbounds
        .where(
          (value) =>
              value['tag'] != tunnelTag &&
              const ['socks', 'http'].contains(value['protocol']),
        )
        .toList();
    final tags = <String>[];
    for (final inbound in ingress) {
      final tag = inbound['tag'];
      if (tag is! String || tag.isEmpty || tags.contains(tag)) {
        throw const FormatException('Provider proxy inbounds need unique tags');
      }
      tags.add(tag);
    }
    if (ingress.length > 1) {
      final first = ingress.first;
      final firstRules = _ingressRules(rules, tags.first);
      for (var index = 1; index < ingress.length; index++) {
        if (!_equality.equals(first['sniffing'], ingress[index]['sniffing']) ||
            !_equality.equals(firstRules, _ingressRules(rules, tags[index]))) {
          throw const FormatException(
            'Provider proxy ingress policies conflict',
          );
        }
      }
    }
    final fakeDns = FakeDns.usedByRaw(config);
    final tunnel = managed.isEmpty
        ? createTunInbound(fakeDns: fakeDns).toJson()
        : managed.single;
    final sniffing = ingress.firstOrNull?['sniffing'];
    if (sniffing != null) {
      if (sniffing is! Map<String, dynamic>) {
        throw const FormatException('Provider sniffing must be an object');
      }
      if (managed.isNotEmpty &&
          tunnel['sniffing'] != null &&
          !_equality.equals(tunnel['sniffing'], sniffing)) {
        throw const FormatException(
          'Provider tunnel and proxy sniffing conflict',
        );
      }
      tunnel['sniffing'] = JsonTool.copyMap(sniffing);
    } else if (tunnel['sniffing'] == null) {
      tunnel['sniffing'] = createTunInbound(fakeDns: fakeDns)
          .toJson()['sniffing'];
    }
    if (fakeDns) {
      final actual = tunnel['sniffing'];
      final overrides = actual is Map ? actual['destOverride'] : null;
      if (actual is! Map<String, dynamic> ||
          actual['enabled'] == false ||
          (overrides != null &&
              (overrides is! List ||
                  overrides.any((value) => value is! String)))) {
        throw const FormatException(
          'Provider FakeDNS requires tunnel domain recovery',
        );
      }
      actual['enabled'] = true;
      final values = overrides is List ? [...overrides] : <dynamic>[];
      if (!values.any(
        (value) => value == 'fakedns' || value == 'fakedns+others',
      )) {
        values.add('fakedns');
      }
      actual['destOverride'] = values;
    }
    if (managed.isEmpty) inbounds.insert(0, tunnel);
    config['inbounds'] = inbounds;
    for (final rule in rules) {
      final inboundTags = rule['inboundTag'];
      if (inboundTags == null) continue;
      if (inboundTags is! List ||
          inboundTags.any((value) => value is! String)) {
        throw const FormatException(
          'routing inboundTag must be a string array',
        );
      }
      if (inboundTags.any(tags.contains) && !inboundTags.contains(tunnelTag)) {
        rule['inboundTag'] = [...inboundTags, tunnelTag];
      }
    }
    final dns = config['dns'];
    if (dns != null && dns is! Map<String, dynamic>) {
      throw const FormatException('dns must be an object');
    }
    if (dns != null || fakeDns) {
      if (dns is Map && dns['tag'] == tunnelTag) {
        throw const FormatException('Provider DNS tag conflicts with tunIn');
      }
      if (!_hasDnsIngress(rules, outbounds)) {
        _checkDnsTag(config, outbounds);
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
      }
    }
    if (routing != null || rules.isNotEmpty) {
      config['routing'] = <String, dynamic>{
        if (routing is Map<String, dynamic>) ...routing,
        'rules': rules,
      };
    }
    config['outbounds'] = outbounds;
    return config;
  }

  static List<Map<String, dynamic>> _objects(Object? value, String field) {
    if (value == null) return [];
    if (value is! List || value.any((item) => item is! Map<String, dynamic>)) {
      throw FormatException('$field must be an object array');
    }
    return value.cast<Map<String, dynamic>>().toList();
  }

  static List<Map<String, dynamic>> _ingressRules(
    List<Map<String, dynamic>> rules,
    String tag,
  ) => [
    for (final rule in rules)
      if (rule['inboundTag'] is List &&
          (rule['inboundTag'] as List).contains(tag))
        {...rule}..remove('inboundTag'),
  ];

  static bool _hasDnsIngress(
    List<Map<String, dynamic>> rules,
    List<Map<String, dynamic>> outbounds,
  ) {
    var earlierMayMatch = false;
    var usable = false;
    for (final rule in rules) {
      final tags = rule['inboundTag'];
      if (tags != null && (tags is! List || !tags.contains(tunnelTag))) {
        continue;
      }
      final network = rule['network'];
      final simple =
          '${rule['port']}' == '53' &&
          (network == null || network == 'tcp,udp' || network == 'udp,tcp') &&
          !rule.keys.any(
            (key) => !const {
              'type',
              'ruleTag',
              'inboundTag',
              'port',
              'network',
              'outboundTag',
            }.contains(key),
          );
      if (!simple) {
        earlierMayMatch |= _mayMatchDns(rule);
        continue;
      }
      final outbound = outbounds
          .where((value) => value['tag'] == rule['outboundTag'])
          .firstOrNull;
      final settings = outbound?['settings'];
      if (outbound?['protocol'] != 'dns' ||
          (settings != null && (settings is! Map || settings.isNotEmpty)) ||
          outbound?['proxySettings'] != null ||
          _dialerProxy(outbound) != null) {
        throw const FormatException(
          'Provider DNS ingress conflicts with built-in DNS integration',
        );
      }
      usable |= !earlierMayMatch;
      earlierMayMatch = true;
    }
    return usable;
  }

  static bool _mayMatchDns(Map<String, dynamic> rule) {
    final network = rule['network'];
    if (network is String &&
        !network.split(',').any((value) => value == 'tcp' || value == 'udp')) {
      return false;
    }
    final port = rule['port'];
    if (port == null) return true;
    for (final value in '$port'.split(',')) {
      final ends = value.split('-');
      final first = int.tryParse(ends.first.trim());
      final last = int.tryParse(ends.last.trim());
      if (first == null || last == null || (first <= 53 && last >= 53)) {
        return true;
      }
    }
    return false;
  }

  static Object? _dialerProxy(Map<String, dynamic>? outbound) {
    final stream = outbound?['streamSettings'];
    final sockopt = stream is Map ? stream['sockopt'] : null;
    return sockopt is Map ? sockopt['dialerProxy'] : null;
  }

  static void _checkDnsTag(
    Map<String, dynamic> config,
    List<Map<String, dynamic>> outbounds,
  ) {
    if (outbounds.any((value) => value['tag'] == dnsTag)) {
      throw const FormatException(
        'Provider outbound uses reserved app-remna-dns tag',
      );
    }
    final routing = config['routing'];
    final rules = routing is Map ? routing['rules'] : null;
    if (rules is List &&
        rules.whereType<Map>().any(
          (rule) =>
              rule['outboundTag'] == dnsTag || rule['balancerTag'] == dnsTag,
        )) {
      throw const FormatException(
        'Provider rule references reserved DNS bridge',
      );
    }
    final balancers = routing is Map ? routing['balancers'] : null;
    final selectors = <Object?>[
      if (balancers is List)
        for (final balancer in balancers.whereType<Map>()) balancer['selector'],
      for (final key in const ['observatory', 'burstObservatory'])
        if (config[key] is Map) (config[key] as Map)['subjectSelector'],
    ];
    if (selectors.any(
      (value) =>
          value is List &&
          value.any((prefix) => prefix is String && dnsTag.startsWith(prefix)),
    )) {
      throw const FormatException(
        'Provider selector captures reserved DNS bridge',
      );
    }
    final dns = config['dns'];
    if (dns is Map && dns['tag'] == tunnelTag) {
      throw const FormatException('Provider DNS tag conflicts with tunIn');
    }
  }
}
