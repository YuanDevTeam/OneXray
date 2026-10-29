// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'xray_json.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

XrayJson _$XrayJsonFromJson(Map<String, dynamic> json) => XrayJson(
  env: json['env'] == null
      ? null
      : XrayEnv.fromJson(json['env'] as Map<String, dynamic>),
  geodata: json['geodata'] == null
      ? null
      : XrayGeoData.fromJson(json['geodata'] as Map<String, dynamic>),
  log: json['log'] == null
      ? null
      : XrayLog.fromJson(json['log'] as Map<String, dynamic>),
  dns: json['dns'] == null
      ? null
      : XrayDns.fromJson(json['dns'] as Map<String, dynamic>),
  fakedns: (json['fakedns'] as List<dynamic>?)
      ?.map((e) => XrayFakeDns.fromJson(e as Map<String, dynamic>))
      .toList(),
  routing: json['routing'] == null
      ? null
      : XrayRouting.fromJson(json['routing'] as Map<String, dynamic>),
  inbounds: (json['inbounds'] as List<dynamic>?)
      ?.map((e) => XrayInbound.fromJson(e as Map<String, dynamic>))
      .toList(),
  outbounds: (json['outbounds'] as List<dynamic>?)
      ?.map((e) => e as Map<String, dynamic>)
      .toList(),
  policy: json['policy'] == null
      ? null
      : XrayPolicy.fromJson(json['policy'] as Map<String, dynamic>),
  stats: json['stats'] == null
      ? null
      : XrayStats.fromJson(json['stats'] as Map<String, dynamic>),
  metrics: json['metrics'] == null
      ? null
      : XrayMetrics.fromJson(json['metrics'] as Map<String, dynamic>),
  observatory: json['observatory'] == null
      ? null
      : XrayObservatory.fromJson(json['observatory'] as Map<String, dynamic>),
);

Map<String, dynamic> _$XrayJsonToJson(XrayJson instance) => <String, dynamic>{
  'env': ?instance.env?.toJson(),
  'geodata': ?instance.geodata?.toJson(),
  'log': ?instance.log?.toJson(),
  'dns': ?instance.dns?.toJson(),
  'fakedns': ?instance.fakedns?.map((e) => e.toJson()).toList(),
  'routing': ?instance.routing?.toJson(),
  'inbounds': ?instance.inbounds?.map((e) => e.toJson()).toList(),
  'outbounds': ?instance.outbounds,
  'policy': ?instance.policy?.toJson(),
  'stats': ?instance.stats?.toJson(),
  'metrics': ?instance.metrics?.toJson(),
  'observatory': ?instance.observatory?.toJson(),
};

XrayGeoData _$XrayGeoDataFromJson(Map<String, dynamic> json) => XrayGeoData(
  assets: (json['assets'] as List<dynamic>?)
      ?.map((e) => XrayGeoDataAsset.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$XrayGeoDataToJson(XrayGeoData instance) =>
    <String, dynamic>{
      'assets': ?instance.assets?.map((e) => e.toJson()).toList(),
    };

XrayGeoDataAsset _$XrayGeoDataAssetFromJson(Map<String, dynamic> json) =>
    XrayGeoDataAsset(
      file: json['file'] as String?,
      url: json['url'] as String?,
    );

Map<String, dynamic> _$XrayGeoDataAssetToJson(XrayGeoDataAsset instance) =>
    <String, dynamic>{'file': ?instance.file, 'url': ?instance.url};

XrayEnv _$XrayEnvFromJson(Map<String, dynamic> json) => XrayEnv(
  assetLocation: json['xray.location.asset'] as String?,
  certLocation: json['xray.location.cert'] as String?,
);

Map<String, dynamic> _$XrayEnvToJson(XrayEnv instance) => <String, dynamic>{
  'xray.location.asset': ?instance.assetLocation,
  'xray.location.cert': ?instance.certLocation,
};

XrayLog _$XrayLogFromJson(Map<String, dynamic> json) => XrayLog(
  access: json['access'] as String?,
  error: json['error'] as String?,
  logLevel: json['loglevel'] as String?,
  dnsLog: json['dnsLog'] as bool?,
  maskAddress: json['maskAddress'] as String?,
);

Map<String, dynamic> _$XrayLogToJson(XrayLog instance) => <String, dynamic>{
  'access': ?instance.access,
  'error': ?instance.error,
  'loglevel': ?instance.logLevel,
  'dnsLog': ?instance.dnsLog,
  'maskAddress': ?instance.maskAddress,
};

XrayDns _$XrayDnsFromJson(Map<String, dynamic> json) => XrayDns(
  servers: (json['servers'] as List<dynamic>?)
      ?.map((e) => XrayDnsServer.fromJson(e as Map<String, dynamic>))
      .toList(),
  disableCache: json['disableCache'] as bool?,
  disableFallback: json['disableFallback'] as bool?,
  disableFallbackIfMatch: json['disableFallbackIfMatch'] as bool?,
);

Map<String, dynamic> _$XrayDnsToJson(XrayDns instance) => <String, dynamic>{
  'servers': ?instance.servers?.map((e) => e.toJson()).toList(),
  'disableCache': ?instance.disableCache,
  'disableFallback': ?instance.disableFallback,
  'disableFallbackIfMatch': ?instance.disableFallbackIfMatch,
};

XrayFakeDns _$XrayFakeDnsFromJson(Map<String, dynamic> json) => XrayFakeDns(
  ipPool: json['ipPool'] as String?,
  poolSize: (json['poolSize'] as num?)?.toInt(),
);

Map<String, dynamic> _$XrayFakeDnsToJson(XrayFakeDns instance) =>
    <String, dynamic>{
      'ipPool': ?instance.ipPool,
      'poolSize': ?instance.poolSize,
    };

XrayDnsServer _$XrayDnsServerFromJson(Map<String, dynamic> json) =>
    XrayDnsServer(
      address: json['address'] as String?,
      domains: (json['domains'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      skipFallback: json['skipFallback'] as bool?,
      queryStrategy: json['queryStrategy'] as String?,
      tag: json['tag'] as String?,
      finalQuery: json['finalQuery'] as bool?,
    );

Map<String, dynamic> _$XrayDnsServerToJson(XrayDnsServer instance) =>
    <String, dynamic>{
      'address': ?instance.address,
      'domains': ?instance.domains,
      'skipFallback': ?instance.skipFallback,
      'queryStrategy': ?instance.queryStrategy,
      'tag': ?instance.tag,
      'finalQuery': ?instance.finalQuery,
    };

XrayRouting _$XrayRoutingFromJson(Map<String, dynamic> json) => XrayRouting(
  domainStrategy: json['domainStrategy'] as String?,
  rules: (json['rules'] as List<dynamic>?)
      ?.map((e) => XrayRoutingRule.fromJson(e as Map<String, dynamic>))
      .toList(),
  balancers: (json['balancers'] as List<dynamic>?)
      ?.map((e) => XrayBalancer.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$XrayRoutingToJson(XrayRouting instance) =>
    <String, dynamic>{
      'domainStrategy': ?instance.domainStrategy,
      'rules': ?instance.rules?.map((e) => e.toJson()).toList(),
      'balancers': ?instance.balancers?.map((e) => e.toJson()).toList(),
    };

XrayRoutingRule _$XrayRoutingRuleFromJson(Map<String, dynamic> json) =>
    XrayRoutingRule(
      domain: (json['domain'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      ip: (json['ip'] as List<dynamic>?)?.map((e) => e as String).toList(),
      port: json['port'],
      network: json['network'],
      protocol: (json['protocol'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      localOS: (json['localOS'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      inboundTag: (json['inboundTag'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      outboundTag: json['outboundTag'] as String?,
      balancerTag: json['balancerTag'] as String?,
      ruleTag: json['ruleTag'] as String?,
    );

Map<String, dynamic> _$XrayRoutingRuleToJson(XrayRoutingRule instance) =>
    <String, dynamic>{
      'domain': ?instance.domain,
      'ip': ?instance.ip,
      'port': ?instance.port,
      'network': ?instance.network,
      'protocol': ?instance.protocol,
      'localOS': ?instance.localOS,
      'inboundTag': ?instance.inboundTag,
      'outboundTag': ?instance.outboundTag,
      'balancerTag': ?instance.balancerTag,
      'ruleTag': ?instance.ruleTag,
    };

XrayBalancer _$XrayBalancerFromJson(Map<String, dynamic> json) => XrayBalancer(
  tag: json['tag'] as String?,
  selector: (json['selector'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  strategy: json['strategy'] == null
      ? null
      : XrayBalancingStrategy.fromJson(
          json['strategy'] as Map<String, dynamic>,
        ),
  fallbackTag: json['fallbackTag'] as String?,
);

Map<String, dynamic> _$XrayBalancerToJson(XrayBalancer instance) =>
    <String, dynamic>{
      'tag': ?instance.tag,
      'selector': ?instance.selector,
      'strategy': ?instance.strategy?.toJson(),
      'fallbackTag': ?instance.fallbackTag,
    };

XrayBalancingStrategy _$XrayBalancingStrategyFromJson(
  Map<String, dynamic> json,
) => XrayBalancingStrategy(type: json['type'] as String?);

Map<String, dynamic> _$XrayBalancingStrategyToJson(
  XrayBalancingStrategy instance,
) => <String, dynamic>{'type': ?instance.type};

XrayInbound _$XrayInboundFromJson(Map<String, dynamic> json) => XrayInbound(
  listen: json['listen'] as String?,
  port: json['port'] as String?,
  protocol: json['protocol'] as String?,
  settings: json['settings'] as Map<String, dynamic>?,
  tag: json['tag'] as String?,
  sniffing: json['sniffing'] == null
      ? null
      : XrayInboundSniffing.fromJson(json['sniffing'] as Map<String, dynamic>),
);

Map<String, dynamic> _$XrayInboundToJson(XrayInbound instance) =>
    <String, dynamic>{
      'listen': ?instance.listen,
      'port': ?instance.port,
      'protocol': ?instance.protocol,
      'settings': ?instance.settings,
      'tag': ?instance.tag,
      'sniffing': ?instance.sniffing?.toJson(),
    };

XrayInboundTunSettings _$XrayInboundTunSettingsFromJson(
  Map<String, dynamic> json,
) => XrayInboundTunSettings(
  name: json['name'] as String?,
  mtu: (json['mtu'] as num?)?.toInt(),
  gateway: (json['gateway'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  dns: (json['dns'] as List<dynamic>?)?.map((e) => e as String).toList(),
  autoSystemRoutingTable: (json['autoSystemRoutingTable'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  autoOutboundsInterface: json['autoOutboundsInterface'] as String?,
  autoSystemDnsToGateway: json['autoSystemDnsToGateway'] as bool?,
  autoSystemWfpBlockLeak: (json['autoSystemWfpBlockLeak'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$XrayInboundTunSettingsToJson(
  XrayInboundTunSettings instance,
) => <String, dynamic>{
  'name': ?instance.name,
  'mtu': ?instance.mtu,
  'gateway': ?instance.gateway,
  'dns': ?instance.dns,
  'autoSystemRoutingTable': ?instance.autoSystemRoutingTable,
  'autoOutboundsInterface': ?instance.autoOutboundsInterface,
  'autoSystemDnsToGateway': ?instance.autoSystemDnsToGateway,
  'autoSystemWfpBlockLeak': ?instance.autoSystemWfpBlockLeak,
};

XrayInboundSocksSettings _$XrayInboundSocksSettingsFromJson(
  Map<String, dynamic> json,
) => XrayInboundSocksSettings(
  auth: json['auth'] as String?,
  udp: json['udp'] as bool?,
);

Map<String, dynamic> _$XrayInboundSocksSettingsToJson(
  XrayInboundSocksSettings instance,
) => <String, dynamic>{'auth': ?instance.auth, 'udp': ?instance.udp};

XrayInboundSniffing _$XrayInboundSniffingFromJson(Map<String, dynamic> json) =>
    XrayInboundSniffing(
      enabled: json['enabled'] as bool?,
      routeOnly: json['routeOnly'] as bool?,
      destOverride: (json['destOverride'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      metadataOnly: json['metadataOnly'] as bool?,
    );

Map<String, dynamic> _$XrayInboundSniffingToJson(
  XrayInboundSniffing instance,
) => <String, dynamic>{
  'enabled': ?instance.enabled,
  'routeOnly': ?instance.routeOnly,
  'destOverride': ?instance.destOverride,
  'metadataOnly': ?instance.metadataOnly,
};

XrayPolicy _$XrayPolicyFromJson(Map<String, dynamic> json) => XrayPolicy(
  system: json['system'] == null
      ? null
      : XrayPolicySystem.fromJson(json['system'] as Map<String, dynamic>),
);

Map<String, dynamic> _$XrayPolicyToJson(XrayPolicy instance) =>
    <String, dynamic>{'system': ?instance.system?.toJson()};

XrayPolicySystem _$XrayPolicySystemFromJson(Map<String, dynamic> json) =>
    XrayPolicySystem(
      statsInboundUplink: json['statsInboundUplink'] as bool?,
      statsInboundDownlink: json['statsInboundDownlink'] as bool?,
      statsOutboundUplink: json['statsOutboundUplink'] as bool?,
      statsOutboundDownlink: json['statsOutboundDownlink'] as bool?,
    );

Map<String, dynamic> _$XrayPolicySystemToJson(XrayPolicySystem instance) =>
    <String, dynamic>{
      'statsInboundUplink': ?instance.statsInboundUplink,
      'statsInboundDownlink': ?instance.statsInboundDownlink,
      'statsOutboundUplink': ?instance.statsOutboundUplink,
      'statsOutboundDownlink': ?instance.statsOutboundDownlink,
    };

XrayStats _$XrayStatsFromJson(Map<String, dynamic> json) => XrayStats();

Map<String, dynamic> _$XrayStatsToJson(XrayStats instance) =>
    <String, dynamic>{};

XrayMetrics _$XrayMetricsFromJson(Map<String, dynamic> json) =>
    XrayMetrics(listen: json['listen'] as String?);

Map<String, dynamic> _$XrayMetricsToJson(XrayMetrics instance) =>
    <String, dynamic>{'listen': ?instance.listen};

XrayObservatory _$XrayObservatoryFromJson(Map<String, dynamic> json) =>
    XrayObservatory(
      subjectSelector: (json['subjectSelector'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      probeURL: json['probeURL'] as String?,
      probeInterval: json['probeInterval'] as String?,
      enableConcurrency: json['enableConcurrency'] as bool?,
    );

Map<String, dynamic> _$XrayObservatoryToJson(XrayObservatory instance) =>
    <String, dynamic>{
      'subjectSelector': ?instance.subjectSelector,
      'probeURL': ?instance.probeURL,
      'probeInterval': ?instance.probeInterval,
      'enableConcurrency': ?instance.enableConcurrency,
    };

XrayOutbound _$XrayOutboundFromJson(Map<String, dynamic> json) => XrayOutbound(
  tag: json['tag'] as String,
  protocol: json['protocol'] as String,
  settings: json['settings'] as Map<String, dynamic>?,
  streamSettings: json['streamSettings'] == null
      ? null
      : XrayStreamSettings.fromJson(
          json['streamSettings'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$XrayOutboundToJson(XrayOutbound instance) =>
    <String, dynamic>{
      'tag': instance.tag,
      'protocol': instance.protocol,
      'settings': ?instance.settings,
      'streamSettings': ?instance.streamSettings?.toJson(),
    };

XrayOutboundDnsRule _$XrayOutboundDnsRuleFromJson(Map<String, dynamic> json) =>
    XrayOutboundDnsRule(
      action: json['action'] as String,
      qType: json['qType'] as String?,
    );

Map<String, dynamic> _$XrayOutboundDnsRuleToJson(
  XrayOutboundDnsRule instance,
) => <String, dynamic>{'action': instance.action, 'qType': ?instance.qType};

XrayStreamSettings _$XrayStreamSettingsFromJson(Map<String, dynamic> json) =>
    XrayStreamSettings(
      sockopt: json['sockopt'] == null
          ? null
          : XraySockopt.fromJson(json['sockopt'] as Map<String, dynamic>),
      finalmask: json['finalmask'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$XrayStreamSettingsToJson(XrayStreamSettings instance) =>
    <String, dynamic>{
      'sockopt': ?instance.sockopt?.toJson(),
      'finalmask': ?instance.finalmask,
    };

XraySockopt _$XraySockoptFromJson(Map<String, dynamic> json) => XraySockopt(
  dialerProxy: json['dialerProxy'] as String?,
  interface: json['interface'] as String?,
);

Map<String, dynamic> _$XraySockoptToJson(XraySockopt instance) =>
    <String, dynamic>{
      'dialerProxy': ?instance.dialerProxy,
      'interface': ?instance.interface,
    };
