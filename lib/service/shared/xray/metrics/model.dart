import 'package:json_annotation/json_annotation.dart';

part 'model.g.dart';

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayMetricsVars {
  final XrayMetricsStats? stats;
  final Map<String, XrayMetricsObservation>? observatory;

  const XrayMetricsVars(this.stats, {this.observatory});

  ({int uplink, int downlink}) get managedTraffic {
    final counter = stats?.inbound?.tunIn;
    return (uplink: counter?.uplink ?? 0, downlink: counter?.downlink ?? 0);
  }

  factory XrayMetricsVars.fromJson(Map<String, dynamic> json) =>
      _$XrayMetricsVarsFromJson(json);

  Map<String, dynamic> toJson() => _$XrayMetricsVarsToJson(this);
}

/// /debug/vars uses Go encoding/json on OutboundStatus, hence snake_case
/// timestamps in Unix seconds and omitted false/zero values.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayMetricsObservation {
  final bool? alive;
  final int? delay;
  @JsonKey(name: 'outbound_tag')
  final String? outboundTag;
  @JsonKey(name: 'last_try_time')
  final int? lastTryTime;
  @JsonKey(name: 'last_seen_time')
  final int? lastSeenTime;

  const XrayMetricsObservation({
    this.alive,
    this.delay,
    this.outboundTag,
    this.lastTryTime,
    this.lastSeenTime,
  });

  factory XrayMetricsObservation.fromJson(Map<String, dynamic> json) =>
      _$XrayMetricsObservationFromJson(json);

  Map<String, dynamic> toJson() => _$XrayMetricsObservationToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayMetricsStats {
  final XrayMetricsInboundStats? inbound;

  const XrayMetricsStats(this.inbound);

  factory XrayMetricsStats.fromJson(Map<String, dynamic> json) =>
      _$XrayMetricsStatsFromJson(json);

  Map<String, dynamic> toJson() => _$XrayMetricsStatsToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayMetricsInboundStats {
  final XrayTrafficCounter? tunIn;

  const XrayMetricsInboundStats(this.tunIn);

  factory XrayMetricsInboundStats.fromJson(Map<String, dynamic> json) =>
      _$XrayMetricsInboundStatsFromJson(json);

  Map<String, dynamic> toJson() => _$XrayMetricsInboundStatsToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayTrafficCounter {
  final int? uplink;
  final int? downlink;

  const XrayTrafficCounter(this.uplink, this.downlink);

  factory XrayTrafficCounter.fromJson(Map<String, dynamic> json) =>
      _$XrayTrafficCounterFromJson(json);

  Map<String, dynamic> toJson() => _$XrayTrafficCounterToJson(this);
}
