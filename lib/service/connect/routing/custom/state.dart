import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/shared/xray/fake_dns.dart';
import 'package:onexray/service/shared/xray/fragment.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';

enum RoutingRuleAction { proxy, direct, block }

/// Editable state for one Custom routing rule.
///
/// It deliberately mirrors only the conditions and three actions exposed
/// by the ordinary UI. Raw JSON never passes through this state.
final class RoutingRuleState {
  final String ruleTag;
  final List<String> domain;
  final List<String> ip;
  final Object? port;
  final Object? network;
  final List<String> protocol;
  final List<String> localOS;
  final RoutingRuleAction action;

  RoutingRuleState({
    this.ruleTag = '',
    Iterable<String> domain = const [],
    Iterable<String> ip = const [],
    Object? port,
    Object? network,
    Iterable<String> protocol = const [],
    Iterable<String> localOS = const [],
    this.action = RoutingRuleAction.proxy,
  }) : domain = List.unmodifiable(domain),
       ip = List.unmodifiable(ip),
       port = _copyValue(port),
       protocol = List.unmodifiable(protocol),
       localOS = List.unmodifiable(localOS),
       network = _copyValue(network);

  factory RoutingRuleState.fromXrayJson(
    XrayRoutingRule rule, {
    List<Object>? path,
  }) {
    if (rule.inboundTag != null) {
      throw JsonDiagnostic(
        'Unsupported Custom routing rule field',
        path: path == null ? null : [...path, 'inboundTag'],
      );
    }
    final action = switch ((rule.balancerTag, rule.outboundTag)) {
      ('proxy', null) => RoutingRuleAction.proxy,
      (null, 'direct') => RoutingRuleAction.direct,
      (null, 'block') => RoutingRuleAction.block,
      _ => throw JsonDiagnostic(
        'Routing rule must select exactly one supported action',
        path: path,
      ),
    };
    return RoutingRuleState(
      ruleTag: rule.ruleTag ?? '',
      domain: rule.domain ?? const [],
      ip: rule.ip ?? const [],
      port: _copyValue(rule.port),
      network: _copyValue(rule.network),
      protocol: rule.protocol ?? const [],
      localOS: rule.localOS ?? const [],
      action: action,
    );
  }

  XrayRoutingRule get xrayJson {
    return XrayRoutingRule(
      ruleTag: ruleTag.isEmpty ? null : ruleTag,
      domain: domain.isEmpty ? null : List.of(domain),
      ip: ip.isEmpty ? null : List.of(ip),
      port: _copyValue(port),
      network: _copyValue(network),
      protocol: protocol.isEmpty ? null : List.of(protocol),
      localOS: localOS.isEmpty ? null : List.of(localOS),
      balancerTag: action == RoutingRuleAction.proxy ? 'proxy' : null,
      outboundTag: action == RoutingRuleAction.proxy ? null : action.name,
    );
  }

  Map<String, dynamic> toJson() => xrayJson.toJson();

  RoutingRuleState copyWith({
    String? ruleTag,
    Iterable<String>? domain,
    Iterable<String>? ip,
    Object? port,
    Object? network,
    Iterable<String>? protocol,
    Iterable<String>? localOS,
    RoutingRuleAction? action,
  }) => RoutingRuleState(
    ruleTag: ruleTag ?? this.ruleTag,
    domain: domain ?? this.domain,
    ip: ip ?? this.ip,
    port: port ?? this.port,
    network: network ?? this.network,
    protocol: protocol ?? this.protocol,
    localOS: localOS ?? this.localOS,
    action: action ?? this.action,
  );
}

/// The ordinary Custom routing state between UI, Xray models and persistence.
final class RoutingProfileState implements RoutingConfiguration {
  @override
  final int? id;
  @override
  final String name;
  @override
  final int entryCount;
  final RoutingDnsSettings dns;
  final RoutingSniffingSettings sniffing;
  final RoutingSelectionSettings selection;
  String get directDnsAddress => dns.directAddress;
  final bool fakeDns;
  final Map<String, dynamic>? _fragmentOutbound;
  final List<RoutingRuleState> rules;

  RoutingProfileState({
    this.id,
    required this.name,
    this.entryCount = 1,
    String? directDnsAddress,
    RoutingDnsSettings dns = const RoutingDnsSettings(),
    this.sniffing = const RoutingSniffingSettings(),
    this.selection = const RoutingSelectionSettings(),
    this.fakeDns = false,
    Map<String, dynamic>? fragmentOutbound,
    Iterable<RoutingRuleState> rules = const [],
  }) : dns = directDnsAddress == null
           ? dns
           : dns.withDirectAddress(directDnsAddress),
       _fragmentOutbound = fragmentOutbound == null
           ? null
           : JsonTool.copyMap(fragmentOutbound),
       rules = List.unmodifiable(rules);

  bool get fragment => _fragmentOutbound != null;

  Map<String, dynamic>? get fragmentOutbound =>
      _fragmentOutbound == null ? null : JsonTool.copyMap(_fragmentOutbound);

  factory RoutingProfileState.fromXrayJson({
    int? id,
    required String name,
    required XrayJson xrayJson,
  }) {
    if (xrayJson.env != null ||
        xrayJson.geodata != null ||
        xrayJson.log != null ||
        xrayJson.fakedns != null ||
        xrayJson.policy != null ||
        xrayJson.stats != null ||
        xrayJson.metrics != null) {
      throw const FormatException('Unsupported Custom routing field');
    }
    final outbounds = xrayJson.outbounds;
    if (outbounds == null) {
      throw const JsonDiagnostic(
        'outbounds must be an array',
        path: ['outbounds'],
      );
    }
    final entryCount = outbounds
        .takeWhile((outbound) => outbound.isEmpty)
        .length;
    final helpers = outbounds.skip(entryCount).toList();
    if (entryCount < 1 || entryCount > 3 || helpers.length > 2) {
      throw const JsonDiagnostic(
        'outbounds must start with 1–3 empty object slots followed by an '
        'optional fragment freedom outbound and optional managed DNS outbound',
        path: ['outbounds'],
      );
    }
    final fragment = helpers.isNotEmpty && XrayFragment.matches(helpers.first)
        ? helpers.removeAt(0)
        : null;
    if (helpers.length > 1) {
      throw const JsonDiagnostic(
        'Custom routing supports one fragment and one managed DNS outbound',
        path: ['outbounds'],
      );
    }
    final nonAddressPolicy = helpers.isEmpty
        ? NonAddressDnsPolicy.proxy
        : _nonAddressPolicy(helpers.single, [
            'outbounds',
            entryCount + (fragment == null ? 0 : 1),
          ]);
    final dns = RoutingDnsSettings.fromXrayDns(xrayJson.dns)
        .copyWith(nonAddressPolicy: nonAddressPolicy);
    final sniffing = RoutingSniffingSettings.fromXraySniffing(
      (xrayJson.inbounds?.isNotEmpty == true
          ? xrayJson.inbounds!.first.sniffing
          : null),
    );
    final selection = RoutingSelectionSettings.fromXray(
      routing: xrayJson.routing,
      observatory: xrayJson.observatory,
    );
    final state = RoutingProfileState(
      id: id,
      name: name,
      entryCount: entryCount,
      dns: dns,
      sniffing: sniffing,
      selection: selection,
      fakeDns:
          xrayJson.dns?.servers?.any((server) => server.tag == FakeDns.tag) ??
          false,
      fragmentOutbound: fragment,
      rules: [
        for (final (index, rule)
            in (xrayJson.routing?.rules ?? const <XrayRoutingRule>[]).indexed)
          RoutingRuleState.fromXrayJson(
            rule,
            path: ['routing', 'rules', index],
          ),
      ],
    );
    state.validate();
    return state;
  }

  XrayJson get xrayJson {
    validate();
    return XrayJson(
      dns: dns.toStoredXrayDns(fakeDns: fakeDns),
      inbounds: [
        XrayInbound(
          tag: 'tunIn',
          sniffing: sniffing.toXraySniffing(fakeDns: fakeDns, forStorage: true),
        ),
      ],
      observatory: selection.toStoredObservatory(),
      outbounds: [
        for (var index = 0; index < entryCount; index++) <String, dynamic>{},
        if (_fragmentOutbound != null) JsonTool.copyMap(_fragmentOutbound),
        if (dns.nonAddressPolicy != NonAddressDnsPolicy.proxy)
          {
            'tag': 'dnsOut',
            'protocol': 'dns',
            'settings': {
              'rules': [
                {'action': 'hijack', 'qType': '1,28'},
                {
                  'action': dns.nonAddressPolicy == NonAddressDnsPolicy.direct
                      ? 'direct'
                      : 'return',
                },
              ],
            },
          },
      ],
      routing: XrayRouting(
        domainStrategy: 'IPIfNonMatch',
        balancers: selection.toStoredRouting().balancers,
        rules: rules.isEmpty ? null : [for (final rule in rules) rule.xrayJson],
      ),
    );
  }

  @override
  String encode() => JsonTool.encoder.convert(xrayJson.toJson());

  @override
  bool get advanced => false;

  @override
  int get ruleCount => rules.length;

  @override
  Map<String, dynamic> toJson() => xrayJson.toJson();

  @override
  RoutingProfileState copyWith({
    int? id,
    bool clearId = false,
    String? name,
    int? entryCount,
    String? directDnsAddress,
    RoutingDnsSettings? dns,
    RoutingSniffingSettings? sniffing,
    RoutingSelectionSettings? selection,
    bool? fakeDns,
    Map<String, dynamic>? fragmentOutbound,
    bool clearFragment = false,
    Iterable<RoutingRuleState>? rules,
  }) => RoutingProfileState(
    id: clearId ? null : id ?? this.id,
    name: name ?? this.name,
    entryCount: entryCount ?? this.entryCount,
    directDnsAddress: directDnsAddress,
    dns: dns ?? this.dns,
    sniffing: sniffing ?? this.sniffing,
    selection: selection ?? this.selection,
    fakeDns: fakeDns ?? this.fakeDns,
    fragmentOutbound: clearFragment
        ? null
        : fragmentOutbound ?? _fragmentOutbound,
    rules: rules ?? this.rules,
  );

  @override
  void validate() {
    dns.validate();
    sniffing.validate(fakeDns: fakeDns);
    selection.validate();
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty && trimmedName.runes.length > 32) {
      throw const FormatException(
        'Custom route name must contain at most 32 characters',
      );
    }
    if (entryCount < 1 || entryCount > 3) {
      throw const FormatException('Custom routing requires 1–3 entry nodes');
    }
    if (_fragmentOutbound != null && !XrayFragment.matches(_fragmentOutbound)) {
      throw JsonDiagnostic(
        'Custom routing supports only a freedom outbound tagged fragment',
        path: ['outbounds', entryCount],
      );
    }
  }
}

Object? _copyValue(Object? value) =>
    value is List ? List<Object?>.unmodifiable(value) : value;

// The ordinary form represents only this fixed helper. Runtime socket and
// destination settings must never be imported into its persisted state.
NonAddressDnsPolicy _nonAddressPolicy(
  Map<String, dynamic> outbound,
  List<Object> path,
) {
  if (outbound.length != 3 ||
      outbound['tag'] != 'dnsOut' ||
      outbound['protocol'] != 'dns') {
    throw JsonDiagnostic(
      'Custom DNS outbound must contain only dnsOut tag, dns protocol and settings',
      path: path,
    );
  }
  final settings = outbound['settings'];
  if (settings is! Map<String, dynamic> || settings.length != 1) {
    throw JsonDiagnostic(
      'Custom DNS outbound settings must contain only rules',
      path: [...path, 'settings'],
    );
  }
  final rules = settings['rules'];
  if (rules is! List || rules.length != 2) {
    throw JsonDiagnostic(
      'Custom DNS outbound requires one A/AAAA hijack and one fallback rule',
      path: [...path, 'settings', 'rules'],
    );
  }
  final addressRule = rules.first;
  if (addressRule is! Map<String, dynamic> ||
      addressRule.length != 2 ||
      addressRule['action'] != 'hijack' ||
      addressRule['qType'] != '1,28') {
    throw JsonDiagnostic(
      'Custom DNS outbound must hijack exactly A/AAAA queries first',
      path: [...path, 'settings', 'rules', 0],
    );
  }
  final fallback = rules.last;
  if (fallback is! Map<String, dynamic> || fallback.length != 1) {
    throw JsonDiagnostic(
      'Custom DNS outbound fallback must contain only an action',
      path: [...path, 'settings', 'rules', 1],
    );
  }
  return switch (fallback['action']) {
    'direct' => NonAddressDnsPolicy.direct,
    'return' => NonAddressDnsPolicy.empty,
    _ => throw JsonDiagnostic(
      'Custom DNS outbound fallback must use direct or return',
      path: [...path, 'settings', 'rules', 1, 'action'],
    ),
  };
}
