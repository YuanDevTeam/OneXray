import 'dart:convert';

import 'package:onexray/core/tools/json_tokens.dart';

enum JsonEditorKind { outbound, customRouting, advancedRouting, raw }

class JsonCompletion {
  final String label;
  final String insertText;
  final int start;
  final int end;

  const JsonCompletion({
    required this.label,
    required this.insertText,
    required this.start,
    required this.end,
  });
}

/// Small, advisory dictionaries. Unknown fields remain ordinary editable JSON;
/// only libXray decides whether protocol fields and values are valid.
class JsonEditing {
  static List<JsonCompletion> complete(
    String text,
    int offset,
    JsonEditorKind kind, {
    List<String> domainSuggestions = const [],
    List<String> ipSuggestions = const [],
  }) {
    if (offset < 0 || offset > text.length) return const [];
    final tokens = scanJsonTokens(text);
    JsonToken? target;
    for (final token in tokens) {
      if (token.kind == JsonTokenKind.string &&
          token.contentEnd == offset &&
          token.start < offset) {
        target = token;
        break;
      }
    }
    if (target == null || target.value == null) return const [];
    if (!target.closed && target.end < text.length) return const [];
    final shape = _Shape(tokens);
    final location = shape.locations[target];
    if (location == null) return const [];
    final prefix = target.value!;
    final candidates = location.isKey
        ? _fields(location.path, kind, shape)
        : _values(location.path, kind, shape, domainSuggestions, ipSuggestions);
    final existing = location.isKey
        ? shape.keys[_pathKey(location.path)] ?? const <String>{}
        : const <String>{};
    final geodata =
        !location.isKey && _geodataType(location.path, shape, kind) != null;
    final search = geodata ? prefix.trim().toLowerCase() : prefix.toLowerCase();
    final filtered = candidates
        .toSet()
        .where(
          (candidate) =>
              candidate != prefix &&
              (geodata
                  ? candidate.toLowerCase().contains(search)
                  : candidate.toLowerCase().startsWith(search)) &&
              !existing.contains(candidate),
        )
        .toList();
    if (geodata) {
      int rank(String value) {
        final lower = value.toLowerCase();
        final code = lower.split(':').last;
        if (lower == search || code == search) return 0;
        return code.startsWith(search) ? 1 : 2;
      }

      filtered.sort((a, b) {
        final order = rank(a).compareTo(rank(b));
        return order == 0 ? a.compareTo(b) : order;
      });
    }
    return [
      for (final candidate in filtered.take(10))
        JsonCompletion(
          label: candidate,
          insertText: _stringContent(candidate),
          start: target.start + 1,
          end: offset,
        ),
    ];
  }

  static List<String> _fields(
    List<Object> path,
    JsonEditorKind kind,
    _Shape shape,
  ) {
    final custom = kind == JsonEditorKind.customRouting;
    final advanced = kind == JsonEditorKind.advancedRouting;
    if (path.isEmpty) {
      if (kind == JsonEditorKind.outbound) {
        final rootKeys = shape.keys[_pathKey(const [])] ?? const <String>{};
        if (rootKeys.any(
          (key) => key.isNotEmpty && 'outbounds'.startsWith(key),
        )) {
          return const ['outbounds'];
        }
        return _outboundFields;
      }
      if (custom) {
        return const [
          'name',
          'outbounds',
          'inbounds',
          'routing',
          'dns',
          'observatory',
          'geodata',
        ];
      }
      if (advanced) {
        return const [
          'name',
          'outbounds',
          'inbounds',
          'dns',
          'routing',
          'fakeDns',
          'observatory',
          'geodata',
        ];
      }
      return const [
        'outbounds',
        'inbounds',
        'routing',
        'dns',
        'log',
        'policy',
        'api',
        'stats',
        'metrics',
        'fakeDns',
        'observatory',
        'burstObservatory',
        'transport',
      ];
    }
    if (custom && path.firstOrNull == 'outbounds') return const [];
    if (custom &&
        path.firstOrNull == 'inbounds' &&
        !_matches(path, ['inbounds', '*']) &&
        !_matches(path, ['inbounds', '*', 'sniffing'])) {
      return const [];
    }
    if (advanced &&
        path.contains('streamSettings') &&
        !_matches(path, ['outbounds', '*', 'streamSettings']) &&
        !_matches(path, ['outbounds', '*', 'streamSettings', 'sockopt']) &&
        !_advancedFreedomMaskPath(path, shape)) {
      return const [];
    }
    if (_matches(path, ['outbounds', '*'])) {
      if (custom) return const [];
      if (advanced) {
        return const ['tag', 'protocol', 'settings', 'streamSettings'];
      }
      return _outboundFields;
    }
    if (_matches(path, ['inbounds', '*'])) {
      if (custom) return const ['tag', 'sniffing'];
      if (advanced && shape.value([...path, 'tag']) == 'tunIn') {
        return const ['tag', 'sniffing'];
      }
      return [
        'tag',
        'protocol',
        'listen',
        'port',
        'settings',
        'sniffing',
        if (!advanced) ...['streamSettings', 'allocate'],
      ];
    }
    if (_matches(path, ['routing'])) {
      return [
        'domainStrategy',
        'rules',
        'balancers',
        if (!custom && !advanced) 'domainMatcher',
      ];
    }
    if (_matches(path, ['routing', 'rules', '*'])) {
      return [
        'ruleTag',
        'domain',
        'ip',
        'port',
        'network',
        'protocol',
        'localOS',
        'balancerTag',
        'outboundTag',
        if (!custom) ...['inboundTag', 'localIP', 'localPort'],
        if (!custom && !advanced) ...[
          'type',
          'sourceIP',
          'sourcePort',
          'user',
          'domainMatcher',
          'attrs',
        ],
      ];
    }
    if (_matches(path, ['routing', 'balancers', '*'])) {
      if (custom || advanced) {
        return _managedProxyBalancer(path, shape)
            ? const ['tag', 'strategy']
            : const ['tag'];
      }
      if (kind == JsonEditorKind.raw) {
        return const ['tag', 'selector', 'strategy', 'fallbackTag'];
      }
    }
    if (_matches(path, ['routing', 'balancers', '*', 'strategy'])) {
      if (custom || advanced) {
        return _managedProxyBalancer(path.sublist(0, 3), shape)
            ? const ['type']
            : const [];
      }
      if (kind == JsonEditorKind.raw) return const ['type', 'settings'];
    }
    if (_matches(path, ['observatory'])) {
      return [
        'probeURL',
        'probeInterval',
        'enableConcurrency',
        if (!custom && !advanced) 'subjectSelector',
      ];
    }
    if (_matches(path, ['dns'])) {
      return [
        'servers',
        'disableCache',
        'serveStale',
        'serveExpiredTTL',
        'enableParallelQuery',
        'disableFallbackIfMatch',
        if (!custom) ...['hosts', 'tag', 'disableFallback', 'clientIp'],
        if (!custom && !advanced) ...['queryStrategy', 'useSystemHosts'],
      ];
    }
    if (_matches(path, ['dns', 'servers', '*'])) {
      return [
        'address',
        'tag',
        'timeoutMs',
        'expectedIPs',
        'unexpectedIPs',
        'disableCache',
        'serveStale',
        'serveExpiredTTL',
        if (!custom) ...[
          'port',
          'domains',
          'skipFallback',
          'clientIp',
          'finalQuery',
        ],
        if (!custom && !advanced) 'queryStrategy',
      ];
    }
    if (_matches(path, ['fakeDns']) ||
        _matches(path, ['fakeDns', '*']) ||
        _matches(path, ['fakedns']) ||
        _matches(path, ['fakedns', '*'])) {
      return const ['ipPool', 'poolSize'];
    }
    if (_matches(path, ['geodata']) && (custom || advanced)) {
      return const ['assets'];
    }
    if (_matches(path, ['geodata', 'assets', '*']) && (custom || advanced)) {
      return const ['file', 'url'];
    }

    final tail = path.last;
    if (_streamSettingsPath(path, kind)) {
      return advanced
          ? [
              'sockopt',
              if (shape.value([
                    ...path.sublist(0, path.length - 1),
                    'protocol',
                  ]) ==
                  'freedom')
                'finalmask',
            ]
          : const [
              'network',
              'security',
              'tlsSettings',
              'realitySettings',
              'wsSettings',
              'grpcSettings',
              'xhttpSettings',
              'httpupgradeSettings',
              'hysteriaSettings',
              'masqueSettings',
              'xdriveSettings',
              'finalmask',
              'sockopt',
            ];
    }
    if (!custom && !advanced) {
      if (tail == 'masqueSettings' &&
          _streamSettingsPath(path.sublist(0, path.length - 1), kind)) {
        return const [
          'host',
          'path',
          'user',
          'pass',
          'headers',
          'warp',
          'xmux',
        ];
      }
      if (_endsWith(path, ['masqueSettings', 'warp']) &&
          _streamSettingsPath(path.sublist(0, path.length - 2), kind)) {
        return const ['privateKey', 'publicKey', 'address'];
      }
      if (tail == 'hysteriaSettings' &&
          _streamSettingsPath(path.sublist(0, path.length - 1), kind)) {
        return const ['version', 'auth', 'udpIdleTimeout', 'masquerade'];
      }
      if (_endsWith(path, ['hysteriaSettings', 'masquerade']) &&
          _streamSettingsPath(path.sublist(0, path.length - 2), kind)) {
        return const [
          'type',
          'dir',
          'url',
          'rewriteHost',
          'xForwarded',
          'insecure',
          'content',
          'headers',
          'statusCode',
        ];
      }
      if (_streamSettingsChildPath(path, kind, 'xdriveSettings')) {
        return const [
          'remoteFolder',
          'service',
          'secrets',
          'segmentBytes',
          'flushIntervalMs',
          'pollIntervalMs',
          'maxPollIntervalMs',
          'sessionTtlSeconds',
          'concurrency',
          'eagerWindowMs',
          'holeTimeoutMs',
          'template',
          's3',
          'xmux',
        ];
      }
      if (tail == 's3' &&
          _streamSettingsChildPath(
            path.sublist(0, path.length - 1),
            kind,
            'xdriveSettings',
          )) {
        return const ['endpoint', 'region', 'bucket', 'pathStyle'];
      }
      if (_xdriveTemplatePath(path, kind)) {
        return const [
          'flatten',
          'concurrency',
          'auth',
          'put',
          'get',
          'delete',
          'list',
          'retry',
        ];
      }
      if (_xdriveTemplatePath(path.sublist(0, path.length - 1), kind)) {
        if (tail == 'auth') {
          return const [
            'type',
            'header',
            'username',
            'password',
            'tokenUrl',
            'form',
            'tokenPath',
            'expiryPath',
          ];
        }
        if (tail == 'retry') return const ['status', 'rateReason'];
      }
      if (_xdriveTemplateOperationPath(path, kind)) {
        return const [
          'method',
          'url',
          'headers',
          'body',
          'namesRegex',
          'hrefPath',
          'hrefMethod',
        ];
      }
      if (tail == 'xmux' &&
          (_streamSettingsChildPath(
                path.sublist(0, path.length - 1),
                kind,
                'masqueSettings',
              ) ||
              _streamSettingsChildPath(
                path.sublist(0, path.length - 1),
                kind,
                'xdriveSettings',
              ))) {
        return _xmuxFields;
      }
    }
    if (!custom && (!advanced || _advancedFreedomMaskPath(path, shape))) {
      if (_streamSettingsChildPath(path, kind, 'finalmask')) {
        return const ['tcp', 'udp', 'quicParams'];
      }
      if (_maskElementPath(path, kind, 'udp') ||
          _maskElementPath(path, kind, 'tcp')) {
        return const ['type', 'settings'];
      }
      if (_maskType(path, shape, kind, 'tcp') == 'fragment') {
        return const [
          'packets',
          'length',
          'delay',
          'lengths',
          'delays',
          'maxSplit',
        ];
      }
      final maskType = _udpMaskType(path, shape, kind);
      if (maskType != null) {
        return switch (maskType) {
          'xdns' => const ['domains', 'resolvers', 'extraPoll'],
          'noise' => const ['reset', 'noise'],
          'udphop' => const ['mode', 'interval', 'remoteIPs', 'remotePorts'],
          _ => const [],
        };
      }
      if (_endsWith(path, ['domains', '*']) &&
          _udpMaskType(path.sublist(0, path.length - 2), shape, kind) ==
              'xdns') {
        return const ['names', 'lenLimit', 'labelLimit', 'types', 'edns0'];
      }
      if (_xdnsResolverPath(path, kind, shape)) {
        return const ['addrs', 'worker', 'tlsConfig', 'quicConfig'];
      }
      if (_quicSettingsPath(path, kind, shape)) {
        return _quicFields;
      }
      if (_endsWith(path, ['noise', '*']) &&
          _udpMaskType(path.sublist(0, path.length - 2), shape, kind) ==
              'noise') {
        return const ['rand', 'randRange', 'type', 'packet', 'delay'];
      }
      if (tail == 'sockopt' &&
          _udpMaskType(path.sublist(0, path.length - 1), shape, kind) ==
              'udphop') {
        return const [];
      }
      if (advanced) return const [];
    }
    if (tail == 'happyEyeballs' &&
        !custom &&
        !advanced &&
        _socketSettingsPath(path.sublist(0, path.length - 1), kind, shape)) {
      return const [
        'prioritizeIPv6',
        'tryDelayMs',
        'interleave',
        'maxConcurrentTry',
      ];
    }
    if (_socketSettingsPath(path, kind, shape)) {
      return advanced
          ? const ['dialerProxy']
          : const [
              'dialerProxy',
              'mark',
              'tcpFastOpen',
              'tcpKeepAliveIdle',
              'tcpKeepAliveInterval',
              'tcpNoDelay',
              'domainStrategy',
              'happyEyeballs',
              'interface',
            ];
    }
    if (!custom && !advanced && _tlsSettingsPath(path, kind, shape)) {
      return const [
        'serverName',
        'alpn',
        'fingerprint',
        'certificates',
        'useSystemCA',
        'pinnedPeerCertSha256',
        'verifyPeerCertByName',
        'echConfigList',
        'echSockopt',
      ];
    }
    if (_streamSettingsChildPath(path, kind, 'realitySettings')) {
      return const [
        'serverName',
        'fingerprint',
        'password',
        'publicKey',
        'shortId',
        'spiderX',
        'mldsa65Verify',
      ];
    }
    if (tail == 'wsSettings' || tail == 'httpupgradeSettings') {
      return const ['path', 'host', 'headers'];
    }
    if (tail == 'grpcSettings') {
      return const ['serviceName', 'multiMode', 'authority'];
    }
    if (tail == 'xhttpSettings') return const ['path', 'host', 'mode', 'extra'];
    if (_matches(path, ['inbounds', '*', 'sniffing'])) {
      return const [
        'enabled',
        'routeOnly',
        'destOverride',
        'metadataOnly',
        'domainsExcluded',
        'ipsExcluded',
      ];
    }
    if (tail == 'mux') {
      return const [
        'enabled',
        'concurrency',
        'xudpConcurrency',
        'xudpProxyUDP443',
      ];
    }
    if (tail == 'proxySettings') return const ['tag', 'transportLayer'];
    if (tail == 'settings') {
      final parent = path.sublist(0, path.length - 1);
      final protocol = shape.value([...parent, 'protocol']);
      if (_matches(parent, ['inbounds', '*'])) {
        return switch (protocol) {
          'tun' when kind == JsonEditorKind.raw => const [
            'name',
            'desc',
            'mtu',
            'gateway',
            'dns',
            'userLevel',
            'autoSystemRoutingTable',
            'autoOutboundsInterface',
            'autoSystemDnsToGateway',
            'autoSystemWfpBlockLeak',
          ],
          'socks' => const ['auth', 'users', 'accounts', 'udp'],
          'http' => const ['users', 'accounts'],
          'masque' when kind == JsonEditorKind.raw => const [
            'users',
            'address',
            'mtu',
          ],
          'hysteria' when kind == JsonEditorKind.raw => const [
            'version',
            'users',
          ],
          'tunnel' => const ['rewriteAddress', 'rewritePort', 'allowedNetwork'],
          _ => const [],
        };
      }
      return switch (protocol) {
        'vless' || 'vmess' => const ['vnext'],
        'trojan' || 'shadowsocks' || 'socks' || 'http' => const ['servers'],
        'freedom' => [
          'domainStrategy',
          'targetStrategy',
          'redirect',
          'userLevel',
          if (_freedomSettingsPath(path, shape, kind)) 'finalRules',
          'fragment',
          'noises',
        ],
        'blackhole' => const ['response'],
        'dns' => const [
          'rules',
          'rewriteNetwork',
          'rewriteAddress',
          'rewritePort',
          'userLevel',
        ],
        'wireguard' => const [
          'secretKey',
          'address',
          'peers',
          'mtu',
          'reserved',
          'remoteDNS',
        ],
        'masque' when !custom && !advanced => const [
          'address',
          'port',
          'remoteDNS',
        ],
        'hysteria' when !custom && !advanced => const [
          'version',
          'address',
          'port',
        ],
        'loopback' => const ['inboundTag'],
        _ => const [],
      };
    }
    if (_isDnsRule(path, shape)) {
      return const ['action', 'qType', 'domain', 'rCode'];
    }
    if (_isFreedomRule(path, shape, kind)) {
      return const ['action', 'network', 'port', 'ip', 'blockDelay'];
    }
    if (_endsWith(path, ['vnext', '*'])) {
      return const ['address', 'port', 'users'];
    }
    if (_endsWith(path, ['servers', '*']) && path.contains('settings')) {
      return const ['address', 'port', 'password', 'method', 'users', 'uot'];
    }
    if (_endsWith(path, ['users', '*']) || _endsWith(path, ['accounts', '*'])) {
      return _accountFields(path, kind, shape);
    }
    if (_matches(path, ['log'])) {
      return const ['loglevel', 'access', 'error', 'dnsLog', 'maskAddress'];
    }
    return const [];
  }

  static List<String> _values(
    List<Object> path,
    JsonEditorKind kind,
    _Shape shape,
    List<String> domains,
    List<String> ips,
  ) {
    if (path.isEmpty) return const [];
    final fieldPath = path.last is int
        ? path.sublist(0, path.length - 1)
        : path;
    if (fieldPath.isEmpty) return const [];
    final field = fieldPath.last;
    final parent = fieldPath.sublist(0, fieldPath.length - 1);
    final managed =
        kind == JsonEditorKind.customRouting ||
        kind == JsonEditorKind.advancedRouting;
    final rule = _matches(parent, ['routing', 'rules', '*']);
    final dnsRule = _isDnsRule(parent, shape);
    if (field == 'tag' && managed) {
      if (_matches(parent, ['routing', 'balancers', '*'])) {
        return const ['proxy'];
      }
      if (kind == JsonEditorKind.customRouting &&
          _matches(parent, ['inbounds', '*'])) {
        return const ['tunIn'];
      }
    }
    if (field == 'fallbackTag' && managed) return const [];
    if (field == 'outboundTag' ||
        field == 'dialerProxy' ||
        field == 'fallbackTag') {
      return [
        if (managed) ...['direct', 'block'],
        if (kind != JsonEditorKind.customRouting)
          ...shape
              .tags('outbounds')
              .where((tag) => !managed || _publicTag(tag)),
      ];
    }
    if (field == 'balancerTag') {
      return managed ? const ['proxy'] : shape.tags('balancers');
    }
    if (field == 'inboundTag') {
      return [
        ...shape
            .tags('inbounds')
            .where((tag) => !managed || _publicTag(tag) || tag == 'tunIn'),
        ...shape.dnsTags().where((tag) => !managed || _publicTag(tag)),
      ];
    }
    if (field == 'protocol') {
      if (rule) return const ['http', 'tls', 'quic', 'bittorrent'];
      if (_matches(parent, ['inbounds', '*'])) {
        if (kind == JsonEditorKind.customRouting ||
            kind == JsonEditorKind.advancedRouting &&
                shape.value([...parent, 'tag']) == 'tunIn') {
          return const [];
        }
        return kind == JsonEditorKind.advancedRouting
            ? const ['socks', 'http', 'tunnel']
            : const [
                'socks',
                'http',
                'tunnel',
                'vless',
                'vmess',
                'trojan',
                'shadowsocks',
                'hysteria',
                'masque',
                'tun',
              ];
      }
      if ((parent.isEmpty && kind == JsonEditorKind.outbound) ||
          _matches(parent, ['outbounds', '*'])) {
        if (kind == JsonEditorKind.customRouting) return const [];
        return kind == JsonEditorKind.advancedRouting
            ? const ['freedom', 'blackhole', 'dns']
            : const [
                'vless',
                'vmess',
                'trojan',
                'shadowsocks',
                'socks',
                'http',
                'freedom',
                'blackhole',
                'dns',
                'wireguard',
                'hysteria',
                'masque',
                'loopback',
              ];
      }
    }
    final geodataType = _geodataType(path, shape, kind);
    if (geodataType == 'domain') return domains;
    if (geodataType == 'ip') return ips;
    if (field == 'network') {
      if (rule || _isFreedomRule(parent, shape, kind)) {
        return const ['tcp', 'udp', 'tcp,udp'];
      }
      if (_streamSettingsPath(parent, kind) && !managed) {
        return [
          'raw',
          'tcp',
          'ws',
          'grpc',
          'xhttp',
          'httpupgrade',
          'kcp',
          'hysteria',
          'masque',
          'xdrive',
        ];
      }
    }
    if (kind != JsonEditorKind.customRouting &&
        (kind != JsonEditorKind.advancedRouting ||
            _advancedFreedomMaskPath(path, shape))) {
      if (field == 'type' && _maskElementPath(parent, kind, 'tcp')) {
        return const ['fragment'];
      }
      if (field == 'packets' &&
          _maskType(parent, shape, kind, 'tcp') == 'fragment') {
        return const ['tlshello'];
      }
      if (field == 'type' && _maskElementPath(parent, kind, 'udp')) {
        return const ['noise', 'xdns', 'udphop'];
      }
      if (field == 'type' &&
          _endsWith(parent, ['noise', '*']) &&
          _udpMaskType(parent.sublist(0, parent.length - 2), shape, kind) ==
              'noise') {
        return const ['array', 'str', 'hex', 'base64', 'exp'];
      }
    }
    if (!managed) {
      if (field == 'service' &&
          _streamSettingsChildPath(parent, kind, 'xdriveSettings')) {
        return const ['local', 'google-drive', 'template', 's3'];
      }
      if (field == 'type' &&
          parent.lastOrNull == 'auth' &&
          _xdriveTemplatePath(parent.sublist(0, parent.length - 1), kind)) {
        return const ['none', 'static', 'oauth2', 'basic'];
      }
      if ((field == 'method' || field == 'hrefMethod') &&
          _xdriveTemplateOperationPath(parent, kind)) {
        return const [
          'GET',
          'POST',
          'PUT',
          'PATCH',
          'DELETE',
          'HEAD',
          'OPTIONS',
        ];
      }
      if (field == 'alpn' && _tlsSettingsPath(parent, kind, shape)) {
        return const ['h2', 'http/1.1', 'h3'];
      }
      if (_quicSettingsPath(parent, kind, shape)) {
        if (field == 'congestion') {
          return const ['reno', 'bbr', 'brutal', 'force-brutal'];
        }
        if (field == 'bbrProfile') {
          return const ['conservative', 'standard', 'aggressive'];
        }
      }
      if (field == 'type') {
        if (_endsWith(parent, ['hysteriaSettings', 'masquerade']) &&
            _streamSettingsPath(parent.sublist(0, parent.length - 2), kind)) {
          return const ['file', 'proxy', 'string'];
        }
      }
    }
    if (field == 'action' && dnsRule) {
      if (kind == JsonEditorKind.customRouting) {
        return parent.last == 0 ? const ['hijack'] : const ['direct', 'return'];
      }
      return const ['hijack', 'direct', 'drop', 'return'];
    }
    if (field == 'action' && _isFreedomRule(parent, shape, kind)) {
      return const ['allow', 'block'];
    }
    if (field == 'rewriteNetwork' &&
        parent.lastOrNull == 'settings' &&
        shape.value([...parent.sublist(0, parent.length - 1), 'protocol']) ==
            'dns') {
      return const ['tcp', 'udp'];
    }
    if (field == 'security' && parent.lastOrNull == 'streamSettings') {
      return const ['none', 'tls', 'reality'];
    }
    if (field == 'security' &&
        _accountFields(parent, kind, shape).contains('security')) {
      return const ['auto', 'aes-128-gcm', 'chacha20-poly1305', 'none', 'zero'];
    }
    if (field == 'domainStrategy') {
      if (_matches(parent, ['routing'])) {
        return kind == JsonEditorKind.customRouting
            ? const ['IPIfNonMatch']
            : const ['AsIs', 'IPIfNonMatch', 'IPOnDemand'];
      }
      if (kind == JsonEditorKind.customRouting) return const [];
      if (parent.lastOrNull == 'settings' &&
          shape.value([...parent.sublist(0, parent.length - 1), 'protocol']) ==
              'freedom') {
        return _dialingStrategies;
      }
      return !managed && _socketSettingsPath(parent, kind, shape)
          ? _dialingStrategies
          : const [];
    }
    if (field == 'targetStrategy' && kind != JsonEditorKind.customRouting) {
      if (parent.lastOrNull == 'settings' &&
          shape.value([...parent.sublist(0, parent.length - 1), 'protocol']) ==
              'freedom') {
        return _dialingStrategies;
      }
      return !managed &&
              (kind == JsonEditorKind.outbound && parent.isEmpty ||
                  _matches(parent, ['outbounds', '*']))
          ? _dialingStrategies
          : const [];
    }
    if (field == 'queryStrategy') {
      return managed
          ? const []
          : const ['UseIP', 'UseIPv4', 'UseIPv6', 'UseSystem'];
    }
    if (field == 'localOS' && rule) {
      return const ['ios', 'android', 'darwin', 'windows', 'linux'];
    }
    if (field == 'destOverride' && parent.lastOrNull == 'sniffing') {
      return const ['http', 'tls', 'quic', 'fakedns'];
    }
    if (kind == JsonEditorKind.raw &&
        field == 'autoSystemWfpBlockLeak' &&
        _matches(parent, ['inbounds', '*', 'settings']) &&
        shape.value([...parent.sublist(0, parent.length - 1), 'protocol']) ==
            'tun') {
      return const ['dns', 'misconfigtun'];
    }
    if (field == 'type' &&
        _matches(parent, ['routing', 'balancers', '*', 'strategy'])) {
      if (managed) {
        return _managedProxyBalancer(parent.sublist(0, 3), shape)
            ? const ['roundRobin', 'leastPing']
            : const [];
      }
      return const ['random', 'roundRobin', 'leastPing', 'leastLoad'];
    }
    if (field == 'loglevel' && _matches(parent, ['log'])) {
      return const ['debug', 'info', 'warning', 'error', 'none'];
    }
    if (field == 'flow' &&
        _accountFields(parent, kind, shape).contains('flow')) {
      return const ['xtls-rprx-vision'];
    }
    if (field == 'encryption' &&
        _accountFields(parent, kind, shape).contains('encryption')) {
      return const ['none'];
    }
    if (field == 'auth' && parent.lastOrNull == 'settings') {
      return const ['noauth', 'password'];
    }
    return const [];
  }

  static const _quicFields = [
    'congestion',
    'debug',
    'bbrProfile',
    'brutalUp',
    'brutalDown',
    'brutalDisableLossCompensation',
    'initStreamReceiveWindow',
    'maxStreamReceiveWindow',
    'initConnectionReceiveWindow',
    'maxConnectionReceiveWindow',
    'maxIdleTimeout',
    'keepAlivePeriod',
    'disablePathMTUDiscovery',
    'disableChromeParrot',
    'disableGSO',
    'maxIncomingStreams',
    'disableStatelessReset',
  ];

  static const _xmuxFields = [
    'maxConcurrency',
    'maxConnections',
    'cMaxReuseTimes',
    'hMaxRequestTimes',
    'hMaxReusableSecs',
    'hKeepAlivePeriod',
  ];

  static const _outboundFields = [
    'tag',
    'protocol',
    'settings',
    'streamSettings',
    'mux',
    'sendThrough',
    'proxySettings',
    'targetStrategy',
  ];

  static const _dialingStrategies = [
    'AsIs',
    'UseIP',
    'UseIPv4',
    'UseIPv6',
    'UseIPv4v6',
    'UseIPv6v4',
    'ForceIP',
    'ForceIPv4',
    'ForceIPv6',
    'ForceIPv4v6',
    'ForceIPv6v4',
  ];
}

String _stringContent(String value) {
  final encoded = jsonEncode(value);
  return encoded.substring(1, encoded.length - 1);
}

String _pathKey(List<Object> path) => jsonEncode(path);
bool _publicTag(String tag) =>
    !tag.startsWith('app-entry-') &&
    !tag.startsWith('app-exit-') &&
    tag != 'proxy';
bool _matches(List<Object> path, List<Object> pattern) =>
    path.length == pattern.length &&
    [
      for (var i = 0; i < path.length; i++)
        pattern[i] == '*' ? path[i] is int : path[i] == pattern[i],
    ].every((value) => value);
bool _endsWith(List<Object> path, List<Object> suffix) =>
    path.length >= suffix.length &&
    _matches(path.sublist(path.length - suffix.length), suffix);
bool _streamSettingsPath(List<Object> path, JsonEditorKind kind) =>
    kind == JsonEditorKind.outbound && _matches(path, ['streamSettings']) ||
    _matches(path, ['outbounds', '*', 'streamSettings']) ||
    kind == JsonEditorKind.raw &&
        _matches(path, ['inbounds', '*', 'streamSettings']);
bool _streamSettingsChildPath(
  List<Object> path,
  JsonEditorKind kind,
  String field,
) =>
    path.lastOrNull == field &&
    _streamSettingsPath(path.sublist(0, path.length - 1), kind);
bool _xdriveTemplatePath(List<Object> path, JsonEditorKind kind) =>
    (kind == JsonEditorKind.outbound || kind == JsonEditorKind.raw) &&
    path.lastOrNull == 'template' &&
    _streamSettingsChildPath(
      path.sublist(0, path.length - 1),
      kind,
      'xdriveSettings',
    );

bool _xdriveTemplateOperationPath(List<Object> path, JsonEditorKind kind) =>
    const ['put', 'get', 'delete', 'list'].contains(path.lastOrNull) &&
    _xdriveTemplatePath(path.sublist(0, path.length - 1), kind);

bool _managedProxyBalancer(List<Object> path, _Shape shape) {
  final tag = shape.value([...path, 'tag']);
  return tag == null || tag == 'proxy';
}

bool _isDnsRule(List<Object> path, _Shape shape) =>
    _endsWith(path, ['settings', 'rules', '*']) &&
    shape.value([...path.sublist(0, path.length - 3), 'protocol']) == 'dns';

bool _freedomSettingsPath(
  List<Object> path,
  _Shape shape,
  JsonEditorKind kind,
) {
  if (kind == JsonEditorKind.customRouting || path.lastOrNull != 'settings') {
    return false;
  }
  final owner = path.sublist(0, path.length - 1);
  return (kind == JsonEditorKind.outbound && owner.isEmpty ||
          _matches(owner, ['outbounds', '*'])) &&
      shape.value([...owner, 'protocol']) == 'freedom';
}

bool _isFreedomRule(List<Object> path, _Shape shape, JsonEditorKind kind) =>
    _endsWith(path, ['finalRules', '*']) &&
    _freedomSettingsPath(path.sublist(0, path.length - 2), shape, kind);

bool _advancedFreedomMaskPath(List<Object> path, _Shape shape) =>
    path.length >= 4 &&
    path[0] == 'outbounds' &&
    path[1] is int &&
    path[2] == 'streamSettings' &&
    path[3] == 'finalmask' &&
    shape.value(['outbounds', path[1], 'protocol']) == 'freedom';

bool _maskElementPath(List<Object> path, JsonEditorKind kind, String network) =>
    _endsWith(path, [network, '*']) &&
    _streamSettingsChildPath(
      path.sublist(0, path.length - 2),
      kind,
      'finalmask',
    );

String? _maskType(
  List<Object> settingsPath,
  _Shape shape,
  JsonEditorKind kind,
  String network,
) =>
    settingsPath.lastOrNull == 'settings' &&
        _maskElementPath(
          settingsPath.sublist(0, settingsPath.length - 1),
          kind,
          network,
        )
    ? shape.value([
        ...settingsPath.sublist(0, settingsPath.length - 1),
        'type',
      ])?.toLowerCase()
    : null;

String? _udpMaskType(
  List<Object> settingsPath,
  _Shape shape,
  JsonEditorKind kind,
) => _maskType(settingsPath, shape, kind, 'udp');

bool _xdnsResolverPath(List<Object> path, JsonEditorKind kind, _Shape shape) =>
    _endsWith(path, ['resolvers', '*']) &&
    _udpMaskType(path.sublist(0, path.length - 2), shape, kind) == 'xdns';

bool _tlsSettingsPath(List<Object> path, JsonEditorKind kind, _Shape shape) =>
    _streamSettingsChildPath(path, kind, 'tlsSettings') ||
    path.lastOrNull == 'tlsConfig' &&
        _xdnsResolverPath(path.sublist(0, path.length - 1), kind, shape);

bool _socketSettingsPath(
  List<Object> path,
  JsonEditorKind kind,
  _Shape shape,
) =>
    _streamSettingsChildPath(path, kind, 'sockopt') ||
    path.lastOrNull == 'echSockopt' &&
        _tlsSettingsPath(path.sublist(0, path.length - 1), kind, shape);

bool _quicSettingsPath(List<Object> path, JsonEditorKind kind, _Shape shape) =>
    path.lastOrNull == 'quicConfig' &&
        _xdnsResolverPath(path.sublist(0, path.length - 1), kind, shape) ||
    path.lastOrNull == 'quicParams' &&
        _streamSettingsChildPath(
          path.sublist(0, path.length - 1),
          kind,
          'finalmask',
        );

String? _geodataType(List<Object> path, _Shape shape, JsonEditorKind kind) {
  if (path.isEmpty) return null;
  final fieldPath = path.last is int ? path.sublist(0, path.length - 1) : path;
  if (fieldPath.isEmpty) return null;
  final field = fieldPath.last;
  final parent = fieldPath.sublist(0, fieldPath.length - 1);
  final rule = _matches(parent, ['routing', 'rules', '*']);
  if (field == 'domain' && (rule || _isDnsRule(parent, shape)) ||
      field == 'domains' && _matches(parent, ['dns', 'servers', '*']) ||
      field == 'domainsExcluded' &&
          _matches(parent, ['inbounds', '*', 'sniffing'])) {
    return 'domain';
  }
  if (field == 'ip' && (rule || _isFreedomRule(parent, shape, kind)) ||
      field == 'localIP' && rule ||
      field == 'sourceIP' && rule ||
      (field == 'expectIPs' ||
              field == 'expectedIPs' ||
              field == 'unexpectedIPs') &&
          _matches(parent, ['dns', 'servers', '*']) ||
      field == 'ipsExcluded' &&
          _matches(parent, ['inbounds', '*', 'sniffing'])) {
    return 'ip';
  }
  return null;
}

List<String> _accountFields(
  List<Object> path,
  JsonEditorKind kind,
  _Shape shape,
) {
  if (kind == JsonEditorKind.customRouting) return const [];
  if (_matches(path, ['inbounds', '*', 'settings', 'users', '*']) ||
      _matches(path, ['inbounds', '*', 'settings', 'accounts', '*'])) {
    final protocol = shape.value([...path.sublist(0, 2), 'protocol']);
    if (protocol == 'masque' && kind == JsonEditorKind.raw) {
      return const ['pass', 'level', 'email'];
    }
    if (protocol == 'hysteria' && kind == JsonEditorKind.raw) {
      return const ['auth', 'level', 'email'];
    }
    return protocol == 'socks' || protocol == 'http'
        ? const ['user', 'pass']
        : const [];
  }
  if (kind == JsonEditorKind.advancedRouting) return const [];
  final List<Object> owner;
  if (path.length >= 2 && path[0] == 'outbounds' && path[1] is int) {
    owner = path.sublist(0, 2);
  } else if (kind == JsonEditorKind.outbound &&
      path.firstOrNull == 'settings') {
    owner = const [];
  } else {
    return const [];
  }
  final relative = path.sublist(owner.length);
  final protocol = shape.value([...owner, 'protocol']);
  if (_matches(relative, ['settings', 'vnext', '*', 'users', '*'])) {
    return switch (protocol) {
      'vless' => const ['id', 'encryption', 'flow', 'level', 'email'],
      'vmess' => const ['id', 'security', 'level', 'email'],
      _ => const [],
    };
  }
  if (_matches(relative, ['settings', 'servers', '*', 'users', '*']) &&
      (protocol == 'socks' || protocol == 'http')) {
    return const ['user', 'pass', 'level', 'email'];
  }
  return const [];
}

class _Location {
  final List<Object> path;
  final bool isKey;
  const _Location(this.path, {this.isKey = false});
}

enum _Phase { key, colon, value, after }

class _Frame {
  final List<Object> path;
  final bool object;
  _Phase phase;
  String? key;
  int index = 0;
  _Frame(this.path, {required this.object})
    : phase = object ? _Phase.key : _Phase.value;
  List<Object>? get valuePath => phase != _Phase.value
      ? null
      : object
      ? key == null
            ? null
            : [...path, key!]
      : [...path, index];
}

/// Keeps paths for partial documents without turning suggestions into a schema.
class _Shape {
  final locations = <JsonToken, _Location>{};
  final keys = <String, Set<String>>{};
  final strings = <({List<Object> path, String value})>[];

  _Shape(List<JsonToken> tokens) {
    final stack = <_Frame>[];
    for (final token in tokens) {
      final frame = stack.lastOrNull;
      if (token.kind == JsonTokenKind.objectStart ||
          token.kind == JsonTokenKind.arrayStart) {
        final path = frame?.valuePath ?? (stack.isEmpty ? <Object>[] : null);
        if (path == null) continue;
        if (frame != null) frame.phase = _Phase.after;
        stack.add(
          _Frame(path, object: token.kind == JsonTokenKind.objectStart),
        );
      } else if (token.kind == JsonTokenKind.objectEnd ||
          token.kind == JsonTokenKind.arrayEnd) {
        if (stack.isNotEmpty) stack.removeLast();
      } else if (token.kind == JsonTokenKind.colon &&
          frame?.phase == _Phase.colon) {
        frame!.phase = _Phase.value;
      } else if (token.kind == JsonTokenKind.comma && frame != null) {
        frame.phase = frame.object ? _Phase.key : _Phase.value;
        frame.key = null;
        frame.index++;
      } else if (token.kind == JsonTokenKind.string &&
          frame?.phase == _Phase.key) {
        locations[token] = _Location(frame!.path, isKey: true);
        frame.key = token.value;
        frame.phase = _Phase.colon;
        if (token.value != null) {
          keys.putIfAbsent(_pathKey(frame.path), () => {}).add(token.value!);
        }
      } else if (token.kind == JsonTokenKind.string ||
          token.kind == JsonTokenKind.literal) {
        final path = frame?.valuePath;
        if (path == null) continue;
        locations[token] = _Location(path);
        if (token.kind == JsonTokenKind.string &&
            token.closed &&
            token.value != null) {
          strings.add((path: path, value: token.value!));
        }
        frame!.phase = _Phase.after;
      }
    }
  }

  String? value(List<Object> path) {
    final found = strings.where(
      (entry) => _pathKey(entry.path) == _pathKey(path),
    );
    return found.length == 1 ? found.single.value : null;
  }

  List<String> tags(String namespace) => [
    for (final entry in strings)
      if (_matches(
            entry.path,
            namespace == 'balancers'
                ? ['routing', 'balancers', '*', 'tag']
                : [namespace, '*', 'tag'],
          ) &&
          entry.value.isNotEmpty)
        entry.value,
  ];

  List<String> dnsTags() => [
    for (final entry in strings)
      if ((_matches(entry.path, ['dns', 'tag']) ||
              _matches(entry.path, ['dns', 'servers', '*', 'tag'])) &&
          entry.value.isNotEmpty)
        entry.value,
  ];
}
