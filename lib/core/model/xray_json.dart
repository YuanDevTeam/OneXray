import 'package:json_annotation/json_annotation.dart';

part 'xray_json.g.dart';

/// App-owned Xray configuration used by regular connection compilation.
///
/// Raw JSON is intentionally handled as a map outside this model. Proxy
/// outbounds also remain maps so every Xray protocol field is preserved.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayJson {
  XrayEnv? env;
  XrayGeoData? geodata;
  XrayLog? log;
  XrayDns? dns;
  List<XrayFakeDns>? fakedns;
  XrayRouting? routing;
  List<XrayInbound>? inbounds;
  List<Map<String, dynamic>>? outbounds;
  XrayPolicy? policy;
  XrayStats? stats;
  XrayMetrics? metrics;
  XrayObservatory? observatory;

  XrayJson({
    this.env,
    this.geodata,
    this.log,
    this.dns,
    this.fakedns,
    this.routing,
    this.inbounds,
    this.outbounds,
    this.policy,
    this.stats,
    this.metrics,
    this.observatory,
  });

  factory XrayJson.fromJson(Map<String, dynamic> json) =>
      _$XrayJsonFromJson(json);

  Map<String, dynamic> toJson() => _$XrayJsonToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayGeoData {
  List<XrayGeoDataAsset>? assets;

  XrayGeoData({this.assets});

  factory XrayGeoData.fromJson(Map<String, dynamic> json) =>
      _$XrayGeoDataFromJson(json);

  Map<String, dynamic> toJson() => _$XrayGeoDataToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayGeoDataAsset {
  String? file;
  String? url;

  XrayGeoDataAsset({this.file, this.url});

  factory XrayGeoDataAsset.fromJson(Map<String, dynamic> json) =>
      _$XrayGeoDataAssetFromJson(json);

  Map<String, dynamic> toJson() => _$XrayGeoDataAssetToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayEnv {
  @JsonKey(name: 'xray.location.asset')
  String? assetLocation;
  @JsonKey(name: 'xray.location.cert')
  String? certLocation;

  XrayEnv({this.assetLocation, this.certLocation});

  factory XrayEnv.fromJson(Map<String, dynamic> json) =>
      _$XrayEnvFromJson(json);

  Map<String, dynamic> toJson() => _$XrayEnvToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayLog {
  String? access;
  String? error;
  @JsonKey(name: 'loglevel')
  String? logLevel;
  bool? dnsLog;
  String? maskAddress;

  XrayLog({
    this.access,
    this.error,
    this.logLevel,
    this.dnsLog,
    this.maskAddress,
  });

  factory XrayLog.fromJson(Map<String, dynamic> json) =>
      _$XrayLogFromJson(json);

  Map<String, dynamic> toJson() => _$XrayLogToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayDns {
  List<XrayDnsServer>? servers;
  bool? disableCache;
  bool? disableFallback;
  bool? disableFallbackIfMatch;

  XrayDns({
    this.servers,
    this.disableCache,
    this.disableFallback,
    this.disableFallbackIfMatch,
  });

  factory XrayDns.fromJson(Map<String, dynamic> json) =>
      _$XrayDnsFromJson(json);

  Map<String, dynamic> toJson() => _$XrayDnsToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayFakeDns {
  String? ipPool;
  int? poolSize;

  XrayFakeDns({this.ipPool, this.poolSize});

  factory XrayFakeDns.fromJson(Map<String, dynamic> json) =>
      _$XrayFakeDnsFromJson(json);

  Map<String, dynamic> toJson() => _$XrayFakeDnsToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayDnsServer {
  String? address;
  List<String>? domains;
  bool? skipFallback;
  String? queryStrategy;
  String? tag;
  bool? finalQuery;

  XrayDnsServer({
    this.address,
    this.domains,
    this.skipFallback,
    this.queryStrategy,
    this.tag,
    this.finalQuery,
  });

  factory XrayDnsServer.fromJson(Map<String, dynamic> json) =>
      _$XrayDnsServerFromJson(json);

  Map<String, dynamic> toJson() => _$XrayDnsServerToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayRouting {
  String? domainStrategy;
  List<XrayRoutingRule>? rules;
  List<XrayBalancer>? balancers;

  XrayRouting({this.domainStrategy, this.rules, this.balancers});

  factory XrayRouting.fromJson(Map<String, dynamic> json) =>
      _$XrayRoutingFromJson(json);

  Map<String, dynamic> toJson() => _$XrayRoutingToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayRoutingRule {
  List<String>? domain;
  List<String>? ip;
  Object? port;
  Object? network;
  List<String>? protocol;
  List<String>? localOS;
  List<String>? inboundTag;
  String? outboundTag;
  String? balancerTag;
  String? ruleTag;

  XrayRoutingRule({
    this.domain,
    this.ip,
    this.port,
    this.network,
    this.protocol,
    this.localOS,
    this.inboundTag,
    this.outboundTag,
    this.balancerTag,
    this.ruleTag,
  });

  factory XrayRoutingRule.fromJson(Map<String, dynamic> json) =>
      _$XrayRoutingRuleFromJson(json);

  Map<String, dynamic> toJson() => _$XrayRoutingRuleToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayBalancer {
  String? tag;
  List<String>? selector;
  XrayBalancingStrategy? strategy;
  String? fallbackTag;

  XrayBalancer({this.tag, this.selector, this.strategy, this.fallbackTag});

  factory XrayBalancer.fromJson(Map<String, dynamic> json) =>
      _$XrayBalancerFromJson(json);

  Map<String, dynamic> toJson() => _$XrayBalancerToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayBalancingStrategy {
  String? type;

  XrayBalancingStrategy({this.type});

  factory XrayBalancingStrategy.fromJson(Map<String, dynamic> json) =>
      _$XrayBalancingStrategyFromJson(json);

  Map<String, dynamic> toJson() => _$XrayBalancingStrategyToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayInbound {
  String? listen;
  String? port;
  String? protocol;
  Map<String, dynamic>? settings;
  String? tag;
  XrayInboundSniffing? sniffing;

  XrayInbound({
    this.listen,
    this.port,
    this.protocol,
    this.settings,
    this.tag,
    this.sniffing,
  });

  factory XrayInbound.fromJson(Map<String, dynamic> json) =>
      _$XrayInboundFromJson(json);

  Map<String, dynamic> toJson() => _$XrayInboundToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayInboundTunSettings {
  String? name;
  int? mtu;
  List<String>? gateway;
  List<String>? dns;
  List<String>? autoSystemRoutingTable;
  String? autoOutboundsInterface;
  bool? autoSystemDnsToGateway;
  List<String>? autoSystemWfpBlockLeak;

  XrayInboundTunSettings({
    this.name,
    this.mtu,
    this.gateway,
    this.dns,
    this.autoSystemRoutingTable,
    this.autoOutboundsInterface,
    this.autoSystemDnsToGateway,
    this.autoSystemWfpBlockLeak,
  });

  factory XrayInboundTunSettings.fromJson(Map<String, dynamic> json) =>
      _$XrayInboundTunSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$XrayInboundTunSettingsToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayInboundSocksSettings {
  String? auth;
  bool? udp;

  XrayInboundSocksSettings({this.auth, this.udp});

  factory XrayInboundSocksSettings.fromJson(Map<String, dynamic> json) =>
      _$XrayInboundSocksSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$XrayInboundSocksSettingsToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayInboundSniffing {
  bool? enabled;
  bool? routeOnly;
  List<String>? destOverride;
  bool? metadataOnly;

  XrayInboundSniffing({
    this.enabled,
    this.routeOnly,
    this.destOverride,
    this.metadataOnly,
  });

  factory XrayInboundSniffing.fromJson(Map<String, dynamic> json) =>
      _$XrayInboundSniffingFromJson(json);

  Map<String, dynamic> toJson() => _$XrayInboundSniffingToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayPolicy {
  XrayPolicySystem? system;

  XrayPolicy({this.system});

  factory XrayPolicy.fromJson(Map<String, dynamic> json) =>
      _$XrayPolicyFromJson(json);

  Map<String, dynamic> toJson() => _$XrayPolicyToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayPolicySystem {
  bool? statsInboundUplink;
  bool? statsInboundDownlink;
  bool? statsOutboundUplink;
  bool? statsOutboundDownlink;

  XrayPolicySystem({
    this.statsInboundUplink,
    this.statsInboundDownlink,
    this.statsOutboundUplink,
    this.statsOutboundDownlink,
  });

  factory XrayPolicySystem.fromJson(Map<String, dynamic> json) =>
      _$XrayPolicySystemFromJson(json);

  Map<String, dynamic> toJson() => _$XrayPolicySystemToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayStats {
  XrayStats();

  factory XrayStats.fromJson(Map<String, dynamic> json) =>
      _$XrayStatsFromJson(json);

  Map<String, dynamic> toJson() => _$XrayStatsToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayMetrics {
  String? listen;

  XrayMetrics({this.listen});

  factory XrayMetrics.fromJson(Map<String, dynamic> json) =>
      _$XrayMetricsFromJson(json);

  Map<String, dynamic> toJson() => _$XrayMetricsToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayObservatory {
  List<String>? subjectSelector;
  String? probeURL;
  String? probeInterval;
  bool? enableConcurrency;

  XrayObservatory({
    this.subjectSelector,
    this.probeURL,
    this.probeInterval,
    this.enableConcurrency,
  });

  factory XrayObservatory.fromJson(Map<String, dynamic> json) =>
      _$XrayObservatoryFromJson(json);

  Map<String, dynamic> toJson() => _$XrayObservatoryToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
final class XrayOutbound {
  final String tag;
  final String protocol;
  final Map<String, dynamic>? settings;
  final XrayStreamSettings? streamSettings;

  XrayOutbound({
    required this.tag,
    required this.protocol,
    this.settings,
    this.streamSettings,
  });

  factory XrayOutbound.fromJson(Map<String, dynamic> json) =>
      _$XrayOutboundFromJson(json);

  Map<String, dynamic> toJson() => _$XrayOutboundToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayOutboundDnsRule {
  final String action;
  final String? qType;

  const XrayOutboundDnsRule({required this.action, this.qType});

  factory XrayOutboundDnsRule.fromJson(Map<String, dynamic> json) =>
      _$XrayOutboundDnsRuleFromJson(json);

  Map<String, dynamic> toJson() => _$XrayOutboundDnsRuleToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayStreamSettings {
  XraySockopt? sockopt;
  Map<String, dynamic>? finalmask;

  XrayStreamSettings({this.sockopt, this.finalmask});

  factory XrayStreamSettings.fromJson(Map<String, dynamic> json) =>
      _$XrayStreamSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$XrayStreamSettingsToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XraySockopt {
  String? dialerProxy;
  String? interface;

  XraySockopt({this.dialerProxy, this.interface});

  factory XraySockopt.fromJson(Map<String, dynamic> json) =>
      _$XraySockoptFromJson(json);

  Map<String, dynamic> toJson() => _$XraySockoptToJson(this);
}
