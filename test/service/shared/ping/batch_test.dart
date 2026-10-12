import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/ping/state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("empty ping batch returns no results", () async {
    final results = await PingBatchRunner.run(const [], PingState());

    expect(results, isEmpty);
  });

  test('native request contains only the delay test configuration', () async {
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.onexray.BridgeHostApi.invoke',
      BridgeHostApi.pigeonChannelCodec,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final payloads = <Map>[];
    messenger.setMockDecodedMessageHandler(channel, (request) async {
      final json = jsonDecode((request as List).single as String) as Map;
      expect(json['apiVersion'], 3);
      expect(json['method'], 'pingBatch');
      payloads.add(json['payload'] as Map);
      return [
        jsonEncode({
          'success': true,
          'error': '',
          'data': {
            'results': [
              {'success': true, 'delay': 0},
              {'success': true, 'delay': 20},
            ],
          },
        }),
      ];
    });
    addTearDown(() => messenger.setMockDecodedMessageHandler(channel, null));
    const sources = [
      PingBatchSource('{"outbounds":[]}', outboundTag: 'proxy'),
      PingBatchSource('{"outbounds":[{"protocol":"freedom"}]}'),
    ];
    final state = PingState()
      ..timeout = 8
      ..url = PingUrl.custom
      ..customUrl = 'https://example.com/ping';

    final first = await PingBatchRunner.run(sources, state);

    final expected = {
      'configs': [
        {'xrayJson': sources[0].xrayJson, 'outboundTag': 'proxy'},
        {'xrayJson': sources[1].xrayJson},
      ],
      'timeout': 8,
      'url': 'https://example.com/ping',
    };
    expect(payloads, [expected]);
    expect(first.map((result) => result.delay), [0, 20]);
  }, skip: !(Platform.isMacOS || Platform.isIOS || Platform.isAndroid));
}
