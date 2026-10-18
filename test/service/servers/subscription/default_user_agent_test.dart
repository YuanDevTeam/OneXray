import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/reader.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'blank subscriptions retain the initialized fallback UA after recovery',
    () async {
      final bus = AppEventBus();
      addTearDown(bus.close);
      const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var attempts = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        if (attempts++ == 0) {
          throw PlatformException(code: 'temporarily-unavailable');
        }
        return {
          'appName': 'OneXray',
          'packageName': 'net.yuandev.onexray',
          'version': '26.10.4',
          'buildNumber': '104',
          'buildSignature': '',
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await NetClient().asyncInit();
      final initializedUserAgent = NetClient().downloadUserAgent;
      expect(initializedUserAgent, startsWith('v2rayN/0.0.0 '));
      expect((await PackageInfo.fromPlatform()).version, '26.10.4');
      expect(attempts, 2);

      // Keep the real initialized default, replacing only the HTTP transport.
      final recorder = _SubscriptionResponse();
      final dio = Dio(
        BaseOptions(headers: {'User-Agent': initializedUserAgent}),
      )..httpClientAdapter = recorder;
      addTearDown(dio.close);
      final client = NetClient.forTesting(dio);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final service = SubscriptionService.forTesting(
        database: database,
        client: client,
        configurationReader: SubscriptionConfigurationReader(
          decode: (text, {ageSecretKey}) async => text,
          validate: (_) async => '',
          withFiles: (action) => action(),
        ),
        schedulePing: (_) {},
      );

      await client.getText('https://data.example/file', httpsOnly: true);
      final defaultSubscription = await service.insertSubscription(
        const SubscriptionInput(
          name: 'Default UA',
          url: 'https://provider.example/default',
          mode: SubscriptionMode.providerManaged,
        ),
      );
      expect(defaultSubscription.success, isTrue);
      await client.getText('https://data.example/file', httpsOnly: true);

      final customSubscription = await service.insertSubscription(
        const SubscriptionInput(
          name: 'Custom UA',
          url: 'https://provider.example/custom',
          userAgent: '  CustomClient/1.0  ',
          mode: SubscriptionMode.providerManaged,
        ),
      );
      expect(customSubscription.success, isTrue);
      await client.getText('https://data.example/file', httpsOnly: true);

      expect(recorder.userAgents, [
        initializedUserAgent,
        initializedUserAgent,
        initializedUserAgent,
        'CustomClient/1.0',
        initializedUserAgent,
      ]);
      expect(client.downloadUserAgent, initializedUserAgent);
      expect(NetClient().downloadUserAgent, initializedUserAgent);
    },
  );
}

class _SubscriptionResponse implements HttpClientAdapter {
  final userAgents = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    userAgents.add(options.headers['User-Agent']?.toString());
    return ResponseBody.fromString(
      jsonEncode([
        {
          'remarks': 'Provider profile',
          'dns': {
            'servers': ['1.1.1.1'],
          },
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'socks',
              'settings': {
                'servers': [
                  {'address': '127.0.0.1', 'port': 1080},
                ],
              },
            },
          ],
        },
      ]),
      200,
    );
  }

  @override
  void close({bool force = false}) {}
}
