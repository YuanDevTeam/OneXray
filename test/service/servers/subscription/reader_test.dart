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
    final conflicting = _config('Conflicting ingress')
      ..['inbounds'] = [
        {
          'tag': 'one',
          'protocol': 'socks',
          'sniffing': {'enabled': true},
        },
        {
          'tag': 'two',
          'protocol': 'http',
          'sniffing': {'enabled': false},
        },
      ];
    await expectLater(
      _reader().read(jsonEncode([source, conflicting]), _input),
      throwsFormatException,
    );
  });

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
    'invalid full arrays fail as a unit without falling back to node parsing',
    () async {
      for (final text in [
        '[]',
        '[1]',
        '{"user":{"name":"Guest"}}',
        jsonEncode([
          _config('Valid'),
          {'outbounds': []},
        ]),
        jsonEncode({
          'remarks': 'Sing-box',
          'outbounds': [
            {'type': 'socks'},
          ],
        }),
        '{"outbounds":',
      ]) {
        await expectLater(_reader().read(text, _input), throwsFormatException);
      }
      await expectLater(
        _reader(validate: (_) async => 'Invalid core configuration')
            .read(jsonEncode(_config('Invalid')), _input),
        throwsFormatException,
      );
    },
  );

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
