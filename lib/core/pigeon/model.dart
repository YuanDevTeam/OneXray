import 'package:json_annotation/json_annotation.dart';
import 'package:onexray/core/model/tun_json.dart';
import 'package:onexray/core/tools/json.dart';

part 'model.g.dart';

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class StartVpnRequest {
  TunJson? tun;
  String? socksPort;
  String? metricsPort;
  String? coreInvokeText;
  String? snapshotToken;
  String? metadataJson;

  StartVpnRequest(
    this.tun,
    this.socksPort,
    this.metricsPort,
    this.coreInvokeText, {
    this.snapshotToken,
    this.metadataJson,
  });

  factory StartVpnRequest.fromJson(Map<String, dynamic> json) =>
      _$StartVpnRequestFromJson(json);

  Map<String, dynamic> toJson() => _$StartVpnRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class LibXrayInvokeResponse {
  final bool success;
  final Map<String, dynamic>? data;
  final String error;

  LibXrayInvokeResponse(this.success, this.data, this.error);

  factory LibXrayInvokeResponse.fromJson(Map<String, dynamic> json) =>
      _$LibXrayInvokeResponseFromJson(json);

  Map<String, dynamic> toJson() => _$LibXrayInvokeResponseToJson(this);
}

final class LibXrayInvokeException implements Exception {
  const LibXrayInvokeException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class LibXrayErrorMessage {
  static const invalidAgeSecretKey = 'invalid or unsupported age secret key';
  static const missingAgeSecretKey = 'missing age secret key';
  static const ageDecryptFailed = 'unable to decrypt age subscription';
  static const malformedAgeArmor = 'malformed age armor';
  static const agePlaintextTooLarge =
      'decrypted subscription exceeds the 16 MiB size limit';
  static const agePlaintextUnsupported =
      'decrypted subscription is unsupported';
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class GetFreePortsResponse {
  List<int>? ports;

  GetFreePortsResponse(this.ports);

  factory GetFreePortsResponse.fromJson(Map<String, dynamic> json) =>
      _$GetFreePortsResponseFromJson(json);

  Map<String, dynamic> toJson() => _$GetFreePortsResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ConvertXrayJsonToShareLinksResponse {
  String? links;

  ConvertXrayJsonToShareLinksResponse(this.links);

  factory ConvertXrayJsonToShareLinksResponse.fromJson(
    Map<String, dynamic> json,
  ) => _$ConvertXrayJsonToShareLinksResponseFromJson(json);

  Map<String, dynamic> toJson() =>
      _$ConvertXrayJsonToShareLinksResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PingBatchResponse {
  List<PingBatchItemResponse>? results;

  PingBatchResponse(this.results);

  factory PingBatchResponse.fromJson(Map<String, dynamic> json) =>
      _$PingBatchResponseFromJson(json);

  Map<String, dynamic> toJson() => _$PingBatchResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PingBatchItemResponse {
  bool? success;
  int? delay;
  String? error;

  PingBatchItemResponse(this.success, this.delay, this.error);

  factory PingBatchItemResponse.fromJson(Map<String, dynamic> json) =>
      _$PingBatchItemResponseFromJson(json);

  Map<String, dynamic> toJson() => _$PingBatchItemResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class XrayVersionResponse {
  String? version;

  XrayVersionResponse(this.version);

  factory XrayVersionResponse.fromJson(Map<String, dynamic> json) =>
      _$XrayVersionResponseFromJson(json);

  Map<String, dynamic> toJson() => _$XrayVersionResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class CountGeoDataRequest {
  String? name;
  String? geoType;
  String? datDir;

  CountGeoDataRequest(this.name, this.geoType, {this.datDir});

  factory CountGeoDataRequest.fromJson(Map<String, dynamic> json) =>
      _$CountGeoDataRequestFromJson(json);

  Map<String, dynamic> toJson() => _$CountGeoDataRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PingBatchRequest {
  List<PingBatchItemRequest>? configs;
  int? timeout;
  String? url;

  PingBatchRequest(this.configs, this.timeout, this.url);

  factory PingBatchRequest.fromJson(Map<String, dynamic> json) =>
      _$PingBatchRequestFromJson(json);

  Map<String, dynamic> toJson() => _$PingBatchRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PingBatchItemRequest {
  String? xrayJson;
  String? outboundTag;

  PingBatchItemRequest(this.xrayJson, {this.outboundTag});

  factory PingBatchItemRequest.fromJson(Map<String, dynamic> json) =>
      _$PingBatchItemRequestFromJson(json);

  Map<String, dynamic> toJson() => _$PingBatchItemRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class RunXrayRequest {
  String? xrayJson;

  RunXrayRequest(this.xrayJson);

  factory RunXrayRequest.fromJson(Map<String, dynamic> json) =>
      _$RunXrayRequestFromJson(json);

  Map<String, dynamic> toJson() => _$RunXrayRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class TestXrayRequest {
  String? xrayJson;

  TestXrayRequest(this.xrayJson);

  factory TestXrayRequest.fromJson(Map<String, dynamic> json) =>
      _$TestXrayRequestFromJson(json);

  Map<String, dynamic> toJson() => _$TestXrayRequestToJson(this);
}

enum LibXrayMethod {
  @JsonValue("getFreePorts")
  getFreePorts,
  @JsonValue("convertShareLinksToXrayJson")
  convertShareLinksToXrayJson,
  @JsonValue("decodeSubscriptionText")
  decodeSubscriptionText,
  @JsonValue("convertXrayJsonToShareLinks")
  convertXrayJsonToShareLinks,
  @JsonValue("generateAgeKeyPair")
  generateAgeKeyPair,
  @JsonValue("countGeoData")
  countGeoData,
  @JsonValue("pingBatch")
  pingBatch,
  @JsonValue("testXray")
  testXray,
  @JsonValue("runXray")
  runXray,
  @JsonValue("stopXray")
  stopXray,
  @JsonValue("xrayVersion")
  xrayVersion,
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class LibXrayInvokeRequest {
  int? apiVersion;
  LibXrayMethod? method;
  Map<String, dynamic>? payload;

  LibXrayInvokeRequest({this.method, this.payload}) : apiVersion = 3;

  factory LibXrayInvokeRequest.fromJson(Map<String, dynamic> json) =>
      _$LibXrayInvokeRequestFromJson(json);

  Map<String, dynamic> toJson() => _$LibXrayInvokeRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class GetFreePortsRequest {
  int? count;
  List<int>? excludePorts;

  GetFreePortsRequest(this.count, {this.excludePorts});

  factory GetFreePortsRequest.fromJson(Map<String, dynamic> json) =>
      _$GetFreePortsRequestFromJson(json);

  Map<String, dynamic> toJson() => _$GetFreePortsRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ConvertShareLinksToXrayJsonRequest {
  String? text;
  AgeDecryptConfig? age;

  ConvertShareLinksToXrayJsonRequest(this.text, {this.age});

  factory ConvertShareLinksToXrayJsonRequest.fromJson(
    Map<String, dynamic> json,
  ) => _$ConvertShareLinksToXrayJsonRequestFromJson(json);

  Map<String, dynamic> toJson() =>
      _$ConvertShareLinksToXrayJsonRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class DecodeSubscriptionTextRequest {
  final String text;
  final AgeDecryptConfig? age;

  const DecodeSubscriptionTextRequest(this.text, {this.age});

  factory DecodeSubscriptionTextRequest.fromJson(Map<String, dynamic> json) =>
      _$DecodeSubscriptionTextRequestFromJson(json);

  Map<String, dynamic> toJson() => _$DecodeSubscriptionTextRequestToJson(this);
}

@JsonSerializable()
class DecodeSubscriptionTextResponse {
  final String text;

  const DecodeSubscriptionTextResponse(this.text);

  factory DecodeSubscriptionTextResponse.fromJson(Map<String, dynamic> json) =>
      _$DecodeSubscriptionTextResponseFromJson(json);

  Map<String, dynamic> toJson() => _$DecodeSubscriptionTextResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class AgeDecryptConfig {
  String? secretKey;

  AgeDecryptConfig(this.secretKey);

  factory AgeDecryptConfig.fromJson(Map<String, dynamic> json) =>
      _$AgeDecryptConfigFromJson(json);

  Map<String, dynamic> toJson() => _$AgeDecryptConfigToJson(this);
}

enum AgeKeyType {
  @JsonValue("x25519")
  x25519,
  @JsonValue("hybrid")
  hybrid,
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class GenerateAgeKeyPairRequest {
  AgeKeyType? keyType;

  GenerateAgeKeyPairRequest(this.keyType);

  factory GenerateAgeKeyPairRequest.fromJson(Map<String, dynamic> json) =>
      _$GenerateAgeKeyPairRequestFromJson(json);

  Map<String, dynamic> toJson() => _$GenerateAgeKeyPairRequestToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class GenerateAgeKeyPairResponse {
  String? secretKey;
  String? publicKey;

  GenerateAgeKeyPairResponse(this.secretKey, this.publicKey);

  factory GenerateAgeKeyPairResponse.fromJson(Map<String, dynamic> json) =>
      _$GenerateAgeKeyPairResponseFromJson(json);

  Map<String, dynamic> toJson() => _$GenerateAgeKeyPairResponseToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ConvertXrayJsonToShareLinksRequest {
  String? xrayJson;

  ConvertXrayJsonToShareLinksRequest(this.xrayJson);

  factory ConvertXrayJsonToShareLinksRequest.fromJson(
    Map<String, dynamic> json,
  ) => _$ConvertXrayJsonToShareLinksRequestFromJson(json);

  Map<String, dynamic> toJson() =>
      _$ConvertXrayJsonToShareLinksRequestToJson(this);
}

class LibXrayRunConfig {
  final LibXrayInvokeRequest invoke;
  final RunXrayRequest request;

  LibXrayRunConfig(this.invoke)
    : request = RunXrayRequest.fromJson(invoke.payload ?? const {});

  factory LibXrayRunConfig.fromInvokeText(String text) {
    final data = JsonTool.decoder.convert(text) as Map<String, dynamic>;
    final invoke = LibXrayInvokeRequest.fromJson(data);
    return LibXrayRunConfig(invoke);
  }
}
