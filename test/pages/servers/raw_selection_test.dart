import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  late AppDatabase db;
  late _Coordinator coordinator;
  late ServersController controller;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = _Coordinator(db);
    controller = ServersController(database: db, coordinator: coordinator);
    addTearDown(() async {
      await controller.close();
      coordinator.dispose();
      await db.close();
    });
  });

  Future<BuildContext> open(WidgetTester tester) async {
    await tester.runAsync(
      () => coordinator.initialize(observe: false, registerReferences: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        builder: (_, child) => ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: ShadToaster(child: child!),
        ),
        home: const Scaffold(body: Text('Raw selection host')),
      ),
    );
    return tester.element(find.text('Raw selection host'));
  }

  Future<CoreConfigData> raw() async {
    final id = await db.coreConfigDao.insertRow(
      CoreConfigCompanion.insert(
        name: 'Personal Raw',
        type: 'raw',
        tags: '',
        delay: 9000,
        subId: 0,
        data: Value(
          base64Encode(
            utf8.encode(
              '{"outbounds":[{"protocol":"freedom"}],"future":{"kept":true}}',
            ),
          ),
        ),
      ),
    );
    return (await db.coreConfigDao.searchRow(id))!;
  }

  testWidgets(
    'a readable Raw is explicitly selected without starting or validating Core',
    (tester) async {
      final context = await open(tester);
      await tester.runAsync(() async {
        final row = await raw();
        final before = await coordinator.configuration;
        await controller.chooseRaw(context, row);
        final saved = await coordinator.configuration;
        expect(saved.connection.expert, isTrue);
        expect(saved.connection.rawId, row.id);
        expect(saved.policy.toJson(), before.policy.toJson());
        expect(coordinator.applies, 1);
        expect(controller.selecting, isNull);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reselecting the same active Raw does not request reconnect or another commit',
    (tester) async {
      final context = await open(tester);
      await tester.runAsync(() async {
        final row = await raw();
        final current = ConnectionConfiguration(
          connection: ConnectionSettings(expert: true, rawId: row.id),
        );
        await db.connectionConfigDao.commit(
          configurationJson: current.encode(),
        );
        coordinator.state.value = const ConnectionView(
          phase: ConnectionPhase.connected,
        );
        await controller.chooseRaw(context, row);
        expect(coordinator.applies, 0);
        expect((await coordinator.configuration).encode(), current.encode());
        expect(controller.selecting, isNull);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deleted, changed-type and unreadable Raw snapshots cannot replace the saved plan',
    (tester) async {
      final context = await open(tester);
      for (final change in ['deleted', 'type', 'encoding', 'json', 'array']) {
        await tester.runAsync(() async {
          final row = await raw();
          final before = await coordinator.configuration;
          if (change == 'deleted') {
            await db.coreConfigDao.deleteRow(row);
          } else if (change == 'type') {
            // The typed asset DAO deliberately refuses changing asset type.
            // Bypass it here to represent a stale row after data replacement.
            await (db.update(db.coreConfig)..where((t) => t.id.equals(row.id)))
                .write(const CoreConfigCompanion(type: Value('outbound')));
            expect(
              (await db.coreConfigDao.searchRow(row.id))!.type,
              'outbound',
            );
          } else {
            final changed = await db.coreConfigDao.updateRow(
              row.copyWith(
                data: Value(
                  change == 'encoding'
                      ? 'not base64'
                      : base64Encode(
                          utf8.encode(
                            change == 'json'
                                ? '{'
                                : change == 'array'
                                ? '[]'
                                : '{}',
                          ),
                        ),
                ),
              ),
            );
            expect(changed, isTrue, reason: change);
          }
          await controller.chooseRaw(context, row);
          expect(
            (await coordinator.configuration).encode(),
            before.encode(),
            reason: change,
          );
          expect(coordinator.applies, 0, reason: change);
          expect(controller.selecting, isNull);
        });
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Raw deletion after precommit validation is caught inside the asset transaction',
    (tester) async {
      final context = await open(tester);
      await tester.runAsync(() async {
        final row = await raw();
        final before = await coordinator.configuration;
        coordinator.afterValidation = () async {
          await db.coreConfigDao.deleteRow(row);
        };
        await controller.chooseRaw(context, row);
        expect(coordinator.applies, 1);
        expect(await db.coreConfigDao.searchRow(row.id), isNull);
        expect((await coordinator.configuration).encode(), before.encode());
        expect(controller.selecting, isNull);
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

class _Coordinator extends ConnectionCoordinator {
  _Coordinator(AppDatabase db)
    : super(
        database: db,
        readRuntime: () async => null,
        inspect: (_, {observedStatus}) async =>
            const HostConnection(VpnStatus.disconnected),
        prepare: (_, _) async =>
            throw StateError('Raw selection must not prepare Core'),
        start: (_) async =>
            throw StateError('Raw selection must not start VPN'),
        stop: () async => throw StateError('Raw selection must not stop VPN'),
        disposeStatus: () {},
      );
  int applies = 0;
  Future<void> Function()? afterValidation;

  @override
  Future<void> apply(
    ConnectionConfiguration next, {
    bool connect = false,
    bool disconnect = false,
    bool affectsRuntime = true,
    bool allowReconnect = true,
    String? expectedConfiguration,
    Future<void> Function()? writeAssets,
    Future<void> Function()? validateAssets,
    ConfigurationImportDraft? imported,
    PrepareConnection? prepare,
  }) async {
    applies++;
    await super.apply(
      next,
      connect: connect,
      disconnect: disconnect,
      affectsRuntime: affectsRuntime,
      allowReconnect: allowReconnect,
      expectedConfiguration: expectedConfiguration,
      writeAssets: writeAssets,
      validateAssets: () async {
        await validateAssets?.call();
        await afterValidation?.call();
      },
      imported: imported,
      prepare: prepare,
    );
  }
}
