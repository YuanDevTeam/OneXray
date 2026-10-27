import 'dart:async';
import 'dart:convert';

import 'package:onexray/service/servers/catalog.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/connect/controller.dart';
import 'package:onexray/pages/connect/view.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/connect/routing/smart/exit_picker_controller.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/sort.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  final preferences = InMemorySharedPreferencesAsync.empty();
  setUpAll(() => SharedPreferencesAsyncPlatform.instance = preferences);
  setUp(() async {
    await SharedPreferencesAsync().clear();
    final bus = AppEventBus();
    addTearDown(bus.close);
  });

  testWidgets(
    'provider selection and runtime snapshot use provider explanations without traffic changes',
    (tester) async {
      final coordinator = _Coordinator();
      final db = coordinator.db;
      final sourceId = await db.subscriptionDao.insertRow(
        SubscriptionCompanion.insert(
          name: 'Provider source',
          url: 'https://example.com/sub',
          timestamp: DateTime(2026, 10, 12),
          mode: Value(SubscriptionMode.providerManaged.name),
        ),
      );
      final id = await db.coreConfigDao.insertAssetRow(
        CoreConfigCompanion.insert(
          name: 'Provider profile',
          type: CoreConfigType.Remnawave.name,
          tags: '',
          delay: PingDelayConstants.unknown,
          subId: sourceId,
          data: Value(
            base64Encode(
              utf8.encode(
                '{"outbounds":[{"tag":"first","protocol":"freedom"}]}',
              ),
            ),
          ),
        ),
      );
      final row = (await db.coreConfigDao.searchRow(id))!;
      final settings = ConnectionConfiguration(
        connection: ConnectionSettings(
          selection: ServerSelection.server(id),
          smart: SmartRoutingSettings(entryCount: 3, finalExitId: 900),
        ),
      );
      coordinator.saved = settings;
      coordinator.state.value = const ConnectionView();
      final controller =
          ConnectController(database: db, coordinator: coordinator)
            ..configuration = settings
            ..servers = [row]
            ..sources = await db.subscriptionDao.allRows;
      addTearDown(controller.close);
      addTearDown(coordinator.dispose);
      addTearDown(db.close);
      bool? changed;
      await tester.pumpWidget(
        _testApp(
          Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => controller.chooseTrafficMethod(context),
                    child: const Text('methods'),
                  ),
                  TextButton(
                    onPressed: () => controller.showWhy(context),
                    child: const Text('why'),
                  ),
                  TextButton(
                    onPressed: () async {
                      changed = await controller.change(context, {
                        'trafficMode': 'allVpn',
                      });
                    },
                    child: const Text('change-method'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      expect(controller.providerConfiguration, isTrue);
      expect(controller.selectionTitle(l), row.name);
      expect(controller.homeMethodTitle(l), l.providerConfigurationTitle);
      expect(controller.methodDescription(l), l.providerRoutingNotice);
      expect(controller.selectionHealth(l), isNull);
      expect(controller.runningRoute, isNull);
      await tester.tap(find.text('methods'));
      await tester.pumpAndSettle();
      expect(find.text(l.prototypeChooseTrafficMethod), findsNothing);
      await tester.tap(find.text('change-method'));
      await tester.pumpAndSettle();
      expect(changed, isFalse);
      expect(coordinator.applyCount, 0);
      expect(controller.configuration.connection.smart.entryCount, 3);
      final runtime = _runtime(profile: ResolvedProfile.fromRow(row));
      coordinator.state.value = ConnectionView(
        phase: ConnectionPhase.connected,
        runtime: runtime,
      );
      await db.subscriptionDao.updateRow(
        (await db.subscriptionDao.searchRow(sourceId))!
            .copyWith(mode: SubscriptionMode.appManaged.name),
      );
      controller.sources = await db.subscriptionDao.allRows;
      controller.servers = [];
      expect(controller.selectionTitle(l), 'Provider profile');
      expect(controller.providerConfiguration, isTrue);
      expect(controller.runningRoute, isNull);
      await tester.tap(find.text('why'));
      await tester.pumpAndSettle();
      expect(find.text(l.providerRoutingNotice), findsOneWidget);
      expect(find.text(l.prototypeNoAvailableEntries), findsNothing);
      expect(find.textContaining('3 entry nodes'), findsNothing);
      for (final selection in [
        const ServerSelection.automatic(),
        ServerSelection.source(sourceId),
      ]) {
        final automatic = ConnectionConfiguration(
          connection: ConnectionSettings(
            selection: selection,
            smart: settings.connection.smart,
          ),
        );
        coordinator.saved = automatic;
        controller.configuration = automatic;
        coordinator.state.value = ConnectionView(
          phase: ConnectionPhase.connected,
          runtime: _runtime(
            profile: ResolvedProfile.fromRow(row),
            selection: selection,
          ),
        );
        expect(controller.selectedProvider, isNull);
        expect(controller.providerConfiguration, isTrue);
        expect(controller.selectionTitle(l), row.name);
        expect(controller.selectionDetail(l), l.providerRoutingNotice);
        expect(controller.homeMethodTitle(l), l.providerConfigurationTitle);
        expect(controller.selectionHealth(l), isNull);
        expect(controller.runningRoute, isNull);
        expect(
          controller.configuration.connection.selection.toJson(),
          selection.toJson(),
        );
        expect(controller.configuration.connection.smart.entryCount, 3);
        expect(coordinator.applyCount, 0);
      }
    },
  );

  test('updated failure counts rebuild the connection status', () {
    final before = ConnectPageState(
      connectionView: const ConnectionView(
        issue: 'insufficientHealthyServers',
        error: ConnectionResolutionException(
          ConnectionResolutionFailure.insufficientHealthyServers,
          requiredCount: 3,
          availableCount: 0,
        ),
      ),
    );
    final after = before.copyWith(
      connectionView: const ConnectionView(
        issue: 'insufficientHealthyServers',
        error: ConnectionResolutionException(
          ConnectionResolutionFailure.insufficientHealthyServers,
          requiredCount: 3,
          availableCount: 1,
        ),
      ),
    );
    expect(before.sameContentAs(after), isFalse);
  });

  test('metrics updates leave non-traffic connection content unchanged', () {
    final before = ConnectPageState(
      connectionView: const ConnectionView(phase: ConnectionPhase.connected),
    );
    final sample = before.copyWith(
      connectionView: const ConnectionView(
        phase: ConnectionPhase.connected,
        uploadSpeed: 1000,
        downloadSpeed: 2000,
      ),
    );
    expect(before.sameContentAs(sample), isTrue);
    expect(before.sameContentAs(sample.copyWith(connectedMinutes: 1)), isFalse);
    expect(
      before.sameContentAs(
        sample.copyWith(
          connectionView: const ConnectionView(
            phase: ConnectionPhase.disconnected,
          ),
        ),
      ),
      isFalse,
    );
  });

  test(
    'all node-list controllers share stable defaults and explicit delay order',
    () async {
      final coordinator = _Coordinator();
      final db = coordinator.db;
      final controllers = _catalogControllers(db, coordinator);
      addTearDown(() async {
        for (final controller in controllers) {
          await controller.close();
        }
        coordinator.dispose();
        await db.close();
      });
      for (final controller in controllers) {
        await controller.initialize();
      }
      final inserted = Future.wait([
        for (final controller in controllers)
          controller.stream.firstWhere((state) => state.servers.length == 2),
      ]);
      await db.transaction(() async {
        for (final delay in [300, 10]) {
          await db.coreConfigDao.insertAssetRow(
            CoreConfigCompanion.insert(
              name: 'Node $delay',
              type: 'outbound',
              tags: '',
              delay: delay,
              subId: 0,
            ),
          );
        }
      });
      await inserted;
      for (final controller in controllers) {
        expect(controller.servers.map((row) => row.delay), [300, 10]);
      }
      final sorted = Future.wait([
        for (final controller in controllers)
          controller.stream.firstWhere(
            (state) =>
                state.sortOrder == ServerSortOrder.delay &&
                state.servers.first.delay == 10,
          ),
      ]);
      await AppEventBus.instance.setServerSort(ServerSortOrder.delay);
      await sorted;
      for (final controller in controllers) {
        expect(controller.servers.map((row) => row.delay), [10, 300]);
      }
      final slow = controllers.first.servers.last;
      final reordered = Future.wait([
        for (final controller in controllers)
          controller.stream.firstWhere(
            (state) => state.servers.first.delay == 0,
          ),
      ]);
      await db.coreConfigDao.updateRow(slow.copyWith(delay: 0, favorite: true));
      await reordered;
      for (final controller in controllers) {
        expect(controller.servers.map((row) => row.delay), [0, 10]);
        expect(controller.servers.first.favorite, isTrue);
      }
      final deleted = Future.wait([
        for (final controller in controllers)
          controller.stream.firstWhere((state) => state.servers.length == 1),
      ]);
      await db.coreConfigDao.deleteRow(slow);
      await deleted;
      expect(
        controllers.every(
          (controller) => controller.servers.single.delay == 10,
        ),
        isTrue,
      );

      final rawInserted = db.coreConfigDao.allRawRowsWithDataStream.firstWhere(
        (rows) => rows.length == 1,
      );
      await db.coreConfigDao.insertAssetRow(
        CoreConfigCompanion.insert(
          name: 'Raw',
          type: 'raw',
          tags: '',
          delay: 0,
          subId: 0,
          data: const Value('e30='),
        ),
      );
      await rawInserted;
      expect(
        controllers.every((controller) => controller.servers.length == 1),
        isTrue,
      );
    },
  );

  test(
    'subscription lists stream inserts, edits and deletes in ID order',
    () async {
      final coordinator = _Coordinator();
      final db = coordinator.db;
      final controllers = _catalogControllers(db, coordinator);
      addTearDown(() async {
        for (final controller in controllers) {
          await controller.close();
        }
        coordinator.dispose();
        await db.close();
      });
      for (final controller in controllers) {
        await controller.initialize();
      }
      final inserted = Future.wait([
        for (final controller in controllers)
          controller.stream.firstWhere((state) => state.sources.length == 3),
      ]);
      await db.transaction(() async {
        for (final id in [20, 3, 10]) {
          await db.subscriptionDao.insertRow(
            SubscriptionCompanion.insert(
              id: Value(id),
              name: 'Source $id',
              url: 'https://example.test/subscription/$id',
              timestamp: DateTime(2026, 9, 8),
            ),
          );
        }
      });
      await inserted;
      for (final controller in controllers) {
        expect(controller.sources.map((source) => source.id), [3, 10, 20]);
      }
      expect((await db.subscriptionDao.allRows).map((source) => source.id), [
        3,
        10,
        20,
      ]);

      final edited = Future.wait([
        for (final controller in controllers)
          controller.stream.firstWhere(
            (state) => state.sources.first.name == 'Renamed source',
          ),
      ]);
      final source = (await db.subscriptionDao.searchRow(3))!;
      await db.subscriptionDao.updateRow(
        source.copyWith(name: 'Renamed source'),
      );
      await edited;
      for (final controller in controllers) {
        expect(controller.sources.map((source) => source.id), [3, 10, 20]);
        expect(controller.sources.first.name, 'Renamed source');
      }

      final deleted = Future.wait([
        for (final controller in controllers)
          controller.stream.firstWhere((state) => state.sources.length == 2),
      ]);
      await db.subscriptionDao.deleteRow(10);
      await deleted;
      for (final controller in controllers) {
        expect(controller.sources.map((source) => source.id), [3, 20]);
      }

      final cleared = Future.wait([
        for (final controller in controllers)
          controller.stream.firstWhere((state) => state.sources.isEmpty),
      ]);
      await db.subscriptionDao.clear();
      await cleared;
      expect(
        controllers.every((controller) => controller.sources.isEmpty),
        isTrue,
      );
    },
  );

  testWidgets(
    'connection labels use configured counts and only the running node probe',
    (tester) async {
      final coordinator = _Coordinator();
      final controller =
          ConnectController(database: coordinator.db, coordinator: coordinator)
            ..configuration = ConnectionConfiguration(
              connection: ConnectionSettings(
                smart: SmartRoutingSettings(entryCount: 3),
              ),
            );
      addTearDown(controller.close);
      addTearDown(coordinator.dispose);
      addTearDown(coordinator.db.close);
      await tester.pumpWidget(_testApp(const Scaffold(body: SizedBox())));
      final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      coordinator.state.value = const ConnectionView();
      expect(
        controller.selectionTitle(l),
        'Automatic selection · 3 entry nodes',
      );
      expect(controller.selectionDetail(l), 'Choose by speed and availability');
      expect(controller.homeMethodTitle(l), 'Smart Routing (recommended)');
      expect(controller.selectionHealth(l), isNull);
      coordinator.state.value = ConnectionView(
        phase: ConnectionPhase.connected,
        runtime: _runtime(),
      );
      controller.servers = [
        CoreConfigData(
          manualSortOrder: 0,
          id: 1,
          name: 'new name',
          type: 'outbound',
          tags: '',
          delay: 42,
          subId: 0,
          favorite: false,
        ),
        CoreConfigData(
          manualSortOrder: 0,
          id: 99,
          name: 'unrelated fastest',
          type: 'outbound',
          tags: '',
          delay: 1,
          subId: 0,
          favorite: false,
        ),
      ];
      expect(
        controller.selectionTitle(l),
        'Automatic selection · 2 entry nodes',
      );
      expect(controller.selectionHealth(l), 'Fast · 42 ms');
      final running = controller.servers.first;
      for (final (delay, label) in [
        (0, 'Fast · 0 ms'),
        (500, 'Fast · 500 ms'),
        (501, 'Slow · 501 ms'),
        (1000, 'Slow · 1000 ms'),
        (1001, 'Available · 1001 ms'),
        (-1, null),
        (PingDelayConstants.unknown, null),
        (PingDelayConstants.error, null),
        (PingDelayConstants.timeout, null),
      ]) {
        controller.servers = [
          running.copyWith(delay: delay),
          controller.servers.last,
        ];
        expect(controller.selectionHealth(l), label);
      }
      expect(
        controller.selectionDetail(l),
        'Singapore 03 + Japan 02 → United States 01',
      );
      controller.servers = controller.servers.sublist(1);
      expect(controller.selectionHealth(l), isNull);
    },
  );

  testWidgets(
    'connect actions keep editors, server browsing and groups in the source tab',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final coordinator = _Coordinator()..saved = ConnectionConfiguration();
      coordinator.state.value = const ConnectionView();
      final controller =
          ConnectController(database: coordinator.db, coordinator: coordinator)
            ..configuration = coordinator.saved
            ..expertView = true;
      final servers = ServersController(
        database: coordinator.db,
        coordinator: coordinator,
      );
      final router = GoRouter(
        initialLocation: '/connect',
        routes: [
          GoRoute(
            path: '/connect',
            builder: (context, _) => Scaffold(
              body: Column(
                children: [
                  const Text('connection-home'),
                  TextButton(
                    onPressed: () => controller.connectionAction(context),
                    child: const Text('connect-action'),
                  ),
                  TextButton(
                    onPressed: () => controller.chooseTrafficMethod(context),
                    child: const Text('methods-action'),
                  ),
                  TextButton(
                    onPressed: () => controller.chooseServer(context),
                    child: const Text('location-action'),
                  ),
                ],
              ),
            ),
            routes: [
              GoRoute(
                path: 'raw-editor',
                builder: (_, _) => const Scaffold(body: Text('raw-editor')),
              ),
              GoRoute(
                path: 'smart-routing',
                builder: (_, _) => const Scaffold(body: Text('smart-editor')),
              ),
              GoRoute(
                path: 'servers',
                builder: (context, _) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        context.pushScoped(AppPageDestination.serverGroup),
                    child: const Text('servers-browser'),
                  ),
                ),
              ),
              GoRoute(
                path: 'server-group',
                builder: (context, _) => Scaffold(
                  body: TextButton(
                    onPressed: () => servers.choose(
                      context,
                      const ServerSelection.source(0),
                    ),
                    child: const Text('use-group'),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(controller.close);
      addTearDown(servers.close);
      addTearDown(coordinator.dispose);
      addTearDown(coordinator.db.close);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.material(Brightness.light, mobile: true),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          builder: (_, child) => ShadTheme(
            data: AppTheme.shad(Brightness.light, mobile: true),
            child: ShadToaster(child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('connect-action'));
      await tester.pumpAndSettle();
      expect(find.text('raw-editor'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      controller.expertView = false;
      await tester.tap(find.text('methods-action'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a traffic method'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('smart-editor'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('connection-home'), findsOneWidget);
      expect(find.text('Choose a traffic method'), findsNothing);
      // The backdrop remains a dismiss target outside the compact dialog.
      await tester.tap(find.text('methods-action'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Choose a traffic method'), findsNothing);
      await tester.tap(find.text('location-action'));
      await tester.pumpAndSettle();
      expect(
        GoRouterState.of(tester.element(find.text('servers-browser'))).uri.path,
        '/connect/servers',
      );
      expect(router.canPop(), true);
      await tester.tap(find.text('servers-browser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('use-group'));
      await tester.pumpAndSettle();
      expect(
        GoRouterState.of(tester.element(find.text('use-group'))).uri.path,
        '/connect/server-group',
      );
      expect(find.text('use-group'), findsOneWidget);
      expect(coordinator.saved.connection.expert, false);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('servers-browser'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('connection-home'), findsOneWidget);
      expect(router.canPop(), false);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fail in [false, true]) {
    testWidgets('leaving Raw follows the committed result; failure=$fail', (
      tester,
    ) async {
      final coordinator = _Coordinator(fail: fail);
      final controller =
          ConnectController(database: coordinator.db, coordinator: coordinator)
            ..expertView = true
            ..configuration = coordinator.saved;
      addTearDown(controller.close);
      addTearDown(coordinator.dispose);
      addTearDown(coordinator.db.close);
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
          home: const Scaffold(body: SizedBox()),
        ),
      );
      final context = tester.element(find.byType(Scaffold));
      final changing = controller.toggleExpert(context, false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply and reconnect'));
      await tester.pumpAndSettle();
      await changing;
      expect(controller.expertView, fail);
      expect(coordinator.saved.connection.expert, fail);
      if (!fail) {
        expect(controller.configuration.encode(), coordinator.saved.encode());
        expect(
          controller.configuration.connection.selection.kind,
          SelectionKind.automatic,
        );
        expect(coordinator.state.value.issue, 'selectionReset');
      }
    });
  }

  test('running path keeps all frozen names and is absent for Raw or stopped sessions', () async {
    final coordinator = _Coordinator();
    final controller = ConnectController(
      database: coordinator.db,
      coordinator: coordinator,
    );
    addTearDown(controller.close);
    addTearDown(coordinator.dispose);
    addTearDown(coordinator.db.close);
    final runtime = _runtime();
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: runtime,
    );
    controller.servers = [
      CoreConfigData(
        manualSortOrder: 0,
        id: 1,
        name: 'Renamed after connection',
        type: 'outbound',
        tags: '',
        delay: 10,
        subId: 0,
        favorite: false,
      ),
    ];
    expect(controller.runningRoute, (
      entryCount: 2,
      path: 'Singapore 03 + Japan 02 → United States 01',
    ));
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.disconnected,
      runtime: runtime,
    );
    expect(controller.runningRoute, isNull);
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.connected,
      runtime: _runtime(expert: true),
    );
    expect(controller.runningRoute, isNull);
  });

  for (final stop in [false, true]) {
    for (final width in [390.0, 1160.0]) {
      testWidgets(
        'immediate connection action feedback: stop=$stop width=$width',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final gate = Completer<void>();
          final coordinator = _Coordinator(actionGate: gate);
          final phase = stop
              ? ConnectionPhase.connected
              : ConnectionPhase.disconnected;
          coordinator.state.value = ConnectionView(phase: phase);
          final controller = ConnectController(
            database: coordinator.db,
            coordinator: coordinator,
          );
          addTearDown(controller.close);
          addTearDown(coordinator.dispose);
          addTearDown(coordinator.db.close);
          await tester.pumpWidget(_testApp(_connectionScreen(controller)));
          final action = find.widgetWithText(
            FilledButton,
            stop ? 'Disconnect' : 'Connect',
          );
          try {
            // A second tap before rebuilding must not enqueue another command.
            await tester.tap(action);
            await tester.tap(action);
            await tester.pump();
            expect(find.byType(CircularProgressIndicator), findsWidgets);
            expect(coordinator.state.value.phase, phase);
            expect(
              tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
              isNull,
            );
            expect(
              stop ? coordinator.disconnectCount : coordinator.connectCount,
              1,
            );
          } finally {
            gate.complete();
            await tester.pumpAndSettle();
          }
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNotNull,
          );
        },
      );
    }
  }

  for (final stop in [false, true]) {
    testWidgets('a rejected connection action clears loading: stop=$stop', (
      tester,
    ) async {
      final gate = Completer<void>();
      final coordinator = _Coordinator(actionGate: gate);
      final phase = stop
          ? ConnectionPhase.connected
          : ConnectionPhase.disconnected;
      coordinator.state.value = ConnectionView(phase: phase);
      final controller = ConnectController(
        database: coordinator.db,
        coordinator: coordinator,
      );
      addTearDown(controller.close);
      addTearDown(coordinator.dispose);
      addTearDown(coordinator.db.close);
      await tester.pumpWidget(_testApp(_connectionScreen(controller)));
      await tester.tap(
        find.widgetWithText(FilledButton, stop ? 'Disconnect' : 'Connect'),
      );
      await tester.pump();
      gate.completeError(const ConnectionHostException('runtimeUnavailable'));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(coordinator.state.value.phase, phase);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an acknowledged connecting phase still allows cancellation', (
    tester,
  ) async {
    final gate = Completer<void>();
    final coordinator = _Coordinator(actionGate: gate);
    coordinator.state.value = const ConnectionView();
    final controller = ConnectController(
      database: coordinator.db,
      coordinator: coordinator,
    );
    addTearDown(controller.close);
    addTearDown(coordinator.dispose);
    addTearDown(coordinator.db.close);
    await tester.pumpWidget(_testApp(_connectionScreen(controller)));
    try {
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pump();
      coordinator.state.value = const ConnectionView(
        phase: ConnectionPhase.preparing,
      );
      await tester.pump();
      final cancel = find.widgetWithText(FilledButton, 'Cancel');
      expect(tester.widget<FilledButton>(cancel).onPressed, isNotNull);
      await tester.tap(cancel);
      expect(coordinator.cancelCount, 1);
      expect(coordinator.connectCount, 1);
      expect(coordinator.disconnectCount, 0);
    } finally {
      coordinator.state.value = const ConnectionView();
      gate.complete();
      await tester.pumpAndSettle();
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a native stop failure still uses the disconnect action', (
    tester,
  ) async {
    final coordinator = _Coordinator();
    final controller = ConnectController(
      database: coordinator.db,
      coordinator: coordinator,
    );
    addTearDown(controller.close);
    addTearDown(coordinator.dispose);
    addTearDown(coordinator.db.close);
    coordinator.state.value = ConnectionView(
      phase: ConnectionPhase.failed,
      issue: 'stopFailed',
    );
    await tester.pumpWidget(
      _testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => controller.connectionAction(context),
            child: const Text('connection-action'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('connection-action'));
    await tester.pumpAndSettle();

    expect(coordinator.disconnectCount, 1);
    expect(coordinator.connectCount, 0);
  });
}

/// Exercises the controller's result handling; native transaction
/// behavior is covered by service/connect/coordinator_test.dart.
class _Coordinator extends ConnectionCoordinator {
  _Coordinator({this.fail = false, this.actionGate})
    : super(database: AppDatabase.forTesting(NativeDatabase.memory())) {
    state.value = const ConnectionView(phase: ConnectionPhase.connected);
  }
  final bool fail;
  final Completer<void>? actionGate;
  int applyCount = 0;
  int connectCount = 0;
  int disconnectCount = 0;
  int cancelCount = 0;

  @override
  void cancel() {
    cancelCount++;
    super.cancel();
  }

  @override
  Future<void> connect() async {
    connectCount++;
    await actionGate?.future;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    await actionGate?.future;
  }

  ConnectionConfiguration saved = ConnectionConfiguration(
    connection: ConnectionSettings(
      expert: true,
      rawId: 9,
      selection: const ServerSelection.server(99),
    ),
  );

  @override
  Future<ConnectionConfiguration> get configuration async => saved;

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
    applyCount++;
    if (fail) {
      state.value = const ConnectionView(
        phase: ConnectionPhase.connected,
        issue: 'changeFailed',
      );
      throw StateError('Previous settings restored');
    }
    saved = ConnectionConfiguration(
      connection: ConnectionSettings.fromJson({
        ...next.connection.toJson(),
        'selection': const ServerSelection.automatic().toJson(),
      }),
      policy: next.policy,
    );
    state.value = const ConnectionView(
      phase: ConnectionPhase.connected,
      issue: 'selectionReset',
    );
  }
}

Widget _connectionScreen(ConnectController controller) => ShadTheme(
  data: AppTheme.shad(Brightness.light),
  child: ShadToaster(
    child: Scaffold(
      body: BlocBuilder<ConnectController, ConnectPageState>(
        bloc: controller,
        buildWhen: (previous, next) => !previous.sameContentAs(next),
        builder: (context, state) => ConnectView(
          view: state.connectionView,
          pendingChange: state.pendingChange,
          hasServers: true,
          expert: false,
          raws: const [],
          activeRawId: null,
          location: 'Automatic selection',
          method: 'Smart Routing',
          onConnection: () => controller.connectionAction(context),
          onAddServers: () {},
          onExpert: (_) {},
          onServer: () {},
          onMethod: () {},
          onWhy: () {},
          onRawAdd: () {},
          onRawSelect: (_) {},
          onRawActions: (_) {},
        ),
      ),
    ),
  ),
);

Widget _testApp(Widget home) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  home: home,
);

ConnectionRuntime _runtime({
  bool expert = false,
  ResolvedProfile? profile,
  ServerSelection? selection,
}) {
  final configuration = ConnectionConfiguration(
    connection: ConnectionSettings(
      expert: expert,
      selection:
          selection ??
          (profile == null
              ? const ServerSelection.automatic()
              : ServerSelection.server(profile.id)),
    ),
  );
  ResolvedServer server(int id, String name) => ResolvedServer(
    id: id,
    sourceId: 0,
    outbound: {'protocol': 'freedom', 'tag': name},
  );
  final invoke = LibXrayInvokeRequest(
    method: LibXrayMethod.runXray,
    payload: RunXrayRequest('{}').toJson(),
  );
  return ConnectionRuntime.create(
    configuration: configuration,
    compiled: CompiledConnection(
      xrayJson: '{}',
      entries: profile == null
          ? [server(1, 'Singapore 03'), server(2, 'Japan 02')]
          : const [],
      finalExit: profile == null ? server(3, 'United States 01') : null,
      profile: profile,
      nodeTags: {},
    ),
    platform: ConnectionPlatform.android,
    request: StartVpnRequest(
      configuration.policy.toTun(ConnectionPlatform.android),
      null,
      '18003',
      jsonEncode(invoke.toJson()),
    ),
  );
}

class _CatalogController {
  final Future<void> Function() initialize;
  final Future<void> Function() close;
  final Stream<ServerCatalog> stream;
  final ServerCatalog Function() read;
  const _CatalogController(this.initialize, this.close, this.stream, this.read);
  List<CoreConfigData> get servers => read().servers;
  List<SubscriptionData> get sources => read().sources;
}

List<_CatalogController> _catalogControllers(
  AppDatabase db,
  ConnectionCoordinator coordinator,
) {
  final connect = ConnectController(database: db, coordinator: coordinator);
  final servers = ServersController(database: db, coordinator: coordinator);
  final exit = ServerExitPickerController(
    const ServerExitPickerParams(),
    database: db,
    coordinator: coordinator,
  );
  return [
    _CatalogController(
      connect.initialize,
      connect.close,
      connect.stream.map((state) => state.catalog),
      () => connect.catalog,
    ),
    _CatalogController(
      servers.initialize,
      servers.close,
      servers.stream.map((state) => state.catalog),
      () => servers.catalog,
    ),
    _CatalogController(
      exit.initialize,
      exit.close,
      exit.stream.map((state) => state.catalog),
      () => exit.catalog,
    ),
  ];
}
