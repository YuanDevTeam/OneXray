import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:onexray/service/shared/ping/state.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    // PreferencesKey retains the backend selected by its first construction.
    // Clear through that instance so a saved toggle cannot leak between cases.
    await PreferencesKey().clearUserDataPreferences();
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  });

  test('manual retest updates delay and clears an old probe failure', () async {
    final node = await db.coreConfigDao.insertRow(_node('Node'));
    var runs = 0;
    final service = PingService.forTesting(
      database: db,
      runBatch: (_, _) async {
        runs++;
        return [
          runs == 1
              ? const PingBatchResult(
                  false,
                  PingDelayConstants.timeout,
                  'timeout',
                )
              : const PingBatchResult(true, 0, ''),
        ];
      },
    );
    await service.pingConfigIds([node]);
    expect(
      (await db.coreConfigDao.searchRow(node))!.delay,
      PingDelayConstants.timeout,
    );
    expect(AppEventBus.instance.state.pingFailures[node]?.error, 'timeout');
    await service.pingConfigIds([node], force: true);
    expect((await db.coreConfigDao.searchRow(node))!.delay, 0);
    expect(AppEventBus.instance.state.pingFailures.containsKey(node), isFalse);
  });

  test(
    'a task keeps its timeout across batches and later tasks reread it',
    () async {
      final ids = <int>[];
      for (var index = 0; index < 7; index++) {
        ids.add(await db.coreConfigDao.insertRow(_node('Node $index')));
      }
      final automatic = await db.coreConfigDao.insertRow(_node('Automatic'));
      final timeouts = <double>[];
      final service = PingService.forTesting(
        database: db,
        runBatch: (sources, state) async {
          timeouts.add(state.timeout);
          if (timeouts.length == 1) {
            await (PingState()..timeout = 8).saveToPreferences();
          }
          return _successes(sources.length);
        },
      );
      await service.pingConfigIds(ids, force: true);
      service.schedulePingConfigIds([automatic]);
      await service.pingConfigIds([automatic]);
      expect(timeouts, [5, 5, 8]);
      expect((await db.coreConfigDao.searchRow(automatic))!.delay, 20);
      expect(service.isPinging, isFalse);
    },
  );

  test('manual node probes leave Raw configurations unmeasured', () async {
    final node = await db.coreConfigDao.insertRow(_node('Node'));
    final raw = await db.coreConfigDao.insertRow(
      _node('Raw').copyWith(type: const Value('raw')),
    );
    final service = PingService.forTesting(
      database: db,
      runBatch: (sources, _) async {
        expect(sources, hasLength(1));
        expect(
          jsonDecode(sources.single.xrayJson)['outbounds'][0]['tag'],
          'Node',
        );
        return _successes(sources.length);
      },
    );

    await service.pingConfigIds([raw, node], force: true);

    expect((await db.coreConfigDao.searchRow(node))!.delay, 20);
    expect(
      (await db.coreConfigDao.searchRow(raw))!.delay,
      PingDelayConstants.unknown,
    );
  });

  test('imported-node and subscription queues always run', () async {
    final local = await db.coreConfigDao.insertRow(_node('Local'));
    final remote = await db.coreConfigDao.insertRow(_node('Remote', subId: 9));
    var batches = 0;
    final service = PingService.forTesting(
      database: db,
      runBatch: (sources, state) async {
        batches++;
        return _successes(sources.length);
      },
    );

    service.schedulePingConfigIds([local, local]);
    service.schedulePingSubscriptions([9, 9]);
    await service.pingConfigIds([local, remote]);

    // The last queued selection sees both measurements and does not probe again.
    expect(batches, 2);
    for (final id in [local, remote]) {
      final row = (await db.coreConfigDao.searchRow(id))!;
      expect(row.delay, 20);
      expect(PingService.isUnmeasured(row), isFalse);
    }
    expect(AppEventBus.instance.state.pinging, isFalse);
  });

  test(
    'automatic probes start after readiness and resume unmeasured rows',
    () async {
      final local = await db.coreConfigDao.insertRow(_node('Local'));
      final remote = await db.coreConfigDao.insertRow(
        _node('Remote', subId: 9),
      );
      final measured = await db.coreConfigDao.insertRow(
        _node('Measured').copyWith(delay: const Value(30)),
      );
      await db.coreConfigDao.insertRow(
        _node('Raw').copyWith(type: const Value('raw')),
      );
      await db.coreConfigDao.insertRow(
        _node('Empty').copyWith(data: const Value(null)),
      );
      final batches = <int>[];
      final service = PingService.forTesting(
        database: db,
        automaticEnabled: false,
        runBatch: (sources, _) async {
          batches.add(sources.length);
          return _successes(sources.length);
        },
      );
      service.schedulePingConfigIds([local]);
      service.schedulePingSubscriptions([9]);
      expect(service.isPinging, isFalse);
      expect(AppEventBus.instance.state.pinging, isFalse);
      expect(batches, isEmpty);
      expect(
        await db.coreConfigDao.unmeasuredOutboundIds,
        unorderedEquals([local, remote]),
      );

      final drained = AppEventBus.instance.stream
          .skipWhile((state) => !state.pinging)
          .firstWhere((state) => !state.pinging);
      service.startAutomatic();
      service.startAutomatic();
      await drained.timeout(const Duration(seconds: 5));
      expect(batches, [1, 1]);
      expect((await db.coreConfigDao.searchRow(measured))!.delay, 30);
      expect(await db.coreConfigDao.unmeasuredOutboundIds, isEmpty);

      service.stopAutomatic();
      final later = await db.coreConfigDao.insertRow(_node('Later'));
      service.schedulePingConfigIds([later]);
      expect(service.isPinging, isFalse);
      expect(await db.coreConfigDao.unmeasuredOutboundIds, [later]);
    },
  );

  test('five-node batch commits let selection finish while the remaining two continue', () async {
    final ids = <int>[];
    for (var index = 0; index < 7; index++) {
      ids.add(await db.coreConfigDao.insertRow(_node('Node $index')));
    }
    final secondStarted = Completer<void>();
    final releaseSecond = Completer<void>();
    final sizes = <int>[];
    Future<void>? probing;
    addTearDown(() async {
      if (!releaseSecond.isCompleted) releaseSecond.complete();
      await probing;
    });
    final service = PingService.forTesting(
      database: db,
      runBatch: (sources, _) async {
        sizes.add(sources.length);
        if (sizes.length == 2) {
          secondStarted.complete();
          await releaseSecond.future;
        }
        return _successes(sources.length);
      },
    );
    final resolver = ConnectionResolver(
      rows: () => db.select(db.coreConfig).watch(),
      probe: (ids) => probing = service.pingConfigIds(ids),
    );

    final resolving = resolver.resolve(
      ConnectionSettings(smart: SmartRoutingSettings(entryCount: 2)),
    );
    await secondStarted.future.timeout(const Duration(seconds: 5));
    final selected = await resolving.timeout(const Duration(seconds: 5));
    expect(sizes, [5, 2]);
    expect(releaseSecond.isCompleted, isFalse);
    expect(selected.map((node) => node.id), ids.take(2));
    expect(
      (await db.coreConfigDao.searchRow(ids.last))!.delay,
      PingDelayConstants.unknown,
    );
    releaseSecond.complete();
    await probing;
    expect((await db.coreConfigDao.searchRow(ids.last))!.delay, 20);
    expect(selected.map((node) => node.id), ids.take(2));
  });

  test(
    'cancelling finishes the current batch without cancelling queued work',
    () async {
      final ids = <int>[];
      for (var index = 0; index < 7; index++) {
        ids.add(await db.coreConfigDao.insertRow(_node('Node $index')));
      }
      final automaticId = await db.coreConfigDao.insertRow(_node('Automatic'));
      final started = Completer<void>();
      final release = Completer<void>();
      final sizes = <int>[];
      var cancelled = false;
      final service = PingService.forTesting(
        database: db,
        runBatch: (sources, _) async {
          sizes.add(sources.length);
          if (sizes.length == 1) {
            started.complete();
            await release.future;
          }
          return _successes(sources.length);
        },
      );
      final manual = service.pingConfigIds(
        ids,
        force: true,
        isCancelled: () => cancelled,
      );
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await manual;
      });
      expect(service.isPinging, isTrue);
      await started.future;
      final automatic = service.pingConfigIds([automaticId]);
      cancelled = true;
      expect(service.isPinging, isTrue);
      expect(sizes, [5]);

      release.complete();
      await manual;
      await automatic;

      expect(sizes, [5, 1]);
      for (final id in ids.take(5)) {
        expect((await db.coreConfigDao.searchRow(id))!.delay, 20);
      }
      for (final id in ids.skip(5)) {
        expect(
          (await db.coreConfigDao.searchRow(id))!.delay,
          PingDelayConstants.unknown,
        );
      }
      expect((await db.coreConfigDao.searchRow(automaticId))!.delay, 20);
      expect(service.isPinging, isFalse);
      expect(AppEventBus.instance.state.pinging, isFalse);
    },
  );

  test('failed results cannot look healthy and delayed writes preserve edits and favorites', () async {
    final first = await db.coreConfigDao.insertRow(_node('Failure'));
    final second = await db.coreConfigDao.insertRow(_node('Edited'));
    final started = Completer<void>();
    final release = Completer<void>();
    final service = PingService.forTesting(
      database: db,
      runBatch: (_, _) async {
        started.complete();
        await release.future;
        return const [
          PingBatchResult(false, 7, 'failure'),
          PingBatchResult(true, 9, ''),
        ];
      },
    );
    final probing = service.pingConfigIds([first, second]);
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await probing;
    });
    await started.future.timeout(const Duration(seconds: 5));
    await (db.update(db.coreConfig)..where((row) => row.id.equals(first)))
        .write(const CoreConfigCompanion(favorite: Value(true)));
    final edit = _node(
      'New content',
      subId: 9,
    ).copyWith(id: Value(second), favorite: const Value(true));
    await db.update(db.coreConfig).replace(edit);
    release.complete();
    await probing;

    final failed = (await db.coreConfigDao.searchRow(first))!;
    expect(failed.delay, PingDelayConstants.error);
    expect(PingService.isUnmeasured(failed), isFalse);
    expect(failed.favorite, isTrue);
    final edited = (await db.coreConfigDao.searchRow(second))!;
    expect(edited.name, 'New content');
    expect(edited.subId, 9);
    expect(edited.delay, PingDelayConstants.unknown);
    expect(PingService.isUnmeasured(edited), isTrue);
    expect(edited.favorite, isTrue);
  });

  test(
    'subscriptions and single nodes share FIFO without mixed batches',
    () async {
      final first = await db.coreConfigDao.insertRow(_node('S1-A', subId: 11));
      await db.coreConfigDao.insertRow(_node('S1-B', subId: 11));
      final second = await db.coreConfigDao.insertRow(_node('S2-A', subId: 12));
      final local = await db.coreConfigDao.insertRow(_node('Local'));
      final started = Completer<void>();
      final release = Completer<void>();
      final batches = <List<String>>[];
      var active = 0;
      var maximumActive = 0;
      final service = PingService.forTesting(
        database: db,
        runBatch: (sources, _) async {
          active++;
          if (active > maximumActive) maximumActive = active;
          batches.add([
            for (final source in sources)
              jsonDecode(source.xrayJson)['outbounds'][0]['tag'] as String,
          ]);
          if (!started.isCompleted) started.complete();
          await release.future;
          active--;
          return _successes(sources.length);
        },
      );
      service.schedulePingSubscriptions([11, 12]);
      await started.future.timeout(const Duration(seconds: 2));
      final single = service.pingConfigIds([local], force: true);
      final repeated = service.pingConfigIds([local], force: true);
      final mixed = service.pingConfigIds([first, second, local], force: true);
      release.complete();
      await Future.wait([single, repeated, mixed]);

      expect(batches, [
        ['S1-A', 'S1-B'],
        ['S2-A'],
        ['Local'],
        ['Local'],
        ['S1-A'],
        ['S2-A'],
        ['Local'],
      ]);
      expect(maximumActive, 1);
      expect(service.isPinging, isFalse);
      expect(AppEventBus.instance.state.pinging, isFalse);
    },
  );

  test(
    'a failed queued task does not block later requests or leave loading',
    () async {
      final failed = await db.coreConfigDao.insertRow(_node('Failed'));
      final next = await db.coreConfigDao.insertRow(_node('Next'));
      var calls = 0;
      final service = PingService.forTesting(
        database: db,
        runBatch: (sources, _) async {
          if (++calls == 1) throw StateError('Native probe failed');
          return _successes(sources.length);
        },
      );
      final failure = expectLater(
        service.pingConfigIds([failed]),
        throwsStateError,
      );
      final succeeding = service.pingConfigIds([next]);
      await Future.wait([failure, succeeding]);

      expect(calls, 2);
      expect((await db.coreConfigDao.searchRow(next))!.delay, 20);
      expect(service.isPinging, isFalse);
      expect(AppEventBus.instance.state.pinging, isFalse);
    },
  );

  test(
    'clear-data cancels queued subscription probes after the active batch',
    () async {
      final first = await db.coreConfigDao.insertRow(_node('First', subId: 11));
      final second = await db.coreConfigDao.insertRow(
        _node('Second', subId: 12),
      );
      final started = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final service = PingService.forTesting(
        database: db,
        runBatch: (sources, _) async {
          calls++;
          if (!started.isCompleted) started.complete();
          await release.future;
          return _successes(sources.length);
        },
      );
      service.schedulePingSubscription(11);
      await started.future.timeout(const Duration(seconds: 2));
      service.schedulePingSubscription(12);
      final drained = AppEventBus.instance.stream.firstWhere(
        (state) => !state.pinging,
      );
      final maintenance = service.pauseForDataClear();
      release.complete();
      await Future.wait([drained, maintenance])
          .timeout(const Duration(seconds: 2));

      expect(calls, 1, reason: 'The queued subscription must not start');
      expect((await db.coreConfigDao.searchRow(first))!.delay, 20);
      expect(
        (await db.coreConfigDao.searchRow(second))!.delay,
        PingDelayConstants.unknown,
      );
      expect(service.isPinging, isFalse);
      service.resumeAfterDataClear();
      await service.pingConfigIds([second]);
      expect(calls, 2);
    },
  );

  test('clear-data discards queued work before IDs can be reused', () async {
    final first = await db.coreConfigDao.insertRow(_node('First'));
    final second = await db.coreConfigDao.insertRow(_node('Second'));
    final started = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    var restored = false;
    final service = PingService.forTesting(
      database: db,
      runBatch: (sources, _) async {
        calls++;
        if (!started.isCompleted) started.complete();
        await release.future;
        return _successes(sources.length);
      },
    );
    final active = service.pingConfigIds([first]);
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await active;
    });
    await started.future.timeout(const Duration(seconds: 5));
    final queued = expectLater(
      service.pingConfigIds([second]),
      throwsStateError,
    );
    final restoring = service.pauseForDataClear().then((_) async {
      expect(calls, 1);
      await db.transaction(() async {
        await db.delete(db.coreConfig).go();
        for (final id in [first, second]) {
          await db.coreConfigDao.insertRow(
            _node('Restored').copyWith(id: Value(id)),
          );
        }
      });
      restored = true;
    });
    expect(restored, isFalse);
    release.complete();
    await active;
    await queued;
    await restoring;

    expect(restored, isTrue);
    expect(calls, 1);
    for (final id in [first, second]) {
      final row = (await db.coreConfigDao.searchRow(id))!;
      expect(row.name, 'Restored');
      expect(row.delay, PingDelayConstants.unknown);
    }
  });
}

List<PingBatchResult> _successes(int count) =>
    List.generate(count, (_) => const PingBatchResult(true, 20, ''));

CoreConfigCompanion _node(String name, {int subId = 0}) =>
    CoreConfigCompanion.insert(
      name: name,
      type: 'outbound',
      tags: 'socks',
      delay: PingDelayConstants.unknown,
      subId: subId,
      data: Value(
        base64Encode(
          utf8.encode(
            jsonEncode({
              'outbounds': [
                {
                  'tag': name,
                  'protocol': 'socks',
                  'settings': {'address': '127.0.0.1', 'port': 1080},
                },
              ],
            }),
          ),
        ),
      ),
    );
