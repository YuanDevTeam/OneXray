import 'dart:async';

import 'package:onexray/core/errors/failure.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/servers/import.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/sort.dart';
import 'package:onexray/service/settings/data_cleanup.dart';
import 'package:onexray/service/advanced/tunnel/android/automation/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/ping/service.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late GeoDataService geodata;
  var stopFails = false;
  var stops = 0;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    stops = 0;
    stopFails = false;
    coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => null,
      inspect: (_, {observedStatus}) async =>
          const HostConnection(VpnStatus.disconnected),
      prepare: (_, _) async => throw StateError('Must not prepare'),
      start: (_) async => throw StateError('Must not start VPN'),
      stop: () async {
        stops++;
        if (stopFails) throw const ConnectionHostException('stopFailed');
        return const HostConnection(VpnStatus.disconnected);
      },
    );
    await coordinator.initialize(observe: false, registerReferences: false);
    addTearDown(coordinator.dispose);
    // This test exercises the real file queue, but never accesses the filesystem.
    geodata = GeoDataService.forTesting(
      database: db,
      directory: '../references/onexray-tests/unused-clear-data',
      download: (_, _) async => fail('No download expected'),
      count: (_, _, _) async => fail('No indexing expected'),
      copyBundled: (_) async => fail('No asset installation expected'),
    );
  });

  test(
    'clear cancels queued probes and later sources, then drains active writes',
    () async {
      final ids = <int>[];
      for (var i = 0; i < 7; i++) {
        ids.add(await db.coreConfigDao.insertRow(_node('Node $i')));
      }
      final probing = Completer<void>();
      final releaseProbe = Completer<void>();
      var batches = 0;
      final ping = PingService.forTesting(
        database: db,
        runBatch: (sources, _) async {
          batches++;
          probing.complete();
          await releaseProbe.future;
          return List.generate(
            sources.length,
            (_) => const PingBatchResult(true, 20, ''),
          );
        },
      );
      final downloading = Completer<void>();
      final response = Completer<SubscriptionLoadResult>();
      final loaded = <String>[];
      final subscriptions = SubscriptionService.forTesting(
        database: db,
        loadRows: (input) {
          loaded.add(input.name);
          downloading.complete();
          return response.future;
        },
        schedulePing: ping.schedulePingSubscription,
      );
      final imports = ServerImportService(
        subscribe: (link) => subscriptions.insertSubscription(
          SubscriptionInput(name: link.name, url: link.url),
        ),
      );
      final active = ping.pingConfigIds(ids.take(6).toList());
      await probing.future;
      final queued = expectLater(
        ping.pingConfigIds([ids.last]),
        throwsStateError,
      );
      final importing = imports.importSubscriptions(
        imports
            .detect(
              'https://example.com/one#First\nhttps://example.com/two#Second',
            )
            .subscriptions,
      );
      await downloading.future;

      final fileEntered = Completer<void>();
      final releaseFile = Completer<void>();
      final publication = geodata.withFiles(() async {
        fileEntered.complete();
        await releaseFile.future;
      });
      await fileEntered.future;
      var cleared = false;
      final cleanup = AppDataCleanupService.forTesting(
        coordinator: coordinator,
        geodata: geodata,
        subscriptions: subscriptions,
        ping: ping,
        clear: () async {
          expect(batches, 1);
          expect(loaded, ['First']);
          await db.transaction(() async {
            await db.coreConfigDao.clear();
            await db.subscriptionDao.clear();
            await db.connectionConfigDao.reset();
          });
          cleared = true;
        },
      );
      final clearing = cleanup.clearFromSettings();
      addTearDown(() async {
        if (!releaseProbe.isCompleted) releaseProbe.complete();
        if (!releaseFile.isCompleted) releaseFile.complete();
        if (!response.isCompleted) {
          response.complete(
            const SubscriptionLoadResult(
              status: SubscriptionUpdateResult.downloadFailed,
            ),
          );
        }
        await Future.wait([active, queued, importing, publication, clearing]);
      });
      expect(await cleanup.clearFromSettings(), isFalse);
      await expectLater(
        subscriptions.insertSubscription(
          const SubscriptionInput(
            name: 'Too late',
            url: 'https://example.com/late',
          ),
        ),
        throwsStateError,
      );
      expect(cleared, isFalse);

      releaseProbe.complete();
      response.complete(
        SubscriptionLoadResult(
          status: SubscriptionUpdateResult.success,
          rows: [_node('Downloaded')],
        ),
      );
      await active;
      await queued;
      expect(await importing, hasLength(1));
      expect(cleared, isFalse, reason: 'File publication must finish first');
      expect(stops, 0);
      releaseFile.complete();
      expect(await clearing, isTrue);
      expect(stops, 1);
      expect(AppEventBus.instance.state.pinging, isFalse);
      expect(await db.select(db.coreConfig).get(), isEmpty);
      expect(await db.subscriptionDao.allRows, isEmpty);

      await db.coreConfigDao.insertRow(
        _node('Fresh').copyWith(id: Value(ids.last)),
      );
      await Future<void>.delayed(Duration.zero);
      final fresh = (await db.coreConfigDao.searchRow(ids.last))!;
      expect(fresh.name, 'Fresh');
      expect(fresh.delay, PingDelayConstants.unknown);
      expect(batches, 1);
    },
  );

  test('failed stop preserves data and resumes paused modules', () async {
    await AppEventBus.instance.setServerSort(ServerSortOrder.name);
    final id = await db.coreConfigDao.insertRow(_node('Existing'));
    final ping = PingService.forTesting(
      database: db,
      runBatch: (sources, _) async => List.generate(
        sources.length,
        (_) => const PingBatchResult(true, 20, ''),
      ),
    );
    final subscriptions = SubscriptionService.forTesting(
      database: db,
      loadRows: (_) async => SubscriptionLoadResult(
        status: SubscriptionUpdateResult.success,
        rows: [_node('New')],
      ),
      schedulePing: (_) {},
    );
    var clears = 0;
    final cleanup = AppDataCleanupService.forTesting(
      coordinator: coordinator,
      geodata: geodata,
      subscriptions: subscriptions,
      ping: ping,
      clear: () async {
        clears++;
      },
    );
    stopFails = true;
    await expectLater(
      cleanup.clearFromSettings(),
      throwsA(
        isA<AppFailure>()
            .having((error) => error.code, 'stage', 'cleanupBeforeDelete')
            .having(
              (error) => error.cause,
              'cause',
              isA<ConnectionHostException>(),
            ),
      ),
    );
    expect(clears, 0);
    expect(AppEventBus.instance.state.serverSort, ServerSortOrder.name);
    expect(await PreferencesKey().readServerSort(), 'name');
    expect(await db.coreConfigDao.searchRow(id), isNotNull);
    await ping.pingConfigIds([id]);
    expect((await db.coreConfigDao.searchRow(id))!.delay, 20);
    expect(
      (await subscriptions.insertSubscription(
        const SubscriptionInput(name: 'New', url: 'https://example.com/new'),
      )).success,
      isTrue,
    );
    await coordinator.apply(
      await coordinator.configuration,
      affectsRuntime: false,
    );
    stopFails = false;
    expect(await cleanup.clearFromSettings(), isTrue);
    expect(clears, 1);
  });

  test('native admission is blocked before data writes; restore preserves authorization', () async {
    await AppEventBus.instance.setServerSort(ServerSortOrder.delay);
    final native = _AutomationHost();
    final cleanup = AppDataCleanupService.forTesting(
      coordinator: coordinator,
      geodata: geodata,
      subscriptions: SubscriptionService.forTesting(
        database: db,
        loadRows: (_) async => throw UnimplementedError(),
        schedulePing: (_) {},
      ),
      ping: PingService.forTesting(database: db, runBatch: (_, _) async => []),
      automation: AndroidAutomationService(api: native, supported: true),
      clear: () async {
        expect(native.blocked, isTrue);
        expect(native.clears, 1);
      },
    );
    await cleanup.runForRestore(() async {
      expect(native.blocked, isTrue);
    });
    expect(native.clears, 0);
    expect(native.blocked, isFalse);
    expect(AppEventBus.instance.state.serverSort, ServerSortOrder.delay);
    expect(await PreferencesKey().readServerSort(), 'delay');
    await expectLater(
      cleanup.runForRestore(() async => throw StateError('restore failed')),
      throwsStateError,
    );
    expect(native.blocked, isFalse);
    expect(native.clears, 0);
    native.failBlock = true;
    final stopsBefore = stops;
    await expectLater(cleanup.clearFromSettings(), throwsA(isA<AppFailure>()));
    expect(stops, stopsBefore);
    expect(native.clears, 0);
    native.failBlock = false;
    expect(await cleanup.clearFromSettings(), isTrue);
    expect(native.clears, 1);
    expect(native.blocked, isFalse);
  });
}

class _AutomationHost extends AndroidAutomationHostApi {
  bool blocked = false;
  bool failBlock = false;
  int clears = 0;
  @override
  Future<void> setStartBlocked(bool value) async {
    if (value && failBlock) throw StateError('Cannot block native starts');
    blocked = value;
  }

  @override
  Future<void> clear() async {
    expect(blocked, isTrue);
    clears++;
  }
}

CoreConfigCompanion _node(String name) => outboundCompanion({
  'tag': name,
  'protocol': 'socks',
  'settings': {'address': '127.0.0.1', 'port': 1080},
});
