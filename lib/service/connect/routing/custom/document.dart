import 'dart:convert';

import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/metadata.dart';
import 'package:onexray/service/connect/routing/custom/selection_document.dart';

/// External Custom-routing document after import-only metadata is separated.
final class RoutingProfileDocument {
  final RoutingProfileState state;
  final List<Map<String, String>> assets;

  RoutingProfileDocument._(this.state, this.assets);

  factory RoutingProfileDocument.parse(
    String text, {
    int? id,
    String? name,
    bool allowMetadata = true,
    bool ignoreRemovedDnsFields = false,
  }) => RoutingProfileDocument.fromJson(
    jsonDecode(text),
    id: id,
    name: name,
    allowMetadata: allowMetadata,
    ignoreRemovedDnsFields: ignoreRemovedDnsFields,
  );

  factory RoutingProfileDocument.fromJson(
    Object? value, {
    int? id,
    String? name,
    bool allowMetadata = true,
    bool ignoreRemovedDnsFields = false,
  }) {
    final document = Map<String, dynamic>.of(_object(value, const []));
    _onlyKeys(
      document,
      allowMetadata
          ? const {
              'name',
              'outbounds',
              'routing',
              'geodata',
              'dns',
              'inbounds',
              'observatory',
            }
          : const {'outbounds', 'routing', 'dns', 'inbounds', 'observatory'},
      const [],
    );
    final embeddedName = document['name'];
    if (document.containsKey('name') &&
        (embeddedName is! String ||
            embeddedName.trim().isEmpty ||
            embeddedName.trim().runes.length > 32)) {
      throw const JsonDiagnostic(
        'name must contain 1–32 characters',
        path: ['name'],
      );
    }
    final assets = document.containsKey('geodata')
        ? routingAssets(document.remove('geodata'))
        : <Map<String, String>>[];
    document.remove('name');
    if (ignoreRemovedDnsFields) _removeRetiredDnsFields(document);
    _checkEditableFields(document);
    try {
      final xrayJson = XrayJson.fromJson(document);
      return RoutingProfileDocument._(
        RoutingProfileState.fromXrayJson(
          id: id,
          name: name ?? (embeddedName as String? ?? ''),
          xrayJson: xrayJson,
        ),
        List.unmodifiable(
          assets.map((asset) => Map<String, String>.unmodifiable(asset)),
        ),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid Custom routing configuration');
    }
  }
}

// Only stored App data and backups use this compatibility boundary. External
// ordinary imports still reject fields the current form cannot represent.
void _removeRetiredDnsFields(Map<String, dynamic> document) {
  final value = document['dns'];
  if (value is! Map<String, dynamic>) return;
  final dns = Map<String, dynamic>.of(value)
    ..remove('serveStale')
    ..remove('serveExpiredTTL')
    ..remove('enableParallelQuery');
  final servers = dns['servers'];
  if (servers is List) {
    dns['servers'] = [
      for (final server in servers)
        if (server is Map<String, dynamic>)
          Map<String, dynamic>.of(server)
            ..remove('expectedIPs')
            ..remove('expectIPs')
            ..remove('unexpectedIPs')
            ..remove('serveStale')
            ..remove('serveExpiredTTL')
        else
          server,
    ];
  }
  document['dns'] = dns;
}

// Do not silently discard fields the ordinary editor cannot represent.
// Field values and rule semantics are validated by libXray when saving.
void _checkEditableFields(Map<String, dynamic> document) {
  if (document.containsKey('dns')) {
    final dns = _object(document['dns'], const ['dns']);
    _onlyKeys(
      dns,
      const {'servers', 'disableCache', 'disableFallbackIfMatch'},
      const ['dns'],
    );
    final servers = dns['servers'];
    if (servers is! List) {
      throw const JsonDiagnostic(
        'dns.servers must be an array',
        path: ['dns', 'servers'],
      );
    }
    for (var index = 0; index < servers.length; index++) {
      final path = <Object>['dns', 'servers', index];
      _onlyKeys(_object(servers[index], path), const {
        'tag',
        'address',
        'timeoutMs',
        'disableCache',
      }, path);
    }
  }
  if (document.containsKey('inbounds')) {
    final inbounds = document['inbounds'];
    if (inbounds is! List || inbounds.length != 1) {
      throw const JsonDiagnostic(
        'Only one tunIn sniffing placeholder is supported',
        path: ['inbounds'],
      );
    }
    final inbound = _object(inbounds.single, const ['inbounds', 0]);
    _onlyKeys(inbound, const {'tag', 'sniffing'}, const ['inbounds', 0]);
    if (inbound['tag'] != 'tunIn') {
      throw const JsonDiagnostic('Use tunIn', path: ['inbounds', 0, 'tag']);
    }
    _onlyKeys(
      _object(inbound['sniffing'], const ['inbounds', 0, 'sniffing']),
      const {
        'enabled',
        'routeOnly',
        'destOverride',
        'metadataOnly',
        'domainsExcluded',
        'ipsExcluded',
      },
      const ['inbounds', 0, 'sniffing'],
    );
  }
  checkSelectionDocument(document);
  final routing = document.containsKey('routing')
      ? _object(document['routing'], const ['routing'])
      : <String, dynamic>{};
  _onlyKeys(
    routing,
    const {'domainStrategy', 'rules', 'balancers'},
    const ['routing'],
  );
  final rules = routing.containsKey('rules') ? routing['rules'] : <dynamic>[];
  if (rules is! List) {
    throw const JsonDiagnostic(
      'routing.rules must be an array',
      path: ['routing', 'rules'],
    );
  }
  for (var index = 0; index < rules.length; index++) {
    final path = <Object>['routing', 'rules', index];
    _onlyKeys(_object(rules[index], path), const {
      'ruleTag',
      'domain',
      'ip',
      'port',
      'network',
      'protocol',
      'localOS',
      'balancerTag',
      'outboundTag',
    }, path);
  }
}

Map<String, dynamic> _object(Object? value, List<Object> path) {
  if (value is! Map<String, dynamic>) {
    throw JsonDiagnostic('${_pathLabel(path)} must be an object', path: path);
  }
  return value;
}

void _onlyKeys(
  Map<String, dynamic> value,
  Set<String> allowed,
  List<Object> path,
) {
  for (final key in value.keys) {
    if (!allowed.contains(key)) {
      throw JsonDiagnostic(
        'Unsupported field: ${_pathLabel(path)}.$key',
        path: [...path, key],
      );
    }
  }
}

String _pathLabel(List<Object> path) => path.isEmpty
    ? 'template'
    : path
          .map((part) => part is int ? '[$part]' : '.$part')
          .join()
          .substring(1);
