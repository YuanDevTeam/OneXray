import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'OneXray',
      packageName: 'net.yuandev.onexray',
      version: '26.10.3',
      buildNumber: '103',
      buildSignature: '',
    );
  });

  for (final customUserAgent in [null, '  v2rayNG/2.2.6  ']) {
    test(
      'Remnawave ${customUserAgent == null ? "default" : "custom"} UA selects JSON at the original URL',
      () async {
        final bus = AppEventBus();
        addTearDown(bus.close);
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final provider = {
          'remarks': 'Provider profile',
          'dns': {
            'servers': ['1.1.1.1'],
          },
          'routing': {
            'rules': [
              {
                'type': 'field',
                'domain': ['example.com'],
                'outboundTag': 'proxy',
              },
            ],
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
        };
        const channel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.onexray.BridgeHostApi.invoke',
          BridgeHostApi.pigeonChannelCodec,
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockDecodedMessageHandler(channel, (request) async {
          final invoke = jsonDecode((request as List).single as String) as Map;
          expect(invoke['method'], anyOf('decodeSubscriptionText', 'testXray'));
          return [
            jsonEncode({
              'success': true,
              'error': '',
              if (invoke['method'] == 'decodeSubscriptionText')
                'data': {'text': invoke['payload']['text']},
            }),
          ];
        });
        addTearDown(
          () => messenger.setMockDecodedMessageHandler(channel, null),
        );

        final defaultUserAgent =
            'v2rayN/26.10.3 OneXray/26.10.3 '
            '(net.yuandev.onexray; build:103; ${Platform.operatingSystem})';
        final expectedUserAgent = customUserAgent?.trim() ?? defaultUserAgent;
        final requests = <RequestOptions>[];
        final client =
            Dio(BaseOptions(headers: {'User-Agent': 'System/browser'}))
              ..httpClientAdapter = _SubscriptionResponse((request) {
                requests.add(request);
                return ResponseBody.fromString(
                  (request.headers['User-Agent'] == 'v2rayNG/2.2.6' ||
                          request.headers['User-Agent'] == defaultUserAgent)
                      ? jsonEncode([provider])
                      : base64Encode(
                          utf8.encode('socks://127.0.0.1:1080#Node'),
                        ),
                  200,
                  headers: {
                    'Subscription-Userinfo': [
                      'upload=10;download=20;total=100',
                    ],
                  },
                );
              });
        addTearDown(client.close);
        final pings = <int>[];
        final service = SubscriptionService.forTesting(
          database: database,
          client: NetClient.forTesting(client),
          schedulePing: pings.add,
        );
        const url = 'https://provider.example/sub/example?token=test';
        final generic = await service.insertSubscription(
          const SubscriptionInput(
            name: 'Provider',
            url: url,
            mode: SubscriptionMode.providerManaged,
          ),
        );
        expect(generic.status, SubscriptionUpdateResult.invalidContent);
        expect(await database.subscriptionDao.allRows, isEmpty);
        expect(requests.single.headers['User-Agent'], 'System/browser');
        requests.clear();

        final inserted = await service.insertSubscription(
          SubscriptionInput(
            name: 'Provider',
            url: url,
            userAgent: customUserAgent,
            panel: SubscriptionPanel.remnawave,
            ageSecretKey: 'test-secret',
            agePublicKey: 'test-public',
            hwidEnabled: true,
            hwid: 'test-device',
          ),
        );
        expect(inserted.error, isNull);
        expect(inserted.success, isTrue);
        expect(inserted.count, 1);
        final source = (await database.subscriptionDao.searchRow(
          inserted.subId,
        ))!;
        expect(source.url, url);
        expect(source.userAgent, customUserAgent?.trim());
        expect(source.mode, SubscriptionMode.providerManaged.name);
        expect(source.uploadBytes, 10);
        final saved = (await database.select(database.coreConfig).get())
            .singleWhere((row) => row.type == CoreConfigType.Remnawave.name);
        expect(jsonDecode(utf8.decode(base64Decode(saved.data!))), provider);

        final refreshed = await service.refreshSubscriptionResult(source);
        expect(refreshed.error, isNull);
        expect(refreshed.success, isTrue);
        expect(refreshed.count, 1);
        expect(requests, hasLength(2));
        for (final request in requests) {
          expect(request.uri.toString(), url);
          expect(request.headers['User-Agent'], expectedUserAgent);
          expect(request.headers['X-Age-Public-Key'], 'test-public');
          expect(request.headers['x-hwid'], 'test-device');
        }
        expect(pings, isEmpty);
        expect(client.options.headers['User-Agent'], 'System/browser');

        final before = await database.select(database.coreConfig).get();
        expect(
          await service.saveSubscriptionInput(
            source.id,
            SubscriptionInput(
              name: source.name,
              url: source.url,
              userAgent: 'Unsupported/1.0',
              panel: SubscriptionPanel.remnawave,
            ),
          ),
          SubscriptionUpdateResult.success,
        );
        final cleared = (await database.subscriptionDao.searchRow(source.id))!;
        expect(cleared.userAgent, 'Unsupported/1.0');
        expect(cleared.userInfoUpdatedAt, isNull);
        final failed = await service.refreshSubscriptionResult(cleared);
        expect(failed.status, SubscriptionUpdateResult.remnawaveFormatMismatch);
        expect(await database.subscriptionDao.searchRow(source.id), cleared);
        expect(await database.select(database.coreConfig).get(), before);
        expect(requests, hasLength(3));
        expect(requests.last.uri.toString(), url);
        expect(requests.last.headers['User-Agent'], 'Unsupported/1.0');

        expect(
          await service.saveSubscriptionInput(
            source.id,
            SubscriptionInput(
              name: source.name,
              url: source.url,
              panel: SubscriptionPanel.remnawave,
            ),
          ),
          SubscriptionUpdateResult.success,
        );
        final reset = (await database.subscriptionDao.searchRow(source.id))!;
        expect(reset.userAgent, isNull);
        final fallback = await service.refreshSubscriptionResult(reset);
        expect(fallback.success, isTrue);
        expect(requests.last.uri.toString(), url);
        expect(requests.last.headers['User-Agent'], defaultUserAgent);
        expect(client.options.headers['User-Agent'], 'System/browser');
      },
    );
  }
}

class _SubscriptionResponse implements HttpClientAdapter {
  _SubscriptionResponse(this.respond);

  final ResponseBody Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}
