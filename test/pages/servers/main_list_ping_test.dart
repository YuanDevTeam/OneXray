import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadOption, ShadTheme, ShadToaster;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fixtures/server_test_router.dart';

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late ServersController controller;
  late ScrollController scroll;
  GoRouter? router;
  late int sourceId;
  late List<int> targetIds;
  late List<int> nodeIds;
  late Map<String, int> idsByTag;
  late Completer<void> firstEntered;
  late Completer<List<PingBatchResult>> firstResults;
  late List<List<int>> batches;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(
      database: db,
      readRuntime: () async => null,
      inspect: (_, {observedStatus}) async =>
          const HostConnection(VpnStatus.disconnected),
      prepare: (_, _) async =>
          throw StateError('List tests must not prepare VPN'),
      start: (_) async => throw StateError('List tests must not start VPN'),
      stop: () async => throw StateError('List tests must not stop VPN'),
    );
    await coordinator.initialize(observe: false, registerReferences: false);
    Future<int> source(String name, {bool provider = false}) =>
        db.subscriptionDao.insertRow(
          SubscriptionCompanion.insert(
            name: name,
            url: 'https://example.test/$name',
            mode: Value(
              provider
                  ? SubscriptionMode.providerManaged.name
                  : SubscriptionMode.appManaged.name,
            ),
            timestamp: DateTime(2026, 11, 9),
          ),
        );
    sourceId = await source('First source');
    final otherSourceId = await source('Second source');
    final providerSourceId = await source('Complete source', provider: true);
    idsByTag = {};
    nodeIds = [];
    Future<int> node(String name, int subId, {bool favorite = true}) async {
      final id = await db.coreConfigDao.insertAssetRow(
        outboundCompanion({'tag': name, 'protocol': 'vless'})
            .copyWith(subId: Value(subId), favorite: Value(favorite)),
      );
      idsByTag[name] = id;
      nodeIds.add(id);
      return id;
    }

    targetIds = [];
    for (var index = 0; index < PingBatchRunner.maxBatchSize + 1; index++) {
      targetIds.add(await node('Target $index', sourceId));
    }
    await node('Target not favorite', sourceId, favorite: false);
    await node('Other name', sourceId);
    await node('Target local', 0);
    await node('Target other source', otherSourceId);
    final graph = base64Encode(
      utf8.encode('{"outbounds":[{"tag":"direct","protocol":"freedom"}]}'),
    );
    for (final (name, type, subId) in [
      ('Target complete profile', CoreConfigType.Remnawave, providerSourceId),
      ('Target Raw', CoreConfigType.raw, 0),
    ]) {
      await db.coreConfigDao.insertAssetRow(
        CoreConfigCompanion.insert(
          name: name,
          type: type.name,
          tags: '',
          data: Value(graph),
          delay: PingDelayConstants.unknown,
          subId: subId,
          favorite: const Value(true),
        ),
      );
    }
    await db.connectionConfigDao.commit(
      configurationJson: ConnectionConfiguration(
        connection: ConnectionSettings(
          selection: ServerSelection.server(targetIds.first),
          trafficMode: TrafficMode.allVpn,
        ),
      ).encode(),
    );
    firstEntered = Completer<void>();
    firstResults = Completer<List<PingBatchResult>>();
    batches = [];
    final ping = PingService.forTesting(
      database: db,
      automaticEnabled: false,
      runBatch: (sources, _) async {
        batches.add([
          for (final source in sources)
            idsByTag[((jsonDecode(source.xrayJson)
                            as Map<String, dynamic>)['outbounds']
                        as List)
                    .first['tag']
                as String]!,
        ]);
        if (!firstEntered.isCompleted) {
          firstEntered.complete();
          return firstResults.future;
        }
        return [for (final _ in sources) const PingBatchResult(true, 25, '')];
      },
    );
    controller = ServersController(
      database: db,
      coordinator: coordinator,
      ping: ping,
    );
    await controller.initialize();
    bool loaded(ServersPageState state) =>
        state.servers.length == nodeIds.length + 1 &&
        state.rawConfigurations.length == 1;
    if (!loaded(controller.state)) {
      await controller.stream
          .firstWhere(loaded)
          .timeout(const Duration(seconds: 5));
    }
    scroll = ScrollController();
  });

  tearDown(() async {
    if (!firstResults.isCompleted) {
      firstResults.complete([
        for (final _ in batches.isEmpty ? <int>[] : batches.first)
          const PingBatchResult(true, 25, ''),
      ]);
    }
    if (controller.state.serverTests.isNotEmpty) {
      await controller.stream
          .firstWhere((state) => state.serverTests.isEmpty)
          .timeout(const Duration(seconds: 5));
    }
    router?.dispose();
    router = null;
    scroll.dispose();
    await controller.close();
    coordinator.dispose();
    await db.close();
  });

  Future<AppLocalizations> open(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    router = serverTestRouter(
      home: (_) => Scaffold(
        body: BlocBuilder<ServersController, ServersPageState>(
          bloc: controller,
          builder: (_, _) =>
              ServerBrowser(controller: controller, scroll: scroll),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) => ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: ShadToaster(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(ServerBrowser)))!;
  }

  final testAction = find.byKey(const ValueKey('server-test-visible'));

  Future<void> filterSource(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey(('server-source-filter', -1))));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is ShadOption<int> && widget.value == sourceId,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.ensureVisible(testAction);
    await tester.runAsync(() async {
      // Reusing the same callback before a rebuild must not duplicate a task.
      await tester.tap(testAction);
      await tester.tap(testAction);
      await firstEntered.future.timeout(const Duration(seconds: 5));
    });
    await tester.pump();
    expect(controller.state.serverTests, hasLength(1));
    expect(
      controller.testingGroup(ServersController.mainListTestGroupId),
      isTrue,
    );
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.runAsync(() async {
      firstResults.complete([
        for (final _ in batches.first) const PingBatchResult(true, 25, ''),
      ]);
      if (controller.state.serverTests.isNotEmpty) {
        await controller.stream
            .firstWhere((state) => state.serverTests.isEmpty)
            .timeout(const Duration(seconds: 5));
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'main list tests a snapshot of source, search and favorite matches on mobile',
    (tester) async {
      final before = (await tester.runAsync(() => coordinator.configuration))!
          .encode();
      final l = await open(tester, 390);
      await filterSource(tester);
      await tester.tap(find.byKey(const ValueKey('server-favorites-filter')));
      await tester.enterText(
        find.byKey(const ValueKey('server-search')),
        'Target',
      );
      await tester.pumpAndSettle();
      await start(tester);
      expect(batches.single, targetIds.take(PingBatchRunner.maxBatchSize));
      expect(
        find.descendant(of: testAction, matching: find.text(l.prototypeCancel)),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('server-search')),
        'Other name',
      );
      await tester.pump();
      await finish(tester);
      expect(batches.expand((batch) => batch), targetIds);
      expect(batches.map((batch) => batch.length), [5, 1]);
      expect(
        (await tester.runAsync(() => coordinator.configuration))!.encode(),
        before,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'main list cancellation keeps its task after filtering and leaves later nodes unmeasured',
    (tester) async {
      final before = (await tester.runAsync(() => coordinator.configuration))!
          .encode();
      final l = await open(tester, 1160);
      expect(controller.configuration.connection.selection.id, targetIds.first);
      await filterSource(tester);
      await start(tester);
      final request = controller.state.serverTests.keys.single;
      final inFlightIds = batches.single.toList();
      expect(inFlightIds, hasLength(PingBatchRunner.maxBatchSize));
      await tester.enterText(
        find.byKey(const ValueKey('server-search')),
        'no matching nodes',
      );
      await tester.pump();
      expect(find.text(l.serverNoMatchingResources), findsOneWidget);
      expect(tester.widget<OutlinedButton>(testAction).onPressed, isNotNull);
      await tester.tap(testAction);
      await tester.pump();
      expect(controller.state.serverTests.keys.single, same(request));
      expect(
        controller.cancellingGroup(ServersController.mainListTestGroupId),
        isTrue,
      );
      expect(tester.widget<OutlinedButton>(testAction).onPressed, isNull);
      expect(
        find.descendant(
          of: testAction,
          matching: find.text(l.prototypePleaseWait),
        ),
        findsOneWidget,
      );
      await finish(tester);
      expect(batches, hasLength(1));
      final rows = await tester.runAsync(
        () => Future.wait(nodeIds.map(db.coreConfigDao.searchRow)),
      );
      for (final row in rows!) {
        expect(
          row!.delay,
          inFlightIds.contains(row.id) ? 25 : PingDelayConstants.unknown,
        );
      }
      expect(tester.widget<OutlinedButton>(testAction).onPressed, isNull);
      expect(
        (await tester.runAsync(() => coordinator.configuration))!.encode(),
        before,
      );
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('main list disables testing for no matches or a busy selection', (
    tester,
  ) async {
    await open(tester, 1032);
    expect(tester.widget<OutlinedButton>(testAction).onPressed, isNotNull);
    await tester.enterText(
      find.byKey(const ValueKey('server-search')),
      'no matching nodes',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(testAction).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('server-search-clear')));
    await tester.pumpAndSettle();
    controller.selecting = ServerSelection.server(targetIds.first);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(testAction).onPressed, isNull);
    controller.selecting = null;
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(testAction).onPressed, isNotNull);
    expect(batches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'main list and manual group management omit connection scope buttons',
    (tester) async {
      final l = await open(tester, 1160);
      void expectNoScopeButtons() {
        expect(
          find.widgetWithText(OutlinedButton, l.prototypeAutomaticSelection),
          findsNothing,
        );
        expect(
          find.widgetWithText(OutlinedButton, l.prototypeManualAdditions),
          findsNothing,
        );
      }

      expectNoScopeButtons();
      final groups = find.text(l.manualGroupsTitle);
      await tester.ensureVisible(groups);
      await tester.tap(groups);
      await tester.pumpAndSettle();
      expect(find.byType(ServerManualGroupsPage), findsOneWidget);
      expectNoScopeButtons();
      expect(
        find.widgetWithText(FilledButton, l.manualGroupNew),
        findsOneWidget,
      );
      expect(controller.state.serverTests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
