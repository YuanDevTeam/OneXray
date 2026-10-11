// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

XrayMetricsVars _$XrayMetricsVarsFromJson(Map<String, dynamic> json) =>
    XrayMetricsVars(
      json['stats'] == null
          ? null
          : XrayMetricsStats.fromJson(json['stats'] as Map<String, dynamic>),
      observatory: (json['observatory'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
          k,
          XrayMetricsObservation.fromJson(e as Map<String, dynamic>),
        ),
      ),
    );

Map<String, dynamic> _$XrayMetricsVarsToJson(
  XrayMetricsVars instance,
) => <String, dynamic>{
  'stats': ?instance.stats?.toJson(),
  'observatory': ?instance.observatory?.map((k, e) => MapEntry(k, e.toJson())),
};

XrayMetricsObservation _$XrayMetricsObservationFromJson(
  Map<String, dynamic> json,
) => XrayMetricsObservation(
  alive: json['alive'] as bool?,
  delay: (json['delay'] as num?)?.toInt(),
  outboundTag: json['outbound_tag'] as String?,
  lastTryTime: (json['last_try_time'] as num?)?.toInt(),
  lastSeenTime: (json['last_seen_time'] as num?)?.toInt(),
);

Map<String, dynamic> _$XrayMetricsObservationToJson(
  XrayMetricsObservation instance,
) => <String, dynamic>{
  'alive': ?instance.alive,
  'delay': ?instance.delay,
  'outbound_tag': ?instance.outboundTag,
  'last_try_time': ?instance.lastTryTime,
  'last_seen_time': ?instance.lastSeenTime,
};

XrayMetricsStats _$XrayMetricsStatsFromJson(Map<String, dynamic> json) =>
    XrayMetricsStats(
      json['inbound'] == null
          ? null
          : XrayMetricsInboundStats.fromJson(
              json['inbound'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$XrayMetricsStatsToJson(XrayMetricsStats instance) =>
    <String, dynamic>{'inbound': ?instance.inbound?.toJson()};

XrayMetricsInboundStats _$XrayMetricsInboundStatsFromJson(
  Map<String, dynamic> json,
) => XrayMetricsInboundStats(
  json['tunIn'] == null
      ? null
      : XrayTrafficCounter.fromJson(json['tunIn'] as Map<String, dynamic>),
);

Map<String, dynamic> _$XrayMetricsInboundStatsToJson(
  XrayMetricsInboundStats instance,
) => <String, dynamic>{'tunIn': ?instance.tunIn?.toJson()};

XrayTrafficCounter _$XrayTrafficCounterFromJson(Map<String, dynamic> json) =>
    XrayTrafficCounter(
      (json['uplink'] as num?)?.toInt(),
      (json['downlink'] as num?)?.toInt(),
    );

Map<String, dynamic> _$XrayTrafficCounterToJson(XrayTrafficCounter instance) =>
    <String, dynamic>{
      'uplink': ?instance.uplink,
      'downlink': ?instance.downlink,
    };
