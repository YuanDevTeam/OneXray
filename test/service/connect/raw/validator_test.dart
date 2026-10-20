import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/service/connect/raw/validator.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/share/configuration_source.dart';

const source = '''
  {
    "name": "Expert",
    "inbounds": [{"tag":"custom","protocol":"socks","port":12345}],
    "outbounds": [{"tag":"direct","protocol":"freedom"}],
    "routing": {"rules":[{"inboundTag":["custom"],"outboundTag":"direct"}]},
    "policy": {"levels":{"0":{"connIdle":123}},"system":{"statsOutboundUplink":true}},
    "metrics": {"listen":"127.0.0.1:12346"},
    "stats": {},
    "env": {"xray.location.asset":"/user/assets","xray.location.cert":"/user/certs","other":"retained"},
    "log": {"access":"/user/access.log","error":"/user/error.log","loglevel":"debug"},
    "customRoot": {"value":true}
  }

''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('syntax diagnostics retain the original UTF-16 source offset', () {
    const text = '{\r\n "name": "😀",\r\n "outbounds": [#]\r\n}';
    expect(
      () => XrayRawValidator.normalize(text, nameOverride: 'Renamed'),
      throwsA(
        isA<JsonDiagnostic>()
            .having((error) => error.offset, 'offset', text.indexOf('#'))
            .having((error) => error.path, 'path', isNull),
      ),
    );
  });

  test('App root and name checks expose structured paths', () {
    final bus = AppEventBus();
    addTearDown(bus.close);
    expect(
      () => XrayRawValidator.normalize('[]'),
      throwsA(
        isA<JsonDiagnostic>()
            .having((error) => error.path, 'path', isEmpty)
            .having((error) => error.offset, 'offset', isNull),
      ),
    );
    expect(
      () => XrayRawValidator.normalize('{"name":42,"outbounds":[]}'),
      throwsA(
        isA<JsonDiagnostic>()
            .having((error) => error.path, 'path', ['name'])
            .having((error) => error.offset, 'offset', isNull),
      ),
    );
  });

  test(
    'core text with a path or offset does not become a source location',
    () async {
      const error = 'routing.rules[1]: invalid field (offset 34)';
      await expectLater(
        XrayRawValidator.validate(source, testXray: (_) async => error),
        throwsA(
          isA<AppFailure>()
              .having(
                (failure) => failure.category,
                'category',
                FailureCategory.configuration,
              )
              .having((failure) => failure.cause, 'core error', error)
              .having(
                (failure) => JsonDiagnostic.fromError(failure),
                'diagnostic',
                isNull,
              ),
        ),
      );
    },
  );

  test('ordinary normalization preserves every byte and expert field', () {
    final result = XrayRawValidator.normalize(source);
    expect(result.name, 'Expert');
    expect(result.text, source);
    expect(
      XrayRawValidator.normalize(source, nameOverride: 'Expert').text,
      source,
    );
    expect(result.json, jsonDecode(source));
    expect(XrayRawValidator.normalize(source, nameOverride: ' ').text, source);
  });

  test('explicit name override only changes the root name', () {
    final result = XrayRawValidator.normalize(
      source,
      nameOverride: ' Renamed ',
    );
    final expected = jsonDecode(source) as Map<String, dynamic>;
    expected['name'] = 'Renamed';
    expect(result.name, 'Renamed');
    expect(jsonDecode(result.text), expected);
  });

  test('renaming parsed input does not change its source text or map', () {
    final parsed = ConfigurationSource.parse(source);
    final renamed = XrayRawValidator.normalizeParsed(
      parsed,
      nameOverride: 'Renamed',
    );
    expect(parsed.text, source);
    expect(parsed.value, jsonDecode(source));
    expect(renamed.json['name'], 'Renamed');
    expect(jsonDecode(renamed.text), renamed.json);
  });

  test(
    'instance validation projects App fields and returns the original source',
    () async {
      var calls = 0;
      final result = await XrayRawValidator.validate(
        source,
        testXray: (text) async {
          calls++;
          final actual = jsonDecode(text) as Map<String, dynamic>;
          final expected = jsonDecode(source) as Map<String, dynamic>;
          expected['env'] = {
            'xray.location.asset': VpnConstants.datDir,
            'xray.location.cert': VpnConstants.datDir,
            'other': 'retained',
          };
          expected['log'] = {
            'access': 'none',
            'error': 'none',
            'loglevel': 'none',
            'dnsLog': false,
          };
          expected.remove('metrics');
          expected['policy']['system'] = {};
          expect(actual['inbounds'].first['tag'], 'tunIn');
          expect(actual['inbounds'].first['protocol'], 'socks');
          expect(actual['routing']['rules'].first['port'], '53');
          expect(actual['outbounds'].last['protocol'], 'dns');
          // Check the user graph after excluding the bounded VPN supplements.
          actual['inbounds'] = (actual['inbounds'] as List).skip(1).toList();
          actual['outbounds'] = (actual['outbounds'] as List).take(1).toList();
          actual['routing']['rules'] = (actual['routing']['rules'] as List)
              .skip(1)
              .toList();
          expect(actual, expected);
          return '';
        },
      );
      expect(calls, 1);
      expect(result.text, source);
      expect(result.json, jsonDecode(source));
    },
  );

  test(
    'core construction errors reject save without returning a patched copy',
    () async {
      await expectLater(
        XrayRawValidator.validate(
          source,
          testXray: (_) async => 'Invalid inbound settings',
        ),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.cause,
            'core error',
            'Invalid inbound settings',
          ),
        ),
      );
    },
  );

  test('invalid native field shapes are reported by libXray', () async {
    const text = '{"name":"Expert","env":false,"outbounds":[]}';
    var calls = 0;
    await expectLater(
      XrayRawValidator.validate(
        text,
        testXray: (input) async {
          calls++;
          expect(jsonDecode(input)['env'], false);
          return 'Core rejected env';
        },
      ),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.cause,
          'core error',
          'Core rejected env',
        ),
      ),
    );
    expect(calls, 1);
  });

  test(
    'unavailable native validation preserves its original failure',
    () async {
      final error = PlatformException(
        code: 'unavailable',
        message: 'Core not loaded',
      );
      await expectLater(
        XrayRawValidator.validate(source, testXray: (_) async => throw error),
        throwsA(same(error)),
      );
    },
  );
}
