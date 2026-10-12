import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/shared/share/app_link_model.dart';
import 'package:onexray/service/shared/share/app_link_parser.dart';
import 'package:onexray/pages/shared/share/controller.dart';
import 'package:onexray/pages/shared/share/params.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ShareController controller;

  setUp(() {
    final eventBus = AppEventBus();
    addTearDown(eventBus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    await controller.close();
    await db.close();
  });

  Future<void> loadSubscription({
    Future<Uint8List?> Function(String)? qrEncoder,
  }) async {
    final id = await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'My subscription',
        url: 'https://example.test/subscription',
        ageSecretKey: const Value('AGE-SECRET-KEY-1PRIVATE'),
        agePublicKey: const Value('age1public'),
        timestamp: DateTime(2026, 9, 1),
      ),
    );
    controller = ShareController(
      SharePageParams(ShareType.subscription, id),
      database: db,
      qrEncoder: qrEncoder,
    );
    await controller.stream.firstWhere((state) => !state.loading);
  }

  test(
    'starts with the original link and shares Age type, never keys',
    () async {
      var qrCalls = 0;
      await loadSubscription(
        qrEncoder: (_) async {
          qrCalls++;
          return Uint8List(0);
        },
      );
      expect(controller.state.name, 'My subscription');
      expect(controller.state.format, ShareLinkFormat.original);
      expect(controller.state.qrExpanded, isFalse);
      expect(controller.state.qrCode, isNull);
      expect(qrCalls, 0);
      expect(
        controller.state.selectedLink,
        'https://example.test/subscription#My%20subscription',
      );

      controller.selectFormat(ShareLinkFormat.onexray);
      final link = Uri.parse(controller.state.selectedLink);
      expect(link.scheme, 'onexray');
      expect(Uri.decodeComponent(link.fragment), 'My subscription');
      expect(link.queryParameters['age'], 'x25519');
      expect(controller.state.selectedLink, isNot(contains('PRIVATE')));
      expect(controller.state.selectedLink, isNot(contains('age1public')));
      expect(qrCalls, 0);
    },
  );

  test('format changes and collapsing discard obsolete QR results', () async {
    final links = <String>[];
    final results = <Completer<Uint8List?>>[];
    await loadSubscription(
      qrEncoder: (link) {
        links.add(link);
        final result = Completer<Uint8List?>();
        results.add(result);
        return result.future;
      },
    );
    controller.toggleQr();
    controller.selectFormat(ShareLinkFormat.onexray);
    controller.selectFormat(ShareLinkFormat.original);
    expect(links, [
      controller.state.originalLink,
      controller.state.appLink,
      controller.state.originalLink,
    ]);
    results[0].complete(Uint8List.fromList([1]));
    results[1].complete(Uint8List.fromList([2]));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.qrCode, isNull);
    results[2].complete(Uint8List.fromList([3]));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.qrCode, [3]);

    controller.selectFormat(ShareLinkFormat.onexray);
    expect(controller.state.qrCode, isNull);
    controller.toggleQr();
    results[3].complete(Uint8List.fromList([4]));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.qrExpanded, isFalse);
    expect(controller.state.qrCode, isNull);
  });

  test('a missing subscription stops loading and exposes failure', () async {
    controller = ShareController(
      SharePageParams(ShareType.subscription, 999),
      database: db,
    );
    await controller.stream.firstWhere((state) => !state.loading);
    expect(controller.state.selectedLink, isEmpty);
    expect(controller.state.linkError, isNotEmpty);
    expect(controller.state.qrCode, isNull);
  });
  for (final type in [CoreConfigType.Remnawave, CoreConfigType.raw]) {
    test('${type.name} shares a complete Raw App Link and cannot select Original', () async {
      const source =
          '{"remarks":"Source title","inbounds":[{"tag":"socksIn","protocol":"socks","listen":"127.0.0.1","port":1080}],"outbounds":[{"tag":"provider-direct","protocol":"freedom"}],"dns":{"servers":["1.1.1.1"]},"routing":{"rules":[{"type":"field","inboundTag":["socksIn"],"domain":["domain:example.test"],"outboundTag":"provider-direct"}]},"unknownExtension":{"kept":true}}';
      final sourceId = type == CoreConfigType.Remnawave
          ? await db.subscriptionDao.insertRow(
              SubscriptionCompanion.insert(
                name: 'Provider source',
                url: 'https://example.test/provider',
                mode: const Value('providerManaged'),
                timestamp: DateTime(2026, 10, 12),
              ),
            )
          : 0;
      final id = await db.coreConfigDao.insertAssetRow(
        CoreConfigCompanion.insert(
          name: 'Complete profile',
          type: type.name,
          tags: '',
          data: Value(base64Encode(utf8.encode(source))),
          delay: -1,
          subId: sourceId,
        ),
      );
      final before = (await db.coreConfigDao.searchRow(id))!;
      final qrLinks = <String>[];
      controller = ShareController(
        SharePageParams(ShareType.config, id),
        database: db,
        originalLinkEncoder: (_) async =>
            fail('Complete configs must not use standard outbound conversion'),
        qrEncoder: (link) async {
          qrLinks.add(link);
          return Uint8List.fromList([1]);
        },
      );
      await controller.stream.firstWhere((state) => !state.loading);
      expect(controller.state.supportsOriginal, isFalse);
      expect(controller.state.format, ShareLinkFormat.onexray);
      expect(controller.state.originalLink, isEmpty);
      expect(controller.state.linkError, isEmpty);
      final share = controller.state.selectedLink;
      final link =
          OneXrayAppLinkParser.parse(Uri.parse(share))! as OneXrayConfigLink;
      expect(link.type, OneXrayConfigLinkType.raw);
      expect(link.name, 'Complete profile');
      if (type == CoreConfigType.Remnawave) {
        final config = jsonDecode(link.xrayJson) as Map<String, dynamic>;
        expect(config['name'], 'Complete profile');
        expect(config['remarks'], 'Source title');
        expect(config['unknownExtension'], {'kept': true});
        expect(
          (config['inbounds'] as List).where(
            (value) => value['tag'] == 'tunIn',
          ),
          hasLength(1),
        );
        final rule = (config['routing']['rules'] as List).last;
        expect(rule['inboundTag'], ['socksIn', 'tunIn']);
        expect(rule['outboundTag'], 'provider-direct');
      } else {
        expect(link.xrayJson, source);
      }
      controller.selectFormat(ShareLinkFormat.original);
      expect(controller.state.format, ShareLinkFormat.onexray);
      expect(controller.state.selectedLink, share);
      controller.toggleQr();
      if (controller.state.qrCode == null) {
        await controller.stream.firstWhere((state) => state.qrCode != null);
      }
      expect(qrLinks, [share]);
      expect((await db.coreConfigDao.searchRow(id))!, before);
    });
  }

  test('ordinary outbound keeps Original and OneXray formats', () async {
    final outbound = {
      'tag': 'Ordinary node',
      'protocol': 'socks',
      'settings': {
        'servers': [
          {'address': 'proxy.example.test', 'port': 1080},
        ],
      },
    };
    final id = await db.coreConfigDao.insertAssetRow(
      outboundCompanion(outbound),
    );
    final converted = <Map<String, dynamic>>[];
    controller = ShareController(
      SharePageParams(ShareType.config, id),
      database: db,
      originalLinkEncoder: (json) async {
        converted.add(json);
        return 'socks://proxy.example.test:1080#Ordinary';
      },
    );
    await controller.stream.firstWhere((state) => !state.loading);
    expect(controller.state.supportsOriginal, isTrue);
    expect(controller.state.format, ShareLinkFormat.original);
    expect(
      controller.state.selectedLink,
      'socks://proxy.example.test:1080#Ordinary',
    );
    expect(converted, [
      {
        'outbounds': [outbound],
      },
    ]);
    controller.selectFormat(ShareLinkFormat.onexray);
    final link =
        OneXrayAppLinkParser.parse(Uri.parse(controller.state.selectedLink))!
            as OneXrayConfigLink;
    expect(link.type, OneXrayConfigLinkType.outbound);
    expect(jsonDecode(link.xrayJson), {
      'outbounds': [outbound],
    });
    controller.selectFormat(ShareLinkFormat.original);
    expect(
      controller.state.selectedLink,
      'socks://proxy.example.test:1080#Ordinary',
    );
    expect(controller.state.linkError, isEmpty);
  });
}
