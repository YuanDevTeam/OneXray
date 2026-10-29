import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/service/servers/import.dart';
import 'package:onexray/service/shared/db/config_writer.dart';
import 'package:onexray/service/shared/share/app_link_model.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/connect/raw/db.dart';
import 'package:onexray/service/connect/raw/editor.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';

import '../../support/fake_geodata_import.dart';

void main() {
  test(
    'manual JSON syntax retains leading whitespace and Unicode offsets',
    () async {
      const source = ' \r\n {"name":"😀", "outbounds":[#]}';
      final service = ServerImportService(
        validate: (_) async => fail('Malformed input must not reach libXray'),
      );
      await expectLater(
        service.preview(source, manual: true),
        throwsA(
          isA<FormatException>().having(
            (e) => JsonDiagnostic.fromError(e)?.offset,
            'original offset',
            source.indexOf('#'),
          ),
        ),
      );
    },
  );

  test(
    'manual outbounds boundary has a path but core text has no location',
    () async {
      const error = 'outbounds[0].settings: invalid (offset 27)';
      final service = ServerImportService(validate: (_) async => error);
      await expectLater(
        service.preview('{"outbounds":[]}', manual: true),
        throwsA(
          isA<JsonDiagnostic>()
              .having((e) => e.path, 'array path', ['outbounds'])
              .having((e) => e.offset, 'offset', isNull),
        ),
      );
      await expectLater(
        service.preview('{"outbounds":[{}]}', manual: true),
        throwsA(
          isA<AppFailure>()
              .having((e) => e.cause, 'core message', error)
              .having((e) => JsonDiagnostic.fromError(e), 'diagnostic', isNull),
        ),
      );
    },
  );

  test('preparation has no writes; commit writes once and queues the saved IDs', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final queued = <int>[];
    final validated = <Map<String, dynamic>>[];
    final service = ServerImportService(
      database: db,
      validate: (text) async {
        validated.add(jsonDecode(text) as Map<String, dynamic>);
        return '';
      },
      write: (rows) => ConfigWriter.writeRowsInTransaction(db, rows, null),
      schedule: queued.addAll,
    );
    const source =
        '{"outbounds":[{"tag":"one","protocol":"freedom"},{"tag":"two","protocol":"freedom"}]}';
    final preview = await service.preview(source, manual: true);
    expect(validated, [
      {
        ...jsonDecode(source) as Map<String, dynamic>,
        'env': {
          'xray.location.asset': VpnConstants.datDir,
          'xray.location.cert': VpnConstants.datDir,
        },
        'log': {
          'access': 'none',
          'error': 'none',
          'loglevel': 'none',
          'dnsLog': false,
        },
      },
    ]);
    expect(preview.count, 2);
    expect(await db.coreConfigDao.allOutboundRowsWithDataBySubId(0), isEmpty);
    expect(queued, isEmpty);
    final result = await service.commit(preview);
    final saved = await db.coreConfigDao.allOutboundRowsWithDataBySubId(0);
    expect(result.count, 2);
    expect(queued, saved.map((row) => row.id));
    expect(saved.map(readOutboundFromDbData).map((node) => node['tag']), [
      'one',
      'two',
    ]);
    expect(saved.every((row) => row.delay == PingDelayConstants.unknown), true);
  });

  test(
    'manual S3 JSON keeps its full map through validation, preview and commit',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      const source = '''
 {"outbounds":[{
   "tag":"S3 node","protocol":"vless",
   "settings":{"address":"logical.example","port":443,
     "id":"11111111-1111-4111-8111-111111111111","encryption":"none"},
   "mux":{"enabled":true,"concurrency":8},
   "streamSettings":{"network":"xdrive","xdriveSettings":{
     "service":"s3","remoteFolder":"sessions/test",
     "secrets":["test-access-key","test-secret-key","test-session-token"],
     "s3":{"endpoint":"https://storage.example/prefix/","region":"test-region",
       "bucket":"tunnel","pathStyle":false,"future":{"keep":true}}}},
   "future":{"values":[1,{"keep":true}]}
 }]}
''';
      final original =
          (jsonDecode(source) as Map<String, dynamic>)['outbounds'];
      final validated = <Map<String, dynamic>>[];
      final queued = <int>[];
      final service = ServerImportService(
        database: db,
        parse: (_) async => fail('Manual JSON must bypass share projection'),
        validate: (text) async {
          validated.add(jsonDecode(text) as Map<String, dynamic>);
          return '';
        },
        write: (rows) => ConfigWriter.writeRowsInTransaction(db, rows, null),
        schedule: queued.addAll,
      );
      final preview = await service.preview(source, manual: true);
      expect(validated.single['outbounds'], original);
      expect(preview.count, 1);
      expect(await db.coreConfigDao.allOutboundRowsWithDataBySubId(0), isEmpty);
      expect(queued, isEmpty);

      final result = await service.commit(preview);
      final saved = (await db.coreConfigDao.allOutboundRowsWithDataBySubId(0))
          .single;
      expect(result.count, 1);
      expect(readOutboundFromDbData(saved), (original as List).single);
      expect(queued, [saved.id]);
      expect(validated, hasLength(1));
      expect(
        (jsonDecode(source) as Map<String, dynamic>)['outbounds'],
        original,
      );
    },
  );

  test(
    'batch subscription import retains errors and continues with later sources',
    () async {
      const downloadError = HttpException('HTTP 403');
      const writeError = FileSystemException(
        'Permission denied',
        'subscriptions',
      );
      final service = ServerImportService(
        subscribe: (link) async => switch (link.name) {
          'download' => const SubscriptionInsertResult(
            status: SubscriptionUpdateResult.downloadFailed,
            error: downloadError,
          ),
          'write' => throw writeError,
          _ => const SubscriptionInsertResult(
            status: SubscriptionUpdateResult.success,
            subId: 3,
            count: 1,
          ),
        },
      );
      final results = await service.importSubscriptions([
        for (final name in ['download', 'write', 'success'])
          OneXraySubscriptionLink(name: name, url: 'https://example.com/$name'),
      ]);

      expect(results[0].result.error, same(downloadError));
      expect(results[1].result.status, SubscriptionUpdateResult.writeFailed);
      expect(results[1].result.error, same(writeError));
      expect(results[2].result.success, isTrue);
      expect(results[2].result.subId, 3);
    },
  );

  test(
    'subscription AppLink policy survives detection and the import boundary',
    () async {
      final received = <OneXraySubscriptionLink>[];
      final service = ServerImportService(
        subscribe: (link) async {
          received.add(link);
          return const SubscriptionInsertResult(
            status: SubscriptionUpdateResult.success,
            subId: 1,
            count: 2,
          );
        },
      );
      final input = Uri(
        scheme: 'onexray',
        host: 'onexray.com',
        path: '/sub/add',
        queryParameters: {
          'url': 'https://example.com/sub',
          'panel': 'remnawave',
          'mode': 'providerManaged',
        },
        fragment: 'Provider',
      ).toString();
      final detection = service.detect(input);
      expect(detection.localText, isEmpty);
      final results = await service.importSubscriptions(
        detection.subscriptions,
      );
      expect(results.single.result.success, isTrue);
      expect(received.single.panel, SubscriptionPanel.remnawave);
      expect(received.single.mode, SubscriptionMode.providerManaged);
      expect(received.single.name, 'Provider');
      expect(received.single.url, 'https://example.com/sub');
    },
  );

  test(
    'manual import delegates node values and duplicate tags to libXray',
    () async {
      final inputs = <Map<String, dynamic>>[];
      final service = ServerImportService(
        validate: (text) async {
          inputs.add(jsonDecode(text) as Map<String, dynamic>);
          return '';
        },
      );
      final outbounds = [
        {'tag': 'same', 'protocol': 'vmess', 'settings': <String, dynamic>{}},
        {
          'tag': 'same',
          'protocol': 'vmess',
          'settings': {'security': 'none'},
        },
        {'protocol': 'freedom'},
      ];
      final preview = await service.preview(
        jsonEncode({'outbounds': outbounds}),
        manual: true,
      );
      expect(inputs.single['outbounds'], outbounds);
      expect(preview.rows.map((row) => row.name.value), [
        'same',
        'same',
        'freedom',
      ]);
    },
  );

  test('libXray rejection aborts manual import before persistence', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var validations = 0;
    final service = ServerImportService(
      database: db,
      validate: (_) async {
        validations++;
        return 'Invalid node';
      },
      write: (_) async => throw StateError('Must not write rejected input'),
    );
    for (final source in [
      '{"outbounds":[{"tag":"one","protocol":"freedom"},{}]}',
      '{"outbounds":[1]}',
    ]) {
      await expectLater(
        service.preview(source, manual: true),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.cause,
            'core reason',
            'Invalid node',
          ),
        ),
      );
      expect(await db.coreConfigDao.allOutboundRowsWithDataBySubId(0), isEmpty);
    }
    expect(validations, 2);
  });

  test('OneXray node links use the existing decoder; subscriptions stay read-only form inputs', () async {
    final link = Uri(
      scheme: 'onexray',
      host: 'onexray.com',
      path: '/config/add',
      queryParameters: {
        'type': 'outbound',
        'data': base64Encode(
          utf8.encode(
            '{"outbounds":[{"tag":"same-name","protocol":"freedom"}]}',
          ),
        ),
      },
    );
    final service = ServerImportService(
      parse: (_) async => throw StateError('Unexpected native parsing'),
      validate: (_) async => '',
    );
    final preview = await service.preview('$link\n$link');
    expect(
      preview.count,
      2,
    ); // Equal labels never collapse distinct imported assets.
    final subscription = service
        .detect('https://provider.example/list#Provider')
        .subscriptions
        .single;
    expect(subscription.url, 'https://provider.example/list');
    expect(subscription.name, 'Provider');
    expect(
      service.detect('http://provider.example/list').subscriptions,
      isEmpty,
    );
  });

  test('HTTPS restriction rejects initial cleartext and downgraded redirect targets', () async {
    final origin = Uri.parse('https://provider.example/sub');
    expect(NetClient.isHttpsDownloadUri(origin), true);
    expect(NetClient.isHttpsDownloadUri(origin.resolve('/next')), true);
    for (final target in [
      'http://provider.example/next',
      'https://user:secret@provider.example/next',
      'file:///tmp/sub',
    ]) {
      expect(NetClient.isHttpsDownloadUri(origin.resolve(target)), false);
      await expectLater(
        NetClient().getText(target, httpsOnly: true),
        throwsA(isA<AppFailure>().having((e) => e.code, 'code', 'downloadUrl')),
      );
    }
  });

  test('mixed detection imports subscriptions independently before read-only local preview', () async {
    final events = <String>[];
    final node = outboundCompanion({'tag': 'local', 'protocol': 'freedom'});
    final service = ServerImportService(
      subscribe: (link) async {
        events.add('subscription:${link.name}');
        return SubscriptionInsertResult(
          status: link.name == 'good'
              ? SubscriptionUpdateResult.success
              : SubscriptionUpdateResult.downloadFailed,
          count: link.name == 'good' ? 2 : 0,
          subId: link.name == 'good' ? 7 : 0,
        );
      },
      parse: (text) async {
        events.add('preview');
        expect(text.trim(), 'vless://local');
        return [node];
      },
      write: (_) async =>
          throw StateError('Cancelled local content must not write'),
      schedule: (_) =>
          throw StateError('Cancelled local content must not queue'),
    );
    final detected = service.detect(
      'https://provider.example/a#good\nhttps://provider.example/b#bad\nvless://local',
    );
    expect(events, isEmpty);
    final subscriptions = await service.importSubscriptions(
      detected.subscriptions,
    );
    final preview = await service.previewDetected(detected);
    expect(events, ['subscription:good', 'subscription:bad', 'preview']);
    expect(subscriptions.map((item) => item.result.success), [true, false]);
    expect(preview.count, 1);
    // Cancel means commit is never called; the completed subscription is kept.
    expect(subscriptions.first.result.subId, 7);
  });

  test(
    'clear-data stops the imported subscription list after its active source',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final events = <String>[];
      final service = ServerImportService(
        subscribe: (link) async {
          if (!started.isCompleted) {
            started.complete();
            await release.future;
          }
          events.add(link.name);
          return const SubscriptionInsertResult(
            status: SubscriptionUpdateResult.success,
            subId: 1,
            count: 1,
          );
        },
      );
      final links = service
          .detect('https://example.com/one#one\nhttps://example.com/two#two')
          .subscriptions;
      final importing = service.importSubscriptions(links);
      await started.future;
      final clearing = ServerImportService.pauseForDataClear().then(
        (_) => events.add('clear'),
      );
      addTearDown(ServerImportService.resumeAfterDataClear);
      release.complete();
      expect(
        (await importing).every((result) => result.result.success),
        isTrue,
      );
      await clearing;
      expect(events, ['one', 'clear']);
    },
  );

  test('Raw and data sources stay read-only until confirmation and partial results remain distinct', () async {
    const raw =
        '{ "name": "Expert", "outbounds": [{"protocol":"freedom"}], "custom": true }';
    final node = _configLink(
      'outbound',
      '{"outbounds":[{"tag":"local","protocol":"freedom"}]}',
    );
    final rawLink = _configLink('raw', raw);
    final writes = <CoreConfigCompanion>[];
    final queued = <int>[];
    final downloaded = <String>[];
    final service = ServerImportService(
      validate: (_) async => '',
      validateGeoData: (_) async => true,
      writeGeoData: (link) async {
        downloaded.add(link.name);
        return link.name == 'good-data';
      },
      write: (rows) async {
        writes.addAll(rows);
        return ConfigWriteResult(
          count: rows.length,
          ids: List.generate(rows.length, (index) => 20 + index),
        );
      },
      schedule: queued.addAll,
    );
    final preview = await service.preview(
      '$node\n$rawLink\n${_geoLink('good-data')}\n${_geoLink('failed-data')}',
    );
    expect(preview.count, 1);
    expect(preview.rawCount, 1);
    expect(preview.geoData, hasLength(2));
    expect(writes, isEmpty);
    expect(downloaded, isEmpty);
    final result = await service.commit(preview);
    expect(result.count, 1);
    expect(result.rawCount, 1);
    expect(result.geoDataCount, 1);
    expect(result.failedGeoData.single.name, 'failed-data');
    expect(utf8.decode(base64Decode(writes[1].data.value!)), raw);
    expect(queued, [20]); // Only the outbound, never the Raw config.
    expect(
      XrayRawDb.configCompanion('Expert', raw).data.value,
      writes[1].data.value,
    );
  });

  test('mixed node and Raw import commits referenced Geodata with the original configuration', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const source = '''
  {"name":"Expert","outbounds":[{"protocol":"freedom"}],
   "routing":{"rules":[{"domain":["ext:rules.dat:CN"],"outboundTag":"direct"}]},
   "customRoot":true}
''';
    final lifecycle = <String>[];
    final queued = <int>[];
    final validations = <Map<String, dynamic>>[];
    final service = ServerImportService(
      database: db,
      transfer: ConfigurationTransferService(
        prepare: (inputs) async {
          expect(inputs.single.fileName, 'rules.dat');
          return FakeGeoDataImport(events: lifecycle);
        },
      ),
      parse: (_) async =>
          fail('Known App links must not reach the node parser'),
      validate: (text) async {
        validations.add(jsonDecode(text) as Map<String, dynamic>);
        return '';
      },
      schedule: queued.addAll,
    );
    final preview = await service.preview(
      [
        _geoLink('rules'),
        _configLink(
          'outbound',
          '{"outbounds":[{"tag":"Local","protocol":"freedom"}]}',
        ),
        _configLink('raw', source),
      ].join('\n'),
    );
    expect(preview.rows, hasLength(1));
    expect(preview.raw.single.text, source);
    expect(preview.raw.single.json, jsonDecode(source));
    expect(preview.assets.single.fileName, 'rules.dat');
    expect(preview.geoData, isEmpty);
    expect(lifecycle, isEmpty);
    expect(validations, hasLength(1));
    expect(await db.coreConfigDao.allRawRowsWithData, isEmpty);

    final result = await service.commit(preview);
    expect(result.count, 1);
    expect(result.rawCount, 1);
    expect(lifecycle, ['publish', 'commit', 'complete']);
    expect(validations.last['customRoot'], true);
    final saved = (await db.coreConfigDao.allRawRowsWithData).single;
    expect(XrayRawDb.readFromDbData(saved), source);
    expect(
      queued,
      (await db.coreConfigDao.allOutboundRowsWithDataBySubId(0))
          .map((row) => row.id),
    );
    await preview.dispose();
  });

  test(
    'direct Raw import retains the editor name limit before kernel validation',
    () async {
      final service = ServerImportService(
        validate: (_) async => fail('Invalid name must not reach the kernel'),
      );
      await expectLater(
        service.preview(
          jsonEncode({'name': 'N' * 33, 'inbounds': [], 'outbounds': []}),
        ),
        throwsA(
          isA<RawEditorException>().having(
            (error) => error.reason,
            'reason',
            'name',
          ),
        ),
      );
    },
  );

  test('unrecognized legacy assets and unsafe data names cannot become Raw or file paths', () async {
    final service = ServerImportService(validateGeoData: (_) async => true);
    final preview = await service.preview(
      '${_configLink('profile', '{"name":"legacy"}')}\n${_geoLink('../outside')}',
    );
    expect(preview.hasItems, false);
    expect(preview.rawCount, 0);
    await expectLater(service.commit(preview), throwsFormatException);
  });

  test(
    'empty parsed lists cannot be imported; JSON input remains intact',
    () async {
      final zero = ServerImportService(parse: (_) async => []);
      final failed = await zero.preview('vless://invalid');
      expect(failed.hasItems, false);
      await expectLater(zero.commit(failed), throwsFormatException);
      final unknown = await ServerImportService(parse: (_) async => [])
          .preview('plain text');
      expect(unknown.hasItems, false);
      const json = '''
  {
    "outbounds": [{"tag": "https://not-a-subscription.example", "protocol": "freedom"}]
  }
''';
      final detection = zero.detect(json);
      expect(detection.subscriptions, isEmpty);
      expect(detection.localText, json);
    },
  );
}

String _configLink(String type, String json) => Uri(
  scheme: 'onexray',
  host: 'onexray.com',
  path: '/config/add',
  queryParameters: {'type': type, 'data': base64Encode(utf8.encode(json))},
).toString();

String _geoLink(String name) => Uri(
  scheme: 'onexray',
  host: 'onexray.com',
  path: '/dat/add',
  fragment: name,
  queryParameters: {'type': 'domain', 'url': 'https://data.example/list.dat'},
).toString();
