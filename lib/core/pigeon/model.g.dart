// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StartVpnRequest _$StartVpnRequestFromJson(Map<String, dynamic> json) =>
    StartVpnRequest(
      json['tun'] == null
          ? null
          : TunJson.fromJson(json['tun'] as Map<String, dynamic>),
      json['socksPort'] as String?,
      json['metricsPort'] as String?,
      json['coreInvokeText'] as String?,
      snapshotToken: json['snapshotToken'] as String?,
      metadataJson: json['metadataJson'] as String?,
    );

Map<String, dynamic> _$StartVpnRequestToJson(StartVpnRequest instance) =>
    <String, dynamic>{
      'tun': ?instance.tun?.toJson(),
      'socksPort': ?instance.socksPort,
      'metricsPort': ?instance.metricsPort,
      'coreInvokeText': ?instance.coreInvokeText,
      'snapshotToken': ?instance.snapshotToken,
      'metadataJson': ?instance.metadataJson,
    };

LibXrayInvokeResponse _$LibXrayInvokeResponseFromJson(
  Map<String, dynamic> json,
) => LibXrayInvokeResponse(
  json['success'] as bool,
  json['data'] as Map<String, dynamic>?,
  json['error'] as String,
);

Map<String, dynamic> _$LibXrayInvokeResponseToJson(
  LibXrayInvokeResponse instance,
) => <String, dynamic>{
  'success': instance.success,
  'data': ?instance.data,
  'error': instance.error,
};

GetFreePortsResponse _$GetFreePortsResponseFromJson(
  Map<String, dynamic> json,
) => GetFreePortsResponse(
  (json['ports'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList(),
);

Map<String, dynamic> _$GetFreePortsResponseToJson(
  GetFreePortsResponse instance,
) => <String, dynamic>{'ports': ?instance.ports};

ConvertXrayJsonToShareLinksResponse
_$ConvertXrayJsonToShareLinksResponseFromJson(Map<String, dynamic> json) =>
    ConvertXrayJsonToShareLinksResponse(json['links'] as String?);

Map<String, dynamic> _$ConvertXrayJsonToShareLinksResponseToJson(
  ConvertXrayJsonToShareLinksResponse instance,
) => <String, dynamic>{'links': ?instance.links};

PingBatchResponse _$PingBatchResponseFromJson(Map<String, dynamic> json) =>
    PingBatchResponse(
      (json['results'] as List<dynamic>?)
          ?.map(
            (e) => PingBatchItemResponse.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );

Map<String, dynamic> _$PingBatchResponseToJson(PingBatchResponse instance) =>
    <String, dynamic>{
      'results': ?instance.results?.map((e) => e.toJson()).toList(),
    };

PingBatchItemResponse _$PingBatchItemResponseFromJson(
  Map<String, dynamic> json,
) => PingBatchItemResponse(
  json['success'] as bool?,
  (json['delay'] as num?)?.toInt(),
  json['error'] as String?,
);

Map<String, dynamic> _$PingBatchItemResponseToJson(
  PingBatchItemResponse instance,
) => <String, dynamic>{
  'success': ?instance.success,
  'delay': ?instance.delay,
  'error': ?instance.error,
};

XrayVersionResponse _$XrayVersionResponseFromJson(Map<String, dynamic> json) =>
    XrayVersionResponse(json['version'] as String?);

Map<String, dynamic> _$XrayVersionResponseToJson(
  XrayVersionResponse instance,
) => <String, dynamic>{'version': ?instance.version};

CountGeoDataRequest _$CountGeoDataRequestFromJson(Map<String, dynamic> json) =>
    CountGeoDataRequest(
      json['name'] as String?,
      json['geoType'] as String?,
      datDir: json['datDir'] as String?,
    );

Map<String, dynamic> _$CountGeoDataRequestToJson(
  CountGeoDataRequest instance,
) => <String, dynamic>{
  'name': ?instance.name,
  'geoType': ?instance.geoType,
  'datDir': ?instance.datDir,
};

PingBatchRequest _$PingBatchRequestFromJson(Map<String, dynamic> json) =>
    PingBatchRequest(
      (json['configs'] as List<dynamic>?)
          ?.map((e) => PingBatchItemRequest.fromJson(e as Map<String, dynamic>))
          .toList(),
      (json['timeout'] as num?)?.toInt(),
      json['url'] as String?,
    );

Map<String, dynamic> _$PingBatchRequestToJson(PingBatchRequest instance) =>
    <String, dynamic>{
      'configs': ?instance.configs?.map((e) => e.toJson()).toList(),
      'timeout': ?instance.timeout,
      'url': ?instance.url,
    };

PingBatchItemRequest _$PingBatchItemRequestFromJson(
  Map<String, dynamic> json,
) => PingBatchItemRequest(
  json['xrayJson'] as String?,
  outboundTag: json['outboundTag'] as String?,
);

Map<String, dynamic> _$PingBatchItemRequestToJson(
  PingBatchItemRequest instance,
) => <String, dynamic>{
  'xrayJson': ?instance.xrayJson,
  'outboundTag': ?instance.outboundTag,
};

RunXrayRequest _$RunXrayRequestFromJson(Map<String, dynamic> json) =>
    RunXrayRequest(json['xrayJson'] as String?);

Map<String, dynamic> _$RunXrayRequestToJson(RunXrayRequest instance) =>
    <String, dynamic>{'xrayJson': ?instance.xrayJson};

TestXrayRequest _$TestXrayRequestFromJson(Map<String, dynamic> json) =>
    TestXrayRequest(json['xrayJson'] as String?);

Map<String, dynamic> _$TestXrayRequestToJson(TestXrayRequest instance) =>
    <String, dynamic>{'xrayJson': ?instance.xrayJson};

LibXrayInvokeRequest _$LibXrayInvokeRequestFromJson(
  Map<String, dynamic> json,
) => LibXrayInvokeRequest(
  method: $enumDecodeNullable(_$LibXrayMethodEnumMap, json['method']),
  payload: json['payload'] as Map<String, dynamic>?,
)..apiVersion = (json['apiVersion'] as num?)?.toInt();

Map<String, dynamic> _$LibXrayInvokeRequestToJson(
  LibXrayInvokeRequest instance,
) => <String, dynamic>{
  'apiVersion': ?instance.apiVersion,
  'method': ?_$LibXrayMethodEnumMap[instance.method],
  'payload': ?instance.payload,
};

const _$LibXrayMethodEnumMap = {
  LibXrayMethod.getFreePorts: 'getFreePorts',
  LibXrayMethod.convertShareLinksToXrayJson: 'convertShareLinksToXrayJson',
  LibXrayMethod.convertXrayJsonToShareLinks: 'convertXrayJsonToShareLinks',
  LibXrayMethod.generateAgeKeyPair: 'generateAgeKeyPair',
  LibXrayMethod.countGeoData: 'countGeoData',
  LibXrayMethod.pingBatch: 'pingBatch',
  LibXrayMethod.testXray: 'testXray',
  LibXrayMethod.runXray: 'runXray',
  LibXrayMethod.stopXray: 'stopXray',
  LibXrayMethod.xrayVersion: 'xrayVersion',
};

GetFreePortsRequest _$GetFreePortsRequestFromJson(Map<String, dynamic> json) =>
    GetFreePortsRequest(
      (json['count'] as num?)?.toInt(),
      excludePorts: (json['excludePorts'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
    );

Map<String, dynamic> _$GetFreePortsRequestToJson(
  GetFreePortsRequest instance,
) => <String, dynamic>{
  'count': ?instance.count,
  'excludePorts': ?instance.excludePorts,
};

ConvertShareLinksToXrayJsonRequest _$ConvertShareLinksToXrayJsonRequestFromJson(
  Map<String, dynamic> json,
) => ConvertShareLinksToXrayJsonRequest(
  json['text'] as String?,
  age: json['age'] == null
      ? null
      : AgeDecryptConfig.fromJson(json['age'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ConvertShareLinksToXrayJsonRequestToJson(
  ConvertShareLinksToXrayJsonRequest instance,
) => <String, dynamic>{'text': ?instance.text, 'age': ?instance.age?.toJson()};

AgeDecryptConfig _$AgeDecryptConfigFromJson(Map<String, dynamic> json) =>
    AgeDecryptConfig(json['secretKey'] as String?);

Map<String, dynamic> _$AgeDecryptConfigToJson(AgeDecryptConfig instance) =>
    <String, dynamic>{'secretKey': ?instance.secretKey};

GenerateAgeKeyPairRequest _$GenerateAgeKeyPairRequestFromJson(
  Map<String, dynamic> json,
) => GenerateAgeKeyPairRequest(
  $enumDecodeNullable(_$AgeKeyTypeEnumMap, json['keyType']),
);

Map<String, dynamic> _$GenerateAgeKeyPairRequestToJson(
  GenerateAgeKeyPairRequest instance,
) => <String, dynamic>{'keyType': ?_$AgeKeyTypeEnumMap[instance.keyType]};

const _$AgeKeyTypeEnumMap = {
  AgeKeyType.x25519: 'x25519',
  AgeKeyType.hybrid: 'hybrid',
};

GenerateAgeKeyPairResponse _$GenerateAgeKeyPairResponseFromJson(
  Map<String, dynamic> json,
) => GenerateAgeKeyPairResponse(
  json['secretKey'] as String?,
  json['publicKey'] as String?,
);

Map<String, dynamic> _$GenerateAgeKeyPairResponseToJson(
  GenerateAgeKeyPairResponse instance,
) => <String, dynamic>{
  'secretKey': ?instance.secretKey,
  'publicKey': ?instance.publicKey,
};

ConvertXrayJsonToShareLinksRequest _$ConvertXrayJsonToShareLinksRequestFromJson(
  Map<String, dynamic> json,
) => ConvertXrayJsonToShareLinksRequest(json['xrayJson'] as String?);

Map<String, dynamic> _$ConvertXrayJsonToShareLinksRequestToJson(
  ConvertXrayJsonToShareLinksRequest instance,
) => <String, dynamic>{'xrayJson': ?instance.xrayJson};
