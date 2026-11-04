import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/share/standard_outbound_share.dart';

void main() {
  for (final authenticated in [false, true]) {
    test(
      'legacy SOCKS ${authenticated ? "auth" : "anonymous"} uses a share-only flat copy',
      () async {
        final source = <String, dynamic>{
          'tag': 'Legacy SOCKS',
          'protocol': 'socks',
          'settings': {
            'servers': [
              {
                'address': '127.0.0.1',
                'port': 18080,
                if (authenticated)
                  'users': [
                    {'user': 'qa-user', 'pass': 'qa-password'},
                  ],
              },
            ],
          },
          'streamSettings': {
            'network': 'tcp',
            'security': 'tls',
            'tlsSettings': {'serverName': 'proxy.example.test'},
          },
        };
        final before = jsonEncode(source);
        final service = StandardOutboundShareService(
          encoder: (json) async {
            final outbound = (json['outbounds'] as List).single as Map;
            expect(outbound['tag'], 'Legacy SOCKS');
            expect(outbound['streamSettings'], source['streamSettings']);
            expect(outbound['settings'], {
              'address': '127.0.0.1',
              'port': 18080,
              if (authenticated) ...{'user': 'qa-user', 'pass': 'qa-password'},
            });
            // A native encoder must never receive a reference into the source.
            (outbound['streamSettings'] as Map)['network'] = 'ws';
            return authenticated
                ? 'socks://cWEtdXNlcjpxYS1wYXNzd29yZA==@127.0.0.1:18080#Legacy'
                : 'socks://Og==@127.0.0.1:18080#Legacy';
          },
        );
        final result = await service.encode(source);
        expect(Uri.parse(result).host, '127.0.0.1');
        expect(Uri.parse(result).port, 18080);
        expect(jsonEncode(source), before);
      },
    );
  }

  test(
    'flat SOCKS fields retain Core precedence over legacy servers',
    () async {
      final source = <String, dynamic>{
        'protocol': 'socks',
        'settings': {
          'address': 'flat.example.test',
          'port': 1080,
          'user': 'flat-user',
          'pass': 'flat-password',
          'servers': [
            {'address': 'ignored-a.example.test', 'port': 1},
            {'address': 'ignored-b.example.test', 'port': 2},
          ],
        },
      };
      final before = jsonEncode(source);
      final service = StandardOutboundShareService(
        encoder: (json) async {
          expect((json['outbounds'] as List).single, source);
          return 'socks://flat.example.test:1080';
        },
      );
      expect(await service.encode(source), 'socks://flat.example.test:1080');
      expect(jsonEncode(source), before);
    },
  );

  for (final settings in [
    {'servers': <Object>[]},
    {
      'servers': [
        {'address': 'a.example.test', 'port': 1080},
        {'address': 'b.example.test', 'port': 1080},
      ],
    },
    {
      'servers': [
        {
          'address': 'proxy.example.test',
          'port': 1080,
          'users': [
            {'user': 'first', 'pass': 'first-password'},
            {'user': 'second', 'pass': 'second-password'},
          ],
        },
      ],
    },
  ]) {
    test(
      'ambiguous SOCKS endpoint or credentials never reaches the encoder: $settings',
      () async {
        final service = StandardOutboundShareService(
          encoder: (_) async => fail('Ambiguous standard sharing must stop'),
        );
        await expectLater(
          service.encode({'protocol': 'socks', 'settings': settings}),
          throwsFormatException,
        );
      },
    );
  }

  for (final output in [
    'socks://Og==@<nil>:0#Legacy',
    'socks://Og==@%3Cnil%3E:1080',
    'socks://Og==@:1080',
    'socks://127.0.0.1:0',
    'socks://127.0.0.1:65536',
    'socks://127.0.0.1',
    'http://127.0.0.1:1080',
    'socks://127.0.0.1:1080\nsocks://127.0.0.2:1080',
    '',
  ]) {
    test('invalid SOCKS encoder output cannot be shared: $output', () async {
      final service = StandardOutboundShareService(
        encoder: (_) async => output,
      );
      await expectLater(
        service.encode({
          'protocol': 'socks',
          'settings': {'address': '127.0.0.1', 'port': 1080},
        }),
        throwsFormatException,
      );
    });
  }

  test(
    'SOCKS envelope guard does not reinterpret other standard formats',
    () async {
      const output = 'vmess://opaque-base64-payload';
      final source = {'protocol': 'vmess', 'settings': <String, dynamic>{}};
      final service = StandardOutboundShareService(
        encoder: (json) async {
          expect(json, {
            'outbounds': [source],
          });
          return output;
        },
      );
      expect(await service.encode(source), output);
    },
  );
}
