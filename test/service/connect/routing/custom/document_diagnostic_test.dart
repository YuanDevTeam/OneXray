import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/document.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('both Custom parsers retain syntax offsets in the original source', () {
    const text = '{\r\n "name": "😀", "outbounds": [#]\r\n}';
    for (final parse in [
      (String value) => RoutingProfileDocument.parse(value),
      (String value) => AdvancedRoutingDocument.parse(value),
    ]) {
      expect(
        () => parse(text),
        throwsA(
          isA<FormatException>().having(
            (e) => JsonDiagnostic.fromError(e)?.offset,
            'original offset',
            text.indexOf('#'),
          ),
        ),
      );
    }
  });

  test('ordinary fields retain literal keys and nested array indices', () {
    for (final (document, path, message)
        in <(Map<String, dynamic>, List<Object>, String)>[
          (
            {
              'outbounds': [{}],
              'odd.key[3]': false,
            },
            ['odd.key[3]'],
            'Unsupported field: template.odd.key[3]',
          ),
          (
            {
              'outbounds': [{}],
              'dns': {
                'servers': [
                  {'tag': 'app-dns-direct', 'address': '1.1.1.1'},
                  false,
                ],
              },
            },
            ['dns', 'servers', 1],
            'dns.servers[1] must be an object',
          ),
          (
            {
              'outbounds': [{}],
              'routing': {
                'rules': [
                  {'balancerTag': 'proxy'},
                  {'type': 'field'},
                ],
              },
            },
            ['routing', 'rules', 1, 'type'],
            'Unsupported field: routing.rules[1].type',
          ),
          (
            {
              'outbounds': [{}],
              'routing': {
                'rules': [
                  {'balancerTag': 'proxy'},
                  {'outboundTag': 'unknown'},
                ],
              },
            },
            ['routing', 'rules', 1],
            'Routing rule must select exactly one supported action',
          ),
          (
            {
              'outbounds': [{}, {}],
              'name': 42,
            },
            ['name'],
            'name must contain 1–32 characters',
          ),
        ]) {
      expect(
        () => RoutingProfileDocument.parse(jsonEncode(document)),
        throwsA(_diagnostic(path, message)),
      );
    }
  });

  test(
    'ordinary imports reject retired DNS fields at their original paths',
    () {
      for (final field in [
        'serveStale',
        'serveExpiredTTL',
        'enableParallelQuery',
      ]) {
        expect(
          () => RoutingProfileDocument.fromJson({
            'outbounds': [{}],
            'dns': {
              field: false,
              'servers': [
                {'tag': 'app-dns-proxy', 'address': '1.1.1.1'},
              ],
            },
          }),
          throwsA(_diagnostic(['dns', field], 'Unsupported field: dns.$field')),
        );
      }
      for (final field in [
        'expectedIPs',
        'expectIPs',
        'unexpectedIPs',
        'serveStale',
        'serveExpiredTTL',
        'timeoutMs',
        'disableCache',
      ]) {
        expect(
          () => RoutingProfileDocument.fromJson({
            'outbounds': [{}],
            'dns': {
              'servers': [
                {'tag': 'app-dns-proxy', 'address': '1.1.1.1', field: null},
              ],
            },
          }),
          throwsA(
            _diagnostic([
              'dns',
              'servers',
              0,
              field,
            ], 'Unsupported field: dns.servers[0].$field'),
          ),
        );
      }
    },
  );

  test(
    'advanced App checks identify precise members without changing messages',
    () {
      for (final (patch, path, message)
          in <(Map<String, dynamic>, List<Object>, String)>[
            (
              {
                'inbounds': [
                  {'tag': 'tunIn'},
                  false,
                ],
              },
              ['inbounds', 1],
              'inbounds must be an object',
            ),
            (
              {
                'dns': {
                  'servers': [
                    '8.8.8.8',
                    {'address': '1.1.1.1', 'queryStrategy': 'UseIP'},
                  ],
                },
              },
              ['dns', 'servers', 1, 'queryStrategy'],
              'dns.servers[1].queryStrategy is managed by OneXray; use App settings',
            ),
            (
              {
                'routing': {
                  'rules': [
                    {
                      'balancerTag': 'proxy',
                      'inboundTag': ['dns', 'app-entry-0'],
                    },
                  ],
                },
              },
              ['routing', 'rules', 0, 'inboundTag', 1],
              'routing.rules[0].inboundTag is managed by OneXray; use App settings',
            ),
            (
              {
                'outbounds': [
                  {},
                  {
                    'tag': 'dnsOut',
                    'protocol': 'dns',
                    'streamSettings': {
                      'sockopt': {'interface': 'en0'},
                    },
                  },
                ],
              },
              ['outbounds', 1, 'streamSettings', 'sockopt', 'interface'],
              'Unsupported or App-managed field: outbounds[1].streamSettings.sockopt.interface',
            ),
            (
              {
                'outbounds': [
                  {},
                  {'tag': 'extra', 'protocol': 'freedom'},
                  {'tag': 'extra', 'protocol': 'dns'},
                ],
              },
              ['outbounds', 2, 'tag'],
              'Duplicate tag: extra',
            ),
          ]) {
        expect(
          () => AdvancedRoutingDocument.parse(
            jsonEncode({
              'outbounds': [{}],
              ...patch,
            }),
          ),
          throwsA(_diagnostic(path, message)),
        );
      }
    },
  );

  test('metadata reports the original asset index and specific URL field', () {
    final text = jsonEncode({
      'outbounds': [{}],
      'geodata': {
        'assets': [
          {'file': 'first.dat', 'url': 'https://example.com/first.dat'},
          {'file': 'second.dat', 'url': 'http://example.com/second.dat'},
        ],
      },
    });
    for (final parse in [
      (String value) => RoutingProfileDocument.parse(value),
      (String value) => AdvancedRoutingDocument.parse(value),
    ]) {
      expect(
        () => parse(text),
        throwsA(
          _diagnostic([
            'geodata',
            'assets',
            1,
            'url',
          ], 'An HTTPS Geodata URL is required'),
        ),
      );
    }
  });

  test(
    'compiled core errors stay verbatim with no guessed source location',
    () async {
      const error = 'routing.rules[2].port: invalid (offset 48)';
      final state = AdvancedRoutingDocument.parse('{"outbounds":[{}]}').state;
      await expectLater(
        CustomRoutingService.validate(state, testXray: (_) async => error),
        throwsA(
          isA<AppFailure>()
              .having((e) => e.cause, 'core message', error)
              .having((e) => JsonDiagnostic.fromError(e), 'diagnostic', isNull),
        ),
      );
    },
  );
}

Matcher _diagnostic(List<Object> path, String message) => isA<JsonDiagnostic>()
    .having((e) => e.path, 'JSON path', path)
    .having((e) => e.offset, 'offset', isNull)
    .having((e) => e.message, 'unchanged message', message);
