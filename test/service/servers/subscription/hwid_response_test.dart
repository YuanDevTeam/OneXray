import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations_en.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/servers/subscription/failure.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;

  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
    database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
  });

  final cases = [
    (
      {
        'x-hwid-not-supported': ['true'],
        'x-hwid-limit': ['true'],
      },
      SubscriptionUpdateResult.hwidRequired,
    ),
    (
      {
        'X-Hwid-Max-Devices-Reached': ['TRUE'],
        'x-hwid-limit': ['true'],
      },
      SubscriptionUpdateResult.hwidLimitReached,
    ),
    (
      {
        'x-hwid-limit': ['true'],
      },
      SubscriptionUpdateResult.hwidRejected,
    ),
    (
      {
        'x-hwid-active': ['true'],
        'x-hwid-limit': ['false'],
      },
      SubscriptionUpdateResult.downloadFailed,
    ),
  ];

  for (final (headers, expected) in cases) {
    for (final status in [200, 403]) {
      if (expected == SubscriptionUpdateResult.downloadFailed &&
          status == 200) {
        continue;
      }
      test(
        'HTTP $status / $expected is reported before parsing and preserves saved nodes',
        () async {
          final id = await database.subscriptionDao.insertRow(
            SubscriptionCompanion.insert(
              name: 'Provider',
              url: 'https://provider.example/sub',
              timestamp: DateTime.utc(2025),
              uploadBytes: const Value(10),
              downloadBytes: const Value(20),
              totalBytes: const Value(100),
              expireTimestamp: const Value(0),
              userInfoUpdatedAt: Value(DateTime.utc(2025)),
            ),
          );
          final row = (await database.subscriptionDao.searchRow(id))!;
          final nodeId = await database.coreConfigDao.insertRow(
            outboundCompanion({'tag': 'Saved node', 'protocol': 'socks'})
                .copyWith(subId: Value(id)),
          );
          final requests = <RequestOptions>[];
          final client = Dio()
            ..httpClientAdapter = _ResponseAdapter((options) {
              requests.add(options);
              return ResponseBody.fromString(
                // Providers can return remark-only subscriptions even with HTTP 200.
                'vless://00000000-0000-0000-0000-000000000000@example.com:443#Device%20limit',
                status,
                headers: {
                  ...headers,
                  'Subscription-Userinfo': [
                    'upload=0;download=0;total=0;expire=0',
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

          final result = await service.refreshSubscriptionResult(row);
          expect(result.status, expected);
          expect(result.success, isFalse);
          expect(await database.subscriptionDao.searchRow(id), row);
          expect(
            (await database.coreConfigDao.allOutboundRowsWithDataBySubId(id))
                .single
                .id,
            nodeId,
          );
          expect(requests.single.headers['x-hwid'], isNull);
          expect(pings, isEmpty);
          expect(AppEventBus.instance.state.downloading, isFalse);

          final added = await service.insertSubscription(
            const SubscriptionInput(
              name: 'New',
              url: 'https://provider.example/another',
              hwidEnabled: true,
              hwid: 'draft-device-identity',
              ageSecretKey: 'secret',
              agePublicKey: 'public',
            ),
          );
          expect(added.status, expected);
          expect(await database.subscriptionDao.allRows, [row]);
          expect(requests.last.headers['x-hwid'], 'draft-device-identity');
          expect(requests.last.headers['X-Age-Public-Key'], 'public');
          expect(pings, isEmpty);
          if (expected != SubscriptionUpdateResult.downloadFailed) {
            final l = AppLocalizationsEn();
            expect(result.error, isNull);
            expect(subscriptionFailureMessage(l, expected), switch (expected) {
              SubscriptionUpdateResult.hwidRequired =>
                l.subscriptionHwidRequired,
              SubscriptionUpdateResult.hwidLimitReached =>
                l.subscriptionHwidLimitReached,
              _ => l.subscriptionHwidRejected,
            });
          }
        },
      );
    }
  }

  test(
    'normal responses use saved consent; active alone never opts in',
    () async {
      const channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.onexray.BridgeHostApi.invoke',
        BridgeHostApi.pigeonChannelCodec,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var parsed = 0;
      messenger.setMockDecodedMessageHandler(channel, (request) async {
        final json = jsonDecode((request as List).single as String) as Map;
        expect(json['payload'], {'text': 'valid subscription'});
        if (json['method'] == 'decodeSubscriptionText') {
          return [
            jsonEncode({
              'success': true,
              'error': '',
              'data': {'text': json['payload']['text']},
            }),
          ];
        }
        expect(json['method'], 'convertShareLinksToXrayJson');
        parsed++;
        return [
          jsonEncode({
            'success': true,
            'error': '',
            'data': {
              'outbounds': [
                {'protocol': 'socks', 'tag': 'Node'},
              ],
            },
          }),
        ];
      });
      addTearDown(() => messenger.setMockDecodedMessageHandler(channel, null));
      final sent = <String?>[];
      String? userInfoHeader;
      final client = Dio()
        ..httpClientAdapter = _ResponseAdapter((options) {
          sent.add(options.headers['x-hwid'] as String?);
          return ResponseBody.fromString(
            'valid subscription',
            200,
            headers: {
              'x-hwid-active': ['true'],
              'x-hwid-limit': ['false'],
              if (userInfoHeader != null)
                'Subscription-Userinfo': [userInfoHeader],
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
      for (final enabled in [false, true]) {
        userInfoHeader = 'upload=100; download=200; total=1000; expire=0';
        final beforeDownload = DateTime.now().subtract(
          const Duration(seconds: 1),
        );
        final inserted = await service.insertSubscription(
          SubscriptionInput(
            name: 'Provider $enabled',
            url: 'https://provider.example/$enabled',
            hwidEnabled: enabled,
          ),
        );
        expect(inserted.success, isTrue);
        final row = (await database.subscriptionDao.searchRow(inserted.subId))!;
        expect(row.hwidEnabled, enabled);
        expect(sent.last, row.hwid);
        expect(row.hwid, enabled ? isNotNull : isNull);
        expect(row.uploadBytes, 100);
        expect(row.downloadBytes, 200);
        expect(row.totalBytes, 1000);
        expect(row.expireTimestamp, 0);
        expect(row.userInfoUpdatedAt!.isAfter(beforeDownload), isTrue);
        // A successful node refresh must neither fail on malformed metadata nor
        // retain a previous response's cache when metadata is absent.
        userInfoHeader = enabled ? null : 'upload=bad;total=-1;expire=NaN';
        expect((await service.refreshSubscriptionResult(row)).success, isTrue);
        final refreshed = (await database.subscriptionDao.searchRow(row.id))!;
        expect(refreshed.uploadBytes, isNull);
        expect(refreshed.downloadBytes, isNull);
        expect(refreshed.totalBytes, isNull);
        expect(refreshed.expireTimestamp, isNull);
        expect(refreshed.userInfoUpdatedAt, isNull);
        expect(sent.last, row.hwid);
        if (enabled) {
          await service.saveSubscriptionInput(
            row.id,
            SubscriptionInput(name: row.name, url: row.url),
          );
          expect(
            (await service.refreshSubscriptionResult(row)).success,
            isTrue,
          );
          expect(sent.last, isNull);
          expect(
            (await database.subscriptionDao.searchRow(row.id))!.hwid,
            row.hwid,
          );
        }
      }
      expect(parsed, 5);
      expect(pings, hasLength(5));
      expect(AppEventBus.instance.state.downloading, isFalse);
    },
    skip: !(Platform.isMacOS || Platform.isIOS || Platform.isAndroid),
  );
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.respond);
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
