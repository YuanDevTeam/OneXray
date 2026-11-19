import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/connect/routing/custom/geodata_suggestions.dart';
import 'package:onexray/service/shared/xray/provider_geodata.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory workspace;
  late Directory datRoot;
  late AppDatabase db;
  late GeoDataService service;
  var dbClosed = false;
  var revision = 'one';
  String? failDownload;
  String? failIndex;
  var downloads = 0;
  Future<void> Function()? beforeDownload;

  Future<void> count(String path, String name, GeoDataType type) async {
    if (failIndex == name) throw const FormatException('Invalid fixture data');
    final data = await File(p.join(path, '$name.dat')).readAsString();
    if (data == 'broken') throw const FormatException('Invalid fixture data');
    await File(p.join(path, '$name.json')).writeAsString(
      jsonEncode({
        'categoryCount': 1,
        'ruleCount': 2,
        'codes': [
          {'code': type == GeoDataType.ip ? 'cn' : 'CN', 'ruleCount': 2},
        ],
      }),
    );
  }

  Future<void> expectFlatRoot() async {
    final entries = await datRoot.list(followLinks: false).toList();
    expect(
      await Future.wait(
        entries.map(
          (entry) => FileSystemEntity.type(entry.path, followLinks: false),
        ),
      ),
      everyElement(FileSystemEntityType.file),
    );
  }

  Future<Map<String, List<int>>> rootBytes() async {
    final result = <String, List<int>>{};
    await for (final entry in datRoot.list(followLinks: false)) {
      if (entry is File) {
        result[p.basename(entry.path)] = await entry.readAsBytes();
      }
    }
    return result;
  }

  setUp(() async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    final fixtures = await Directory('../references/onexray-tests').absolute
        .create(recursive: true);
    workspace = await fixtures.createTemp('geodata-');
    datRoot = Directory(p.join(workspace.path, 'dat'));
    addTearDown(() => workspace.delete(recursive: true));
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dbClosed = false;
    addTearDown(() async {
      if (!dbClosed) await db.close();
    });
    revision = 'one';
    failDownload = null;
    failIndex = null;
    downloads = 0;
    beforeDownload = null;
    service = GeoDataService.forTesting(
      database: db,
      directory: datRoot.path,
      download: (url, file) async {
        expect(AppEventBus.instance.state.downloading, isTrue);
        downloads++;
        await beforeDownload?.call();
        if (p.basenameWithoutExtension(file.path) == failDownload) {
          throw const SocketException('Fixture download failed');
        }
        await file.writeAsString(revision);
      },
      count: count,
      copyBundled: (path) async {
        for (final name in ['geoip', 'geosite']) {
          await File(p.join(path, '$name.dat')).writeAsString('bundled');
        }
        await File(p.join(path, 'timestamp.txt')).writeAsString('123');
      },
    );
  });

  GeoDataInput input([String name = 'custom.dat']) => GeoDataInput(
    fileName: name,
    type: GeoDataType.domain,
    url: 'https://example.com/$name',
  );

  final providerUrls = ProviderGeoDataUrls(
    geoIpUrl: 'https://example.com/provider-ip.dat',
    geoSiteUrl: 'https://example.com/provider-site.dat',
  );

  Future<ProviderGeoDataBinding> publishProvider(String scope) =>
      service.withProviderAssets(
        providerUrls,
        scope: scope,
        action: (binding) async => binding,
        committed: (_) => true,
      );

  test('Provider DAT names isolate revisions and scopes without replacing defaults', () async {
    await service.ensureInstalled();
    final originalRoot = await rootBytes();
    final first = await publishProvider('first');
    final reused = await publishProvider('first');
    final other = await publishProvider('other');
    expect(first.files, hasLength(2));
    expect(reused.files, unorderedEquals(first.files));
    expect(other.files.toSet().intersection(first.files.toSet()), isEmpty);
    revision = 'two';
    final updated = await publishProvider('first');
    expect(updated.files.toSet().intersection(first.files.toSet()), isEmpty);
    for (final file in first.files) {
      expect(await File(p.join(datRoot.path, file)).readAsString(), 'one');
    }
    for (final file in updated.files) {
      expect(await File(p.join(datRoot.path, file)).readAsString(), 'two');
    }
    expect(
      await rootBytes(),
      containsPair('geoip.dat', originalRoot['geoip.dat']),
    );
    expect(
      await rootBytes(),
      containsPair('geosite.dat', originalRoot['geosite.dat']),
    );
    expect(await db.geoDataDao.allRows, isEmpty);
    await db.geoDataDao.clear();
    await service.resetAfterDataClear();
    expect(await rootBytes(), originalRoot);
  });

  test('aborted Provider publication rolls back only new aliases', () async {
    await service.ensureInstalled();
    await publishProvider('first');
    final committedRoot = await rootBytes();
    revision = 'two';
    final rejected = await service.withProviderAssets(
      providerUrls,
      scope: 'first',
      action: (binding) async {
        for (final file in binding.files) {
          expect(await File(p.join(datRoot.path, file)).readAsString(), 'two');
        }
        return false;
      },
      committed: (result) => result,
    );
    expect(rejected, isFalse);
    expect(await rootBytes(), committedRoot);
    await expectLater(
      service.withProviderAssets<bool>(
        providerUrls,
        scope: 'first',
        action: (_) async => throw StateError('Fixture commit failed'),
        committed: (result) => result,
      ),
      throwsStateError,
    );
    expect(await rootBytes(), committedRoot);
    failDownload = 'geosite';
    await expectLater(
      publishProvider('first'),
      throwsA(isA<SocketException>()),
    );
    expect(await rootBytes(), committedRoot);
  });

  test(
    'Provider aliases cannot be imported or silently reused when damaged',
    () async {
      await service.ensureInstalled();
      final binding = await publishProvider('first');
      final file = binding.geoSiteFile!;
      await expectLater(service.add(input(file)), throwsFormatException);
      final target = File(p.join(datRoot.path, file));
      await target.writeAsString('different bytes');
      await expectLater(publishProvider('first'), throwsFormatException);
      expect(await target.readAsString(), 'different bytes');
      await target.delete();
      await expectLater(
        service.requireDependencies({file: GeoDataType.domain}),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'list metadata and healthy details survive an unrelated broken index',
    () async {
      await service.ensureInstalled();
      await service.add(input('healthy.dat'));
      await service.add(input('broken.dat'));
      final healthy = (await db.geoDataDao.searchRowByName('healthy'))!;
      final broken = (await db.geoDataDao.searchRowByName('broken'))!;
      await File(p.join(datRoot.path, 'broken.json')).writeAsString('{invalid');
      final files = await service.watchPublished().first;
      expect(files, hasLength(4));
      expect(files.every((file) => file.failure == null), true);
      expect(
        (await service.watchFile(healthy.id).first)!.index.categoryCount,
        1,
      );
      await expectLater(
        service.watchFile(broken.id).first,
        throwsFormatException,
      );
      final preview = await service.previewRestore([input('healthy.dat')]);
      expect(preview.reusable['healthy'], healthy);
      expect(preview.pendingCount, 0);
      expect(
        (await service.previewRestore([input('broken.dat')])).pendingCount,
        1,
      );
    },
  );

  test(
    'missing files keep their list row and restore offline as pending',
    () async {
      await service.ensureInstalled();
      await service.add(input());
      final original = (await db.geoDataDao.searchRowByName('custom'))!;
      await File(p.join(datRoot.path, 'custom.dat')).delete();
      final files = await service.watchPublished().first;
      final missing = files.singleWhere((file) => file.row.id == original.id);
      expect(missing.row.installed, true);
      expect(missing.bytes, isNull);
      expect(missing.failure, isNotNull);
      expect(
        files
            .where((file) => file.builtIn)
            .every((file) => file.failure == null),
        true,
      );
      final preview = await service.previewRestore([input()]);
      expect(preview.pendingCount, 1);
      await service.restoreSources(preview, (write) => write());
      final restored = (await db.geoDataDao.allRows).single;
      expect(restored.installed, false);
      expect(restored.id, isNot(original.id));
      expect(await File(p.join(datRoot.path, 'custom.json')).exists(), false);
      expect(downloads, 1);
    },
  );

  test(
    'offline restore registers pending sources and startup never downloads',
    () async {
      await service.ensureInstalled();
      final preview = await service.previewRestore([input()]);
      expect(preview.pendingCount, 1);
      await service.restoreSources(preview, (write) => write());
      final pending = (await db.geoDataDao.allRows).single;
      expect(pending.installed, false);
      expect(await service.watchPublished().first, hasLength(2));
      await service.ensureInstalled();
      expect(downloads, 0);
      failDownload = 'custom';
      await expectLater(
        service.updateCustom(pending),
        throwsA(isA<SocketException>()),
      );
      expect((await db.geoDataDao.allRows).single.installed, false);
      failDownload = null;
      await service.updateCustom(pending);
      expect((await db.geoDataDao.allRows).single.installed, true);
      expect(await service.watchPublished().first, hasLength(3));
    },
  );

  test('a missing dat root preserves pending declarations while rebuilding defaults', () async {
    await service.ensureInstalled();
    final preview = await service.previewRestore([input()]);
    await service.restoreSources(preview, (write) => write());
    await datRoot.delete(recursive: true);
    await service.ensureInstalled();
    expect((await db.geoDataDao.allRows).single.installed, false);
    expect(await service.watchPublished().first, hasLength(2));
    expect(downloads, 0);
  });

  test('pending sources share metadata, not categories, and only block their dependents', () async {
    await service.ensureInstalled();
    final preview = await service.previewRestore([input()]);
    await service.restoreSources(preview, (write) => write());
    final json = {
      'outbounds': [{}],
      'routing': {
        'rules': [
          {
            'domain': ['ext:custom.dat:CN'],
            'balancerTag': 'proxy',
          },
        ],
      },
    };
    final refs = geoDataReferences(json);
    await expectLater(
      service.requireDependencies(refs),
      throwsA(
        isA<FileSystemException>().having(
          (e) => e.path,
          'filename',
          'custom.dat',
        ),
      ),
    );
    await service.requireDependencies(
      geoDataReferences({'remarks': 'ext:custom.dat:CN', 'outbounds': []}),
    );
    final transfer = ConfigurationTransferService(
      lookup: db.geoDataDao.searchRowByName,
    );
    final shared = jsonDecode(
      await transfer.exportJson(
        kind: ConfigurationKind.custom,
        name: 'Pending',
        text: jsonEncode(json),
      ),
    ) as Map<String, dynamic>;
    expect(shared['geodata']['assets'], [
      {'file': 'custom.dat', 'url': 'https://example.com/custom.dat'},
    ]);
    final index = await RoutingGeodataIndex.load(
      database: db,
      directory: datRoot.path,
    );
    expect(index.domainFiles, isNot(contains('custom.dat')));
    expect(downloads, 0);
    await service.updateCustom((await db.geoDataDao.allRows).single);
    await service.requireDependencies(refs);
    expect(
      (await RoutingGeodataIndex.load(
        database: db,
        directory: datRoot.path,
      )).domainFiles,
      contains('custom.dat'),
    );
  });

  test(
    'restore reuses identical sources, rejects newly introduced conflicts',
    () async {
      await service.ensureInstalled();
      final beforeAdd = await service.previewRestore([input()]);
      final different = GeoDataInput(
        fileName: 'custom.dat',
        type: GeoDataType.ip,
        url: 'https://example.com/other.dat',
      );
      await service.add(different);
      await expectLater(
        service.restoreSources(beforeAdd, (write) => write()),
        throwsA(anything),
      );
      final preview = await service.previewRestore([different]);
      final old = (await db.geoDataDao.allRows).single;
      final oldBytes = await rootBytes();
      expect(preview.pendingCount, 0);
      await service.restoreSources(preview, (write) => write());
      final restored = (await db.geoDataDao.allRows).single;
      expect(restored.id, greaterThan(old.id));
      expect(restored.installed, true);
      expect(await rootBytes(), oldBytes);
    },
  );

  test(
    'restore file removals roll back with the database transaction',
    () async {
      await service.ensureInstalled();
      await service.add(input());
      final original = await db.geoDataDao.allRows;
      final bytes = await rootBytes();
      final preview = await service.previewRestore([]);
      await expectLater(
        service.restoreSources(preview, (write) async {
          await write();
          throw StateError('fixture DB failure');
        }),
        throwsStateError,
      );
      expect(await db.geoDataDao.allRows, original);
      expect(await rootBytes(), bytes);
    },
  );

  for (final committed in [false, true]) {
    test(
      'cold recovery finishes interrupted restore, committed=$committed',
      () async {
        await service.ensureInstalled();
        await service.add(input());
        final old = (await db.geoDataDao.allRows).single;
        final stage = await workspace.createTemp('.onexray-geodata-restore-');
        await File(p.join(stage.path, 'restore.json')).writeAsString(
          jsonEncode([
            {'id': old.id, 'name': old.name},
          ]),
        );
        for (final suffix in ['dat', 'json']) {
          final name = '${old.name}.$suffix';
          await File(p.join(datRoot.path, name))
              .rename(p.join(stage.path, name));
        }
        if (committed) await db.geoDataDao.clearCustom();
        final cold = GeoDataService.forTesting(
          database: db,
          directory: datRoot.path,
          download: (_, _) async => fail('Recovery must not download'),
          count: count,
          copyBundled: (_) async => fail('Defaults must be retained'),
        );
        await cold.ensureInstalled();
        expect(await cold.watchPublished().first, hasLength(committed ? 2 : 3));
        expect(await stage.exists(), false);
      },
    );
  }

  test('manual update-all keeps the default pair and updates independent custom data', () async {
    await service.ensureInstalled();
    final draft = await service.prepareImports([input()]);
    await draft.save((writeMetadata) => writeMetadata());
    final defaults = {
      for (final name in ['geosite', 'geoip'])
        name: await File(p.join(datRoot.path, '$name.dat')).readAsString(),
    };
    revision = 'two';
    failDownload = 'geosite';
    final errors = await service.updateAll();
    expect(errors.keys, [-1]);
    for (final entry in defaults.entries) {
      expect(
        await File(p.join(datRoot.path, '${entry.key}.dat')).readAsString(),
        entry.value,
      );
    }
    expect(
      await File(p.join(datRoot.path, 'custom.dat')).readAsString(),
      'two',
    );
    expect(AppEventBus.instance.state.downloading, isFalse);
    await expectFlatRoot();
  });

  test(
    'Geodata download does not block tunnel save or installed reads',
    () async {
      await service.ensureInstalled();
      final coordinator = ConnectionCoordinator(
        database: db,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
        prepare: (_, _) async => throw StateError('Must not prepare'),
        start: (_) async => throw StateError('Must not start'),
        stop: () async => throw StateError('Must not stop'),
      );
      addTearDown(coordinator.dispose);
      await coordinator.initialize(observe: false, registerReferences: false);
      final editor = PolicyEditorService(
        coordinator: coordinator,
        platform: ConnectionPlatform.ios,
      );
      final draft = await editor.load();
      draft.policy['ipv6Enabled'] = false;
      final started = Completer<void>();
      final release = Completer<void>();
      beforeDownload = () async {
        if (!started.isCompleted) started.complete();
        await release.future;
      };
      final update = service.updateDefaults();
      await started.future;
      final saving = editor.save(
        draft: draft,
        confirm: (_) async => fail('Must not reconnect'),
      );
      try {
        expect(await saving.timeout(const Duration(seconds: 1)), isTrue);
        expect(
          await service.watchPublished().first.timeout(
            const Duration(seconds: 1),
          ),
          hasLength(2),
        );
        expect((await coordinator.configuration).policy.ipv6Enabled, isFalse);
        expect(release.isCompleted, isFalse);
      } finally {
        release.complete();
        await update;
        await saving;
      }
    },
  );

  test('publication waits for file readers but unrelated tasks keep running', () async {
    await service.ensureInstalled();
    final downloading = Completer<void>();
    final releaseDownload = Completer<void>();
    final reading = Completer<void>();
    final releaseReader = Completer<void>();
    beforeDownload = () async {
      if (!downloading.isCompleted) downloading.complete();
      await releaseDownload.future;
    };
    var published = false;
    final update = service.updateDefaults().then((_) => published = true);
    await downloading.future;
    final reader = service.withFiles(() async {
      // A nested read shares the same access, instead of queuing behind itself.
      expect(await service.watchPublished().first, hasLength(2));
      reading.complete();
      await releaseReader.future;
      expect(
        await File(p.join(datRoot.path, 'geoip.dat')).readAsString(),
        'bundled',
      );
    });
    try {
      await reading.future;
      releaseDownload.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(published, isFalse);
    } finally {
      if (!releaseDownload.isCompleted) releaseDownload.complete();
      releaseReader.complete();
      await reader;
      await update;
    }
    expect(
      await File(p.join(datRoot.path, 'geoip.dat')).readAsString(),
      revision,
    );
  });

  GeoDataService createService(AppDatabase database) =>
      GeoDataService.forTesting(
        database: database,
        directory: datRoot.path,
        download: (url, file) async {
          downloads++;
          await file.writeAsString(revision);
        },
        count: count,
        copyBundled: (path) async {
          for (final name in ['geoip', 'geosite']) {
            await File(p.join(path, '$name.dat')).writeAsString('bundled');
          }
          await File(p.join(path, 'timestamp.txt')).writeAsString('123');
        },
      );

  test(
    'local install creates both bundled defaults in the flat root',
    () async {
      await service.ensureInstalled();

      final files = await service.watchPublished().first;
      expect(downloads, 0);
      expect(files.map((file) => file.row.id).toSet(), {-1, -2});
      expect(files.map((file) => file.data.parent.path).toSet(), {
        datRoot.path,
      });
      expect(files.map((file) => file.indexFile.parent.path).toSet(), {
        datRoot.path,
      });
      expect(await db.geoDataDao.allRows, isEmpty);
      expect(
        files.every(
          (file) => file.row.timestamp.millisecondsSinceEpoch == 123000,
        ),
        isTrue,
      );
      expect(
        await File(p.join(datRoot.path, 'geoip.dat')).readAsString(),
        'bundled',
      );
      expect(
        await File(p.join(datRoot.path, 'geosite.dat')).readAsString(),
        'bundled',
      );
      await expectFlatRoot();

      await service.ensureInstalled();
      expect(
        await db.geoDataDao.publishedRows,
        files.map((file) => file.row).toList(),
      );
    },
  );

  test('failed initial installation can be retried', () async {
    failIndex = 'geosite';
    await expectLater(service.ensureInstalled(), throwsFormatException);
    failIndex = null;

    await service.ensureInstalled();

    expect(await service.watchPublished().first, hasLength(2));
  });

  test('deleted dat directory rebuilds a clean default publication', () async {
    await service.ensureInstalled();
    await service.add(input());
    await datRoot.delete(recursive: true);

    await service.ensureInstalled();

    expect((await db.geoDataDao.publishedRows).map((row) => row.id).toSet(), {
      -2,
      -1,
    });
    expect((await service.watchPublished().first).length, 2);
    expect(await File(p.join(datRoot.path, 'geoip.dat')).exists(), isTrue);
    expect(await File(p.join(datRoot.path, 'geosite.dat')).exists(), isTrue);
    expect(await File(p.join(datRoot.path, 'custom.dat')).exists(), isFalse);
    expect(await File(p.join(datRoot.path, 'custom.json')).exists(), isFalse);
  });

  test('deleted database file discards orphaned dat files', () async {
    await db.close();
    dbClosed = true;
    final databaseFile = File(p.join(workspace.path, 'db.sqlite'));
    var database = AppDatabase.forTesting(NativeDatabase(databaseFile));
    final installed = createService(database);
    await installed.ensureInstalled();
    await installed.add(input());
    await database.connectionConfigDao.commit(
      configurationJson: '{"connection":{"expert":true}}',
    );
    await database.close();
    await databaseFile.delete();

    database = AppDatabase.forTesting(NativeDatabase(databaseFile));
    addTearDown(database.close);
    final recreated = createService(database);
    await recreated.ensureInstalled(resetOrphanedFiles: true);

    expect(
      (await database.geoDataDao.publishedRows).map((row) => row.id).toSet(),
      {-2, -1},
    );
    expect((await recreated.watchPublished().first).length, 2);
    expect((await database.connectionConfigDao.read()).configurationJson, '{}');
    expect(await File(p.join(datRoot.path, 'custom.dat')).exists(), isFalse);
    expect(await File(p.join(datRoot.path, 'custom.json')).exists(), isFalse);
  });

  test('in-process data clear republishes bundled defaults', () async {
    await service.ensureInstalled();
    await service.add(input());

    await service.pauseForDataClear();
    await service.withFiles(() async {
      await db.geoDataDao.clear();
      await service.resetAfterDataClear();
    });
    service.resumeAfterDataClear();

    expect((await db.geoDataDao.publishedRows).map((row) => row.id).toSet(), {
      -2,
      -1,
    });
    expect(await File(p.join(datRoot.path, 'custom.dat')).exists(), isFalse);
    expect(await File(p.join(datRoot.path, 'custom.json')).exists(), isFalse);
    await expectFlatRoot();
  });

  test('startup ignores unrelated nested entries', () async {
    final nested = await Directory(p.join(datRoot.path, 'nested'))
        .create(recursive: true);
    final unrelated = File(p.join(nested.path, 'legacy.dat'));
    await unrelated.writeAsString('legacy');

    await service.ensureInstalled();

    expect(downloads, 0);
    expect(await service.watchPublished().first, hasLength(2));
    expect(await unrelated.readAsString(), 'legacy');
  });

  test('startup installs defaults despite unregistered routing data', () async {
    await datRoot.create();
    await File(p.join(datRoot.path, 'legacy.dat')).writeAsString('legacy');

    await service.ensureInstalled();

    expect(await service.watchPublished().first, hasLength(2));
    expect(downloads, 0);
    expect(
      await File(p.join(datRoot.path, 'legacy.dat')).readAsString(),
      'legacy',
    );
  });

  for (final damage in [
    'orphan',
    'missing DAT',
    'missing index',
    'invalid index',
  ]) {
    test(
      'startup ignores unrelated $damage with an existing manifest',
      () async {
        await service.ensureInstalled();
        await service.add(input());
        await service.ensureInstalled();
        final rows = await db.geoDataDao.publishedRows;
        switch (damage) {
          case 'orphan':
            await File(p.join(datRoot.path, 'orphan.dat'))
                .writeAsString('orphan');
          case 'missing DAT':
            await File(p.join(datRoot.path, 'custom.dat')).delete();
          case 'missing index':
            await File(p.join(datRoot.path, 'custom.json')).delete();
          case 'invalid index':
            await File(p.join(datRoot.path, 'custom.json')).writeAsString('{}');
        }
        final bytes = await rootBytes();
        final previousDownloads = downloads;

        await service.ensureInstalled();
        await createService(db).ensureInstalled();

        final index = await RoutingGeodataIndex.load(
          database: db,
          directory: datRoot.path,
        );
        expect((await index.regionCatalog()).regionCodes, contains('CN'));
        if (damage != 'orphan') {
          expect(index.domainFiles, isNot(contains('custom.dat')));
        }

        expect(await db.geoDataDao.publishedRows, rows);
        expect(await rootBytes(), bytes);
        expect(downloads, previousDownloads);
      },
    );
  }

  for (final damage in [
    'missing DAT',
    'empty DAT',
    'missing index',
    'empty index',
  ]) {
    test('startup locally overwrites both defaults after $damage', () async {
      await service.ensureInstalled();
      await service.updateDefaults();
      await service.add(input());
      final custom = (await db.geoDataDao.allRows).single;
      final customData = await File(p.join(datRoot.path, 'custom.dat'))
          .readAsBytes();
      final customIndex = await File(p.join(datRoot.path, 'custom.json'))
          .readAsBytes();
      final beforeDownloads = downloads;
      final file = File(
        p.join(
          datRoot.path,
          damage.endsWith('DAT') ? 'geoip.dat' : 'geoip.json',
        ),
      );
      if (damage.startsWith('missing')) {
        await file.delete();
      } else {
        await file.writeAsString('');
      }

      await createService(db).ensureInstalled();

      expect(downloads, beforeDownloads);
      expect(
        await File(p.join(datRoot.path, 'geoip.dat')).readAsString(),
        'bundled',
      );
      expect(
        await File(p.join(datRoot.path, 'geosite.dat')).readAsString(),
        'bundled',
      );
      expect((await service.watchPublished().first).length, 3);
      expect((await db.geoDataDao.allRows).single, custom);
      expect(
        await File(p.join(datRoot.path, 'custom.dat')).readAsBytes(),
        customData,
      );
      expect(
        await File(p.join(datRoot.path, 'custom.json')).readAsBytes(),
        customIndex,
      );
    });
  }

  test(
    'manual default update can replace damaged files without a startup gate',
    () async {
      await service.ensureInstalled();
      await service.add(input());
      await File(p.join(datRoot.path, 'geoip.dat')).writeAsString('');
      await File(p.join(datRoot.path, 'geosite.json')).writeAsString('{}');
      await File(p.join(datRoot.path, 'custom.json')).delete();
      await File(p.join(datRoot.path, 'orphan.dat')).writeAsString('orphan');
      final previous = await rootBytes();
      final previousRows = await db.geoDataDao.publishedRows;
      failDownload = 'geosite';

      await expectLater(
        service.updateDefaults(),
        throwsA(isA<SocketException>()),
      );
      expect(await rootBytes(), previous);
      expect(await db.geoDataDao.publishedRows, previousRows);

      failDownload = null;
      revision = 'repaired';
      await service.updateDefaults();
      expect(
        await File(p.join(datRoot.path, 'geoip.dat')).readAsString(),
        'repaired',
      );
      expect(
        await File(p.join(datRoot.path, 'geosite.dat')).readAsString(),
        'repaired',
      );
      expect(
        await File(p.join(datRoot.path, 'orphan.dat')).readAsString(),
        'orphan',
      );
      await service.updateCustom((await db.geoDataDao.allRows).single);
      expect(await service.watchPublished().first, hasLength(3));
    },
  );

  test(
    'failed default updates preserve every published byte in place',
    () async {
      await service.ensureInstalled();
      final rows = await db.geoDataDao.publishedRows;
      final before = await rootBytes();

      failDownload = 'geosite';
      await expectLater(
        service.updateDefaults(),
        throwsA(isA<SocketException>()),
      );
      expect(await db.geoDataDao.publishedRows, rows);
      expect(await rootBytes(), before);

      failDownload = null;
      failIndex = 'geosite';
      await expectLater(service.updateDefaults(), throwsFormatException);
      expect(await db.geoDataDao.publishedRows, rows);
      expect(await rootBytes(), before);
      await expectFlatRoot();

      failIndex = null;
      revision = 'two';
      await service.updateDefaults();
      expect(
        await File(p.join(datRoot.path, 'geoip.dat')).readAsString(),
        'two',
      );
      expect(
        await File(p.join(datRoot.path, 'geosite.dat')).readAsString(),
        'two',
      );
      await expectFlatRoot();
    },
  );

  test(
    'custom update rolls back, overwrites in place, and delete removes files',
    () async {
      await service.ensureInstalled();
      await service.add(input());
      final original = (await service.watchPublished().first).firstWhere(
        (file) => !file.builtIn,
      );
      final dataPath = original.data.path;
      final indexPath = original.indexFile.path;
      final before = await rootBytes();

      await db.customStatement(
        "CREATE TRIGGER fail_geo_update BEFORE UPDATE ON geo_data WHEN OLD.id > 0 BEGIN SELECT RAISE(FAIL, 'fixture'); END",
      );
      revision = 'two';
      await expectLater(service.updateCustom(original.row), throwsA(anything));
      expect(await db.geoDataDao.searchRow(original.row.id), original.row);
      expect(await rootBytes(), before);
      expect(await File(dataPath).readAsString(), 'one');

      await db.customStatement('DROP TRIGGER fail_geo_update');
      await service.updateCustom(original.row);
      final updated = (await service.watchPublished().first).firstWhere(
        (file) => !file.builtIn,
      );
      expect(updated.data.path, dataPath);
      expect(updated.indexFile.path, indexPath);
      expect(await updated.data.readAsString(), 'two');
      await expectFlatRoot();

      final beforeDelete = await rootBytes();
      await db.customStatement('''
        CREATE TRIGGER fail_geo_delete BEFORE DELETE ON geo_data
        WHEN OLD.id > 0 BEGIN SELECT RAISE(FAIL, 'fixture'); END
      ''');
      await expectLater(service.deleteGeoDat(updated.row), throwsA(anything));
      expect(await db.geoDataDao.searchRow(updated.row.id), updated.row);
      expect(await rootBytes(), beforeDelete);

      await db.customStatement('DROP TRIGGER fail_geo_delete');
      await service.deleteGeoDat(updated.row);
      expect(await File(dataPath).exists(), isFalse);
      expect(await File(indexPath).exists(), isFalse);
      expect(await db.geoDataDao.searchRow(updated.row.id), isNull);
      await expectFlatRoot();
    },
  );

  test(
    'a failed default metadata commit restores the pair and can retry',
    () async {
      await service.ensureInstalled();
      final rows = await db.geoDataDao.publishedRows;
      final before = await rootBytes();
      revision = 'two';
      await db.customStatement('''
      CREATE TRIGGER fail_geo_defaults BEFORE UPDATE ON geo_data
      WHEN OLD.name = 'geosite' BEGIN SELECT RAISE(FAIL, 'fixture'); END
    ''');

      await expectLater(service.updateDefaults(), throwsA(anything));
      expect(await db.geoDataDao.publishedRows, rows);
      expect(await rootBytes(), before);

      await db.customStatement('DROP TRIGGER fail_geo_defaults');
      await service.updateDefaults();
      for (final name in ['geoip', 'geosite']) {
        expect(
          await File(p.join(datRoot.path, '$name.dat')).readAsString(),
          'two',
        );
      }
      await expectFlatRoot();
    },
  );

  test('failed standalone add removes its downloaded flat files', () async {
    await service.ensureInstalled();
    await db.customStatement('''
      CREATE TRIGGER fail_geo_insert BEFORE INSERT ON geo_data
      WHEN NEW.name = 'custom' BEGIN SELECT RAISE(FAIL, 'fixture'); END
    ''');

    await expectLater(service.add(input()), throwsA(anything));

    expect(await db.geoDataDao.allRows, isEmpty);
    expect(await File(p.join(datRoot.path, 'custom.dat')).exists(), isFalse);
    expect(await File(p.join(datRoot.path, 'custom.json')).exists(), isFalse);
    await expectFlatRoot();
  });

  test(
    'import draft publishes only for commit and rolls an outer failure back',
    () async {
      await service.ensureInstalled();
      final draft = await service.prepareImports([input()]);
      final data = File(p.join(datRoot.path, 'custom.dat'));
      final index = File(p.join(datRoot.path, 'custom.json'));
      expect(await db.geoDataDao.allRows, isEmpty);
      expect(await data.exists(), isFalse);
      expect(await index.exists(), isFalse);

      await expectLater(
        draft.save((writeMetadata) async {
          expect(await data.readAsString(), 'one');
          expect(await index.exists(), isTrue);
          await expectFlatRoot();
          return db.transaction(() async {
            await writeMetadata();
            throw StateError('Config save failed');
          });
        }),
        throwsStateError,
      );
      expect(await db.geoDataDao.allRows, isEmpty);
      expect(await data.exists(), isFalse);
      expect(await index.exists(), isFalse);

      await draft.save((writeMetadata) => db.transaction(writeMetadata));
      await draft.dispose();
      expect((await db.geoDataDao.allRows).single.name, 'custom');
      expect(await data.readAsString(), 'one');
      expect(await index.exists(), isTrue);
      await expectFlatRoot();

      final before = downloads;
      await expectLater(
        service.prepareImports([input('CUSTOM.dat')]),
        throwsFormatException,
      );
      await expectLater(
        service.prepareImports([input('dup.dat'), input('Dup.dat')]),
        throwsFormatException,
      );
      await expectLater(
        service.prepareImports([input('other.DAT')]),
        throwsFormatException,
      );
      expect(downloads, before);
    },
  );

  test(
    'a failed import metadata transaction retries the same staged files',
    () async {
      await service.ensureInstalled();
      final before = await rootBytes();
      final draft = await service.prepareImports([
        input(),
        input('second.dat'),
      ]);
      addTearDown(draft.dispose);
      await db.customStatement('''
      CREATE TRIGGER fail_geo_import BEFORE INSERT ON geo_data
      WHEN NEW.name = 'second' BEGIN SELECT RAISE(FAIL, 'fixture'); END
    ''');

      await expectLater(
        draft.save((writeMetadata) => db.transaction(writeMetadata)),
        throwsA(anything),
      );
      expect(await db.geoDataDao.allRows, isEmpty);
      expect(await rootBytes(), before);
      expect(downloads, 2);

      await db.customStatement('DROP TRIGGER fail_geo_import');
      await draft.save((writeMetadata) => db.transaction(writeMetadata));
      expect(
        (await db.geoDataDao.allRows).map((row) => row.name),
        unorderedEquals(['custom', 'second']),
      );
      expect(downloads, 2);
      for (final name in ['custom', 'second']) {
        expect(
          await File(p.join(datRoot.path, '$name.dat')).readAsString(),
          'one',
        );
      }
      await draft.dispose();
      await expectFlatRoot();
    },
  );

  test('startup removes an interrupted unpublished import', () async {
    await service.ensureInstalled();
    final draft = await service.prepareImports([input()]);
    await expectLater(
      draft.save((_) async {
        expect(await File(p.join(datRoot.path, 'custom.dat')).exists(), isTrue);
        // A new process observes the published files before the old save commits.
        await createService(db).ensureInstalled();
        throw StateError('Interrupted save');
      }),
      throwsStateError,
    );
    await draft.dispose();

    expect(await db.geoDataDao.allRows, isEmpty);
    expect(await File(p.join(datRoot.path, 'custom.dat')).exists(), isFalse);
    expect(await File(p.join(datRoot.path, 'custom.json')).exists(), isFalse);
  });

  test('startup finishes an import committed before cleanup', () async {
    await service.ensureInstalled();
    final draft = await service.prepareImports([input()]);
    await draft.save((writeMetadata) async {
      await db.transaction(writeMetadata);
      // Simulate cold startup after SQL commit but before staging cleanup.
      await createService(db).ensureInstalled();
    });
    await draft.dispose();

    expect((await db.geoDataDao.allRows).single.name, 'custom');
    expect(
      await File(p.join(datRoot.path, 'custom.dat')).readAsString(),
      'one',
    );
    expect(await File(p.join(datRoot.path, 'custom.json')).exists(), isTrue);
  });

  test(
    'staging an import does not block clear-data or repopulate it',
    () async {
      await service.ensureInstalled();
      final started = Completer<void>();
      final release = Completer<void>();
      beforeDownload = () async {
        if (!started.isCompleted) started.complete();
        await release.future;
      };
      final preparing = service.prepareImports([input()]);
      await started.future;
      await service.pauseForDataClear();
      await service
          .withFiles(() async {
            await db.geoDataDao.clear();
            await service.resetAfterDataClear();
          })
          .timeout(const Duration(seconds: 1));
      service.resumeAfterDataClear();
      release.complete();
      final draft = await preparing;
      expect(await db.geoDataDao.allRows, isEmpty);
      expect(await File(p.join(datRoot.path, 'custom.dat')).exists(), isFalse);
      await draft.dispose();
    },
  );

  test('cancelled import never publishes files or metadata', () async {
    await service.ensureInstalled();
    final before = await rootBytes();
    final draft = await service.prepareImports([input()]);
    await draft.dispose();
    expect(await rootBytes(), before);
    expect(await db.geoDataDao.allRows, isEmpty);
    expect(
      await workspace
          .list()
          .where(
            (entry) =>
                p.basename(entry.path).startsWith('.onexray-geodata-import-'),
          )
          .toList(),
      isEmpty,
    );
  });

  test(
    'readers wait for the whole import save, not individual phases',
    () async {
      await service.ensureInstalled();
      final draft = await service.prepareImports([input()]);
      final published = Completer<void>();
      final release = Completer<void>();
      final saving = draft.save((writeMetadata) async {
        published.complete();
        await release.future;
        await db.transaction(writeMetadata);
      });
      await published.future;
      var read = false;
      final reading = service
          .watchPublished()
          .firstWhere((files) => files.any((file) => file.row.name == 'custom'))
          .then((files) {
            read = true;
            return files;
          });
      await Future<void>.delayed(Duration.zero);
      expect(read, isFalse);
      release.complete();
      await saving;
      expect((await reading).any((file) => file.row.name == 'custom'), isTrue);
      await draft.dispose();
    },
  );
}
