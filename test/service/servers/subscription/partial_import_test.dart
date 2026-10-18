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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SubscriptionService service;
  late List<Map<String, dynamic>> response;
  late String userInfo;
  late List<String> validated;
  late List<int> pings;
  Object? nativeFailure;

  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
    database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    response = [
      _profile('Saved', ['Saved proxy']),
    ];
    userInfo = 'upload=10;download=20;total=100;expire=1790812800';
    validated = [];
    pings = [];
    nativeFailure = null;
    final client = Dio()
      ..httpClientAdapter = _SubscriptionResponse(
        () => ResponseBody.fromString(
          jsonEncode(response),
          200,
          headers: {
            'subscription-userinfo': [userInfo],
          },
        ),
      );
    addTearDown(client.close);
    service = SubscriptionService.forTesting(
      database: database,
      client: NetClient.forTesting(client),
      configurationReader: SubscriptionConfigurationReader(
        decode: (text, {ageSecretKey}) async => text,
        validate: (text) async {
          final config = jsonDecode(text) as Map<String, dynamic>;
          final name = config['remarks'] as String;
          validated.add(name);
          if (name == 'Unavailable' && nativeFailure != null) {
            throw nativeFailure!;
          }
          return name == 'Rejected' ? 'Core rejected the configuration' : '';
        },
        readNodes: (_) async =>
            throw StateError('Complete JSON reached the ordinary parser'),
        withFiles: (action) => action(),
      ),
      schedulePing: pings.add,
      readReferences: () => const SubscriptionNodeReferences(),
    );
  });

  for (final mode in SubscriptionMode.values) {
    test(
      'partial ${mode.name} imports and refreshes commit only accepted caches',
      () async {
        final first = _profile('First', ['First A', 'First B']);
        final second = _profile('Second', ['Second proxy']);
        response = [first, _rejectedProfile(), second];
        final inserted = await service.insertSubscription(_input(mode));
        final expectedCount = mode == SubscriptionMode.providerManaged ? 2 : 3;
        expect(inserted.error, isNull);
        expect(inserted.success, isTrue);
        expect(inserted.count, expectedCount);
        expect(validated, ['First', 'Rejected', 'Second']);
        final source = (await database.subscriptionDao.searchRow(
          inserted.subId,
        ))!;
        expect(source.mode, mode.name);
        expect(source.uploadBytes, 10);
        expect(source.downloadBytes, 20);
        expect(source.totalBytes, 100);
        expect(source.expireTimestamp, 1790812800);
        expect(source.userInfoUpdatedAt, isNotNull);
        final oldRows = await database.select(database.coreConfig).get();
        _expectCaches(
          oldRows,
          [first, second],
          ['First A', 'First B', 'Second proxy'],
          source.id,
        );
        expect(
          await database.coreConfigDao.allActiveServerRows(),
          hasLength(expectedCount),
        );

        final replacement = _profile('Replacement', ['New A', 'New B']);
        response = [_rejectedProfile(), replacement];
        userInfo = 'download=50;total=500';
        validated.clear();
        final refreshStarted = DateTime.now().subtract(
          const Duration(seconds: 1),
        );
        final refreshed = await service.refreshSubscriptionResult(source);
        final refreshCount = mode == SubscriptionMode.providerManaged ? 1 : 2;
        expect(refreshed.error, isNull);
        expect(refreshed.success, isTrue);
        expect(refreshed.count, refreshCount);
        expect(validated, ['Rejected', 'Replacement']);
        final current = (await database.subscriptionDao.searchRow(source.id))!;
        expect(current.mode, source.mode);
        expect(current.url, source.url);
        expect(current.userAgent, source.userAgent);
        expect(current.uploadBytes, isNull);
        expect(current.downloadBytes, 50);
        expect(current.totalBytes, 500);
        expect(current.expireTimestamp, isNull);
        expect(current.timestamp.isBefore(refreshStarted), isFalse);
        expect(current.userInfoUpdatedAt!.isBefore(refreshStarted), isFalse);
        final rows = await database.select(database.coreConfig).get();
        _expectCaches(rows, [replacement], ['New A', 'New B'], source.id);
        final oldIds = oldRows.map((row) => row.id).toSet();
        expect(rows.map((row) => row.id).toSet().intersection(oldIds), isEmpty);
        expect(
          await database.coreConfigDao.allActiveServerRows(),
          hasLength(refreshCount),
        );
        expect(
          pings,
          mode == SubscriptionMode.appManaged
              ? [source.id, source.id]
              : isEmpty,
        );
      },
    );
  }

  for (final unavailable in [false, true]) {
    test(
      '${unavailable ? "native failure after acceptance" : "all rejected configurations"} preserves the saved source and both caches',
      () async {
        final inserted = await service.insertSubscription(
          _input(SubscriptionMode.providerManaged),
        );
        expect(inserted.success, isTrue);
        final source = (await database.subscriptionDao.searchRow(
          inserted.subId,
        ))!;
        final rows = await database.select(database.coreConfig).get();
        validated.clear();
        userInfo = 'upload=999;download=999;total=9999';
        if (unavailable) {
          nativeFailure = PlatformException(
            code: 'unavailable',
            message: 'Native validation unavailable',
          );
          response = [
            _profile('Before failure', ['Must not commit']),
            _profile('Unavailable', ['Unavailable proxy']),
          ];
        } else {
          response = [_rejectedProfile()];
        }

        final result = await service.refreshSubscriptionResult(source);
        expect(result.status, SubscriptionUpdateResult.invalidContent);
        expect(result.count, 0);
        expect(
          result.error,
          unavailable ? same(nativeFailure) : isA<FormatException>(),
        );
        expect(
          validated,
          unavailable ? ['Before failure', 'Unavailable'] : ['Rejected'],
        );
        expect(await database.subscriptionDao.searchRow(source.id), source);
        expect(await database.select(database.coreConfig).get(), rows);
        expect(pings, isEmpty);
      },
    );
  }
}

SubscriptionInput _input(SubscriptionMode mode) => SubscriptionInput(
  name: 'Synthetic provider',
  url: 'https://provider.example/subscription',
  userAgent: 'Synthetic/1.0',
  mode: mode,
);

Map<String, dynamic> _proxy(String tag) => {
  'tag': tag,
  'protocol': 'socks',
  'settings': {
    'servers': [
      {'address': '127.0.0.1', 'port': 1080},
    ],
  },
};

Map<String, dynamic> _profile(String name, List<String> tags) => {
  'remarks': name,
  'routing': {
    'rules': [
      {
        'type': 'field',
        'domain': ['example.com'],
        'outboundTag': tags.first,
      },
    ],
  },
  'outbounds': [
    ...tags.map(_proxy),
    {'tag': 'direct', 'protocol': 'freedom'},
  ],
};

Map<String, dynamic> _rejectedProfile() {
  final config = _profile('Rejected', ['Rejected ordinary proxy']);
  (config['outbounds'] as List).add({
    'tag': 'broken',
    'protocol': 'unsupported-protocol',
  });
  return config;
}

Map<String, dynamic> _saved(CoreConfigData row) =>
    jsonDecode(utf8.decode(base64Decode(row.data!))) as Map<String, dynamic>;

void _expectCaches(
  List<CoreConfigData> rows,
  List<Map<String, dynamic>> profiles,
  List<String> proxyTags,
  int subId,
) {
  final full = rows.where((row) => row.type == CoreConfigType.Remnawave.name);
  final ordinary = rows.where(
    (row) => row.type == CoreConfigType.outbound.name,
  );
  expect(rows, hasLength(profiles.length + proxyTags.length));
  expect(rows.every((row) => row.subId == subId), isTrue);
  expect(full.map(_saved), unorderedEquals(profiles));
  expect(
    ordinary.map((row) => (_saved(row)['outbounds'] as List).single),
    unorderedEquals(proxyTags.map(_proxy)),
  );
}

class _SubscriptionResponse implements HttpClientAdapter {
  _SubscriptionResponse(this.respond);

  final ResponseBody Function() respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond();

  @override
  void close({bool force = false}) {}
}
