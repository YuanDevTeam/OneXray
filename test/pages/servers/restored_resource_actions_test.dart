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
import 'package:onexray/pages/servers/details.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;
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
  late int providerSourceId;
  late int firstSourceId;
  late int secondSourceId;
  late int oldFavoriteId;
  late int newFavoriteId;
  late int rawId;
  late List<int> firstNodeIds;
  late int secondNodeId;
  late Completer<void> firstEntered;
  late Completer<void> secondEntered;
  late Completer<List<PingBatchResult>> firstResults;
  late Completer<List<PingBatchResult>> secondResults;
  late List<List<String>> batches;

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
          throw StateError('Resource actions must not prepare VPN'),
      start: (_) async =>
          throw StateError('Resource actions must not start VPN'),
      stop: () async => throw StateError('Resource actions must not stop VPN'),
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
            timestamp: DateTime(2026, 11, 4),
          ),
        );
    providerSourceId = await source('Complete source', provider: true);
    firstSourceId = await source('First source');
    secondSourceId = await source('Second source');
    final graph = base64Encode(
      utf8.encode('{"outbounds":[{"tag":"direct","protocol":"freedom"}]}'),
    );
    Future<int> profile(String name, bool favorite) =>
        db.coreConfigDao.insertAssetRow(
          CoreConfigCompanion.insert(
            name: name,
            type: CoreConfigType.Remnawave.name,
            tags: '',
            data: Value(graph),
            delay: PingDelayConstants.unknown,
            subId: providerSourceId,
            favorite: Value(favorite),
          ),
        );
    oldFavoriteId = await profile('Existing favorite', true);
    newFavoriteId = await profile('Another profile', false);
    rawId = await db.coreConfigDao.insertAssetRow(
      CoreConfigCompanion.insert(
        name: 'Personal Raw',
        type: CoreConfigType.raw.name,
        tags: '',
        data: Value(graph),
        delay: PingDelayConstants.unknown,
        subId: 0,
      ),
    );
    Future<int> node(String name, int subId) => db.coreConfigDao.insertAssetRow(
      outboundCompanion({'tag': name, 'protocol': 'vless'})
          .copyWith(subId: Value(subId)),
    );
    firstNodeIds = [];
    for (var index = 0; index < PingBatchRunner.maxBatchSize + 1; index++) {
      firstNodeIds.add(await node('First node $index', firstSourceId));
    }
    secondNodeId = await node('Second node', secondSourceId);
    firstEntered = Completer<void>();
    secondEntered = Completer<void>();
    firstResults = Completer<List<PingBatchResult>>();
    secondResults = Completer<List<PingBatchResult>>();
    batches = [];
    final ping = PingService.forTesting(
      database: db,
      automaticEnabled: false,
      runBatch: (sources, _) {
        final names = sources
            .map(
              (source) =>
                  ((jsonDecode(source.xrayJson)
                                  as Map<String, dynamic>)['outbounds']
                              as List)
                          .first['tag']
                      as String,
            )
            .toList();
        batches.add(names);
        if (names.first.startsWith('First node')) {
          if (!firstEntered.isCompleted) firstEntered.complete();
          return firstResults.future;
        }
        if (!secondEntered.isCompleted) secondEntered.complete();
        return secondResults.future;
      },
    );
    controller = ServersController(
      database: db,
      coordinator: coordinator,
      ping: ping,
    );
    await controller.initialize();
    if (controller.servers.length != 2 + firstNodeIds.length + 1 ||
        controller.rawConfigurations.isEmpty) {
      await controller.stream
          .firstWhere(
            (state) =>
                state.servers.length == 2 + firstNodeIds.length + 1 &&
                state.rawConfigurations.isNotEmpty,
          )
          .timeout(const Duration(seconds: 5));
    }
    scroll = ScrollController();
  });

  tearDown(() async {
    router?.dispose();
    router = null;
    scroll.dispose();
    await controller.close();
    coordinator.dispose();
    await db.close();
  });

  Future<AppLocalizations> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
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

  Future<void> stateWhere(
    WidgetTester tester,
    bool Function(ServersPageState) predicate,
  ) async {
    await tester.runAsync(() async {
      if (!predicate(controller.state)) {
        await controller.stream
            .firstWhere(predicate)
            .timeout(const Duration(seconds: 5));
      }
    });
    await tester.pump();
  }

  testWidgets(
    'complete configuration list and detail can change existing favorites without offering Raw favorites',
    (tester) async {
      final before = (await tester.runAsync(() => coordinator.configuration))!
          .encode();
      final l = await open(tester);
      await tester.tap(find.text(l.serverCompleteConfigurationsTab).first);
      await tester.pumpAndSettle();
      expect(find.text('Personal Raw'), findsOneWidget);
      expect(find.byTooltip(l.prototypeRemoveFavorite), findsOneWidget);
      expect(find.byTooltip(l.prototypeAddFavorite), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('server-favorites-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Existing favorite'), findsOneWidget);
      expect(find.text('Another profile'), findsNothing);
      expect(find.text('Personal Raw'), findsNothing);
      await tester.tap(find.byTooltip(l.prototypeRemoveFavorite));
      await stateWhere(
        tester,
        (state) => !state.servers
            .firstWhere((row) => row.id == oldFavoriteId)
            .favorite,
      );
      await tester.pumpAndSettle();
      expect(find.text('Existing favorite'), findsNothing);
      expect(find.text(l.serverNoMatchingResources), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('server-favorites-filter')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey(('server', newFavoriteId))),
          matching: find.byTooltip(l.prototypeAddFavorite),
        ),
      );
      await stateWhere(
        tester,
        (state) =>
            state.servers.firstWhere((row) => row.id == newFavoriteId).favorite,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Another profile'));
      await tester.pumpAndSettle();
      expect(find.byType(ServerResourcePage), findsOneWidget);
      final remove = find.text(l.prototypeRemoveFavorite);
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await stateWhere(
        tester,
        (state) => !state.servers
            .firstWhere((row) => row.id == newFavoriteId)
            .favorite,
      );
      await tester.pumpAndSettle();
      expect(find.text(l.prototypeAddFavorite), findsOneWidget);
      final rows = await tester.runAsync(
        () async => [
          await db.coreConfigDao.searchRow(oldFavoriteId),
          await db.coreConfigDao.searchRow(newFavoriteId),
          await db.coreConfigDao.searchRow(rawId),
        ],
      );
      expect(rows!.every((row) => !row!.favorite), isTrue);
      expect(
        (await tester.runAsync(() => coordinator.configuration))!.encode(),
        before,
      );
      router!.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal Raw'));
      await tester.pumpAndSettle();
      expect(find.text(l.prototypeAddFavorite), findsNothing);
      expect(find.text(l.prototypeRemoveFavorite), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'subscription detail prevents duplicate tests and cancels only its batch while another source remains queued',
    (tester) async {
      final before = (await tester.runAsync(() => coordinator.configuration))!
          .encode();
      final l = await open(tester);
      await tester.ensureVisible(find.text(l.prototypeSubscriptions).first);
      await tester.tap(find.text(l.prototypeSubscriptions).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('First source'));
      await tester.pumpAndSettle();
      final firstAction = find.byKey(
        ValueKey('source-test-action-$firstSourceId'),
      );
      await tester.scrollUntilVisible(
        firstAction,
        240,
        scrollable: find
            .descendant(
              of: find.byType(ServerSourcePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // Two taps before the next rebuild exercise the original start callback twice.
      await tester.runAsync(() async {
        await tester.tap(firstAction);
        await tester.tap(firstAction);
        await firstEntered.future.timeout(const Duration(seconds: 5));
      });
      await tester.pump();
      expect(controller.state.serverTests, hasLength(1));
      expect(batches, hasLength(1));
      expect(tester.widget<SettingRow>(firstAction).title, l.prototypeCancel);
      await tester.tap(firstAction);
      await tester.pump();
      expect(
        tester.widget<SettingRow>(firstAction).title,
        l.prototypePleaseWait,
      );
      expect(tester.widget<SettingRow>(firstAction).enabled, isFalse);
      expect(controller.cancellingGroup('subscription:$firstSourceId'), isTrue);
      router!.pop();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('Second source'));
      await tester.tap(find.text('Second source'));
      await tester.pump(const Duration(milliseconds: 400));
      final secondAction = find.byKey(
        ValueKey('source-test-action-$secondSourceId'),
      );
      await tester.scrollUntilVisible(
        secondAction,
        240,
        scrollable: find
            .descendant(
              of: find.byType(ServerSourcePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.runAsync(() async {
        await tester.tap(secondAction);
        if (!controller.testingGroup('subscription:$secondSourceId')) {
          await controller.stream
              .firstWhere(
                (_) => controller.testingGroup('subscription:$secondSourceId'),
              )
              .timeout(const Duration(seconds: 5));
        }
      });
      await tester.pump();
      expect(
        controller.cancellingGroup('subscription:$secondSourceId'),
        isFalse,
      );
      expect(controller.state.serverTests, hasLength(2));
      await tester.runAsync(() async {
        firstResults.complete(
          List.generate(
            PingBatchRunner.maxBatchSize,
            (_) => const PingBatchResult(true, 20, ''),
          ),
        );
        await secondEntered.future.timeout(const Duration(seconds: 5));
        if (controller.testingGroup('subscription:$firstSourceId')) {
          await controller.stream
              .firstWhere(
                (_) => !controller.testingGroup('subscription:$firstSourceId'),
              )
              .timeout(const Duration(seconds: 5));
        }
      });
      await tester.pump();
      expect(controller.testingGroup('subscription:$secondSourceId'), isTrue);
      expect(
        controller.cancellingGroup('subscription:$secondSourceId'),
        isFalse,
      );
      expect(batches, hasLength(2));
      expect(batches.first, hasLength(PingBatchRunner.maxBatchSize));
      expect(batches.last, ['Second node']);
      await tester.runAsync(() async {
        secondResults.complete([const PingBatchResult(true, 40, '')]);
        if (controller.state.serverTests.isNotEmpty) {
          await controller.stream
              .firstWhere((state) => state.serverTests.isEmpty)
              .timeout(const Duration(seconds: 5));
        }
      });
      await tester.pumpAndSettle();
      expect(
        tester.widget<SettingRow>(secondAction).title,
        l.prototypeTestServers,
      );
      final untouched = await tester.runAsync(
        () => db.coreConfigDao.searchRow(firstNodeIds.last),
      );
      final measured = await tester.runAsync(
        () => db.coreConfigDao.searchRow(secondNodeId),
      );
      expect(untouched!.delay, PingDelayConstants.unknown);
      expect(measured!.delay, 40);
      expect(
        (await tester.runAsync(() => coordinator.configuration))!.encode(),
        before,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
