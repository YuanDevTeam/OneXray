import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/manual_group_dialogs.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late ServersController controller;
  late ScrollController scroll;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(database: db);
    controller = ServersController(database: db, coordinator: coordinator);
    scroll = ScrollController();
    await controller.initialize();
  });

  tearDown(() async {
    scroll.dispose();
    await controller.close();
    coordinator.dispose();
    await db.close();
  });

  Future<void> settleUntil(WidgetTester tester, bool Function() ready) async {
    for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(
      ready(),
      isTrue,
      reason: 'The operation and catalog stream must complete.',
    );
  }

  Future<T> databaseOperation<T>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    var complete = false;
    T? result;
    Object? failure;
    action().then(
      (value) {
        result = value;
        complete = true;
      },
      onError: (Object error) {
        failure = error;
        complete = true;
      },
    );
    await settleUntil(tester, () => complete);
    if (failure != null) throw failure!;
    return result as T;
  }

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.material(Brightness.light, mobile: true),
        locale: locale,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: ShadToaster(child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              actions: [
                TextButton(
                  onPressed: () => controller.createManualGroup(context),
                  child: const Text('Create'),
                ),
              ],
            ),
            body: BlocBuilder<ServersController, ServersPageState>(
              bloc: controller,
              builder: (_, _) =>
                  ServerBrowser(controller: controller, scroll: scroll),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'empty groups can be created, renamed and dissolved from the list',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('manual-group-name')),
        'Cloud',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settleUntil(
        tester,
        () => controller.catalog.manualGroups.any(
          (group) => group.name == 'Cloud',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ManualGroupNameDialog), findsNothing);
      expect(find.text('Cloud'), findsOneWidget);
      expect(find.text('Ungrouped'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More actions: Cloud'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename group'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('manual-group-name')),
        'Home',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settleUntil(
        tester,
        () => controller.catalog.manualGroups.any(
          (group) => group.name == 'Home',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Cloud'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More actions: Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dissolve group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dissolve group').last);
      await settleUntil(tester, () => controller.catalog.manualGroups.isEmpty);
      await tester.pumpAndSettle();
      expect(find.byType(ManualGroupActionsDialog), findsNothing);
      expect(find.text('Home'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual node menu moves into a folder without selecting a connection',
    (tester) async {
      final group = await databaseOperation(
        tester,
        () => controller.manualGroupService.create('Home'),
      );
      final node = await databaseOperation(
        tester,
        () => db.coreConfigDao.insertAssetRow(
          outboundCompanion({'tag': 'Local node', 'protocol': 'socks'})
              .copyWith(favorite: const Value(true)),
        ),
      );
      await settleUntil(
        tester,
        () =>
            controller.catalog.manualGroups.any((value) => value.id == group) &&
            controller.servers.any((value) => value.id == node),
      );
      await pump(tester);
      await tester.tap(find.byType(ServerMenu).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to group'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ManualGroupMoveDialog),
          matching: find.text('Home'),
        ),
      );
      await settleUntil(
        tester,
        () => controller.servers.any(
          (row) => row.id == node && row.manualGroupId == group,
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.servers.single.manualGroupId, group);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in const [Locale('ru'), Locale('fa')]) {
    testWidgets('group actions fit a compact $locale display', (tester) async {
      await databaseOperation(
        tester,
        () => controller.manualGroupService.create('Cloud'),
      );
      await settleUntil(
        tester,
        () => controller.catalog.manualGroups.any(
          (group) => group.name == 'Cloud',
        ),
      );
      await pump(tester, locale: locale);
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerBrowser)),
      )!;
      await tester.tap(find.byTooltip('${l.prototypeMoreActions}: Cloud'));
      await tester.pumpAndSettle();
      expect(find.text(l.manualGroupDelete), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
