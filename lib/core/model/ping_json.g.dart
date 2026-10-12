// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ping_json.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PingJson _$PingJsonFromJson(Map<String, dynamic> json) => PingJson(
  (json['timeout'] as num?)?.toDouble(),
  json['url'] as String?,
  json['customUrl'] as String?,
);

Map<String, dynamic> _$PingJsonToJson(PingJson instance) => <String, dynamic>{
  'timeout': ?instance.timeout,
  'url': ?instance.url,
  'customUrl': ?instance.customUrl,
};
