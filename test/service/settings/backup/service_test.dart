import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/backup/codec.dart';
import 'package:onexray/core/backup/model.dart';
import 'package:onexray/core/backup/storage.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/backup/assets.dart';
import 'package:onexray/service/settings/backup/service.dart';
import 'package:onexray/service/settings/data_cleanup.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/ping/service.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late BackupAssets assets;
  late BackupService service;
  late AppDataCleanupService cleanup;
  late MemoryBackupPreferences preferences;
  late MemoryBackupStorage storage;
  var stops = 0;
  var stopFails = false;
  Future<void> Function()? beforeRestore;
  var now = DateTime(2026, 9, 16);

  Future<void> insert(String name) => db.coreConfigDao
      .insertRow(
        CoreConfigCompanion.insert(
          name: name,
          type: 'raw',
          tags: '',
          data: Value(base64Encode(utf8.encode('{ "outbounds": [] }'))),
          delay: 0,
          subId: 0,
        ),
      )
      .then((_) {});

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final parent = await Directory('../references/onexray-tests').absolute
        .create(recursive: true);
    final root = await parent.createTemp('backup-service-');
    addTearDown(() => root.delete(recursive: true));
    final geodata = GeoDataService.forTesting(
      database: db,
      directory: '${root.path}/dat',
      download: (_, _) async => fail('Restore must stay offline'),
      count: (_, _, _) async => fail('No indexing'),
      copyBundled: (_) async => fail('No default replacement'),
    );
    assets = BackupAssets(db, geodata, platform: ConnectionPlatform.android);
    stops = 0;
    stopFails = false;
    beforeRestore = null;
    now = DateTime(2026, 9, 16);
    final coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => null,
      inspect: (_, {observedStatus}) async =>
          const HostConnection(VpnStatus.disconnected),
      prepare: (_, _) async => throw StateError('No preparation'),
      start: (_) async => throw StateError('No VPN start'),
      stop: () async {
        stops++;
        if (stopFails) throw const ConnectionHostException('stopFailed');
        return const HostConnection(VpnStatus.disconnected);
      },
    );
    await coordinator.initialize(observe: false, registerReferences: false);
    addTearDown(coordinator.dispose);
    storage = MemoryBackupStorage();
    preferences = MemoryBackupPreferences();
    service = BackupService.forTesting(
      storage: storage,
      preferences: preferences,
      assets: assets,
      now: () => now,
      restore: (commit) => cleanup.runForRestore(() async {
        await beforeRestore?.call();
        await commit();
      }),
    );
    addTearDown(service.close);
    cleanup = AppDataCleanupService.forTesting(
      coordinator: coordinator,
      geodata: geodata,
      backup: service,
      ping: PingService.forTesting(
        database: db,
        runBatch: (_, _) async => fail('No probes'),
      ),
      subscriptions: SubscriptionService.forTesting(
        database: db,
        loadRows: (_) async => fail('No subscriptions'),
        schedulePing: (_) {},
      ),
      clear: () async {
        await db.coreConfigDao.clear();
        preferences.settings = const BackupSettings();
      },
    );
  });

  Future<BackupPreview> savedPreview() async {
    preferences.enabled = false;
    preferences.settings = BackupSettings(target: storage.target);
    await insert('Restored');
    storage.bytes = encodeBackup(await assets.capture());
    await db.coreConfigDao.clear();
    await insert('Current');
    await service.load();
    return service.preview();
  }

  test(
    'preview does not write or stop before restoring an existing binding',
    () async {
      final preview = await savedPreview();
      expect((preview.raw, preview.pending), (1, 0));
      expect((storage.writes, stops), (0, 0));
      expect(
        (await db.coreConfigDao.allRawRowsWithData).single.name,
        'Current',
      );
      expect(await service.restore(preview), 0);
      expect(stops, 1);
      expect(
        (await db.coreConfigDao.allRawRowsWithData).single.name,
        'Restored',
      );
      expect(storage.writes, 0);
    },
  );

  test('failed stop makes no replacement and admits a later retry', () async {
    final preview = await savedPreview();
    final original = await db.coreConfigDao.allRawRowsWithData;
    stopFails = true;
    await expectLater(
      service.restore(preview),
      throwsA(isA<ConnectionHostException>()),
    );
    expect(await db.coreConfigDao.allRawRowsWithData, original);
    expect(service.state.operation, null);
    stopFails = false;
    await service.restore(preview);
    expect((await db.coreConfigDao.allRawRowsWithData).single.name, 'Restored');
  });

  test('empty manual groups count as assets and replace previous groups on restore', () async {
    final originalId = await db.manualServerGroupDao.insertRow(
      ManualServerGroupCompanion.insert(name: 'Empty group'),
    );
    preferences.enabled = false;
    preferences.settings = BackupSettings(target: storage.target);
    storage.bytes = encodeBackup(await assets.capture());
    await db.manualServerGroupDao.clear();
    await db.manualServerGroupDao.insertRow(
      ManualServerGroupCompanion.insert(name: 'Current group'),
    );
    await service.load();
    final preview = await service.preview();
    expect(
      (preview.nodes, preview.raw, preview.groups, preview.empty),
      (0, 0, 1, false),
    );
    expect(stops, 0);
    await service.restore(preview);
    final group = (await db.manualServerGroupDao.allRows).single;
    expect(group.name, 'Empty group');
    expect(group.id, greaterThan(originalId));
    expect(stops, 1);
  });

  test(
    'a missing manual group reference fails preview without replacing assets',
    () async {
      await insert('Current');
      final groupId = await db.manualServerGroupDao.insertRow(
        ManualServerGroupCompanion.insert(name: 'Current group'),
      );
      final json = (await assets.capture()).toJson();
      json['coreConfigs'] = [
        const BackupCoreConfig(
          'Imported',
          'outbound',
          '',
          'e30=',
          manualGroupKey: 'missing',
        ).toJson(),
      ];
      storage.bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      preferences.enabled = false;
      preferences.settings = BackupSettings(target: storage.target);
      await service.load();
      await expectLater(service.preview(), throwsFormatException);
      expect(
        (await db.coreConfigDao.allRawRowsWithData).single.name,
        'Current',
      );
      expect((await db.manualServerGroupDao.allRows).single.id, groupId);
      expect((stops, storage.writes), (0, 0));
    },
  );

  test(
    'a transaction failure restores original rows and does not start VPN',
    () async {
      await db.manualServerGroupDao.insertRow(
        ManualServerGroupCompanion.insert(name: 'Group'),
      );
      await db.connectionConfigDao.commit(
        configurationJson: ConnectionConfiguration(
          policy: PlatformPolicy.fromJson({
            'ipv6Enabled': false,
            'android': {
              'appScope': 'included',
              'includedAppPackageNames': ['net.example.backup'],
            },
          }),
        ).encode(),
      );
      final preview = await savedPreview();
      await db.connectionConfigDao.commit(
        configurationJson: ConnectionConfiguration(
          policy: PlatformPolicy.fromJson({
            'android': {
              'appScope': 'excluded',
              'excludedAppPackageNames': ['net.example.target'],
            },
          }),
        ).encode(),
      );
      final original = await db.coreConfigDao.allRawRowsWithData;
      final groups = await db.manualServerGroupDao.allRows;
      final originalConfiguration = await db.connectionConfigDao.read();
      await db.customStatement(
        "CREATE TRIGGER reject_restore BEFORE INSERT ON core_config WHEN NEW.name = 'Restored' BEGIN SELECT RAISE(ABORT, 'fixture insert failure'); END;",
      );
      await expectLater(service.restore(preview), throwsA(anything));
      expect(await db.coreConfigDao.allRawRowsWithData, original);
      expect(await db.manualServerGroupDao.allRows, groups);
      expect(await db.connectionConfigDao.read(), originalConfiguration);
      expect(stops, 1);
    },
  );

  for (final invalid in [
    42,
    {
      'android': {'appScope': 'unsupported'},
    },
    {
      'android': {'includedAppPackageNames': 'not a list'},
    },
    {
      'lanProxy': {'port': 'not a port'},
    },
  ]) {
    test(
      'invalid matching platform settings fail preview before destructive work: $invalid',
      () async {
        await insert('Current');
        await db.connectionConfigDao.commit(
          configurationJson: ConnectionConfiguration(
            policy: PlatformPolicy.fromJson({
              'android': {
                'appScope': 'excluded',
                'excludedAppPackageNames': ['net.example.keep'],
              },
            }),
          ).encode(),
        );
        final original = await db.coreConfigDao.allRawRowsWithData;
        final originalConfiguration = await db.connectionConfigDao.read();
        final snapshot = (await assets.capture()).toJson();
        snapshot['platformSettings'] = {'android': invalid};
        storage.bytes = Uint8List.fromList(utf8.encode(jsonEncode(snapshot)));
        preferences.enabled = false;
        preferences.settings = BackupSettings(target: storage.target);
        await service.load();

        await expectLater(service.preview(), throwsFormatException);
        expect(await db.coreConfigDao.allRawRowsWithData, original);
        expect(await db.connectionConfigDao.read(), originalConfiguration);
        expect((stops, storage.writes), (0, 0));
        expect(service.state.operation, null);
      },
    );
  }

  test(
    'preview validates partial platform settings against the target policy',
    () async {
      await insert('Current');
      await db.connectionConfigDao.commit(
        configurationJson: ConnectionConfiguration(
          policy: PlatformPolicy.fromJson({
            'apple': {
              'disconnectWifiSsids': ['Home'],
            },
          }),
        ).encode(),
      );
      final original = await db.connectionConfigDao.read();
      final snapshot = (await assets.capture()).toJson()
        ..['platformSettings'] = {
          'ios': {
            'apple': {
              'connectWifiSsids': ['Home'],
            },
          },
        };
      storage.bytes = Uint8List.fromList(utf8.encode(jsonEncode(snapshot)));
      preferences.enabled = false;
      preferences.settings = BackupSettings(target: storage.target);
      final appleService = BackupService.forTesting(
        storage: storage,
        preferences: preferences,
        assets: BackupAssets(
          db,
          assets.geodata,
          platform: ConnectionPlatform.ios,
        ),
        now: () => now,
        restore: (_) async => fail('Preview cannot begin restore'),
      );
      addTearDown(appleService.close);
      await appleService.load();

      await expectLater(appleService.preview(), throwsFormatException);
      expect(await db.connectionConfigDao.read(), original);
      expect((stops, storage.writes), (0, 0));
      expect(
        (await db.coreConfigDao.allRawRowsWithData).single.name,
        'Current',
      );
    },
  );

  test('malformed foreign platform settings do not block ordinary asset restoration', () async {
    await insert('Restored');
    final snapshot = (await assets.capture()).toJson();
    snapshot['platformSettings'] = {
      'ios': 42,
      'macos': {
        'apple': {'alwaysOn': 'not a boolean'},
      },
      'windows': null,
    };
    storage.bytes = Uint8List.fromList(utf8.encode(jsonEncode(snapshot)));
    await db.coreConfigDao.clear();
    await insert('Current');
    await db.connectionConfigDao.commit(
      configurationJson: ConnectionConfiguration(
        policy: PlatformPolicy.fromJson({
          'ipv6Enabled': false,
          'android': {
            'appScope': 'excluded',
            'excludedAppPackageNames': ['net.example.keep'],
          },
        }),
      ).encode(),
    );
    final originalConfiguration = ConnectionConfiguration.fromJson(
      jsonDecode((await db.connectionConfigDao.read()).configurationJson)
          as Map<String, dynamic>,
    );
    preferences.enabled = false;
    preferences.settings = BackupSettings(target: storage.target);
    await service.load();
    final preview = await service.preview();
    expect((preview.raw, stops, storage.writes), (1, 0, 0));
    await service.restore(preview);
    expect((await db.coreConfigDao.allRawRowsWithData).single.name, 'Restored');
    final restored = ConnectionConfiguration.fromJson(
      jsonDecode((await db.connectionConfigDao.read()).configurationJson)
          as Map<String, dynamic>,
    );
    expect(restored.policy.toJson(), originalConfiguration.policy.toJson());
    expect((stops, storage.writes), (1, 0));
  });

  test('clear waits for accepted provider write, rejects restore, then resets binding', () async {
    final preview = await savedPreview();
    final accepted = Completer<void>();
    final finish = Completer<void>();
    storage.onWrite = () async {
      accepted.complete();
      await finish.future;
    };
    final writing = service.backupNow();
    await accepted.future;
    final clearing = cleanup.clearFromSettings();
    await expectLater(service.restore(preview), throwsStateError);
    expect((await db.coreConfigDao.allRawRowsWithData).single.name, 'Current');
    finish.complete();
    expect(await writing, true);
    expect(await clearing, true);
    await service.load();
    expect(service.state.settings.target, null);
    expect(storage.writes, 1);
  });

  test('restore owns destructive gate; repeated restore and clear cannot deadlock it', () async {
    final preview = await savedPreview();
    final entered = Completer<void>();
    final release = Completer<void>();
    beforeRestore = () async {
      entered.complete();
      await release.future;
    };
    final restoring = service.restore(preview);
    await entered.future;
    expect(await cleanup.clearFromSettings(), false);
    await expectLater(service.restore(preview), throwsStateError);
    release.complete();
    expect(await restoring, 0);
    expect(stops, 1);
  });

  test('auto defaults on; binding writes immediately and subsequent checks follow the interval', () async {
    expect(await BackupPreferences().automatic(), true);
    await service.load();
    await service.checkAutomatic();
    expect((storage.reads, storage.writes), (0, 0));
    await insert('Backed up');
    expect(await service.select(create: false), true);
    expect(storage.writes, 1);
    expect(decodeBackup(storage.bytes!).coreConfigs.single.name, 'Backed up');
    expect(preferences.settings.lastSuccess, now);
    await service.checkAutomatic();
    expect(storage.writes, 1);
    now = now.add(const Duration(days: 2));
    await service.checkAutomatic();
    expect(storage.writes, 1);
    await service.setInterval(AutoUpdateInterval.oneDay);
    expect(service.state.interval, AutoUpdateInterval.oneDay);
    expect(storage.writes, 1);
    await service.checkAutomatic();
    expect(storage.writes, 2);
  });

  test('saving the interval stays local, persists after reload and survives unbinding', () async {
    preferences.enabled = false;
    await service.setInterval(AutoUpdateInterval.oneWeek);
    await service.load();
    expect(service.state.interval, AutoUpdateInterval.oneWeek);
    expect(preferences.period, AutoUpdateInterval.oneWeek);
    expect((storage.reads, storage.writes), (0, 0));
    await service.select(create: false);
    await service.unbind();
    await service.load();
    expect(service.state.interval, AutoUpdateInterval.oneWeek);
    expect((storage.reads, storage.writes), (0, 1));
  });

  test('a failed interval save preserves the previous choice', () async {
    preferences.beforeSaveInterval = () async =>
        throw StateError('Save failed');
    await expectLater(
      service.setInterval(AutoUpdateInterval.oneWeek),
      throwsStateError,
    );
    expect(service.state.operation, null);
    expect(service.state.interval, AutoUpdateInterval.threeDays);
    expect(preferences.period, AutoUpdateInterval.threeDays);
    expect((storage.reads, storage.writes), (0, 0));
  });

  test('disabled automatic backups do not prevent manual writes or advance a separate interval', () async {
    await service.setAutomatic(false);
    await service.select(create: false);
    now = now.add(const Duration(days: 10));
    await service.checkAutomatic();
    expect(storage.writes, 1);
    expect(await service.backupNow(), true);
    expect(preferences.settings.lastSuccess, now);
    await service.setAutomatic(true);
    await Future<void>.delayed(Duration.zero);
    expect(storage.writes, 2);
  });

  test('failed automatic write keeps success time and retries no sooner than one hour', () async {
    await service.select(create: false);
    final lastSuccess = now;
    now = now.add(const Duration(days: 3));
    storage.onWrite = () async =>
        throw const FileSystemException('Fixture quota exceeded');
    await service.checkAutomatic();
    expect(preferences.settings.lastSuccess, lastSuccess);
    expect(service.state.error, isA<FileSystemException>());
    expect(storage.writes, 2);
    now = now.add(const Duration(minutes: 59));
    await service.checkAutomatic();
    expect(storage.writes, 2);
    storage.onWrite = null;
    now = now.add(const Duration(minutes: 1));
    await service.checkAutomatic();
    expect(storage.writes, 3);
    expect(service.state.error, null);
    expect(preferences.settings.lastSuccess, now);
  });

  test('checks coalesce, target cannot change during write, and accepted write may finish after disabling', () async {
    final accepted = Completer<void>();
    final release = Completer<void>();
    storage.onWrite = () async {
      accepted.complete();
      await release.future;
    };
    final binding = service.select(create: false);
    await accepted.future;
    await service.checkAutomatic();
    await expectLater(service.select(create: false), throwsStateError);
    await service.setAutomatic(false);
    release.complete();
    expect(await binding, true);
    expect(storage.writes, 1);
    expect(service.state.automatic, false);
    expect(preferences.settings.lastSuccess, now);
    storage.target = const BackupTarget('new', 'New backup');
    storage.bytes = null;
    storage.onWrite = null;
    await service.select(create: false);
    expect(preferences.settings.target!.identifier, 'new');
    expect(preferences.settings.lastSuccess, now);
    expect(storage.released, ['fixture']);
    expect(storage.writes, 2);
  });

  test(
    'disabling before provider I/O cancels an automatic write being encoded',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      service = BackupService.forTesting(
        storage: storage,
        preferences: preferences,
        assets: _HeldAssets(assets.db, assets.geodata, entered, release),
        now: () => now,
      );
      addTearDown(service.close);
      preferences.settings = BackupSettings(target: storage.target);
      final writing = service.checkAutomatic();
      await entered.future;
      await service.setAutomatic(false);
      release.complete();
      await writing;
      expect(storage.writes, 0);
      expect(preferences.settings.lastSuccess, null);
    },
  );

  test('a late preference read cannot undo disabling auto backup', () async {
    preferences.settings = BackupSettings(target: storage.target);
    final reading = Completer<void>();
    final release = Completer<void>();
    preferences.beforeInterval = () async {
      reading.complete();
      await release.future;
    };
    final checking = service.checkAutomatic();
    await reading.future;
    await service.setAutomatic(false);
    release.complete();
    await checking;
    expect(service.state.automatic, false);
    expect(storage.writes, 0);
  });

  test('cancelled selection keeps the binding and explicit unbind never deletes a file', () async {
    await service.select(create: false);
    final before = preferences.settings;
    final bytes = storage.bytes;
    storage.target = null;
    expect(await service.select(create: false), false);
    expect(preferences.settings, before);
    await service.unbind();
    expect(preferences.settings.target, null);
    expect(storage.released, ['fixture']);
    expect(storage.writes, 1);
    expect(storage.bytes, bytes);
  });

  test(
    'existing content requires a choice before rebinding or writing',
    () async {
      await service.select(create: false);
      expect(await service.select(create: false), false);
      expect(storage.writes, 1);
      storage.target = const BackupTarget('new', 'New backup');
      storage.bytes = null;
      await service.select(create: false);
      expect(storage.writes, 2);
      expect(storage.released, ['fixture']);
      expect(preferences.settings.lastSuccess, now);
    },
  );

  test('failed first backup retains the binding, throttles automatic retry and allows manual retry', () async {
    storage.onWrite = () async =>
        throw const FileSystemException('Fixture quota exceeded');
    await expectLater(
      service.select(create: false),
      throwsA(isA<FileSystemException>()),
    );
    expect(preferences.settings.target!.identifier, 'fixture');
    expect(preferences.settings.lastSuccess, null);
    expect(service.state.error, isA<FileSystemException>());
    await service.checkAutomatic();
    expect(storage.writes, 1);
    storage.onWrite = null;
    expect(await service.backupNow(), true);
    expect(storage.writes, 2);
    expect(service.state.error, null);
    expect(preferences.settings.lastSuccess, now);
  });

  test(
    'legacy unconfirmed targets stay unbound until the file is selected again',
    () async {
      preferences.settings = BackupSettings.fromJson({
        'target': storage.target!.toJson(),
        'confirmed': false,
      });
      storage.bytes = Uint8List.fromList([1, 2, 3]);
      final original = storage.bytes;
      await service.checkAutomatic();
      expect(service.state.settings.target, null);
      expect(storage.writes, 0);
      expect(storage.bytes, original);
      expect(await service.select(create: false), false);
      expect(storage.probes, 1);
      expect(preferences.settings.target, null);
      expect(preferences.settings.toJson(), isNot(contains('confirmed')));
    },
  );

  for (final legacyConfirmed in [true, null]) {
    test(
      'confirmed or current bindings retain automatic backup ($legacyConfirmed)',
      () async {
        preferences.settings = BackupSettings.fromJson({
          'target': storage.target!.toJson(),
          'confirmed': ?legacyConfirmed,
        });
        await service.checkAutomatic();
        expect(
          preferences.settings.target?.identifier,
          storage.target!.identifier,
        );
        expect(storage.writes, 1);
        expect(preferences.settings.lastSuccess, now);
        expect(preferences.settings.toJson(), isNot(contains('confirmed')));
      },
    );
  }

  test('interruption before the initial write does not postpone a new empty target', () async {
    preferences.settings = BackupSettings(
      target: const BackupTarget('old', 'Old backup'),
      lastSuccess: now,
    );
    storage.onRelease = () async =>
        throw const FileSystemException('Fixture grant release failed');
    await expectLater(
      service.select(create: true),
      throwsA(isA<FileSystemException>()),
    );
    expect(preferences.settings.target!.identifier, 'fixture');
    expect(storage.writes, 0);
    storage.onRelease = null;
    await service.checkAutomatic();
    expect(storage.writes, 1);
    expect(preferences.settings.lastSuccess, now);
  });

  test('existing-file decisions block other writes and cancel preserves the old binding', () async {
    final original = BackupSettings(
      target: const BackupTarget('old', 'Old backup'),
      lastSuccess: now,
    );
    preferences.settings = original;
    storage.bytes = Uint8List.fromList([1, 2, 3]);
    final before = storage.bytes;
    final entered = Completer<void>();
    final choice = Completer<BackupExistingAction?>();
    final binding = service.select(
      create: false,
      onExisting: (_, _) {
        entered.complete();
        return choice.future;
      },
    );
    await entered.future;
    await service.checkAutomatic();
    await expectLater(service.backupNow(), throwsStateError);
    expect(preferences.settings, original);
    expect((storage.reads, storage.writes), (0, 0));
    choice.complete(null);
    expect(await binding, false);
    expect(preferences.settings, original);
    expect(storage.bytes, before);
    expect(storage.released, ['fixture']);
  });

  test('overwrite works without parsing the existing contents even with automatic backup disabled', () async {
    preferences.enabled = false;
    storage.bytes = Uint8List.fromList(utf8.encode('not a backup'));
    await insert('Current');
    expect(
      await service.select(
        create: false,
        onExisting: (_, _) async => BackupExistingAction.overwrite,
      ),
      true,
    );
    expect(storage.reads, 0);
    expect(storage.writes, 1);
    expect(decodeBackup(storage.bytes!).coreConfigs.single.name, 'Current');
    expect(service.state.automatic, false);
  });

  test('restoring during binding reuses one preview and preserves the file until the next interval', () async {
    preferences.settings = BackupSettings(
      target: const BackupTarget('old', 'Old backup'),
      lastSuccess: now,
    );
    await insert('Restored');
    storage.bytes = encodeBackup(await assets.capture());
    final original = storage.bytes;
    await db.coreConfigDao.clear();
    await insert('Current');
    expect(
      await service.select(
        create: false,
        onExisting: (_, preview) async {
          expect((await preview()).raw, 1);
          return BackupExistingAction.restore;
        },
      ),
      true,
    );
    expect((await db.coreConfigDao.allRawRowsWithData).single.name, 'Restored');
    expect((storage.reads, storage.writes, stops), (1, 0, 1));
    expect(storage.bytes, original);
    expect(preferences.settings.boundAt, now);
    expect(preferences.settings.lastSuccess, null);
    expect(storage.released, ['old']);
    await service.checkAutomatic();
    expect(storage.writes, 0);
    now = now.add(const Duration(days: 3));
    await service.checkAutomatic();
    expect(storage.writes, 1);
  });

  test('invalid restore and probe failures cannot bind or overwrite the selected file', () async {
    storage.bytes = Uint8List.fromList([42]);
    final original = storage.bytes;
    await expectLater(
      service.select(
        create: false,
        onExisting: (_, _) async => BackupExistingAction.restore,
      ),
      throwsFormatException,
    );
    expect(preferences.settings.target, null);
    expect(storage.bytes, original);
    expect((storage.writes, stops), (0, 0));
    storage.onProbe = () async =>
        throw const FileSystemException('Fixture access denied');
    await expectLater(
      service.select(create: false),
      throwsA(isA<FileSystemException>()),
    );
    expect(preferences.settings.target, null);
    expect(storage.writes, 0);
    expect(storage.released, ['fixture', 'fixture']);
  });

  test('binding persistence failure cannot commit a restore or release the old target', () async {
    await insert('Restored');
    storage.bytes = encodeBackup(await assets.capture());
    final source = storage.bytes;
    await db.coreConfigDao.clear();
    await insert('Current');
    final previous = BackupSettings(
      target: const BackupTarget('old', 'Old backup'),
      lastSuccess: now,
    );
    preferences.settings = previous;
    preferences.beforeSave = (_) async =>
        throw const FileSystemException('Fixture preferences unavailable');
    await expectLater(
      service.select(
        create: false,
        onExisting: (_, _) async => BackupExistingAction.restore,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect((await db.coreConfigDao.allRawRowsWithData).single.name, 'Current');
    expect(preferences.settings, previous);
    expect(service.state.settings, previous);
    expect((storage.writes, stops), (0, 0));
    expect(storage.bytes, source);
    expect(storage.released, ['fixture']);
  });

  for (final rollbackFails in [false, true]) {
    test(
      'failed restore rolls back the binding or retains its grant if rollback fails ($rollbackFails)',
      () async {
        await insert('Restored');
        storage.bytes = encodeBackup(await assets.capture());
        final source = storage.bytes;
        await db.coreConfigDao.clear();
        await insert('Current');
        final previous = BackupSettings(
          target: const BackupTarget('old', 'Old backup'),
          boundAt: now.subtract(const Duration(days: 5)),
          lastSuccess: now.subtract(const Duration(days: 4)),
          lastAttempt: now.subtract(const Duration(days: 2)),
        );
        preferences.settings = previous;
        preferences.beforeSave = (value) async {
          if (rollbackFails && value.target == previous.target) {
            throw const FileSystemException('Fixture preferences unavailable');
          }
        };
        String? boundDuringRestore;
        beforeRestore = () async {
          boundDuringRestore = preferences.settings.target?.identifier;
          await service.checkAutomatic();
          throw StateError('Fixture restore failure');
        };
        await expectLater(
          service.select(
            create: false,
            onExisting: (_, _) async => BackupExistingAction.restore,
          ),
          rollbackFails
              ? throwsA(isA<FileSystemException>())
              : throwsStateError,
        );
        expect(boundDuringRestore, storage.target!.identifier);
        expect(
          (await db.coreConfigDao.allRawRowsWithData).single.name,
          'Current',
        );
        if (rollbackFails) {
          expect(preferences.settings.target, storage.target);
          expect(service.state.settings.target, storage.target);
          expect(storage.released, isEmpty);
        } else {
          expect(preferences.settings, previous);
          expect(service.state.settings, previous);
          expect(storage.released, ['fixture']);
        }
        expect(storage.writes, 0);
        expect(storage.bytes, source);
      },
    );
  }

  test('a failed first write retries after one hour instead of waiting a whole interval', () async {
    storage.onWrite = () async =>
        throw const FileSystemException('Fixture quota exceeded');
    await expectLater(
      service.select(create: true),
      throwsA(isA<FileSystemException>()),
    );
    now = now.add(const Duration(minutes: 59));
    await service.checkAutomatic();
    expect(storage.writes, 1);
    storage.onWrite = null;
    now = now.add(const Duration(minutes: 1));
    await service.checkAutomatic();
    expect(storage.writes, 2);
    expect(preferences.settings.lastSuccess, now);
  });
}

class MemoryBackupPreferences extends BackupPreferences {
  BackupSettings settings = const BackupSettings();
  bool enabled = true;
  AutoUpdateInterval period = AutoUpdateInterval.threeDays;
  Future<void> Function()? beforeInterval;
  Future<void> Function()? beforeSaveInterval;
  Future<void> Function(BackupSettings)? beforeSave;
  @override
  Future<BackupSettings> read() async => settings;
  @override
  Future<void> save(BackupSettings value) async {
    await beforeSave?.call(value);
    settings = value;
  }

  @override
  Future<bool> automatic() async => enabled;
  @override
  Future<void> saveAutomatic(bool value) async {
    enabled = value;
  }

  @override
  Future<AutoUpdateInterval> interval() async {
    await beforeInterval?.call();
    return period;
  }

  @override
  Future<void> saveInterval(AutoUpdateInterval value) async {
    await beforeSaveInterval?.call();
    period = value;
  }
}

class MemoryBackupStorage implements BackupStorage {
  BackupTarget? target = const BackupTarget('fixture', 'Fixture backup');
  Uint8List? bytes;
  int writes = 0;
  int reads = 0;
  int probes = 0;
  final released = <String>[];
  final selections = <(bool, bool)>[];
  Future<void> Function()? onWrite;
  Future<void> Function()? onProbe;
  Future<void> Function()? onRelease;
  @override
  Future<BackupTarget?> select({
    required bool create,
    bool local = false,
  }) async {
    selections.add((create, local));
    return target;
  }

  @override
  Future<Uint8List> read(BackupTarget target) async {
    reads++;
    return bytes!;
  }

  @override
  Future<bool> hasContents(BackupTarget target) async {
    probes++;
    await onProbe?.call();
    return bytes?.isNotEmpty ?? false;
  }

  @override
  Future<void> write(BackupTarget target, Uint8List value) async {
    writes++;
    await onWrite?.call();
    bytes = value;
  }

  @override
  Future<void> release(BackupTarget target) async {
    await onRelease?.call();
    released.add(target.identifier);
  }
}

class _HeldAssets extends BackupAssets {
  _HeldAssets(super.db, super.geodata, this.entered, this.release);
  final Completer<void> entered;
  final Completer<void> release;
  @override
  Future<BackupDocument> capture() async {
    entered.complete();
    await release.future;
    return super.capture();
  }
}
