import 'dart:convert';

import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/metadata.dart';
import 'package:onexray/service/connect/routing/custom/selection_document.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/shared/xray/runtime_inbounds.dart';
import 'package:onexray/service/shared/xray/runtime_outbounds.dart';
import 'package:onexray/service/shared/xray/fragment.dart';

/// Node-free JSON template. No ordinary model round-trip or implicit DNS rules.
final class AdvancedRoutingProfile implements RoutingConfiguration {
  static const defaultText = '''{
  "outbounds": [
    {},
    {
      "tag": "dnsOut",
      "protocol": "dns",
      "settings": {
        "rules": [
          {"action": "hijack", "qType": "1,28"},
          {"action": "drop"}
        ]
      }
    }
  ],
  "inbounds": [
    {
      "tag": "tunIn",
      "sniffing": {
        "enabled": true,
        "routeOnly": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "dns": {
    "servers": [{"tag": "dns-proxy", "address": "8.8.8.8"}]
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"ruleTag": "Proxy DNS", "inboundTag": ["dns-proxy"], "balancerTag": "proxy"},
      {"ruleTag": "Tunnel DNS", "inboundTag": ["tunIn"], "port": 53, "outboundTag": "dnsOut"},
      {"ruleTag": "DNS over TLS", "inboundTag": ["tunIn"], "port": 853, "balancerTag": "proxy"}
    ]
  }
}''';
  @override
  final int? id;
  @override
  final String name;
  @override
  final int entryCount;
  final Map<String, dynamic> _json;

  AdvancedRoutingProfile._(this.id, this.name, this.entryCount, this._json);

  @override
  bool get advanced => true;
  @override
  int get ruleCount =>
      ((_json['routing'] as Map?)?['rules'] as List?)?.length ?? 0;
  @override
  Map<String, dynamic> toJson() => JsonTool.copyMap(_json);
  @override
  String encode() => JsonTool.encoder.convert(_json);
  RoutingSelectionSettings get selection => RoutingSelectionSettings.fromXray(
    routing: _json['routing'] == null
        ? null
        : XrayRouting.fromJson({
            'balancers': (_json['routing'] as Map)['balancers'],
          }),
    observatory: _json['observatory'] == null
        ? null
        : XrayObservatory.fromJson(
            _json['observatory'] as Map<String, dynamic>,
          ),
  );

  @override
  void validate() {
    selection.validate();
    if (name.trim().runes.length > 32) {
      throw const FormatException(
        'Custom route name must contain at most 32 characters',
      );
    }
  }

  @override
  AdvancedRoutingProfile copyWith({
    int? id,
    bool clearId = false,
    String? name,
  }) => AdvancedRoutingProfile._(
    clearId ? null : id ?? this.id,
    name ?? this.name,
    entryCount,
    _json,
  )..validate();

  /// The same composition is used with real nodes or local validation slots.
  Map<String, dynamic> fillSlots(
    List<Map<String, dynamic>> entries, {
    bool includeLanProxy = false,
  }) {
    final json = toJson();
    final helpers = (json['outbounds'] as List)
        .skip(entryCount)
        .cast<Map<String, dynamic>>()
        .toList();
    json['outbounds'] = [
      ...XrayFragment.connectEntries(entries, helpers),
      ...helpers,
      createFreedomOutbound(tag: 'direct').toJson(),
      createBlackholeOutbound(tag: 'block').toJson(),
    ];
    final routing =
        json['routing'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final compiled = selection.compile(
      selector: [for (final entry in entries) entry['tag'] as String],
    );
    routing['balancers'] = [compiled.balancer.toJson()];
    if (compiled.automatic) {
      routing['rules'] = [
        ...?routing['rules'] as List?,
        XrayRoutingRule(
          ruleTag: 'app-proxy-catchall',
          inboundTag: ['tunIn', if (includeLanProxy) lanProxyInboundTag],
          balancerTag: 'proxy',
        ).toJson(),
      ];
    }
    json['routing'] = routing;
    json['observatory'] = compiled.observatory.toJson();
    return json;
  }
}

final class AdvancedRoutingDocument {
  final AdvancedRoutingProfile state;
  final List<Map<String, String>> assets;
  AdvancedRoutingDocument._(this.state, this.assets);

  factory AdvancedRoutingDocument.parse(
    String text, {
    int? id,
    String? name,
    bool allowMetadata = true,
  }) => AdvancedRoutingDocument.fromJson(
    jsonDecode(text),
    id: id,
    name: name,
    allowMetadata: allowMetadata,
  );

  factory AdvancedRoutingDocument.fromJson(
    Object? value, {
    int? id,
    String? name,
    bool allowMetadata = true,
  }) {
    final json = JsonTool.copyMap(_object(value, const []));
    _keys(json, {
      'outbounds',
      'inbounds',
      'dns',
      'routing',
      'observatory',
      'fakeDns',
      'fakedns',
      if (allowMetadata) ...['name', 'geodata'],
    }, const []);
    final hasName = json.containsKey('name');
    final embeddedName = json.remove('name');
    if (hasName &&
        (embeddedName is! String ||
            embeddedName.trim().isEmpty ||
            embeddedName.trim().runes.length > 32)) {
      throw const JsonDiagnostic(
        'name must contain 1–32 characters',
        path: ['name'],
      );
    }
    final assets = json.containsKey('geodata')
        ? routingAssets(json.remove('geodata'))
        : <Map<String, String>>[];
    final outbounds = _objects(json['outbounds'], const ['outbounds']);
    final count = outbounds.takeWhile((value) => value.isEmpty).length;
    if (count < 1 ||
        count > 3 ||
        outbounds.skip(count).any((value) => value.isEmpty)) {
      throw const JsonDiagnostic(
        'outbounds must start with 1–3 empty entry slots',
        path: ['outbounds'],
      );
    }
    final tags = <String>{};
    for (final (index, outbound) in outbounds.indexed.skip(count)) {
      final path = <Object>['outbounds', index];
      _keys(outbound, {'tag', 'protocol', 'settings', 'streamSettings'}, path);
      _definition(outbound['tag'], path, tags);
      if (!const {
        'freedom',
        'blackhole',
        'dns',
      }.contains(outbound['protocol'])) {
        throw JsonDiagnostic(
          '${_pathLabel(path)} supports only freedom, blackhole and dns',
          path: [...path, 'protocol'],
        );
      }
      final stream = outbound['streamSettings'];
      if (stream != null) {
        final streamPath = [...path, 'streamSettings'];
        final map = _object(stream, streamPath);
        _keys(map, {
          'sockopt',
          if (outbound['protocol'] == 'freedom') 'finalmask',
        }, streamPath);
        if (map['sockopt'] != null) {
          final sockoptPath = [...streamPath, 'sockopt'];
          final sockopt = _object(map['sockopt'], sockoptPath);
          _keys(sockopt, {'dialerProxy'}, sockoptPath);
          _outboundReference(sockopt['dialerProxy'], [
            ...sockoptPath,
            'dialerProxy',
          ]);
        }
      }
    }
    var tunSeen = false;
    if (json.containsKey('inbounds')) {
      for (final (index, inbound) in _objects(json['inbounds'], const [
        'inbounds',
      ]).indexed) {
        final path = <Object>['inbounds', index];
        if (inbound['tag'] == 'tunIn') {
          if (tunSeen) {
            throw JsonDiagnostic(
              'Only one tunIn placeholder is allowed',
              path: [...path, 'tag'],
            );
          }
          tunSeen = true;
          _keys(inbound, {'tag', 'sniffing'}, path);
        } else {
          _keys(inbound, {
            'tag',
            'protocol',
            'listen',
            'port',
            'settings',
            'sniffing',
          }, path);
          _definition(inbound['tag'], path, tags);
          final protocol = inbound['protocol'];
          if (!const {'socks', 'http', 'tunnel'}.contains(protocol)) {
            throw JsonDiagnostic(
              '${_pathLabel(path)} supports only socks, http and tunnel',
              path: [...path, 'protocol'],
            );
          }
          if (inbound.containsKey('settings')) {
            _keys(
              _object(inbound['settings'], [...path, 'settings']),
              switch (protocol) {
                'socks' => {'auth', 'users', 'accounts', 'udp'},
                'http' => {'users', 'accounts'},
                _ => {'rewriteAddress', 'rewritePort', 'allowedNetwork'},
              },
              [...path, 'settings'],
            );
          }
        }
        if (inbound.containsKey('sniffing')) {
          _keys(
            _object(inbound['sniffing'], [...path, 'sniffing']),
            {
              'enabled',
              'routeOnly',
              'destOverride',
              'metadataOnly',
              'domainsExcluded',
              'ipsExcluded',
            },
            [...path, 'sniffing'],
          );
        }
      }
    }
    if (json.containsKey('dns')) {
      final dns = _object(json['dns'], const ['dns']);
      if (dns.containsKey('queryStrategy')) {
        _managed(const ['dns', 'queryStrategy']);
      }
      if (dns.containsKey('tag')) {
        _definition(dns['tag'], const ['dns'], <String>{});
      }
      if (dns['servers'] is List) {
        for (final (index, server) in (dns['servers'] as List).indexed) {
          if (server is! Map) continue;
          if (server.containsKey('queryStrategy')) {
            _managed(['dns', 'servers', index, 'queryStrategy']);
          }
          if (server.containsKey('tag')) {
            _definition(server['tag'], ['dns', 'servers', index], <String>{});
          }
        }
      }
    }
    checkSelectionDocument(json);
    if (json.containsKey('routing')) {
      final routing = _object(json['routing'], const ['routing']);
      _keys(
        routing,
        {'domainStrategy', 'rules', 'balancers'},
        const ['routing'],
      );
      if (routing.containsKey('rules')) {
        for (final (index, rule) in _objects(routing['rules'], const [
          'routing',
          'rules',
        ]).indexed) {
          final path = <Object>['routing', 'rules', index];
          _keys(rule, {
            'ruleTag',
            'domain',
            'ip',
            'port',
            'network',
            'protocol',
            'localOS',
            'inboundTag',
            'localIP',
            'localPort',
            'balancerTag',
            'outboundTag',
          }, path);
          if (rule.containsKey('balancerTag') &&
              rule['balancerTag'] != 'proxy') {
            throw JsonDiagnostic(
              '${_pathLabel(path)}.balancerTag must use proxy',
              path: [...path, 'balancerTag'],
            );
          }
          _outboundReference(rule['outboundTag'], [...path, 'outboundTag']);
          final inboundTags = rule['inboundTag'];
          if (inboundTags is List) {
            for (final (tagIndex, tag) in inboundTags.indexed) {
              if (tag is String && _internal(tag)) {
                _managed([
                  ...path,
                  'inboundTag',
                  tagIndex,
                ], label: '${_pathLabel(path)}.inboundTag');
              }
            }
          }
        }
      }
    }
    final state = AdvancedRoutingProfile._(
      id,
      name ?? embeddedName as String? ?? '',
      count,
      json,
    )..validate();
    return AdvancedRoutingDocument._(state, List.unmodifiable(assets));
  }
}

Map<String, dynamic> _object(
  Object? value,
  List<Object> path, {
  String? label,
}) {
  if (value is! Map<String, dynamic>) {
    throw JsonDiagnostic(
      '${label ?? _pathLabel(path)} must be an object',
      path: path,
    );
  }
  return value;
}

List<Map<String, dynamic>> _objects(Object? value, List<Object> path) {
  if (value is! List) {
    throw JsonDiagnostic('${_pathLabel(path)} must be an array', path: path);
  }
  return [
    for (final (index, item) in value.indexed)
      _object(item, [...path, index], label: _pathLabel(path)),
  ];
}

void _keys(Map<String, dynamic> value, Set<String> allowed, List<Object> path) {
  for (final key in value.keys) {
    if (!allowed.contains(key)) {
      throw JsonDiagnostic(
        'Unsupported or App-managed field: ${_pathLabel(path)}.$key',
        path: [...path, key],
      );
    }
  }
}

bool _internal(String tag) =>
    tag.startsWith('app-entry-') || tag.startsWith('app-exit-');
Never _managed(List<Object> path, {String? label}) => throw JsonDiagnostic(
  '${label ?? _pathLabel(path)} is managed by OneXray; use App settings',
  path: path,
);
void _definition(Object? tag, List<Object> path, Set<String> tags) {
  if (tag is! String || tag.isEmpty) {
    throw JsonDiagnostic(
      '${_pathLabel(path)} requires a tag',
      path: [...path, 'tag'],
    );
  }
  if (_internal(tag) ||
      const {'proxy', 'direct', 'block', 'tunIn'}.contains(tag)) {
    _managed([...path, 'tag']);
  }
  if (!tags.add(tag)) {
    throw JsonDiagnostic('Duplicate tag: $tag', path: [...path, 'tag']);
  }
}

void _outboundReference(Object? tag, List<Object> path) {
  if (tag is String && (_internal(tag) || tag == 'proxy')) {
    throw JsonDiagnostic(
      '${_pathLabel(path)} cannot reference an internal node or the proxy balancer; use balancerTag: proxy',
      path: path,
    );
  }
}

String _pathLabel(List<Object> path) => path.isEmpty
    ? 'template'
    : path
          .map((part) => part is int ? '[$part]' : '.$part')
          .join()
          .substring(1);
