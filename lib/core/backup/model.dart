import 'package:json_annotation/json_annotation.dart';

part 'model.g.dart';

@JsonSerializable(explicitToJson: true)
class BackupDocument {
  final String format;
  final int version;
  final int createdAt;
  final List<BackupManualGroup> manualGroups;
  final List<BackupCoreConfig> coreConfigs;
  final List<BackupSubscription> subscriptions;
  final List<BackupRoutingProfile> routingProfiles;
  final BackupSmartRouting smartRouting;
  final List<BackupGeoData> geoData;
  @JsonKey(includeIfNull: false)
  final Map<String, dynamic>? platformSettings;

  const BackupDocument({
    this.format = 'onexray-backup',
    this.version = 1,
    required this.createdAt,
    this.manualGroups = const [],
    required this.coreConfigs,
    required this.subscriptions,
    required this.routingProfiles,
    required this.smartRouting,
    required this.geoData,
    this.platformSettings,
  });

  factory BackupDocument.fromJson(Map<String, dynamic> json) =>
      _$BackupDocumentFromJson(json);
  Map<String, dynamic> toJson() => _$BackupDocumentToJson(this);
}

@JsonSerializable()
class BackupManualGroup {
  final String key;
  final String name;
  final int sortOrder;

  const BackupManualGroup(this.key, this.name, this.sortOrder);
  factory BackupManualGroup.fromJson(Map<String, dynamic> json) =>
      _$BackupManualGroupFromJson(json);
  Map<String, dynamic> toJson() => _$BackupManualGroupToJson(this);
}

@JsonSerializable()
class BackupCoreConfig {
  final String name;
  final String type;
  final String tags;
  final String data;
  @JsonKey(includeIfNull: false)
  final String? manualGroupKey;
  final int manualSortOrder;

  const BackupCoreConfig(
    this.name,
    this.type,
    this.tags,
    this.data, {
    this.manualGroupKey,
    this.manualSortOrder = 0,
  });
  factory BackupCoreConfig.fromJson(Map<String, dynamic> json) =>
      _$BackupCoreConfigFromJson(json);
  Map<String, dynamic> toJson() => _$BackupCoreConfigToJson(this);
}

@JsonSerializable()
class BackupSubscription {
  final String name;
  final String url;
  final String? userAgent;
  final String? ageSecretKey;
  final String? agePublicKey;
  final bool hwidEnabled;
  final String? hwid;
  final String panel;
  final String mode;

  const BackupSubscription(
    this.name,
    this.url,
    this.ageSecretKey,
    this.agePublicKey,
    this.hwidEnabled,
    this.hwid, {
    this.userAgent,
    this.panel = 'generic',
    this.mode = 'appManaged',
  });
  factory BackupSubscription.fromJson(Map<String, dynamic> json) =>
      _$BackupSubscriptionFromJson(json);
  Map<String, dynamic> toJson() => _$BackupSubscriptionToJson(this);
}

@JsonSerializable()
class BackupRoutingProfile {
  final String name;
  final bool advanced;
  final String data;

  const BackupRoutingProfile(this.name, this.advanced, this.data);
  factory BackupRoutingProfile.fromJson(Map<String, dynamic> json) =>
      _$BackupRoutingProfileFromJson(json);
  Map<String, dynamic> toJson() => _$BackupRoutingProfileToJson(this);
}

@JsonSerializable()
class BackupGeoData {
  final String name;
  final String type;
  final String url;

  const BackupGeoData(this.name, this.type, this.url);
  factory BackupGeoData.fromJson(Map<String, dynamic> json) =>
      _$BackupGeoDataFromJson(json);
  Map<String, dynamic> toJson() => _$BackupGeoDataToJson(this);
}

@JsonSerializable()
class BackupSmartRouting {
  final int entryCount;
  final List<String> directRegions;
  final bool directPrivate;
  final bool directApple;
  final bool directWindows;
  final bool directDns;
  @JsonKey(includeIfNull: false)
  final String? directDnsAddress;
  @JsonKey(includeIfNull: false)
  final Map<String, dynamic>? dns;
  @JsonKey(includeIfNull: false)
  final Map<String, dynamic>? sniffing;
  @JsonKey(includeIfNull: false)
  final Map<String, dynamic>? selection;
  final bool fakeDns;
  final bool fragment;
  final bool blockAds;

  const BackupSmartRouting({
    required this.entryCount,
    required this.directRegions,
    required this.directPrivate,
    required this.directApple,
    required this.directWindows,
    required this.directDns,
    this.directDnsAddress,
    this.dns,
    this.sniffing,
    this.selection,
    required this.fakeDns,
    this.fragment = false,
    required this.blockAds,
  });
  factory BackupSmartRouting.fromJson(Map<String, dynamic> json) =>
      _$BackupSmartRoutingFromJson(json);
  Map<String, dynamic> toJson() => _$BackupSmartRoutingToJson(this);
}
