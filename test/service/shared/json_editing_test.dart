import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/tools/json_document.dart';
import 'package:onexray/service/shared/json_editing.dart';

List<JsonCompletion> completions(
  String marked,
  JsonEditorKind kind, {
  List<String> domains = const [],
  List<String> ips = const [],
}) {
  final offset = marked.indexOf('|');
  assert(offset >= 0);
  return JsonEditing.complete(
    marked.replaceFirst('|', ''),
    offset,
    kind,
    domainSuggestions: domains,
    ipSuggestions: ips,
  );
}

List<String> labels(String marked, JsonEditorKind kind) =>
    completions(marked, kind).map((value) => value.label).toList();

void main() {
  test('ordinary DNS helper completions match the editable record policy', () {
    String source(String rules) =>
        '{"outbounds":[{}, {"tag":"dnsOut","protocol":"dns","settings":{"rules":[$rules]}}]}';
    expect(
      labels(
        source('{"action":"|","qType":"1,28"}'),
        JsonEditorKind.customRouting,
      ),
      ['hijack'],
    );
    expect(
      labels(
        source('{"action":"hijack","qType":"1,28"},{"action":"|"}'),
        JsonEditorKind.customRouting,
      ),
      ['direct', 'return'],
    );
    expect(labels(source('{"action":"|"}'), JsonEditorKind.raw), [
      'hijack',
      'direct',
      'drop',
      'return',
    ]);
  });

  test('completes object keys and protocol enums in both node input forms', () {
    expect(labels('{"pro|"}', JsonEditorKind.outbound), [
      'protocol',
      'proxySettings',
    ]);
    expect(labels('{"protocol":"vl|"}', JsonEditorKind.outbound), ['vless']);
    expect(labels('{"out|"}', JsonEditorKind.outbound), ['outbounds']);
    expect(labels('{"outbounds":[],"|"}', JsonEditorKind.outbound), isEmpty);
    expect(labels('{"outbounds":[{"pro|"}]}', JsonEditorKind.outbound), [
      'protocol',
      'proxySettings',
    ]);
    expect(
      labels('{"outbounds":[{"protocol":"vm|"}]}', JsonEditorKind.outbound),
      ['vmess'],
    );
    expect(
      labels(
        '{"protocol":"vless","settings":{"vn|"}}',
        JsonEditorKind.outbound,
      ),
      ['vnext'],
    );
  });

  test('completes the core TUN DNS and WFP options only in Raw', () {
    String settings(String body, {String protocol = 'tun'}) =>
        '{"inbounds":[{"tag":"tunIn","protocol":"$protocol","settings":{$body}}]}';
    expect(labels(settings('"autoSystem|"'), JsonEditorKind.raw), [
      'autoSystemRoutingTable',
      'autoSystemDnsToGateway',
      'autoSystemWfpBlockLeak',
    ]);
    expect(
      labels(settings('"autoSystemWfpBlockLeak":["|"]'), JsonEditorKind.raw),
      ['dns', 'misconfigtun'],
    );
    expect(
      labels(settings('"autoSystemWfpBlockLeak":["mi|"]'), JsonEditorKind.raw),
      ['misconfigtun'],
    );
    expect(
      labels(settings('"autoSystem|"'), JsonEditorKind.advancedRouting),
      isEmpty,
    );
    expect(
      labels(settings('"autoSystem|"', protocol: 'socks'), JsonEditorKind.raw),
      isEmpty,
    );
    expect(
      labels(
        settings('"autoSystemWfpBlockLeak":["|"]', protocol: 'socks'),
        JsonEditorKind.raw,
      ),
      isEmpty,
    );
  });

  test('FakeDNS uses the canonical key and recognizes both pool forms', () {
    for (final kind in [JsonEditorKind.raw, JsonEditorKind.advancedRouting]) {
      expect(labels('{"fake|"}', kind), ['fakeDns']);
      for (final key in ['fakeDns', 'fakedns']) {
        expect(labels('{"$key":{"ip|"}}', kind), ['ipPool']);
        expect(labels('{"$key":[{"pool|"}]}', kind), ['poolSize']);
      }
    }
    expect(labels('{"fake|"}', JsonEditorKind.customRouting), isEmpty);
  });

  test('WireGuard removes only the obsolete settings strategy suggestions', () {
    for (final kind in [JsonEditorKind.outbound, JsonEditorKind.raw]) {
      String source(String body) => kind == JsonEditorKind.outbound
          ? '{"protocol":"wireguard",$body}'
          : '{"outbounds":[{"protocol":"wireguard",$body}]}';
      expect(labels(source('"settings":{"dom|"}'), kind), isEmpty);
      expect(
        labels(source('"settings":{"domainStrategy":"U|"}'), kind),
        isEmpty,
      );
      expect(labels(source('"settings":{"remote|"}'), kind), ['remoteDNS']);
      expect(
        labels(
          source('"streamSettings":{"sockopt":{"domainStrategy":"UseIPv|"}}'),
          kind,
        ),
        ['UseIPv4', 'UseIPv6', 'UseIPv4v6', 'UseIPv6v4'],
      );
    }
    expect(
      labels(
        '{"protocol":"freedom","settings":{"domainStrategy":"UseIPv|"}}',
        JsonEditorKind.outbound,
      ),
      ['UseIPv4', 'UseIPv6', 'UseIPv4v6', 'UseIPv6v4'],
    );
  });

  test('dialing suggestions follow socket, DNS and routing contexts', () {
    for (final kind in [JsonEditorKind.outbound, JsonEditorKind.raw]) {
      String outbound(String body) => kind == JsonEditorKind.outbound
          ? '{$body}'
          : '{"outbounds":[{$body}]}';
      String socket(String body) =>
          outbound('"streamSettings":{"sockopt":{$body}}');
      expect(labels(socket('"hap|"'), kind), ['happyEyeballs']);
      expect(labels(socket('"happyEyeballs":{"|"}'), kind), [
        'prioritizeIPv6',
        'tryDelayMs',
        'interleave',
        'maxConcurrentTry',
      ]);
      expect(labels(socket('"domainStrategy":"Use|"'), kind), [
        'UseIP',
        'UseIPv4',
        'UseIPv6',
        'UseIPv4v6',
        'UseIPv6v4',
      ]);
      expect(labels(socket('"domainStrategy":"Force|"'), kind), [
        'ForceIP',
        'ForceIPv4',
        'ForceIPv6',
        'ForceIPv4v6',
        'ForceIPv6v4',
      ]);
      expect(labels(outbound('"tar|"'), kind), ['targetStrategy']);
      expect(labels(outbound('"targetStrategy":"ForceIPv6v|"'), kind), [
        'ForceIPv6v4',
      ]);
      expect(
        labels(outbound('"protocol":"freedom","settings":{"tar|"}'), kind),
        ['targetStrategy'],
      );
    }
    expect(labels('{"dns":{"queryStrategy":"Use|"}}', JsonEditorKind.raw), [
      'UseIP',
      'UseIPv4',
      'UseIPv6',
      'UseSystem',
    ]);
    expect(
      labels(
        '{"dns":{"servers":[{"queryStrategy":"UseS|"}]}}',
        JsonEditorKind.raw,
      ),
      ['UseSystem'],
    );
    expect(labels('{"routing":{"domainStrategy":"|"}}', JsonEditorKind.raw), [
      'AsIs',
      'IPIfNonMatch',
      'IPOnDemand',
    ]);
    for (final marked in [
      '{"future":{"sockopt":{"hap|"}}}',
      '{"future":{"happyEyeballs":{"in|"}}}',
      '{"future":{"domainStrategy":"Use|"}}',
      '{"future":{"targetStrategy":"Use|"}}',
    ]) {
      expect(labels(marked, JsonEditorKind.raw), isEmpty);
    }
  });

  test('advanced templates only suggest supported dialing fields', () {
    String outbound(String body) => '{"outbounds":[{},{$body}]}';
    for (final body in [
      '"tar|"',
      '"targetStrategy":"Use|"',
      '"streamSettings":{"sockopt":{"hap|"}}',
      '"streamSettings":{"sockopt":{"domainStrategy":"Use|"}}',
      '"streamSettings":{"sockopt":{"happyEyeballs":{"in|"}}}',
    ]) {
      expect(labels(outbound(body), JsonEditorKind.advancedRouting), isEmpty);
    }
    expect(
      labels(
        outbound('"streamSettings":{"sockopt":{"dia|"}}'),
        JsonEditorKind.advancedRouting,
      ),
      ['dialerProxy'],
    );
    expect(
      labels(
        outbound(
          '"protocol":"freedom","settings":{"targetStrategy":"ForceIPv6v|"}}',
        ),
        JsonEditorKind.advancedRouting,
      ),
      ['ForceIPv6v4'],
    );
  });

  test(
    'MASQUE and XDrive suggestions preserve advanced template boundaries',
    () {
      expect(labels('{"protocol":"ma|"}', JsonEditorKind.outbound), ['masque']);
      expect(labels('{"inbounds":[{"protocol":"ma|"}]}', JsonEditorKind.raw), [
        'masque',
      ]);
      expect(labels('{"protocol":"xd|"}', JsonEditorKind.outbound), isEmpty);
      expect(
        labels(
          '{"protocol":"masque","settings":{"remote|"}}',
          JsonEditorKind.outbound,
        ),
        ['remoteDNS'],
      );
      expect(
        labels(
          '{"inbounds":[{"protocol":"masque","settings":{"users":[{"pa|"}]}}]}',
          JsonEditorKind.raw,
        ),
        ['pass'],
      );
      for (final kind in [JsonEditorKind.outbound, JsonEditorKind.raw]) {
        String source(String stream) => kind == JsonEditorKind.outbound
            ? '{"streamSettings":{$stream}}'
            : '{"outbounds":[{"streamSettings":{$stream}}]}';
        expect(labels(source('"network":"ma|"'), kind), ['masque']);
        expect(labels(source('"network":"xd|"'), kind), ['xdrive']);
        expect(labels(source('"masqueSettings":{"pa|"}'), kind), [
          'path',
          'pass',
        ]);
        expect(labels(source('"xdriveSettings":{"se|"}'), kind), [
          'service',
          'secrets',
          'segmentBytes',
          'sessionTtlSeconds',
        ]);
        expect(labels(source('"xdriveSettings":{"service":"G|"}'), kind), [
          'google-drive',
        ]);
        expect(
          labels(source('"xdriveSettings":{"secrets":["|"]}'), kind),
          isEmpty,
        );
      }
      for (final body in [
        '"protocol":"ma|"',
        '"streamSettings":{"ma|"}',
        '"streamSettings":{"xdriveSettings":{"se|"}}',
        '"streamSettings":{"network":"ma|"}',
        '"streamSettings":{"network":"xd|"}',
      ]) {
        expect(
          labels('{"outbounds":[{}, {$body}]}', JsonEditorKind.advancedRouting),
          isEmpty,
        );
      }
    },
  );

  test('S3 completions stay within XDrive and leave values user-owned', () {
    for (final (kind, wrapper) in [
      (JsonEditorKind.outbound, '{"streamSettings":{BODY}}'),
      (JsonEditorKind.outbound, '{"outbounds":[{"streamSettings":{BODY}}]}'),
      (JsonEditorKind.raw, '{"inbounds":[{"streamSettings":{BODY}}]}'),
      (JsonEditorKind.raw, '{"outbounds":[{"streamSettings":{BODY}}]}'),
    ]) {
      String source(String body) =>
          wrapper.replaceFirst('BODY', '"xdriveSettings":{$body}');
      expect(labels(source('"service":"s|"'), kind), ['s3']);
      expect(labels(source('"s|"'), kind), contains('s3'));
      expect(labels(source('"s3":{"|"}'), kind), [
        'endpoint',
        'region',
        'bucket',
        'pathStyle',
      ]);
      expect(
        labels(source('"s3":{"endpoint":"https://s3.example","en|"}'), kind),
        isEmpty,
      );
      for (final body in [
        '"s3":{"endpoint":"https://|"}',
        '"s3":{"region":"us-|"}',
        '"s3":{"pathStyle":"t|"}',
        '"secrets":["|"]',
      ]) {
        expect(labels(source(body), kind), isEmpty);
      }
    }
    for (final kind in [
      JsonEditorKind.customRouting,
      JsonEditorKind.advancedRouting,
    ]) {
      expect(
        labels(
          '{"outbounds":[{}, {"streamSettings":{"xdriveSettings":{"service":"s|"}}}]}',
          kind,
        ),
        isEmpty,
      );
      expect(
        labels(
          '{"outbounds":[{}, {"streamSettings":{"xdriveSettings":{"s3":{"en|"}}}}]}',
          kind,
        ),
        isEmpty,
      );
    }
    for (final marked in [
      '{"future":{"xdriveSettings":{"s3":{"en|"}}}}',
      '{"streamSettings":{"future":{"xdriveSettings":{"s3":{"en|"}}}}}',
      '{"streamSettings":{"masqueSettings":{"s3":{"en|"}}}}',
    ]) {
      expect(labels(marked, JsonEditorKind.outbound), isEmpty);
    }
    const marked =
        '{"protocol":"vless","settings":{"future":{"keep":true}},"streamSettings":{"xdriveSettings":{"service":"s|","secrets":["fixture-key","fixture-secret"],"s3":{"endpoint":"https://store.example:8443/prefix","bucket":"fixture","pathStyle":false},"future":{"keep":[1,2]}}}}';
    final completion = completions(marked, JsonEditorKind.outbound).single;
    final text = marked.replaceFirst('|', '');
    final before = jsonDecode(text) as Map<String, dynamic>;
    final after = jsonDecode(
      text.replaceRange(
        completion.start,
        completion.end,
        completion.insertText,
      ),
    ) as Map<String, dynamic>;
    before['streamSettings']['xdriveSettings']['service'] = 's3';
    expect(after, before);
  });

  test('XMUX and XDrive timing hints follow their transport owner', () {
    for (final (kind, template) in [
      (JsonEditorKind.outbound, '{"streamSettings":{BODY}}'),
      (JsonEditorKind.outbound, '{"outbounds":[{"streamSettings":{BODY}}]}'),
      (JsonEditorKind.raw, '{"outbounds":[{"streamSettings":{BODY}}]}'),
      (JsonEditorKind.raw, '{"inbounds":[{"streamSettings":{BODY}}]}'),
    ]) {
      for (final transport in ['masqueSettings', 'xdriveSettings']) {
        String source(String body) =>
            template.replaceFirst('BODY', '"$transport":{$body}');
        expect(labels(source('"xm|"'), kind), ['xmux']);
        expect(labels(source('"xmux":{"max|"}'), kind), [
          'maxConcurrency',
          'maxConnections',
        ]);
        expect(labels(source('"xmux":{"h|"}'), kind), [
          'hMaxRequestTimes',
          'hMaxReusableSecs',
          'hKeepAlivePeriod',
        ]);
        expect(labels(source('"xmux":{"cM|"}'), kind), ['cMaxReuseTimes']);
        expect(labels(source('"xmux":{"maxConnections":"|"}'), kind), isEmpty);
      }
      for (final field in [
        'maxPollIntervalMs',
        'sessionTtlSeconds',
        'eagerWindowMs',
        'holeTimeoutMs',
      ]) {
        final body = '"xdriveSettings":{"${field.substring(0, 4)}|"}';
        expect(labels(template.replaceFirst('BODY', body), kind), [field]);
      }
    }
    for (final kind in [
      JsonEditorKind.customRouting,
      JsonEditorKind.advancedRouting,
    ]) {
      expect(
        labels(
          '{"outbounds":[{"streamSettings":{"xdriveSettings":{"xmux":{"max|"}}}}]}',
          kind,
        ),
        isEmpty,
      );
    }
    for (final marked in [
      '{"future":{"xdriveSettings":{"ser|"}}}',
      '{"future":{"xdriveSettings":{"service":"goo|"}}}',
      '{"future":{"masqueSettings":{"xmux":{"max|"}}}}',
      '{"streamSettings":{"xhttpSettings":{"xmux":{"max|"}}}}',
    ]) {
      expect(labels(marked, JsonEditorKind.outbound), isEmpty);
    }
  });

  test('XDrive template keys and enums follow their exact storage owner', () {
    for (final (kind, wrapper) in [
      (JsonEditorKind.outbound, '{"streamSettings":{BODY}}'),
      (JsonEditorKind.outbound, '{"outbounds":[{"streamSettings":{BODY}}]}'),
      (JsonEditorKind.raw, '{"outbounds":[{"streamSettings":{BODY}}]}'),
      (JsonEditorKind.raw, '{"inbounds":[{"streamSettings":{BODY}}]}'),
    ]) {
      String source(String body) =>
          wrapper.replaceFirst('BODY', '"xdriveSettings":{"template":{$body}}');
      expect(labels(source('"|"'), kind), [
        'flatten',
        'concurrency',
        'auth',
        'put',
        'get',
        'delete',
        'list',
        'retry',
      ]);
      expect(labels(source('"auth":{"|"}'), kind), [
        'type',
        'header',
        'username',
        'password',
        'tokenUrl',
        'form',
        'tokenPath',
        'expiryPath',
      ]);
      expect(labels(source('"auth":{"type":"|"}'), kind), [
        'none',
        'static',
        'oauth2',
        'basic',
      ]);
      expect(labels(source('"retry":{"|"}'), kind), ['status', 'rateReason']);
      for (final operation in ['put', 'get', 'delete', 'list']) {
        expect(labels(source('"$operation":{"|"}'), kind), [
          'method',
          'url',
          'headers',
          'body',
          'namesRegex',
          'hrefPath',
          'hrefMethod',
        ]);
        for (final field in ['method', 'hrefMethod']) {
          expect(labels(source('"$operation":{"$field":"P|"}'), kind), [
            'POST',
            'PUT',
            'PATCH',
          ]);
        }
      }
      expect(labels(source('"get":{"hrefPath":"reply.url","href|"}'), kind), [
        'hrefMethod',
      ]);
    }
  });

  test(
    'template hints avoid lookalike owners and leave free text unconstrained',
    () {
      String source(String body) =>
          '{"streamSettings":{"xdriveSettings":{"template":{$body}}}}';
      for (final body in [
        '"href|"',
        '"auth":{"href|"}',
        '"retry":{"href|"}',
        '"future":{"href|"}',
        '"future":{"get":{"href|"}}',
        '"get":{"headers":{"href|"}}',
        '"auth":{"header":{"ty|"}}',
        '"auth":{"form":{"ty|"}}',
        '"auth":{"username":"|"}',
        '"auth":{"password":"|"}',
        '"auth":{"tokenPath":"|"}',
        '"get":{"url":"|"}',
        '"get":{"body":"|"}',
        '"list":{"namesRegex":"|"}',
        '"get":{"hrefPath":"|"}',
        '"get":{"headers":{"method":"P|"}}',
        '"auth":{"form":{"type":"o|"}}',
        '"get":{"method":"CUSTOM|"}',
      ]) {
        expect(labels(source(body), JsonEditorKind.outbound), isEmpty);
      }
      for (final kind in [
        JsonEditorKind.customRouting,
        JsonEditorKind.advancedRouting,
      ]) {
        for (final body in [
          '"con|"',
          '"auth":{"type":"o|"}',
          '"get":{"href|"}',
          '"get":{"method":"G|"}',
        ]) {
          expect(labels('{"outbounds":[${source(body)}]}', kind), isEmpty);
        }
      }
      for (final marked in [
        '{"template":{"auth":{"type":"o|"}}}',
        '{"future":{"streamSettings":{"xdriveSettings":{"template":{"get":{"href|"}}}}}}',
        '{"streamSettings":{"future":{"xdriveSettings":{"template":{"get":{"href|"}}}}}}',
        '{"streamSettings":{"masqueSettings":{"template":{"get":{"method":"G|"}}}}}',
      ]) {
        expect(labels(marked, JsonEditorKind.raw), isEmpty);
        expect(labels(marked, JsonEditorKind.outbound), isEmpty);
      }
    },
  );

  test('template completion replaces only the selected key string', () {
    const marked =
        '{"streamSettings":{"xdriveSettings":{"template":{"get":{"hrefP|":"result.url","method":"CUSTOM","url":"https://example.test/{name}","headers":{"Authorization":"{secret0}"},"future":{"keep":true}},"auth":{"type":"static","header":{"X-Token":"{secret0}"}}}}}}';
    final completion = completions(marked, JsonEditorKind.outbound).single;
    final edited = marked
        .replaceFirst('|', '')
        .replaceRange(completion.start, completion.end, completion.insertText);
    expect(edited, marked.replaceFirst('hrefP|', 'hrefPath'));
    expect(JsonDocument(edited).syntaxError, isNull);
  });

  test('XDrive service completion preserves surrounding user JSON', () {
    const marked =
        '{"streamSettings":{"xdriveSettings":{"service":"goo|","secrets":["user-value"],"future":{"a":1}}}}';
    final completion = completions(marked, JsonEditorKind.outbound).single;
    final source = marked.replaceFirst('|', '');
    final edited = source.replaceRange(
      completion.start,
      completion.end,
      completion.insertText,
    );
    expect(edited, marked.replaceFirst('goo|', 'google-drive'));
    expect(JsonDocument(edited).syntaxError, isNull);
    expect(jsonDecode(edited)['streamSettings']['xdriveSettings']['future'], {
      'a': 1,
    });
    expect(
      labels(
        '{"streamSettings":{"xdriveSettings":{"xmux":{"maxConnections":1,"max|"}}}}',
        JsonEditorKind.outbound,
      ),
      ['maxConcurrency'],
    );
  });

  test('TCP Fragment hints follow native mask paths in each JSON editor', () {
    for (final (kind, wrapper) in [
      (JsonEditorKind.outbound, '{"streamSettings":{BODY}}'),
      (JsonEditorKind.outbound, '{"outbounds":[{"streamSettings":{BODY}}]}'),
      (JsonEditorKind.raw, '{"inbounds":[{"streamSettings":{BODY}}]}'),
      (JsonEditorKind.raw, '{"outbounds":[{"streamSettings":{BODY}}]}'),
      (
        JsonEditorKind.advancedRouting,
        '{"outbounds":[{},{"protocol":"freedom","streamSettings":{BODY}}]}',
      ),
    ]) {
      String source(String body) =>
          wrapper.replaceFirst('BODY', '"finalmask":{"tcp":[{$body}]}');
      expect(labels(source('"type":"fr|"'), kind), ['fragment']);
      expect(labels(source('"type":"fragment","se|"'), kind), ['settings']);
      expect(labels(source('"type":"fragment","settings":{"len|"}'), kind), [
        'length',
        'lengths',
      ]);
      expect(labels(source('"type":"fragment","settings":{"del|"}'), kind), [
        'delay',
        'delays',
      ]);
      expect(labels(source('"type":"fragment","settings":{"max|"}'), kind), [
        'maxSplit',
      ]);
      expect(
        labels(source('"type":"fragment","settings":{"packets":"tl|"}'), kind),
        ['tlshello'],
      );
      expect(
        labels(source('"type":"fragment","settings":{"in|"}'), kind),
        isEmpty,
      );
      expect(
        labels(
          source('"type":"fragment","settings":{"length":100,"len|"}'),
          kind,
        ),
        ['lengths'],
      );
      expect(
        labels(source('"type":"future","settings":{"len|"}'), kind),
        isEmpty,
      );
    }
  });

  test('advanced FinalMask hints stay on Freedom helpers', () {
    String source(String body, {String protocol = 'freedom'}) =>
        '{"outbounds":[{},{"protocol":"$protocol","streamSettings":{$body}}]}';
    expect(labels(source('"fi|"'), JsonEditorKind.advancedRouting), [
      'finalmask',
    ]);
    expect(
      labels(
        source(
          '"finalmask":{"udp":[{"type":"noise","settings":{"noise":[{"type":"e|"}]}}]}',
        ),
        JsonEditorKind.advancedRouting,
      ),
      ['exp'],
    );
    for (final body in [
      '"finalmask":{"future":{"wsSettings":{"pa|"}}}',
      '"finalmask":{"future":{"grpcSettings":{"ser|"}}}',
      '"finalmask":{"future":{"mux":{"ena|"}}}',
    ]) {
      expect(labels(source(body), JsonEditorKind.advancedRouting), isEmpty);
    }
    for (final kind in [
      JsonEditorKind.customRouting,
      JsonEditorKind.advancedRouting,
    ]) {
      for (final protocol in ['dns', 'blackhole']) {
        expect(labels(source('"fi|"', protocol: protocol), kind), isEmpty);
        expect(
          labels(
            source('"finalmask":{"tcp":[{"type":"fr|"}]}', protocol: protocol),
            kind,
          ),
          isEmpty,
        );
      }
    }
    for (final marked in [
      '{"future":{"streamSettings":{"finalmask":{"tcp":[{"type":"fr|"}]}}}}',
      '{"streamSettings":{"future":{"finalmask":{"tcp":[{"type":"fr|"}]}}}}',
      '{"streamSettings":{"finalmask":{"udp":[{"type":"fragment","settings":{"len|"}}]}}}',
    ]) {
      expect(labels(marked, JsonEditorKind.outbound), isEmpty);
    }
  });

  test(
    'keepalive hints cover both native values without extending templates',
    () {
      for (final (kind, wrapper) in [
        (JsonEditorKind.outbound, '{"streamSettings":{"sockopt":{BODY}}}'),
        (
          JsonEditorKind.raw,
          '{"outbounds":[{"streamSettings":{"sockopt":{BODY}}}]}',
        ),
        (
          JsonEditorKind.raw,
          '{"inbounds":[{"streamSettings":{"sockopt":{BODY}}}]}',
        ),
      ]) {
        expect(labels(wrapper.replaceFirst('BODY', '"tcpKeepAlive|"'), kind), [
          'tcpKeepAliveIdle',
          'tcpKeepAliveInterval',
        ]);
        expect(
          labels(
            wrapper.replaceFirst(
              'BODY',
              '"tcpKeepAliveIdle":90,"tcpKeepAlive|"',
            ),
            kind,
          ),
          ['tcpKeepAliveInterval'],
        );
      }
      expect(
        labels(
          '{"outbounds":[{},{"protocol":"freedom","streamSettings":{"sockopt":{"tcpKeepAlive|"}}}]}',
          JsonEditorKind.advancedRouting,
        ),
        isEmpty,
      );
    },
  );

  test('Freedom final rules get owned fields and native action candidates', () {
    for (final (kind, wrapper) in [
      (JsonEditorKind.outbound, '{"protocol":"freedom","settings":{BODY}}'),
      (
        JsonEditorKind.outbound,
        '{"outbounds":[{"protocol":"freedom","settings":{BODY}}]}',
      ),
      (
        JsonEditorKind.raw,
        '{"outbounds":[{"protocol":"freedom","settings":{BODY}}]}',
      ),
      (
        JsonEditorKind.advancedRouting,
        '{"outbounds":[{},{"protocol":"freedom","settings":{BODY}}]}',
      ),
    ]) {
      String source(String body) => wrapper.replaceFirst('BODY', body);
      expect(labels(source('"fi|"'), kind), ['finalRules']);
      expect(labels(source('"finalRules":[{"|"}]'), kind), [
        'action',
        'network',
        'port',
        'ip',
        'blockDelay',
      ]);
      expect(labels(source('"finalRules":[{"action":"|"}]'), kind), [
        'allow',
        'block',
      ]);
      expect(labels(source('"finalRules":[{"network":"|"}]'), kind), [
        'tcp',
        'udp',
        'tcp,udp',
      ]);
      expect(
        labels(source('"finalRules":[{"blockDelay":"|"}]'), kind),
        isEmpty,
      );
      final suggestions = completions(
        source('"finalRules":[{"ip":["private|"]}]'),
        kind,
        domains: ['geosite:PRIVATE'],
        ips: ['geoip:PRIVATE', 'ext:fixture.dat:PRIVATE'],
      );
      expect(
        suggestions.map((s) => s.label),
        unorderedEquals(['geoip:PRIVATE', 'ext:fixture.dat:PRIVATE']),
      );
      expect(labels(source('"frag|"'), kind), ['fragment']);
      expect(labels(source('"noi|"'), kind), ['noises']);
    }
    for (final marked in [
      '{"protocol":"dns","settings":{"finalRules":[{"action":"|"}]}}',
      '{"future":{"protocol":"freedom","settings":{"finalRules":[{"action":"|"}]}}}',
      '{"inbounds":[{"protocol":"freedom","settings":{"finalRules":[{"action":"|"}]}}]}',
    ]) {
      expect(labels(marked, JsonEditorKind.raw), isEmpty);
    }
    expect(
      labels(
        '{"outbounds":[{},{"protocol":"freedom","settings":{"fi|"}}]}',
        JsonEditorKind.customRouting,
      ),
      isEmpty,
    );
    expect(
      completions(
        '{"protocol":"socks","settings":{"finalRules":[{"ip":["private|"]}]}}',
        JsonEditorKind.outbound,
        ips: ['geoip:PRIVATE'],
      ),
      isEmpty,
    );
  });

  test('XDNS completes names and addrs in UDP masks without old fields', () {
    String source(String settings) =>
        '{"outbounds":[{"streamSettings":{"finalmask":{"udp":[{"type":"XDNS","settings":{$settings}}]}}}]}';
    expect(labels(source('"ex|"'), JsonEditorKind.raw), ['extraPoll']);
    expect(labels(source('"domains":[{"na|"}]'), JsonEditorKind.raw), [
      'names',
    ]);
    expect(labels(source('"domains":[{"len|"}]'), JsonEditorKind.raw), [
      'lenLimit',
    ]);
    expect(labels(source('"resolvers":[{"ad|"}]'), JsonEditorKind.raw), [
      'addrs',
    ]);
    expect(
      labels(source('"resolvers":[{"ty|"}]'), JsonEditorKind.raw),
      isEmpty,
    );
    expect(
      labels(source('"resolvers":[{"type":"u|"}]'), JsonEditorKind.raw),
      isEmpty,
    );
    expect(
      labels(
        source('"resolvers":[{"type":"tcp","settings":{"ad|"}}]'),
        JsonEditorKind.raw,
      ),
      isEmpty,
    );
    expect(
      labels('{"future":{"domains":[{"na|"}]}}', JsonEditorKind.raw),
      isEmpty,
    );
    expect(labels(source('"ex|"'), JsonEditorKind.advancedRouting), isEmpty);
  });

  test('noise expressions and UDPHop fields follow their UDP mask owner', () {
    String source(String type, String settings, {String network = 'udp'}) =>
        '{"streamSettings":{"finalmask":{"$network":[{"type":"$type","settings":{$settings}}]}}}';
    expect(
      labels(source('noise', '"noise":[{"ty|"}]'), JsonEditorKind.outbound),
      ['type'],
    );
    expect(
      labels(
        source('noise', '"noise":[{"type":"e|"}]'),
        JsonEditorKind.outbound,
      ),
      ['exp'],
    );
    expect(
      labels(
        source('noise', '"noise":[{"packet":"<|"}]'),
        JsonEditorKind.outbound,
      ),
      isEmpty,
    );
    expect(
      labels(
        source('xdns', '"noise":[{"type":"e|"}]'),
        JsonEditorKind.outbound,
      ),
      isEmpty,
    );
    expect(
      labels(
        source('noise', '"noise":[{"type":"e|"}]', network: 'tcp'),
        JsonEditorKind.outbound,
      ),
      isEmpty,
    );
    expect(labels(source('UDPHOP', '"re|"'), JsonEditorKind.outbound), [
      'remoteIPs',
      'remotePorts',
    ]);
    expect(labels(source('UDPHOP', '"so|"'), JsonEditorKind.outbound), isEmpty);
    expect(
      labels(source('UDPHOP', '"sockopt":{"in|"}'), JsonEditorKind.outbound),
      isEmpty,
    );
  });

  test('XDNS resolves nested TLS ECH and QUIC completion contexts', () {
    for (final (kind, wrapper) in [
      (JsonEditorKind.outbound, '{"streamSettings":{BODY}}'),
      (JsonEditorKind.outbound, '{"outbounds":[{"streamSettings":{BODY}}]}'),
      (JsonEditorKind.raw, '{"inbounds":[{"streamSettings":{BODY}}]}'),
      (JsonEditorKind.raw, '{"outbounds":[{"streamSettings":{BODY}}]}'),
    ]) {
      String resolver(
        String body, {
        String type = 'XDNS',
        String net = 'udp',
      }) => wrapper.replaceFirst(
        'BODY',
        '"finalmask":{"$net":[{"type":"$type","settings":{"resolvers":[{$body}]}}]}',
      );
      expect(labels(resolver('"|"'), kind), [
        'addrs',
        'worker',
        'tlsConfig',
        'quicConfig',
      ]);
      expect(labels(resolver('"tlsConfig":{"ech|"}'), kind), [
        'echConfigList',
        'echSockopt',
      ]);
      expect(labels(resolver('"tlsConfig":{"alpn":["h|"]}'), kind), [
        'h2',
        'http/1.1',
        'h3',
      ]);
      expect(labels(resolver('"tlsConfig":{"echSockopt":{"hap|"}}'), kind), [
        'happyEyeballs',
      ]);
      expect(
        labels(
          resolver('"tlsConfig":{"echSockopt":{"domainStrategy":"ForceI|"}}'),
          kind,
        ),
        containsAll(['ForceIP', 'ForceIPv4', 'ForceIPv6']),
      );
      expect(
        labels(
          resolver('"tlsConfig":{"echSockopt":{"happyEyeballs":{"try|"}}}'),
          kind,
        ),
        ['tryDelayMs'],
      );
      expect(labels(resolver('"quicConfig":{"disable|"}'), kind), [
        'disablePathMTUDiscovery',
        'disableChromeParrot',
        'disableGSO',
        'disableStatelessReset',
      ]);
      expect(labels(resolver('"quicConfig":{"congestion":"b|"}'), kind), [
        'bbr',
        'brutal',
      ]);
      expect(labels(resolver('"quicConfig":{"bbrProfile":"a|"}'), kind), [
        'aggressive',
      ]);
      expect(labels(resolver('"quicConfig":{"maxIncoming|"}'), kind), [
        'maxIncomingStreams',
      ]);
      expect(
        labels(resolver('"tlsConfig":{"|"}', type: 'noise'), kind),
        isEmpty,
      );
      expect(labels(resolver('"wo|"', net: 'tcp'), kind), isEmpty);
    }
    for (final kind in [
      JsonEditorKind.customRouting,
      JsonEditorKind.advancedRouting,
    ]) {
      expect(
        labels(
          '{"outbounds":[{"streamSettings":{"finalmask":{"quicParams":{"con|"}}}}]}',
          kind,
        ),
        isEmpty,
      );
    }
    for (final marked in [
      '{"future":{"tlsConfig":{"ech|"}}}',
      '{"future":{"streamSettings":{"finalmask":{"quicParams":{"con|"}}}}}',
      '{"streamSettings":{"future":{"resolvers":[{"wo|"}]}}}',
      '{"streamSettings":{"tlsSettings":{"future":{"echSockopt":{"hap|"}}}}}',
      '{"future":{"realitySettings":{"mld|"}}}',
    ]) {
      expect(labels(marked, JsonEditorKind.outbound), isEmpty);
    }
  });

  test('stream TLS and QUIC reuse nested field and value suggestions', () {
    expect(
      labels(
        '{"streamSettings":{"tlsSettings":{"echSockopt":{"hap|"}}}}',
        JsonEditorKind.outbound,
      ),
      ['happyEyeballs'],
    );
    expect(
      labels(
        '{"streamSettings":{"realitySettings":{"mld|"}}}',
        JsonEditorKind.outbound,
      ),
      ['mldsa65Verify'],
    );
    expect(
      labels(
        '{"streamSettings":{"finalmask":{"quicParams":{"congestion":"r|"}}}}',
        JsonEditorKind.outbound,
      ),
      ['reno'],
    );
    expect(
      labels(
        '{"streamSettings":{"finalmask":{"quicParams":{"disableG|"}}}}',
        JsonEditorKind.outbound,
      ),
      ['disableGSO'],
    );
  });

  test('TLS and MASQUE WARP keys follow the stream owner and editor mode', () {
    for (final kind in [JsonEditorKind.outbound, JsonEditorKind.raw]) {
      String source(String stream) => kind == JsonEditorKind.outbound
          ? '{"streamSettings":{$stream}}'
          : '{"outbounds":[{"streamSettings":{$stream}}]}';
      expect(labels(source('"tlsSettings":{"use|"}'), kind), ['useSystemCA']);
      expect(labels(source('"tlsSettings":{"pin|"}'), kind), [
        'pinnedPeerCertSha256',
      ]);
      expect(labels(source('"tlsSettings":{"ver|"}'), kind), [
        'verifyPeerCertByName',
      ]);
      expect(labels(source('"tlsSettings":{"allow|"}'), kind), isEmpty);
      expect(labels(source('"masqueSettings":{"wa|"}'), kind), ['warp']);
      expect(labels(source('"masqueSettings":{"warp":{"|"}}'), kind), [
        'privateKey',
        'publicKey',
        'address',
      ]);
    }
    for (final body in [
      '"tlsSettings":{"use|"}',
      '"masqueSettings":{"wa|"}',
      '"masqueSettings":{"warp":{"pri|"}}',
      '"hysteriaSettings":{"ver|"}',
    ]) {
      expect(labels('{"future":{$body}}', JsonEditorKind.raw), isEmpty);
      expect(
        labels(
          '{"outbounds":[{}, {"streamSettings":{$body}}]}',
          JsonEditorKind.advancedRouting,
        ),
        isEmpty,
      );
    }
    const original =
        '{"streamSettings":{"tlsSettings":{"allowInsecure":true}}}';
    expect(JsonDocument(original).syntaxError, isNull);
  });

  test('Hysteria protocol transport and settings complete in node and Raw', () {
    for (final kind in [JsonEditorKind.outbound, JsonEditorKind.raw]) {
      String source(String body) => kind == JsonEditorKind.outbound
          ? '{$body}'
          : '{"outbounds":[{$body}]}';
      expect(labels(source('"protocol":"hy|"'), kind), ['hysteria']);
      expect(labels(source('"streamSettings":{"network":"hy|"}'), kind), [
        'hysteria',
      ]);
      expect(labels(source('"streamSettings":{"hy|"}'), kind), [
        'hysteriaSettings',
      ]);
      expect(labels(source('"protocol":"hysteria","settings":{"|"}'), kind), [
        'version',
        'address',
        'port',
      ]);
      expect(
        labels(source('"streamSettings":{"hysteriaSettings":{"|"}}'), kind),
        ['version', 'auth', 'udpIdleTimeout', 'masquerade'],
      );
      expect(
        labels(
          source(
            '"streamSettings":{"hysteriaSettings":{"masquerade":{"type":"p|"}}}',
          ),
          kind,
        ),
        ['proxy'],
      );
    }
    expect(labels('{"inbounds":[{"protocol":"hy|"}]}', JsonEditorKind.raw), [
      'hysteria',
    ]);
    expect(
      labels(
        '{"inbounds":[{"protocol":"hysteria","settings":{"|"}}]}',
        JsonEditorKind.raw,
      ),
      ['version', 'users'],
    );
    expect(
      labels(
        '{"inbounds":[{"protocol":"hysteria","settings":{"users":[{"|"}]}}]}',
        JsonEditorKind.raw,
      ),
      ['auth', 'level', 'email'],
    );
    expect(
      labels(
        '{"outbounds":[{}, {"protocol":"hy|"}]}',
        JsonEditorKind.advancedRouting,
      ),
      isEmpty,
    );
  });

  test(
    'DNS cache and answer filters follow the normal and advanced contracts',
    () {
      for (final kind in [
        JsonEditorKind.customRouting,
        JsonEditorKind.advancedRouting,
        JsonEditorKind.raw,
      ]) {
        expect(labels('{"dns":{"serve|"}}', kind), [
          'servers',
          'serveStale',
          'serveExpiredTTL',
        ]);
        expect(labels('{"dns":{"enable|"}}', kind), ['enableParallelQuery']);
        expect(labels('{"dns":{"servers":[{"time|"}]}}', kind), ['timeoutMs']);
        expect(labels('{"dns":{"servers":[{"ex|"}]}}', kind), ['expectedIPs']);
        expect(labels('{"dns":{"servers":[{"un|"}]}}', kind), [
          'unexpectedIPs',
        ]);
        expect(labels('{"dns":{"servers":[{"serve|"}]}}', kind), [
          'serveStale',
          'serveExpiredTTL',
        ]);
        for (final field in ['expectedIPs', 'expectIPs', 'unexpectedIPs']) {
          expect(
            completions(
              '{"dns":{"servers":[{"$field":["cn|"]}]}}',
              kind,
              domains: ['geosite:CN'],
              ips: ['geoip:CN'],
            ).map((value) => value.label),
            ['geoip:CN'],
          );
        }
        expect(labels('{"dns":{"scr|"}}', kind), isEmpty);
        expect(labels('{"dns":{"servers":[{"id|"}]}}', kind), isEmpty);
      }
      for (final prefix in ['dom', 'fin', 'qu', 'skip', 'host']) {
        expect(
          labels(
            '{"dns":{"servers":[{"$prefix|"}]}}',
            JsonEditorKind.customRouting,
          ),
          isEmpty,
        );
      }
      expect(
        labels('{"dns":{"qu|"}}', JsonEditorKind.advancedRouting),
        isEmpty,
      );
      expect(
        labels('{"dns":{"servers":[{"qu|"}]}}', JsonEditorKind.advancedRouting),
        isEmpty,
      );
      expect(
        completions(
          '{"future":{"expectedIPs":["cn|"]}}',
          JsonEditorKind.raw,
          ips: ['geoip:CN'],
        ),
        isEmpty,
      );
    },
  );

  test('managed selectors and observation subjects remain generated by App', () {
    for (final kind in [
      JsonEditorKind.customRouting,
      JsonEditorKind.advancedRouting,
    ]) {
      expect(labels('{"ob|"}', kind), ['observatory']);
      expect(labels('{"routing":{"ba|"}}', kind), ['balancers']);
      expect(labels('{"routing":{"balancers":[{"tag":"p|"}]}}', kind), [
        'proxy',
      ]);
      expect(
        labels('{"routing":{"balancers":[{"tag":"proxy","str|"}]}}', kind),
        ['strategy'],
      );
      expect(
        labels(
          '{"routing":{"balancers":[{"tag":"proxy","strategy":{"type":"|"}}]}}',
          kind,
        ),
        ['roundRobin', 'leastPing'],
      );
      expect(labels('{"observatory":{"|"}}', kind), [
        'probeURL',
        'probeInterval',
        'enableConcurrency',
      ]);
      for (final prefix in ['sel', 'fall']) {
        expect(
          labels(
            '{"routing":{"balancers":[{"tag":"proxy","$prefix|"}]}}',
            kind,
          ),
          isEmpty,
        );
      }
      expect(
        labels(
          '{"routing":{"balancers":[{"tag":"proxy","strategy":{"se|"}}]}}',
          kind,
        ),
        isEmpty,
      );
      expect(labels('{"observatory":{"sub|"}}', kind), isEmpty);
      expect(
        labels(
          '{"routing":{"balancers":[{"tag":"other","strategy":{"type":"|"}}]}}',
          kind,
        ),
        isEmpty,
      );
    }
    expect(labels('{"in|"}', JsonEditorKind.customRouting), ['inbounds']);
    expect(labels('{"inbounds":[{"|"}]}', JsonEditorKind.customRouting), [
      'tag',
      'sniffing',
    ]);
    expect(
      labels('{"inbounds":[{"tag":"t|"}]}', JsonEditorKind.customRouting),
      ['tunIn'],
    );
    expect(
      labels('{"inbounds":[{"pro|"}]}', JsonEditorKind.customRouting),
      isEmpty,
    );
    expect(
      labels(
        '{"inbounds":[{"tag":"tunIn","sniffing":{"meta|"}}]}',
        JsonEditorKind.customRouting,
      ),
      ['metadataOnly'],
    );
    expect(
      labels(
        '{"outbounds":[{"streamSettings":{"tlsSettings":{"use|"}}}]}',
        JsonEditorKind.customRouting,
      ),
      isEmpty,
    );
    expect(
      labels(
        '{"routing":{"balancers":[{"strategy":{"type":"least|"}}]}}',
        JsonEditorKind.raw,
      ),
      ['leastPing', 'leastLoad'],
    );
    expect(labels('{"observatory":{"sub|"}}', JsonEditorKind.raw), [
      'subjectSelector',
    ]);
  });

  test('offers only token-end replacements, including unfinished strings', () {
    const source = '{"中文😀":true,\r\n"protocol":"vl|';
    final suggestion = completions(source, JsonEditorKind.outbound).single;
    final text = source.replaceFirst('|', '');
    expect(text.substring(suggestion.start, suggestion.end), 'vl');
    expect(suggestion.end, text.length);
    expect(suggestion.insertText, 'vless');
    expect(labels('{"protocol":"v|less"}', JsonEditorKind.outbound), isEmpty);
    expect(labels('{"pro|tocol":"vless"}', JsonEditorKind.outbound), isEmpty);
    expect(labels('{"protocol":"vl"|}', JsonEditorKind.outbound), isEmpty);
    expect(labels('{"protocol":"vl|\n}', JsonEditorKind.outbound), isEmpty);
    expect(labels(r'{"protocol":"v\|', JsonEditorKind.outbound), isEmpty);
    expect(labels(r'{"prot\u006fcol":"vl|"}', JsonEditorKind.outbound), [
      'vless',
    ]);
  });

  test(
    'does not suggest passwords, addresses, UUIDs or unknown value fields',
    () {
      for (final field in [
        'id',
        'password',
        'address',
        'serverName',
        'futureField',
      ]) {
        expect(labels('{"$field":"v|"}', JsonEditorKind.outbound), isEmpty);
      }
      expect(
        labels('{"futureField":{"anything":"|"}}', JsonEditorKind.raw),
        isEmpty,
      );
      expect(
        JsonDocument('{"futureField":{"anything":"manual"}}').syntaxError,
        isNull,
      );
    },
  );

  test(
    'custom and advanced dictionaries follow existing editor boundaries',
    () {
      expect(labels('{"lo|"}', JsonEditorKind.advancedRouting), isEmpty);
      expect(labels('{"lo|"}', JsonEditorKind.raw), ['log']);
      expect(labels('{"routing":{"ba|"}}', JsonEditorKind.advancedRouting), [
        'balancers',
      ]);
      expect(
        labels('{"routing":{"rules":[{"in|"}]}}', JsonEditorKind.customRouting),
        isEmpty,
      );
      expect(
        labels(
          '{"routing":{"rules":[{"in|"}]}}',
          JsonEditorKind.advancedRouting,
        ),
        ['inboundTag'],
      );
      expect(
        labels(
          '{"outbounds":[{}, {"protocol":"v|"}]}',
          JsonEditorKind.advancedRouting,
        ),
        isEmpty,
      );
      expect(
        labels(
          '{"outbounds":[{}, {"protocol":"fr|"}]}',
          JsonEditorKind.advancedRouting,
        ),
        ['freedom'],
      );
      expect(
        labels(
          '{"inbounds":[{"protocol":"s|"}]}',
          JsonEditorKind.advancedRouting,
        ),
        ['socks'],
      );
      expect(
        labels(
          '{"inbounds":[{"tag":"tunIn","pro|"}]}',
          JsonEditorKind.advancedRouting,
        ),
        isEmpty,
      );
      expect(
        labels('{"dns":{"qu|"}}', JsonEditorKind.advancedRouting),
        isEmpty,
      );
      expect(
        labels(
          '{"routing":{"rules":[{"protocol":["ht|"]}]}}',
          JsonEditorKind.raw,
        ),
        ['http'],
      );
    },
  );

  test('tag namespaces and generated tags stay distinct', () {
    String source(String field) =>
        '{"outbounds":[{"tag":"exit-a"}],"inbounds":[{"tag":"entry-a"}],"routing":{"balancers":[{"tag":"pool-a"}],"rules":[{"$field":"|"}]}}';
    expect(labels(source('outboundTag'), JsonEditorKind.raw), ['exit-a']);
    expect(labels(source('balancerTag'), JsonEditorKind.raw), ['pool-a']);
    expect(labels(source('inboundTag'), JsonEditorKind.raw), ['entry-a']);
    expect(labels(source('dialerProxy'), JsonEditorKind.raw), ['exit-a']);
    expect(labels(source('outboundTag'), JsonEditorKind.advancedRouting), [
      'direct',
      'block',
      'exit-a',
    ]);
    expect(labels(source('balancerTag'), JsonEditorKind.advancedRouting), [
      'proxy',
    ]);
    expect(labels(source('dialerProxy'), JsonEditorKind.advancedRouting), [
      'direct',
      'block',
      'exit-a',
    ]);
    expect(labels(source('outboundTag'), JsonEditorKind.customRouting), [
      'direct',
      'block',
    ]);
    expect(
      labels('{"routing":{"rules":[{"outboundTag":"|"}]}}', JsonEditorKind.raw),
      isEmpty,
    );
    expect(
      labels(
        '{"outbounds":[{"tag":"app-entry-0"},{"tag":"proxy"}],"routing":{"rules":[{"outboundTag":"|"}]}}',
        JsonEditorKind.advancedRouting,
      ),
      ['direct', 'block'],
    );
  });

  test(
    'DNS outbound candidates use current rules without mixing legacy policy',
    () {
      String settings(String body) =>
          '{"outbounds":[{}, {"protocol":"dns","settings":{$body}}]}';
      expect(labels(settings('"r|"'), JsonEditorKind.advancedRouting), [
        'rules',
        'rewriteNetwork',
        'rewriteAddress',
        'rewritePort',
      ]);
      expect(
        labels(
          settings('"rules":[{"action":"hijack"}],"non|"'),
          JsonEditorKind.advancedRouting,
        ),
        isEmpty,
      );
      expect(
        labels(settings('"rules":[{"q|"}]'), JsonEditorKind.advancedRouting),
        ['qType'],
      );
      expect(
        labels(
          settings('"rules":[{"action":"dr|"}]'),
          JsonEditorKind.advancedRouting,
        ),
        ['drop'],
      );
      expect(
        labels(settings('"rules":[{"action":"re|"}]'), JsonEditorKind.raw),
        ['return'],
      );
      expect(
        labels(
          settings('"rewriteNetwork":"u|"'),
          JsonEditorKind.advancedRouting,
        ),
        ['udp'],
      );
      expect(
        labels(
          '{"protocol":"dns","settings":{"ru|"}}',
          JsonEditorKind.outbound,
        ),
        ['rules'],
      );
      final domain = completions(
        settings('"rules":[{"domain":["geo|"]}]'),
        JsonEditorKind.advancedRouting,
        domains: ['geosite:CN'],
        ips: ['geoip:CN'],
      );
      expect(domain.map((value) => value.label), ['geosite:CN']);
      expect(
        JsonDocument('{"protocol":"dns","settings":{"nonIPQuery":"drop"}}')
            .syntaxError,
        isNull,
      );
    },
  );

  test('account fields follow the protocol and inbound or outbound direction', () {
    for (final protocol in ['socks', 'http']) {
      for (final field in ['users', 'accounts']) {
        expect(
          labels(
            '{"inbounds":[{"protocol":"$protocol","settings":{"$field":[{"|"}]}}]}',
            JsonEditorKind.advancedRouting,
          ),
          ['user', 'pass'],
        );
      }
      expect(
        labels(
          '{"outbounds":[{"protocol":"$protocol","settings":{"servers":[{"users":[{"|"}]}]}}]}',
          JsonEditorKind.raw,
        ),
        ['user', 'pass', 'level', 'email'],
      );
    }
    expect(
      labels(
        '{"protocol":"vless","settings":{"vnext":[{"users":[{"|"}]}]}}',
        JsonEditorKind.outbound,
      ),
      ['id', 'encryption', 'flow', 'level', 'email'],
    );
    expect(
      labels(
        '{"protocol":"vmess","settings":{"vnext":[{"users":[{"|"}]}]}}',
        JsonEditorKind.outbound,
      ),
      ['id', 'security', 'level', 'email'],
    );
    expect(
      labels(
        '{"settings":{"vnext":[{"users":[{"|"}]}]}}',
        JsonEditorKind.outbound,
      ),
      isEmpty,
    );
    expect(labels('{"future":{"users":[{"|"}]}}', JsonEditorKind.raw), isEmpty);
    expect(
      labels(
        '{"inbounds":[{"protocol":"socks","settings":{"users":[{"security":"a|"}]}}]}',
        JsonEditorKind.advancedRouting,
      ),
      isEmpty,
    );
    expect(
      labels(
        '{"protocol":"vmess","settings":{"vnext":[{"users":[{"security":"a|"}]}]}}',
        JsonEditorKind.outbound,
      ),
      ['auto', 'aes-128-gcm'],
    );
  });

  test('discovers later definitions and escapes inserted tag contents', () {
    const source =
        r'{"routing":{"rules":[{"outboundTag":"出|"}]},"outbounds":[{"tag":"出口\"😀"}]}';
    final result = completions(source, JsonEditorKind.raw).single;
    expect(result.label, '出口"😀');
    expect(result.insertText, r'出口\"😀');
    final updated = source
        .replaceFirst('|', '')
        .replaceRange(result.start, result.end, result.insertText);
    expect(JsonDocument(updated).syntaxError, isNull);
  });

  test(
    'geodata uses supplied installed candidates only in matching positions',
    () {
      const domains = ['geosite:CN', 'ext:domains.dat:LOCAL'];
      const ips = ['geoip:CN', 'ext:ips.dat:LOCAL'];
      final domain = completions(
        '{"routing":{"rules":[{"domain":["geo|"]}]}}',
        JsonEditorKind.raw,
        domains: domains,
        ips: ips,
      );
      expect(domain.map((value) => value.label), ['geosite:CN']);
      final ip = completions(
        '{"routing":{"rules":[{"ip":["geo|"]}]}}',
        JsonEditorKind.raw,
        domains: domains,
        ips: ips,
      );
      expect(ip.map((value) => value.label), ['geoip:CN']);
      expect(
        completions(
          '{"address":"geo|"}',
          JsonEditorKind.raw,
          domains: domains,
          ips: ips,
        ),
        isEmpty,
      );
      expect(
        completions(
          '{"routing":{"rules":[{"domain":["geo|"]}]}}',
          JsonEditorKind.raw,
        ),
        isEmpty,
      );
      final many = completions(
        '{"routing":{"rules":[{"domain":["geo|"]}]}}',
        JsonEditorKind.raw,
        domains: List.generate(30, (i) => 'geosite:C$i'),
      );
      expect(many.length, 10);
      final byCategory = completions(
        '{"routing":{"rules":[{"domain":["cn|"]}]}}',
        JsonEditorKind.raw,
        domains: ['geosite:BRAND@CN', 'geosite:CN', 'ext:other.dat:CN'],
      );
      expect(byCategory.map((value) => value.label), [
        'ext:other.dat:CN',
        'geosite:CN',
        'geosite:BRAND@CN',
      ]);
      final ipCategory = completions(
        '{"routing":{"rules":[{"ip":["cn|"]}]}}',
        JsonEditorKind.raw,
        domains: domains,
        ips: ['geoip:CN'],
      );
      expect(ipCategory.single.label, 'geoip:CN');
      expect(
        labels(
          '{"outbounds":[{"tag":"exit-cn"}],"routing":{"rules":[{"outboundTag":"cn|"}]}}',
          JsonEditorKind.raw,
        ),
        isEmpty,
      );
    },
  );
}
