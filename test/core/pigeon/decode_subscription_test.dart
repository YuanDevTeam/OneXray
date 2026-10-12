import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('subscription decoder carries Age and returns complete plaintext', () async {
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.onexray.BridgeHostApi.invoke',
      BridgeHostApi.pigeonChannelCodec,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const complete =
        '[{"outbounds":[],"routing":{"rules":[]},"dns":{"servers":["fakedns"]}}]';
    messenger.setMockDecodedMessageHandler(channel, (message) async {
      final request = jsonDecode((message as List).single as String);
      expect(request, {
        'apiVersion': 3,
        'method': 'decodeSubscriptionText',
        'payload': {
          'text': 'armor',
          'age': {'secretKey': 'secret'},
        },
      });
      return [
        jsonEncode({
          'success': true,
          'data': {'text': complete},
          'error': '',
        }),
      ];
    });
    addTearDown(() => messenger.setMockDecodedMessageHandler(channel, null));
    expect(
      await AppHostApi().decodeSubscriptionText(
        'armor',
        ageSecretKey: ' secret ',
      ),
      complete,
    );
  }, skip: !(Platform.isMacOS || Platform.isIOS || Platform.isAndroid));
}
