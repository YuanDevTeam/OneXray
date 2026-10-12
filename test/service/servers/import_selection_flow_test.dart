import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/import.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/ping/service.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test('import returns before probes; queued retest updates the list and next selection', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bus = AppEventBus();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(bus.close);
    addTearDown(db.close);

    final automaticStarted = Completer<void>();
    final releaseAutomatic = Completer<void>();
    final manualStarted = Completer<void>();
    final releaseManual = Completer<void>();
    Future<void>? retesting;
    var activeBatches = 0;
    var largestOverlap = 0;
    final ping = PingService.forTesting(
      database: db,
      runBatch: (sources, _) async {
        activeBatches++;
        if (activeBatches > largestOverlap) largestOverlap = activeBatches;
        try {
          if (sources.length == 3) {
            automaticStarted.complete();
            await releaseAutomatic.future;
            return const [
              PingBatchResult(true, 80, ''),
              PingBatchResult(true, 10, ''),
              PingBatchResult(true, 30, ''),
            ];
          }
          manualStarted.complete();
          await releaseManual.future;
          return const [PingBatchResult(true, 5, '')];
        } finally {
          activeBatches--;
        }
      },
    );
    addTearDown(() async {
      if (!releaseAutomatic.isCompleted) releaseAutomatic.complete();
      if (!releaseManual.isCompleted) releaseManual.complete();
      await retesting;
      await ping.pauseForDataClear();
    });
    final importer = ServerImportService(
      database: db,
      validate: (_) async => '', // Native configuration validation boundary.
      schedule: ping.schedulePingConfigIds,
    );
    final importedList = db.coreConfigDao.watchOutbounds().firstWhere(
      (rows) => rows.length == 3,
    );
    final imported = await importer.commit(
      await importer.preview(
        '{"outbounds":['
        '{"tag":"Slow","protocol":"freedom"},'
        '{"tag":"Fast","protocol":"freedom"},'
        '{"tag":"Middle","protocol":"freedom"}]}',
        manual: true,
      ),
    );
    final rows = await importedList.timeout(const Duration(seconds: 5));
    await automaticStarted.future.timeout(const Duration(seconds: 5));
    expect(imported.count, 3);
    expect(rows.every((row) => row.delay == PingDelayConstants.unknown), true);
    expect(bus.state.pinging, true);
    expect(releaseAutomatic.isCompleted, false);

    final slowId = rows.singleWhere((row) => row.name == 'Slow').id;
    retesting = ping.pingConfigIds([slowId], force: true);
    expect(manualStarted.isCompleted, false);
    final measuredList = db.coreConfigDao.watchOutbounds().firstWhere(
      (rows) => rows.every((row) => row.delay != PingDelayConstants.unknown),
    );
    releaseAutomatic.complete();
    await manualStarted.future.timeout(const Duration(seconds: 5));
    final measured = await measuredList.timeout(const Duration(seconds: 5));
    expect(measured.map((row) => row.name), ['Fast', 'Middle', 'Slow']);

    final settings = ConnectionSettings(
      smart: SmartRoutingSettings(entryCount: 2),
    );
    final resolver = ConnectionResolver(
      rows: db.coreConfigDao.watchOutbounds,
      probe: ping.pingConfigIds,
    );
    final beforeRetest = await resolver.resolve(settings);
    expect(beforeRetest.map((node) => node.name), ['Fast', 'Middle']);

    final retestedList = db.coreConfigDao.watchOutbounds().firstWhere(
      (rows) => rows.first.id == slowId && rows.first.delay == 5,
    );
    releaseManual.complete();
    await retesting;
    final retested = await retestedList.timeout(const Duration(seconds: 5));
    expect(retested.map((row) => row.name), ['Slow', 'Fast', 'Middle']);
    expect(largestOverlap, 1);
    expect(bus.state.pinging, false);

    final selected = await resolver.resolve(settings);
    final compiled = ConnectionCompiler.compile(
      settings: settings,
      entries: selected,
      regions: const RegionCatalog.empty(),
      options: RuntimeOptions(
        platform: ConnectionPlatform.android,
        sessionDirectory: '/unused-session',
        metricsPort: 18186,
        socksPort: 18187,
      ),
    );
    expect(compiled.entries.map((node) => node.name), ['Slow', 'Fast']);
    final balancer = (compiled.config['routing']['balancers'] as List).single;
    expect(balancer['tag'], 'proxy');
    expect(
      (balancer['selector'] as List).map((tag) => compiled.nodeTags[tag]),
      selected.map((node) => node.id),
    );
  });
}
