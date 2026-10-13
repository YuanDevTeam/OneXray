import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/reader.dart';

const _input = SubscriptionInput(
  name: 'Source',
  url: 'https://example.com/sub',
);

Map<String, dynamic> _config(String name) => {
  'remarks': name,
  'dns': {
    'hosts': {'example.com': '203.0.113.1'},
  },
  'routing': {
    'rules': [
      {
        'domain': ['example.com'],
        'outboundTag': 'proxy',
      },
    ],
  },
  'outbounds': [
    {
      'tag': 'proxy',
      'protocol': 'socks',
      'settings': {'address': '127.0.0.1', 'port': 1080},
      'mux': {'enabled': true},
    },
    {'tag': 'direct', 'protocol': 'freedom'},
  ],
};

SubscriptionConfigurationReader _reader({
  Future<String> Function(String, {String? ageSecretKey})? decode,
  Future<String> Function(String)? validate,
  Future<List<CoreConfigCompanion>> Function(String)? readNodes,
}) => SubscriptionConfigurationReader(
  decode: decode ?? ((text, {ageSecretKey}) async => text),
  validate: validate ?? ((_) async => ''),
  readNodes:
      readNodes ??
      ((_) async => throw StateError('Complete JSON reached the node parser')),
  withFiles: (action) => action(),
);

Map<String, dynamic> _saved(CoreConfigCompanion row) =>
    jsonDecode(utf8.decode(base64Decode(row.data.value!)))
        as Map<String, dynamic>;

void main() {
  test('native validation uses tunnel adaptation while stored provider JSON stays original', () async {
    final source = _config('Ingress');
    source['inbounds'] = [
      {
        'tag': 'provider',
        'protocol': 'socks',
        'port': 1080,
        'sniffing': {
          'enabled': true,
          'destOverride': ['tls'],
        },
      },
    ];
    (source['routing']['rules'] as List).first['inboundTag'] = ['provider'];
    Map<String, dynamic>? validation;
    final result = await _reader(
      validate: (text) async {
        validation = jsonDecode(text) as Map<String, dynamic>;
        return '';
      },
    ).read(jsonEncode(source), _input);
    final inbounds = validation!['inbounds'] as List;
    expect(inbounds.where((value) => value['tag'] == 'tunIn'), hasLength(1));
    expect(inbounds.first['protocol'], 'socks');
    expect(
      inbounds.first['sniffing'],
      (source['inbounds'] as List).single['sniffing'],
    );
    final rules = validation!['routing']['rules'] as List;
    expect(rules.first['port'], '53');
    expect(rules.first['outboundTag'], 'app-remna-dns');
    expect(rules.last['inboundTag'], ['provider', 'tunIn']);
    expect(_saved(result.rows.first), source);
  });

  test('provider tunnel DNS rules survive validation while source JSON remains original', () async {
    final source = _config('Existing tunnel');
    source['inbounds'] = [
      {
        'tag': 'provider-tun',
        'protocol': 'tun',
        'settings': {'userLevel': 5},
        'sniffing': {'enabled': false, 'routeOnly': true},
      },
    ];
    (source['outbounds'] as List).add({
      'tag': 'provider-dns',
      'protocol': 'dns',
      'settings': {'address': '9.9.9.9', 'port': 5353},
    });
    (source['routing'] as Map)['rules'] = [
      {
        'type': 'field',
        'inboundTag': ['provider-tun'],
        'port': 53,
        'outboundTag': 'provider-dns',
      },
      {
        'type': 'field',
        'inboundTag': ['provider-tun'],
        'domain': ['example.com'],
        'outboundTag': 'proxy',
      },
    ];
    final before = jsonEncode(source);
    Map<String, dynamic>? validation;
    final result = await _reader(
      validate: (text) async {
        validation = jsonDecode(text) as Map<String, dynamic>;
        return '';
      },
    ).read(before, _input);
    final tunnel = (validation!['inbounds'] as List).single;
    expect(tunnel['tag'], 'tunIn');
    expect(tunnel['protocol'], 'socks');
    expect(tunnel['sniffing'], source['inbounds'][0]['sniffing']);
    final rules = validation!['routing']['rules'] as List;
    expect(rules, hasLength(2));
    expect(rules.first, {
      ...source['routing']['rules'][0] as Map<String, dynamic>,
      'inboundTag': ['tunIn'],
    });
    expect(rules.last['inboundTag'], ['tunIn']);
    final dns = (validation!['outbounds'] as List).where(
      (value) => value['protocol'] == 'dns',
    );
    expect(dns, [source['outbounds'][2]]);
    expect(_saved(result.rows.first), source);
    expect(jsonEncode(source), before);
    expect(result.count, 1);
  });

  test(
    'different provider ingress policies reach Core without a Dart rejection',
    () async {
      final conflicting = _config('Conflicting ingress')
        ..['inbounds'] = [
          {
            'tag': 'one',
            'protocol': 'socks',
            'port': 1080,
            'sniffing': {'enabled': true},
          },
          {
            'tag': 'two',
            'protocol': 'http',
            'port': 1081,
            'sniffing': {'enabled': false},
          },
        ];
      Map<String, dynamic>? validation;
      final result = await _reader(
        validate: (text) async {
          validation = jsonDecode(text) as Map<String, dynamic>;
          return '';
        },
      ).read(jsonEncode(conflicting), _input);
      expect(
        (validation!['inbounds'] as List).where(
          (value) => value['tag'] == 'one' || value['tag'] == 'two',
        ),
        conflicting['inbounds'],
      );
      expect(_saved(result.rows.first), conflicting);
      expect(result.count, 1);
    },
  );

  test(
    'multiple profiles preserve complete objects and default to provider mode',
    () async {
      final sources = [_config('First'), _config('Second')];
      final result = await _reader().read(jsonEncode(sources), _input);
      expect(result.mode, SubscriptionMode.providerManaged);
      expect(result.count, 2);
      final complete = result.rows
          .where((row) => row.type.value == 'Remnawave')
          .toList();
      expect(complete.map((row) => row.name.value), ['First', 'Second']);
      expect(complete.map(_saved), sources);
      expect(
        result.rows.where((row) => row.type.value == 'outbound'),
        hasLength(2),
      );
      expect(sources.first.containsKey('name'), isFalse);
    },
  );

  test(
    'App mode derives independent proxies without trimming chain references',
    () async {
      final config = _config('Chain');
      final outbounds = config['outbounds'] as List;
      outbounds.add({
        'tag': 'chained',
        'protocol': 'socks',
        'proxySettings': {'tag': 'proxy'},
      });
      final result = await _reader().read(
        jsonEncode(config),
        const SubscriptionInput(
          name: 'Source',
          url: 'https://example.com/sub',
          mode: SubscriptionMode.appManaged,
        ),
      );
      expect(result.count, 1);
      expect(_saved(result.rows.first)['outbounds'], outbounds);
      expect(_saved(result.rows.last)['outbounds'], [outbounds.first]);
      (outbounds.first as Map)['streamSettings'] = {
        'sockopt': {'dialerProxy': 'chained'},
      };
      await expectLater(
        _reader().read(
          jsonEncode(config),
          const SubscriptionInput(
            name: 'Source',
            url: 'https://example.com/sub',
            mode: SubscriptionMode.appManaged,
          ),
        ),
        throwsFormatException,
      );
      final provider = await _reader().read(jsonEncode(config), _input);
      expect(provider.count, 1);
    },
  );

  test('Age plaintext is classified before projection and keeps fallback metadata separate', () async {
    final config = _config('');
    String? secret;
    final reader = _reader(
      decode: (text, {ageSecretKey}) async {
        expect(text, 'encrypted');
        secret = ageSecretKey;
        return jsonEncode(config);
      },
    );
    final result = await reader.read(
      'encrypted',
      const SubscriptionInput(
        name: 'Source',
        url: 'https://example.com/sub',
        ageSecretKey: 'secret',
        agePublicKey: 'public',
      ),
    );
    expect(secret, 'secret');
    expect(result.rows.first.name.value, 'Source 1');
    expect(_saved(result.rows.first), config);
  });

  test(
    'invalid JSON envelopes fail before Core or ordinary node parsing',
    () async {
      for (final text in [
        '[]',
        '[1]',
        jsonEncode([_config('Valid'), 1]),
        '{"outbounds":',
        '[{"outbounds":[]},',
      ]) {
        await expectLater(
          _reader(
            validate: (_) async =>
                throw StateError('Invalid envelope reached Core validation'),
          ).read(text, _input),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'invalid outbound protocols reach Core intact and retain its error',
    () async {
      for (final protocol in [null, '', 'unsupported-protocol']) {
        final outbound = {'tag': 'invalid-proxy', 'protocol': protocol};
        final config = _config('Invalid')..['outbounds'] = [outbound];
        Map<String, dynamic>? validation;
        const coreError = 'Core rejected the outbound protocol';
        await expectLater(
          _reader(
            validate: (text) async {
              validation = jsonDecode(text) as Map<String, dynamic>;
              return coreError;
            },
          ).read(jsonEncode(config), _input),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              coreError,
            ),
          ),
        );
        expect(
          (validation!['outbounds'] as List).singleWhere(
            (value) => value['tag'] == 'invalid-proxy',
          ),
          outbound,
        );
      }
    },
  );

  test(
    'complete candidates rejected by Core do not fall back to node parsing',
    () async {
      for (final config in [
        {
          'user': {'name': 'Guest'},
        },
        {
          'remarks': 'Sing-box',
          'outbounds': [
            {'type': 'socks'},
          ],
        },
      ]) {
        var reachedCore = false;
        const coreError = 'Core rejected the configuration';
        await expectLater(
          _reader(
            validate: (_) async {
              reachedCore = true;
              return coreError;
            },
          ).read(jsonEncode(config), _input),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              coreError,
            ),
          ),
        );
        expect(reachedCore, isTrue);
      }
    },
  );

  test(
    'a later Core error rejects the entire array without a partial result',
    () async {
      final validated = <String>[];
      const coreError = 'Core rejected the second configuration';
      final configs = [
        _config('First'),
        _config('Second')
          ..['outbounds'] = [
            {'tag': 'invalid-proxy', 'protocol': ''},
          ],
        _config('Third'),
      ];
      await expectLater(
        _reader(
          validate: (text) async {
            final value = jsonDecode(text) as Map<String, dynamic>;
            final name = value['remarks'] as String;
            validated.add(name);
            return name == 'Second' ? coreError : '';
          },
        ).read(jsonEncode(configs), _input),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            coreError,
          ),
        ),
      );
      expect(validated, ['First', 'Second']);
    },
  );

  test('native validation failures propagate through the reader', () async {
    final failure = StateError('Native validation unavailable');
    await expectLater(
      _reader(validate: (_) async => throw failure)
          .read(jsonEncode(_config('Native failure')), _input),
      throwsA(same(failure)),
    );
  });

  for (final outbounds in [null, <Map<String, dynamic>>[]]) {
    test(
      'Core can accept a provider with ${outbounds == null ? 'missing' : 'empty'} source outbounds',
      () async {
        final config = {
          'remarks': 'DNS only',
          'dns': {
            'servers': ['1.1.1.1'],
          },
          'outbounds': ?outbounds,
        };
        Map<String, dynamic>? validation;
        final result = await _reader(
          validate: (text) async {
            validation = jsonDecode(text) as Map<String, dynamic>;
            return '';
          },
        ).read(jsonEncode(config), _input);
        expect(
          (validation!['outbounds'] as List).where(
            (value) => value['protocol'] == 'dns',
          ),
          hasLength(1),
        );
        expect(result.mode, SubscriptionMode.providerManaged);
        expect(result.count, 1);
        expect(result.rows, hasLength(1));
        expect(_saved(result.rows.single), config);
        await expectLater(
          _reader().read(
            jsonEncode(config),
            const SubscriptionInput(
              name: 'Source',
              url: 'https://example.com/sub',
              mode: SubscriptionMode.appManaged,
            ),
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'The selected mode contains no usable configurations',
            ),
          ),
        );
      },
    );
  }

  test('ordinary node text keeps the existing parser and explicit panel format is checked', () async {
    final reader = _reader(
      readNodes: (text) async {
        expect(text, 'vless://node');
        return [
          CoreConfigCompanion.insert(
            name: 'Node',
            type: 'outbound',
            tags: '',
            delay: 9000,
            subId: 0,
          ),
        ];
      },
    );
    final result = await reader.read('vless://node', _input);
    expect(result.mode, SubscriptionMode.appManaged);
    expect(result.count, 1);
    await expectLater(
      reader.read(
        'vless://node',
        const SubscriptionInput(
          name: 'Source',
          url: 'https://example.com/sub',
          panel: SubscriptionPanel.remnawave,
        ),
      ),
      throwsFormatException,
    );
  });
}
