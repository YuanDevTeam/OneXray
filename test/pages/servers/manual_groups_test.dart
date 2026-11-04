import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/details.dart';
import 'package:onexray/pages/servers/manual_group_dialogs.dart';
import 'package:onexray/pages/servers/order/controller.dart';
import 'package:onexray/pages/servers/order/page.dart';
import 'package:onexray/pages/servers/page.dart';
import 'package:onexray/pages/servers/sources.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/servers/sort.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;

import 'fixtures/server_test_router.dart';

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late ServersController controller;
  late ScrollController scroll;
  GoRouter? router;

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
    router?.dispose();
    router = null;
    scroll.dispose();
    await controller.close().timeout(const Duration(seconds: 5));
    coordinator.dispose();
    await db.close().timeout(const Duration(seconds: 5));
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  }

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
    Size size = const Size(390, 844),
    bool fullPage = false,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    router = serverTestRouter(
      extraRoutes: [
        GoRoute(
          path: 'manual-server-order',
          builder: (_, state) =>
              ManualOrderPage(params: state.extra! as ManualOrderParams),
        ),
      ],
      home: (_) => fullPage
          ? ServersPage(controller: controller)
          : Builder(
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
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.material(
          Brightness.light,
          mobile: size.width <= AppLayout.mobileBreakpoint,
        ),
        locale: locale,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: ShadTheme(
            data: AppTheme.shad(Brightness.light),
            child: ShadToaster(child: child!),
          ),
        ),
      ),
    );
    // The real page schedules initialization after its first frame. Drain that
    // SQLite read while both the fake widget clock and real IO can advance,
    // before teardown cancels its query subscriptions.
    await databaseOperation(tester, () => db.connectionConfigDao.read());
    await settle(tester);
  }

  testWidgets(
    'the root arranges all ungrouped nodes without changing display sorting',
    (tester) async {
      final ids = await databaseOperation(
        tester,
        () async => [
          await db.coreConfigDao.insertAssetRow(
            outboundCompanion({'tag': 'Alpha', 'protocol': 'socks'}),
          ),
          await db.coreConfigDao.insertAssetRow(
            outboundCompanion({'tag': 'Zulu', 'protocol': 'socks'}),
          ),
        ],
      );
      await settleUntil(tester, () => controller.servers.length == 2);
      await pump(tester);
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerBrowser)),
      )!;
      final selection = controller.configuration.toJson();
      await tester.tap(find.byTooltip(l.serverSortTitle));
      await settle(tester);
      await tester.tap(find.text(l.serverSortName).last);
      await settleUntil(
        tester,
        () =>
            controller.catalog.sortOrder == ServerSortOrder.name &&
            !controller.state.sortSaving,
      );
      await settle(tester);

      Future<void> openOrder() async {
        final entry = find.byKey(const ValueKey('manual-server-order'));
        await tester.ensureVisible(entry);
        await settle(tester);
        await tester.tap(entry);
        await settle(tester);
        expect(find.byType(ManualServerOrderScopeDialog), findsNothing);
        expect(find.byType(ManualOrderPage), findsOneWidget);
        expect(find.text(l.manualOrderDisplayHint), findsOneWidget);
        expect(
          tester
              .widget<ManualOrderPage>(find.byType(ManualOrderPage))
              .params
              .items
              .map((item) => item.id),
          ids,
        );
      }

      await openOrder();
      await tester.tap(find.byKey(ValueKey('move-up-${ids.last}')));
      await settle(tester);
      await tester.tap(find.text(l.prototypeCancel));
      await settle(tester);
      final afterCancel = await databaseOperation(
        tester,
        () => db.coreConfigDao.allActiveServerRows(),
      );
      expect(afterCancel.map((row) => row.manualSortOrder), [0, 1]);

      await openOrder();
      await tester.tap(find.byKey(ValueKey('move-up-${ids.last}')));
      await settle(tester);
      await tester.tap(find.text(l.prototypeSave));
      await settleUntil(
        tester,
        () =>
            controller.servers
                .firstWhere((row) => row.id == ids.last)
                .manualSortOrder ==
            0,
      );
      await settle(tester);
      expect(find.byType(ManualOrderPage), findsNothing);
      expect(controller.catalog.sortOrder, ServerSortOrder.name);
      expect(AppEventBus.instance.state.serverSort, ServerSortOrder.name);
      expect(controller.servers.map((row) => row.id), ids);
      expect(controller.configuration.toJson(), selection);

      await tester.tap(find.byTooltip(l.serverSortTitle));
      await settle(tester);
      await tester.tap(find.text(l.serverSortDefault).last);
      await settleUntil(
        tester,
        () =>
            controller.catalog.sortOrder == ServerSortOrder.defaultOrder &&
            !controller.state.sortSaving,
      );
      expect(controller.servers.map((row) => row.id), ids.reversed);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multiple manual scopes require a group and only save that complete group',
    (tester) async {
      final fixture = await databaseOperation(tester, () async {
        final home = await controller.manualGroupService.create('Home');
        final singleton = await controller.manualGroupService.create('Single');
        final empty = await controller.manualGroupService.create('Empty');
        final source = await db.subscriptionDao.insertRow(
          SubscriptionCompanion.insert(
            name: 'Subscription',
            url: 'https://example.test/subscription',
            timestamp: DateTime(2026),
          ),
        );
        final subscription = await db.coreConfigDao.insertAssetRow(
          outboundCompanion({'tag': 'Subscription node', 'protocol': 'socks'})
              .copyWith(subId: Value(source)),
        );
        final raw = await db.coreConfigDao.insertAssetRow(
          outboundCompanion({'tag': 'Personal Raw', 'protocol': 'socks'})
              .copyWith(type: const Value('raw')),
        );
        Future<int> add(String name, int? group) async {
          final id = await db.coreConfigDao.insertAssetRow(
            outboundCompanion({'tag': name, 'protocol': 'socks'}),
          );
          if (group != null) {
            await controller.manualGroupService.move({
              id,
            }, targetGroupId: group);
          }
          return id;
        }

        return (
          home: home,
          singleton: singleton,
          empty: empty,
          ungrouped: [
            await add('Ungrouped A', null),
            await add('Ungrouped B', null),
          ],
          grouped: [await add('Home A', home), await add('Home B', home)],
          single: await add('Single A', singleton),
          untouched: [
            (await db.coreConfigDao.searchRow(subscription))!,
            (await db.coreConfigDao.searchRow(raw))!,
          ],
        );
      });
      await settleUntil(
        tester,
        () =>
            controller.servers.length == 6 &&
            controller.rawConfigurations.length == 1 &&
            controller.catalog.manualGroups.length == 3,
      );
      await pump(tester);
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerBrowser)),
      )!;
      Future<void> chooseScope() async {
        final entry = find.byKey(const ValueKey('manual-server-order'));
        await tester.ensureVisible(entry);
        await settle(tester);
        await tester.tap(entry);
        await settle(tester);
        expect(find.byType(ManualServerOrderScopeDialog), findsOneWidget);
        expect(find.byType(ManualOrderPage), findsNothing);
      }

      await chooseScope();
      expect(find.text('Subscription'), findsNothing);
      expect(find.text('Personal Raw'), findsNothing);
      final ungrouped = find.byKey(
        const ValueKey('manual-order-scope-manual:ungrouped'),
      );
      final home = find.byKey(
        ValueKey('manual-order-scope-manual:${fixture.home}'),
      );
      expect(tester.widget<SettingRow>(ungrouped).enabled, isTrue);
      expect(tester.widget<SettingRow>(home).enabled, isTrue);
      expect(
        tester
            .widget<SettingRow>(
              find.byKey(
                ValueKey('manual-order-scope-manual:${fixture.singleton}'),
              ),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<SettingRow>(
              find.byKey(
                ValueKey('manual-order-scope-manual:${fixture.empty}'),
              ),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(home);
      await settle(tester);
      expect(
        tester
            .widget<ManualOrderPage>(find.byType(ManualOrderPage))
            .params
            .items
            .map((item) => item.id),
        fixture.grouped,
      );
      await tester.tap(find.byKey(ValueKey('move-up-${fixture.grouped.last}')));
      await settle(tester);
      await tester.tap(find.text(l.prototypeSave));
      await settleUntil(
        tester,
        () =>
            controller.servers
                .firstWhere((row) => row.id == fixture.grouped.last)
                .manualSortOrder ==
            0,
      );
      await settle(tester);
      final rows = await databaseOperation(
        tester,
        () => db.coreConfigDao.allActiveServerRows(),
      );
      final byId = {for (final row in rows) row.id: row};
      expect(byId[fixture.grouped.first]!.manualSortOrder, 1);
      expect(byId[fixture.grouped.last]!.manualSortOrder, 0);
      expect(byId[fixture.ungrouped.first]!.manualSortOrder, 0);
      expect(byId[fixture.ungrouped.last]!.manualSortOrder, 1);
      expect(byId[fixture.single]!.manualSortOrder, 0);
      final untouched = await databaseOperation(
        tester,
        () async => [
          for (final row in fixture.untouched)
            (await db.coreConfigDao.searchRow(row.id))!,
        ],
      );
      expect(untouched, fixture.untouched);
      expect(
        rows
            .where((row) => fixture.grouped.contains(row.id))
            .map((row) => row.manualGroupId),
        everyElement(fixture.home),
      );
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile subscriptions stay reachable independently of a long group list',
    (tester) async {
      await databaseOperation(tester, () async {
        await db.subscriptionDao.insertRow(
          SubscriptionCompanion.insert(
            name: 'Provider',
            url: 'https://example.test/subscription',
            timestamp: DateTime(2026),
          ),
        );
        for (var index = 0; index < 30; index++) {
          await db.manualServerGroupDao.insertRow(
            ManualServerGroupCompanion.insert(
              name: 'Folder $index',
              sortOrder: Value(index),
            ),
          );
        }
      });
      await settleUntil(
        tester,
        () => controller.catalog.manualGroups.length == 30,
      );
      await pump(tester, fullPage: true);
      final context = tester.element(find.byType(ServersPage));
      final l = AppLocalizations.of(context)!;
      final sources = find.text(l.prototypeSubscriptions).first;
      await tester.ensureVisible(sources);
      expect(sources.hitTestable(), findsOneWidget);
      await tester.tap(sources);
      await settle(tester);
      expect(find.byType(ServerSourcesView), findsOneWidget);
      expect(find.text('Provider'), findsOneWidget);
      await tester.tap(find.text('Provider'));
      await settle(tester);
      expect(find.byType(ServerSourcePage), findsOneWidget);
      expect(controller.catalog.manualGroups, hasLength(30));
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(tester.takeException(), isNull);
      router!.pop();
      await settle(tester);
      expect(find.byType(ServerSourcePage), findsNothing);
      expect(sources.hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'desktop source management survives creating an empty manual group',
    (tester) async {
      await databaseOperation(
        tester,
        () => db.subscriptionDao.insertRow(
          SubscriptionCompanion.insert(
            name: 'Provider',
            url: 'https://example.com/sub',
            timestamp: DateTime(2026),
          ),
        ),
      );
      await settleUntil(tester, () => controller.sources.length == 1);
      await pump(tester, size: const Size(1200, 900), fullPage: true);
      final context = tester.element(find.byType(ServersPage));
      final l = AppLocalizations.of(context)!;
      expect(find.text(l.prototypeSubscriptions), findsOneWidget);

      await tester.tap(find.byTooltip(l.manualGroupNew));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('manual-group-name')),
        'Empty folder',
      );
      await tester.pump();
      await tester.tap(find.text(l.prototypeSave));
      await settleUntil(
        tester,
        () => controller.catalog.manualGroups.length == 1,
      );
      await settle(tester);
      expect(controller.servers, isEmpty);
      await tester.tap(find.text(l.manualGroupsTitle));
      await settle(tester);
      expect(find.byType(ServerManualGroupsPage), findsOneWidget);
      expect(find.text('Empty folder'), findsOneWidget);
      expect(find.widgetWithText(AppBar, l.manualGroupsTitle), findsOneWidget);
      expect(find.text(l.manualGroupsDescription), findsNothing);
      expect(find.text(l.manualGroupsUngroupedFirst), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is SettingSection && w.title == l.manualGroupsTitle,
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, l.manualGroupOrder),
        findsOneWidget,
      );
      router!.pop();
      await settle(tester);
      final sources = find.text(l.prototypeSubscriptions).first;
      expect(sources, findsOneWidget);
      await tester.tap(sources);
      await settle(tester);
      expect(find.byType(ServerSourcesView), findsOneWidget);
      expect(find.text('Provider'), findsOneWidget);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'empty groups can be created, renamed and dissolved from the list',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Create'));
      await settle(tester);
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
      await settle(tester);
      expect(find.byType(ManualGroupNameDialog), findsNothing);
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerBrowser)),
      )!;
      await tester.tap(find.text(l.manualGroupsTitle));
      await settle(tester);
      expect(find.byType(ServerManualGroupsPage), findsOneWidget);
      expect(find.text('Cloud'), findsOneWidget);
      expect(find.text('Ungrouped'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      await tester.tap(find.byTooltip('More actions: Cloud'));
      await settle(tester);
      await tester.tap(find.text('Rename group'));
      await settle(tester);
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
      await settle(tester);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Cloud'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      await tester.tap(find.byTooltip('More actions: Home'));
      await settle(tester);
      await tester.tap(find.text('Dissolve group'));
      await settle(tester);
      await tester.tap(find.text('Dissolve group').last);
      await settleUntil(tester, () => controller.catalog.manualGroups.isEmpty);
      await settle(tester);
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
      await settle(tester);
      await tester.tap(find.text('Move to group'));
      await settle(tester);
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
      await settle(tester);
      expect(controller.servers.single.manualGroupId, group);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a searched folder detail follows its identity after renaming', (
    tester,
  ) async {
    await pump(tester);
    controller.manualGroups = const [
      ManualServerGroupData(id: 9, name: 'Cloud', sortOrder: 0),
    ];
    controller.search.text = 'Cloud';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.material(Brightness.light, mobile: true),
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ServerGroupPage(
          params: ServerGroupParams(controller, 'manual:9'),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(ServerGroupView), findsOneWidget);
    controller.manualGroups = const [
      ManualServerGroupData(id: 9, name: 'Home', sortOrder: 0),
    ];
    await settle(tester);
    expect(find.text('Home'), findsWidgets);
    expect(find.byType(ServerGroupView), findsOneWidget);
    expect(controller.query, 'Cloud');
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [Locale('ru'), Locale('fa')]) {
    testWidgets('mobile add stays reachable with a large $locale title', (
      tester,
    ) async {
      await pump(
        tester,
        locale: locale,
        size: const Size(320, 844),
        fullPage: true,
        textScale: 1.5,
      );
      final l = AppLocalizations.of(tester.element(find.byType(ServersPage)))!;
      final add = find.byKey(const ValueKey('servers-add'));
      expect(add.hitTestable(), findsOneWidget);
      expect(tester.widget<IconButton>(add).onPressed, isNotNull);
      expect(tester.widget<IconButton>(add).tooltip, l.prototypeAddServer);
      expect(find.byTooltip(l.manualGroupNew), findsNothing);
      expect(
        tester.getSize(find.text(l.prototypeServers)).width,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(TextButton, l.manualGroupsTitle));
      await settle(tester);
      expect(find.byType(ServerManualGroupsPage), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, l.manualGroupNew),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

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
      await tester.tap(find.text(l.manualGroupsTitle));
      await settle(tester);
      await tester.tap(find.byTooltip('${l.prototypeMoreActions}: Cloud'));
      await settle(tester);
      expect(find.text(l.manualGroupDelete), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
