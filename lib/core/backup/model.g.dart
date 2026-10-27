// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BackupDocument _$BackupDocumentFromJson(Map<String, dynamic> json) =>
    BackupDocument(
      format: json['format'] as String? ?? 'onexray-backup',
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt: (json['createdAt'] as num).toInt(),
      manualGroups:
          (json['manualGroups'] as List<dynamic>?)
              ?.map(
                (e) => BackupManualGroup.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      coreConfigs: (json['coreConfigs'] as List<dynamic>)
          .map((e) => BackupCoreConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      subscriptions: (json['subscriptions'] as List<dynamic>)
          .map((e) => BackupSubscription.fromJson(e as Map<String, dynamic>))
          .toList(),
      routingProfiles: (json['routingProfiles'] as List<dynamic>)
          .map((e) => BackupRoutingProfile.fromJson(e as Map<String, dynamic>))
          .toList(),
      smartRouting: BackupSmartRouting.fromJson(
        json['smartRouting'] as Map<String, dynamic>,
      ),
      geoData: (json['geoData'] as List<dynamic>)
          .map((e) => BackupGeoData.fromJson(e as Map<String, dynamic>))
          .toList(),
      platformSettings: json['platformSettings'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$BackupDocumentToJson(
  BackupDocument instance,
) => <String, dynamic>{
  'format': instance.format,
  'version': instance.version,
  'createdAt': instance.createdAt,
  'manualGroups': instance.manualGroups.map((e) => e.toJson()).toList(),
  'coreConfigs': instance.coreConfigs.map((e) => e.toJson()).toList(),
  'subscriptions': instance.subscriptions.map((e) => e.toJson()).toList(),
  'routingProfiles': instance.routingProfiles.map((e) => e.toJson()).toList(),
  'smartRouting': instance.smartRouting.toJson(),
  'geoData': instance.geoData.map((e) => e.toJson()).toList(),
  'platformSettings': ?instance.platformSettings,
};

BackupManualGroup _$BackupManualGroupFromJson(Map<String, dynamic> json) =>
    BackupManualGroup(
      json['key'] as String,
      json['name'] as String,
      (json['sortOrder'] as num).toInt(),
    );

Map<String, dynamic> _$BackupManualGroupToJson(BackupManualGroup instance) =>
    <String, dynamic>{
      'key': instance.key,
      'name': instance.name,
      'sortOrder': instance.sortOrder,
    };

BackupCoreConfig _$BackupCoreConfigFromJson(Map<String, dynamic> json) =>
    BackupCoreConfig(
      json['name'] as String,
      json['type'] as String,
      json['tags'] as String,
      json['data'] as String,
      manualGroupKey: json['manualGroupKey'] as String?,
      manualSortOrder: (json['manualSortOrder'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$BackupCoreConfigToJson(BackupCoreConfig instance) =>
    <String, dynamic>{
      'name': instance.name,
      'type': instance.type,
      'tags': instance.tags,
      'data': instance.data,
      'manualGroupKey': ?instance.manualGroupKey,
      'manualSortOrder': instance.manualSortOrder,
    };

BackupSubscription _$BackupSubscriptionFromJson(Map<String, dynamic> json) =>
    BackupSubscription(
      json['name'] as String,
      json['url'] as String,
      json['ageSecretKey'] as String?,
      json['agePublicKey'] as String?,
      json['hwidEnabled'] as bool,
      json['hwid'] as String?,
      userAgent: json['userAgent'] as String?,
      panel: json['panel'] as String? ?? 'generic',
      mode: json['mode'] as String? ?? 'appManaged',
    );

Map<String, dynamic> _$BackupSubscriptionToJson(BackupSubscription instance) =>
    <String, dynamic>{
      'name': instance.name,
      'url': instance.url,
      'userAgent': instance.userAgent,
      'ageSecretKey': instance.ageSecretKey,
      'agePublicKey': instance.agePublicKey,
      'hwidEnabled': instance.hwidEnabled,
      'hwid': instance.hwid,
      'panel': instance.panel,
      'mode': instance.mode,
    };

BackupRoutingProfile _$BackupRoutingProfileFromJson(
  Map<String, dynamic> json,
) => BackupRoutingProfile(
  json['name'] as String,
  json['advanced'] as bool,
  json['data'] as String,
);

Map<String, dynamic> _$BackupRoutingProfileToJson(
  BackupRoutingProfile instance,
) => <String, dynamic>{
  'name': instance.name,
  'advanced': instance.advanced,
  'data': instance.data,
};

BackupGeoData _$BackupGeoDataFromJson(Map<String, dynamic> json) =>
    BackupGeoData(
      json['name'] as String,
      json['type'] as String,
      json['url'] as String,
    );

Map<String, dynamic> _$BackupGeoDataToJson(BackupGeoData instance) =>
    <String, dynamic>{
      'name': instance.name,
      'type': instance.type,
      'url': instance.url,
    };

BackupSmartRouting _$BackupSmartRoutingFromJson(Map<String, dynamic> json) =>
    BackupSmartRouting(
      entryCount: (json['entryCount'] as num).toInt(),
      directRegions: (json['directRegions'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      directPrivate: json['directPrivate'] as bool,
      directApple: json['directApple'] as bool,
      directWindows: json['directWindows'] as bool,
      directDns: json['directDns'] as bool,
      directDnsAddress: json['directDnsAddress'] as String?,
      dns: json['dns'] as Map<String, dynamic>?,
      sniffing: json['sniffing'] as Map<String, dynamic>?,
      selection: json['selection'] as Map<String, dynamic>?,
      fakeDns: json['fakeDns'] as bool,
      fragment: json['fragment'] as bool? ?? false,
      blockAds: json['blockAds'] as bool,
    );

Map<String, dynamic> _$BackupSmartRoutingToJson(BackupSmartRouting instance) =>
    <String, dynamic>{
      'entryCount': instance.entryCount,
      'directRegions': instance.directRegions,
      'directPrivate': instance.directPrivate,
      'directApple': instance.directApple,
      'directWindows': instance.directWindows,
      'directDns': instance.directDns,
      'directDnsAddress': ?instance.directDnsAddress,
      'dns': ?instance.dns,
      'sniffing': ?instance.sniffing,
      'selection': ?instance.selection,
      'fakeDns': instance.fakeDns,
      'fragment': instance.fragment,
      'blockAds': instance.blockAds,
    };
