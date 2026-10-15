import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

const _input = SubscriptionInput(
  name: 'Provider',
  url: 'https://provider.example/subscription',
  userAgent: 'Custom/1.0',
  panel: SubscriptionPanel.remnawave,
  mode: SubscriptionMode.providerManaged,
  ageSecretKey: 'secret',
  agePublicKey: 'public',
  hwidEnabled: true,
  hwid: 'test-device',
);

const _outbound = {
  'tag': 'Ordinary',
  'protocol': 'socks',
  'settings': {
    'servers': [
      {'address': '127.0.0.1', 'port': 1080},
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adding non-JSON requires consent and commits ordinary source with the same response', () async {
    final h = _Harness();
    final unconfirmed = await h.service.insertSubscription(_input);
    expect(
      unconfirmed.status,
      SubscriptionUpdateResult.remnawaveFormatMismatch,
    );
    expect(h.parsed, isEmpty);
    expect(await h.database.subscriptionDao.allRows, isEmpty);

    final declined = await h.service.insertSubscription(
      _input,
      confirmOrdinary: (_) async => false,
    );
    expect(failureCancelled(declined.error), isTrue);
    expect(h.parsed, isEmpty);
    expect(await h.database.subscriptionDao.allRows, isEmpty);

    final requestsBefore = h.requests.length;
    final accepted = await h.service.insertSubscription(
      _input,
      confirmOrdinary: (name) async {
        expect(name, _input.name);
        expect(h.parsed, isEmpty);
        expect(await h.database.subscriptionDao.allRows, isEmpty);
        return true;
      },
    );
    expect(accepted.success, isTrue);
    expect(accepted.count, 1);
    expect(h.requests.length - requestsBefore, 1);
    expect(h.parsed, [h.ordinaryResponse]);
    final source = (await h.database.subscriptionDao.searchRow(
      accepted.subId,
    ))!;
    _expectOrdinary(source);
    expect((await h.rows()).single.type, CoreConfigType.outbound.name);
    expect(h.pings, [source.id]);
  });

  test('native ordinary parse failure never creates a source', () async {
    final h = _Harness()..failNodes = true;
    final result = await h.service.insertSubscription(
      _input,
      confirmOrdinary: (_) async => true,
    );
    expect(result.status, SubscriptionUpdateResult.invalidContent);
    expect(await h.database.subscriptionDao.allRows, isEmpty);
    expect(await h.rows(), isEmpty);
    expect(h.pings, isEmpty);
  });

  test('refresh keeps old data on decline or parse failure and changes mode only on successful conversion', () async {
    final h = _Harness()..plain = false;
    final inserted = await h.service.insertSubscription(_input);
    expect(inserted.success, isTrue);
    final source = (await h.database.subscriptionDao.searchRow(
      inserted.subId,
    ))!;
    final oldRows = await h.rows();
    final selected = oldRows.singleWhere(
      (row) => row.type == CoreConfigType.Remnawave.name,
    );
    h.protectedId = selected.id;
    h.plain = true;

    final background = await h.service.refreshSubscriptionResult(source);
    expect(background.status, SubscriptionUpdateResult.remnawaveFormatMismatch);
    final declined = await h.service.refreshSubscriptionResult(
      source,
      confirmOrdinary: (_) async => false,
    );
    expect(failureCancelled(declined.error), isTrue);
    expect(h.parsed, isEmpty);
    expect(await h.database.subscriptionDao.searchRow(source.id), source);
    expect(await h.rows(), oldRows);

    h.failNodes = true;
    final failed = await h.service.refreshSubscriptionResult(
      source,
      confirmOrdinary: (_) async => true,
    );
    expect(failed.status, SubscriptionUpdateResult.invalidContent);
    expect(await h.database.subscriptionDao.searchRow(source.id), source);
    expect(await h.rows(), oldRows);

    h.failNodes = false;
    final requestsBefore = h.requests.length;
    final accepted = await h.service.refreshSubscriptionResult(
      source,
      confirmOrdinary: (_) async => true,
    );
    expect(accepted.success, isTrue);
    expect(accepted.count, 1);
    expect(h.requests.length - requestsBefore, 1);
    _expectOrdinary((await h.database.subscriptionDao.searchRow(source.id))!);
    final rows = await h.rows();
    expect(
      rows.singleWhere((row) => row.type == CoreConfigType.Remnawave.name),
      selected,
    );
    expect(
      rows.where((row) => row.type == CoreConfigType.outbound.name),
      hasLength(1),
    );
    expect(h.pings, [source.id]);
  });

  test(
    'an edit made while conversion waits for consent supersedes the refresh',
    () async {
      final h = _Harness()..plain = false;
      final inserted = await h.service.insertSubscription(_input);
      final source = (await h.database.subscriptionDao.searchRow(
        inserted.subId,
      ))!;
      final before = await h.rows();
      h.plain = true;
      final opened = Completer<void>();
      final decision = Completer<bool>();
      final refresh = h.service.refreshSubscriptionResult(
        source,
        confirmOrdinary: (_) {
          opened.complete();
          return decision.future;
        },
      );
      await opened.future;
      expect(
        await h.service.saveSubscriptionInput(
          source.id,
          const SubscriptionInput(
            name: 'Edited',
            url: 'https://provider.example/edited',
            panel: SubscriptionPanel.remnawave,
            mode: SubscriptionMode.providerManaged,
            userAgent: 'Custom/2.0',
          ),
        ),
        SubscriptionUpdateResult.success,
      );
      decision.complete(true);
      expect((await refresh).superseded, isTrue);
      final current = (await h.database.subscriptionDao.searchRow(source.id))!;
      expect(current.url, 'https://provider.example/edited');
      expect(current.panel, SubscriptionPanel.remnawave.name);
      expect(current.mode, SubscriptionMode.providerManaged.name);
      expect(await h.rows(), before);
      expect(h.pings, isEmpty);
    },
  );
}

void _expectOrdinary(SubscriptionData source) {
  expect(source.panel, SubscriptionPanel.generic.name);
  expect(source.mode, SubscriptionMode.appManaged.name);
  expect(source.url, _input.url);
  expect(source.userAgent, _input.userAgent);
  expect(source.ageSecretKey, _input.ageSecretKey);
  expect(source.agePublicKey, _input.agePublicKey);
  expect(source.hwid, _input.hwid);
  expect(source.hwidEnabled, isTrue);
  expect(source.uploadBytes, 10);
}

class _Harness {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  final client = Dio(BaseOptions(headers: {'User-Agent': 'OneXray/test'}));
  final requests = <RequestOptions>[];
  final parsed = <String>[];
  final pings = <int>[];
  final ordinaryResponse = base64Encode(
    utf8.encode('socks://127.0.0.1:1080#Ordinary'),
  );
  bool plain = true;
  bool failNodes = false;
  int? protectedId;
  late final SubscriptionService service;

  _Harness() {
    final bus = AppEventBus();
    addTearDown(bus.close);
    addTearDown(database.close);
    addTearDown(client.close);
    client.httpClientAdapter = _Adapter((request) {
      requests.add(request);
      return ResponseBody.fromString(
        plain
            ? ordinaryResponse
            : jsonEncode({
                'remarks': 'Profile',
                'routing': {'rules': []},
                'outbounds': [_outbound],
              }),
        200,
        headers: {
          'subscription-userinfo': ['upload=10;download=20;total=100'],
        },
      );
    });
    service = SubscriptionService.forTesting(
      database: database,
      client: NetClient.forTesting(client),
      schedulePing: pings.add,
      readReferences: () => SubscriptionNodeReferences(fixedId: protectedId),
    );
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.onexray.BridgeHostApi.invoke',
      BridgeHostApi.pigeonChannelCodec,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler(channel, (request) async {
      final invoke = jsonDecode((request as List).single as String) as Map;
      final method = invoke['method'];
      Map<String, dynamic>? data;
      if (method == 'decodeSubscriptionText') {
        data = {'text': invoke['payload']['text']};
      } else if (method == 'convertShareLinksToXrayJson') {
        parsed.add(invoke['payload']['text'] as String);
        expect(invoke['payload']['age'], isNull);
        data = {
          'outbounds': [_outbound],
        };
      } else {
        expect(method, 'testXray');
      }
      final failed = method == 'convertShareLinksToXrayJson' && failNodes;
      return [
        jsonEncode({
          'success': !failed,
          'error': failed ? 'No usable nodes' : '',
          'data': ?data,
        }),
      ];
    });
    addTearDown(() => messenger.setMockDecodedMessageHandler(channel, null));
  }

  Future<List<CoreConfigData>> rows() =>
      database.select(database.coreConfig).get();
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
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
