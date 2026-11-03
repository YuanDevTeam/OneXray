import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/pages/connect/controller.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/routing/custom/editor.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/custom/state_db.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

const _waitTimeout = Duration(seconds: 5);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late ConnectController connect;
  late ServersController servers;
  late AppEventBus bus;
  late int goodId, brokenId, nodeId;
  late RoutingProfileData originalGood;

  Future<void> waitForCatalog(bool Function() predicate) async {
    if (predicate()) return;
    // Subscribe to both real DB-driven controllers before checking again, so
    // either one's next emission can complete the shared readiness barrier.
    final changes = StreamController<void>();
    final connectChanges = connect.stream.listen((_) => changes.add(null));
    final serverChanges = servers.stream.listen((_) => changes.add(null));
    try {
      if (!predicate()) {
        await changes.stream
            .firstWhere((_) => predicate())
            .timeout(_waitTimeout);
      }
    } finally {
      await connectChanges.cancel();
      await serverChanges.cancel();
      await changes.close();
    }
  }

  setUp(() async {
    bus = AppEventBus();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    goodId = await db.routingProfileDao.insertRow(
      RoutingProfileState(name: 'Readable route').insertCompanion,
    );
    brokenId = await db.routingProfileDao.insertRow(
      RoutingProfileCompanion.insert(
        name: 'Damaged route',
        data: 'invalid-base64!',
        advanced: const Value(true),
      ),
    );
    originalGood = (await db.routingProfileDao.searchRow(goodId))!;
    nodeId = await db.coreConfigDao.insertRow(
      outboundCompanion({
        'tag': 'Available node',
        'protocol': 'socks',
        'settings': {
          'servers': [
            {'address': '127.0.0.1', 'port': 18080},
          ],
        },
      }),
    );
    coordinator = ConnectionCoordinator(database: db);
    connect = ConnectController(database: db, coordinator: coordinator);
    servers = ServersController(database: db, coordinator: coordinator);
    await connect.initialize();
    await servers.initialize();
    await waitForCatalog(
      () =>
          connect.customRoutes.any((row) => row.id == goodId) &&
          servers.customRoutes.any((row) => row.id == goodId) &&
          connect.servers.any((row) => row.id == nodeId) &&
          servers.servers.any((row) => row.id == nodeId),
    );
  });

  tearDown(() async {
    await connect.close();
    await servers.close();
    coordinator.dispose();
    await db.close();
    await bus.close();
  });

  test(
    'bad unused routes do not block Smart/All or retain a newly damaged row',
    () async {
      const automatic = ServerSelection.automatic();
      for (final mode in [TrafficMode.smart, TrafficMode.allVpn]) {
        await db.connectionConfigDao.commit(
          configurationJson: ConnectionConfiguration(
            connection: ConnectionSettings(trafficMode: mode),
          ).encode(),
        );
        await waitForCatalog(
          () =>
              connect.configuration.connection.trafficMode == mode &&
              servers.configuration.connection.trafficMode == mode,
        );
        expect(connect.ready && !connect.failed, isTrue);
        expect(servers.ready && !servers.failed, isTrue);
        expect(connect.customRoutes.map((row) => row.id), [goodId]);
        expect(servers.customRoutes.map((row) => row.id), [goodId]);
        expect(connect.candidateCount(automatic), 1);
        expect(servers.canUseSelection(automatic, servers.servers), isTrue);
      }

      expect(
        await db.routingProfileDao.updateRow(
          originalGood.copyWith(data: 'also-invalid-base64!'),
        ),
        isTrue,
      );
      await waitForCatalog(
        () => connect.customRoutes.isEmpty && servers.customRoutes.isEmpty,
      );
      expect(connect.failed || servers.failed, isFalse);
      expect(servers.canUseSelection(automatic, servers.servers), isTrue);

      expect(await db.routingProfileDao.updateRow(originalGood), isTrue);
      await waitForCatalog(
        () =>
            connect.customRoutes.any((row) => row.id == goodId) &&
            servers.customRoutes.any((row) => row.id == goodId),
      );
      expect(connect.customRoutes.map((row) => row.id), [goodId]);
      expect(servers.customRoutes.map((row) => row.id), [goodId]);
      expect(connect.failed || servers.failed, isFalse);
    },
  );

  test(
    'a selected damaged Custom route stays unavailable without changing mode',
    () async {
      final selected = ConnectionConfiguration(
        connection: ConnectionSettings(
          trafficMode: TrafficMode.custom,
          customId: brokenId,
        ),
      );
      await db.connectionConfigDao.commit(configurationJson: selected.encode());
      await waitForCatalog(
        () =>
            connect.configuration.connection.customId == brokenId &&
            servers.configuration.connection.customId == brokenId,
      );
      expect(connect.failed || servers.failed, isFalse);
      expect(servers.entryCount(const ServerSelection.automatic()), 0);
      expect(
        servers.canUseSelection(
          const ServerSelection.automatic(),
          servers.servers,
        ),
        isFalse,
      );
      await expectLater(
        CustomRoutingEditorService(
          database: db,
          coordinator: coordinator,
        ).load((await coordinator.configuration).connection.customId),
        throwsFormatException,
      );
      expect((await coordinator.configuration).encode(), selected.encode());
      expect(connect.configuration.connection.trafficMode, TrafficMode.custom);
      expect(servers.configuration.connection.trafficMode, TrafficMode.custom);
      expect(connect.customRoutes.map((row) => row.id), [goodId]);
      expect(servers.customRoutes.map((row) => row.id), [goodId]);
    },
  );
}
