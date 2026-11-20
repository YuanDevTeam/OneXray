import 'dart:convert';

import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:path/path.dart' as p;

final class ProviderGeoDataUrls {
  const ProviderGeoDataUrls({this.geoIpUrl, this.geoSiteUrl});

  final String? geoIpUrl;
  final String? geoSiteUrl;

  /// Happ puts standard Base64 after the prefix. A slash can be part of
  /// the payload, so the rest of the header is decoded as a single string.
  static ProviderGeoDataUrls? fromRoutingHeader(List<String>? values) {
    const prefixes = ['happ://routing/onadd', 'happ://routing/add'];
    String? payload;
    for (final value in values ?? const <String>[]) {
      final header = value.trim();
      for (final prefix in prefixes) {
        if (header != prefix && !header.startsWith('$prefix/')) continue;
        if (payload != null) {
          throw const FormatException('Multiple Happ routing headers');
        }
        payload = header == prefix ? '' : header.substring(prefix.length + 1);
        break;
      }
    }
    if (payload == null) return null;

    final Object? profile;
    try {
      if (!RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(payload)) {
        throw const FormatException();
      }
      profile = jsonDecode(utf8.decode(base64Decode(payload)));
    } on FormatException {
      throw const FormatException('Invalid Happ routing header');
    }
    if (profile is! Map<String, dynamic>) {
      throw const FormatException('Invalid Happ routing profile');
    }
    final geoIpUrl = _readHttpsUrl(profile['Geoipurl'], 'Geoipurl');
    final geoSiteUrl = _readHttpsUrl(profile['Geositeurl'], 'Geositeurl');
    if (geoIpUrl == null && geoSiteUrl == null) return null;
    return ProviderGeoDataUrls(geoIpUrl: geoIpUrl, geoSiteUrl: geoSiteUrl);
  }
}

String? _readHttpsUrl(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$field must be an HTTPS GeoData URL');
  }
  final url = value.trim();
  if (url.isEmpty) return null;
  try {
    GeoDataInput.httpsUri(url);
  } on FormatException {
    throw FormatException('$field must be an HTTPS GeoData URL');
  }
  return url;
}

const _providerGeoDataFilePattern =
    r'onexray-provider-(geoip|geosite)-[0-9a-f]{64}\.dat';
final _providerGeoDataFile = RegExp('^$_providerGeoDataFilePattern\$');
final _providerGeoDataMention = RegExp(
  _providerGeoDataFilePattern,
  caseSensitive: false,
);

bool isProviderGeoDataFileName(String fileName) =>
    _providerGeoDataFile.hasMatch(fileName);

/// The assets validated with an individual provider profile. The original
/// provider JSON stays intact, including its canonical GeoData references.
final class ProviderGeoDataBinding {
  const ProviderGeoDataBinding({
    this.geoIpFile,
    this.geoSiteFile,
    this.geoIpUrl,
    this.geoSiteUrl,
  });

  final String? geoIpFile;
  final String? geoSiteFile;
  final String? geoIpUrl;
  final String? geoSiteUrl;

  Iterable<String> get files => [?geoIpFile, ?geoSiteFile];

  String encode() {
    _checkFile(geoIpFile, 'geoip');
    _checkFile(geoSiteFile, 'geosite');
    return jsonEncode({
      'geoIpFile': ?geoIpFile,
      'geoSiteFile': ?geoSiteFile,
      'geoIpUrl': ?geoIpUrl,
      'geoSiteUrl': ?geoSiteUrl,
    });
  }

  static ProviderGeoDataBinding? decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    final value = jsonDecode(encoded);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid Provider GeoData binding');
    }
    final geoIpFile = _checkFile(value['geoIpFile'], 'geoip');
    final geoSiteFile = _checkFile(value['geoSiteFile'], 'geosite');
    if (geoIpFile == null && geoSiteFile == null) return null;
    return ProviderGeoDataBinding(
      geoIpFile: geoIpFile,
      geoSiteFile: geoSiteFile,
      geoIpUrl: _readHttpsUrl(value['geoIpUrl'], 'geoIpUrl'),
      geoSiteUrl: _readHttpsUrl(value['geoSiteUrl'], 'geoSiteUrl'),
    );
  }

  static String? _checkFile(Object? value, String kind) {
    if (value == null) return null;
    if (value is! String ||
        !isProviderGeoDataFileName(value) ||
        !value.startsWith('onexray-provider-$kind-')) {
      throw const FormatException('Invalid Provider GeoData filename');
    }
    return value;
  }

  /// Runtime output normally mentions only aliases already checked by [apply].
  /// Inspect the selector fields if other aliases appear, ignoring literal text.
  void requireInScope(Map<String, dynamic> source, String encoded) {
    final owned = files.toSet();
    if (_providerGeoDataMention
        .allMatches(encoded)
        .any((match) => !owned.contains(match[0]))) {
      apply(source);
    }
  }

  Map<String, dynamic> apply(Map<String, dynamic> source) {
    _checkFile(geoIpFile, 'geoip');
    _checkFile(geoSiteFile, 'geosite');
    final result = JsonTool.copyMap(source);
    final routing = _object(_field(result, 'routing'));
    final dns = _object(_field(result, 'dns'));
    if (files.isNotEmpty &&
        [
          _field(routing, 'script'),
          _field(dns, 'script'),
        ].any((value) => value is String && value.isNotEmpty)) {
      throw const FormatException(
        'Provider GeoData is unavailable with Xray routing or DNS scripts',
      );
    }
    for (final rule in _objects(_field(routing, 'rules'))) {
      _rewriteFields(
        rule,
        {'domain', 'domains'},
        {'ip', 'sourceip', 'source', 'localip'},
      );
    }
    for (final server in _objects(_field(dns, 'servers'))) {
      _rewriteFields(
        server,
        {'domains'},
        {'expectedips', 'expectips', 'unexpectedips'},
      );
    }
    if (dns != null) _rewriteDnsHosts(dns);
    for (final inbound in _objects(_field(result, 'inbounds'))) {
      _rewriteSniffing(_field(inbound, 'sniffing'));
      _rewriteStream(_field(inbound, 'streamsettings'));
    }
    for (final outbound in _objects(_field(result, 'outbounds'))) {
      final settings = _object(_field(outbound, 'settings'));
      switch (_field(outbound, 'protocol')) {
        case 'dns':
          for (final rule in _objects(_field(settings, 'rules'))) {
            _rewriteFields(rule, {'domain'}, {});
          }
        case 'freedom':
        case 'direct':
          for (final rule in _objects(_field(settings, 'finalrules'))) {
            _rewriteFields(rule, {}, {'ip'});
          }
        case 'loopback':
          _rewriteSniffing(_field(settings, 'sniffing'));
        case 'vless':
          final reverse = _object(_field(settings, 'reverse'));
          _rewriteSniffing(_field(reverse, 'sniffing'));
      }
      _rewriteStream(_field(outbound, 'streamsettings'));
    }
    return result;
  }

  // Xray's JSON decoder matches field names case-insensitively. Retain the
  // original keys and the precedence of aliases while updating their values.
  static Object? _field(Map<String, dynamic>? map, String name) {
    if (map == null) return null;
    for (final key in map.keys.toList().reversed) {
      if (key.toLowerCase() == name) return map[key];
    }
    return null;
  }

  static Map<String, dynamic>? _object(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static Iterable<Map<String, dynamic>> _objects(Object? value) =>
      value is List ? value.whereType<Map<String, dynamic>>() : const [];

  void _rewriteFields(
    Map<String, dynamic> map,
    Set<String> domains,
    Set<String> ips, {
    bool allowScalar = true,
  }) {
    for (final name in map.keys) {
      final normalized = name.toLowerCase();
      final isIp = ips.contains(normalized);
      if (!isIp && !domains.contains(normalized)) continue;
      final value = map[name];
      if (value is String && allowScalar) {
        map[name] = value
            .split(',')
            .map((part) => _rewriteReference(part, isIp: isIp))
            .join(',');
      } else if (value is List) {
        map[name] = [
          for (final item in value)
            if (item is String) _rewriteReference(item, isIp: isIp) else item,
        ];
      }
    }
  }

  void _rewriteDnsHosts(Map<String, dynamic> dns) {
    for (final field in dns.keys) {
      if (field.toLowerCase() != 'hosts') continue;
      final hosts = _object(dns[field]);
      if (hosts == null) continue;
      final rewritten = <String, dynamic>{};
      for (final entry in hosts.entries) {
        final key = _rewriteReference(entry.key, isIp: false);
        if (rewritten.containsKey(key)) {
          throw const FormatException(
            'Provider GeoData produces duplicate DNS hosts keys',
          );
        }
        rewritten[key] = entry.value;
      }
      dns[field] = rewritten;
    }
  }

  void _rewriteSniffing(Object? value) {
    final sniffing = _object(value);
    if (sniffing != null) {
      _rewriteFields(sniffing, {'domainsexcluded'}, {'ipsexcluded'});
    }
  }

  void _rewriteStream(Object? value) {
    final stream = _object(value);
    if (stream == null) return;
    final finalMask = _object(_field(stream, 'finalmask'));
    for (final transport in ['tcp', 'udp']) {
      for (final mask in _objects(_field(finalMask, transport))) {
        if (_field(mask, 'type') != 'filter') continue;
        final settings = _object(_field(mask, 'settings'));
        if (settings != null) {
          _rewriteFields(settings, {}, {
            'blockedsourceips',
            'allowedsourceips',
          }, allowScalar: false);
        }
      }
    }
    for (final transport in ['xhttpsettings', 'splithttpsettings']) {
      final xhttp = _object(_field(stream, transport));
      _rewriteStream(_field(xhttp, 'downloadsettings'));
      _rewriteStream(
        _field(_object(_field(xhttp, 'extra')), 'downloadsettings'),
      );
    }
  }

  static final _ipReference = RegExp(r'^(!*)(geoip:|ext:|ext-ip:)');
  static final _siteReference = RegExp(
    r'^(geosite:|ext:|ext-site:|ext-domain:)',
  );
  static final _externalPathSeparator = RegExp(r'[/\\]');

  String _rewriteReference(String value, {required bool isIp}) {
    final match = (isIp ? _ipReference : _siteReference).firstMatch(value);
    if (match == null) return value;
    final kind = isIp ? 'geoip' : 'geosite';
    final file = isIp ? geoIpFile : geoSiteFile;
    final negation = isIp ? match.group(1)! : '';
    final prefix = match.group(isIp ? 2 : 1)!;
    final suffix = value.substring(match.end);
    if (prefix == '$kind:') {
      return file == null ? value : '${negation}ext:$file:$suffix';
    }

    final delimiter = suffix.indexOf(':');
    if (delimiter < 0) return value;
    final external = suffix.substring(0, delimiter);
    final normalized = p.normalize(external);
    if (isProviderGeoDataFileName(
          normalized.split(_externalPathSeparator).last.toLowerCase(),
        ) &&
        external != file) {
      throw const FormatException('Provider GeoData reference is out of scope');
    }
    if (file == null || normalized != '$kind.dat') return value;
    final category = suffix.substring(delimiter + 1);
    return '${negation}ext:$file:$category';
  }
}
