import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/menus.dart';
import 'package:onexray/pages/servers/subscription/user_info.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/page_empty_state.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/backup/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/servers/sort.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show ShadTheme, ShadToaster, ShadToast;

class _Controller extends ServersController {
  _Controller({
    required super.database,
    required super.coordinator,
    super.ping,
  });

  bool? browsedOnMobile;
  bool helpOpened = false;
  bool addOpened = false;

  @override
  Future<void> browse(
    BuildContext context,
    ServerGroup group, {
    required bool mobile,
  }) async {
    browsedOnMobile = mobile;
    activeGroupId = group.id;
  }

  @override
  Future<void> openServerHelp(BuildContext context) async {
    helpOpened = true;
  }

  @override
  Future<void> addServers(BuildContext context) async {
    addOpened = true;
  }
}

CoreConfigData _server(int id, {bool favorite = false, String? name}) =>
    CoreConfigData(
      id: id,
      name: name ?? 'Node $id',
      type: 'outbound',
      tags: 'vless,xhttp,tls',
      data: base64Encode(
        utf8.encode(
          jsonEncode({
            'tag': name ?? 'Node $id',
            'protocol': 'vless',
            'streamSettings': {'network': 'xhttp', 'security': 'tls'},
          }),
        ),
      ),
      delay: id * 20,
      subId: 0,
      manualSortOrder: 0,
      favorite: favorite,
    );

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late _Controller controller;
  late ScrollController scroll;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(database: db);
    controller = _Controller(database: db, coordinator: coordinator)
      ..servers = [_server(1, favorite: true), _server(2)];
    scroll = ScrollController();
  });

  tearDown(() async {
    scroll.dispose();
    await controller.close();
    coordinator.dispose();
    await db.close();
  });

  Future<void> pumpBrowser(
    WidgetTester tester,
    double width, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    bool groupPage = false,
    ValueNotifier<bool>? pageVisibility,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final mobile = width <= AppLayout.mobileBreakpoint;
    final browser = BlocBuilder<_Controller, ServersPageState>(
      bloc: controller,
      builder: (context, _) => groupPage
          ? ServerGroupView(
              controller: controller,
              group: controller.groups(AppLocalizations.of(context)!).first,
            )
          : ServerBrowser(controller: controller, scroll: scroll),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.material(brightness, mobile: mobile),
        locale: locale,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ShadTheme(
          data: AppTheme.shad(brightness),
          child: ShadToaster(child: child!),
        ),
        home: Scaffold(
          body: Row(
            children: [
              if (!mobile)
                SizedBox(
                  width: width <= AppLayout.compactDesktopBreakpoint
                      ? AppLayout.compactSidebarWidth
                      : AppLayout.desktopSidebarWidth,
                ),
              Expanded(
                child: ResponsiveContent(
                  child: pageVisibility == null
                      ? browser
                      : ValueListenableBuilder<bool>(
                          valueListenable: pageVisibility,
                          child: browser,
                          builder: (_, active, child) =>
                              TickerMode(enabled: active, child: child!),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<int>> installPing(WidgetTester tester, {int count = 1}) async {
    final batches = <int>[];
    await tester.runAsync(() async {
      final rows = <CoreConfigData>[];
      for (var index = 0; index < count; index++) {
        final id = await db.coreConfigDao.insertRow(
          outboundCompanion({'tag': 'Probe $index', 'protocol': 'socks'}),
        );
        rows.add((await db.coreConfigDao.searchRow(id))!);
      }
      await controller.close();
      controller = _Controller(
        database: db,
        coordinator: coordinator,
        ping: PingService.forTesting(
          database: db,
          runBatch: (sources, _) async {
            batches.add(sources.length);
            return [
              for (final _ in sources) const PingBatchResult(true, 20, ''),
            ];
          },
        ),
      )..servers = rows;
    });
    return batches;
  }

  testWidgets(
    'sorting changes display order without selecting or testing nodes',
    (tester) async {
      controller.servers = [
        _server(2, name: 'Alpha'),
        _server(1, name: 'Zulu'),
      ];
      await pumpBrowser(tester, 1280);
      expect(controller.servers.map((row) => row.id), [1, 2]);

      await tester.tap(find.byTooltip('Sort servers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name').last);
      await tester.pumpAndSettle();
      expect(controller.catalog.sortOrder, ServerSortOrder.name);
      expect(controller.servers.map((row) => row.id), [2, 1]);
      expect(AppEventBus.instance.state.serverSort, ServerSortOrder.name);

      controller.servers = [
        _server(1, name: 'Zulu').copyWith(delay: 1),
        _server(2, name: 'Alpha').copyWith(delay: 900),
      ];
      await tester.pumpAndSettle();
      expect(controller.servers.map((row) => row.id), [2, 1]);
      await tester.enterText(find.byType(TextField).first, 'Alpha');
      await tester.pumpAndSettle();
      final labels = AppLocalizations.of(
        tester.element(find.byType(ServerBrowser)),
      )!;
      expect(
        controller.groups(labels).single.visibleRows.map((row) => row.id),
        [2],
      );
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      expect(
        controller.groups(labels).single.visibleRows.map((row) => row.id),
        [2, 1],
      );

      await tester.tap(find.byTooltip('Sort servers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Latency').last);
      await tester.pumpAndSettle();
      expect(controller.servers.map((row) => row.id), [1, 2]);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(
        controller.configuration.connection.selection.kind,
        SelectionKind.automatic,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final phase in [
    ConnectionPhase.disconnected,
    ConnectionPhase.preparing,
    ConnectionPhase.failed,
  ]) {
    testWidgets('manual probing needs no confirmation when $phase', (
      tester,
    ) async {
      final batches = await installPing(tester);
      coordinator.state.value = ConnectionView(phase: phase);
      await pumpBrowser(tester, 427);
      final context = tester.element(find.byType(ServerBrowser));
      await tester.runAsync(
        () => controller
            .test(context, controller.servers)
            .timeout(const Duration(seconds: 5)),
      );
      await tester.pumpAndSettle();
      expect(batches, [1]);
      expect(controller.state.serverTests, isEmpty);
      expect(AppEventBus.instance.state.pinging, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final view in const [
    ConnectionView(phase: ConnectionPhase.connected),
    ConnectionView(phase: ConnectionPhase.connecting),
    ConnectionView(phase: ConnectionPhase.disconnecting),
    ConnectionView(phase: ConnectionPhase.failed, issue: 'stopFailed'),
  ]) {
    testWidgets('manual probing confirms before queuing when ${view.phase}', (
      tester,
    ) async {
      final batches = await installPing(tester);
      // Failed views can change their stop capability without changing phase;
      // confirmation must read the coordinator, rather than a page snapshot.
      coordinator.state.value = ConnectionView(phase: view.phase);
      coordinator.state.value = view;
      await pumpBrowser(tester, 427);
      final context = tester.element(find.byType(ServerBrowser));
      final l = AppLocalizations.of(context)!;
      late Future<void> operation;
      await tester.runAsync(() async {
        operation = controller.serverAction(
          context,
          controller.servers.single,
          ServerAction.test,
        );
      });
      await tester.pumpAndSettle();
      final title = view.phase == ConnectionPhase.connected
          ? l.pingVpnActiveTitle
          : view.phase == ConnectionPhase.failed
          ? l.pingVpnPossiblyActiveTitle
          : l.pingVpnChangingTitle;
      expect(find.text(title), findsOneWidget);
      expect(find.text(l.pingVpnWarning), findsOneWidget);
      expect(batches, isEmpty);
      expect(controller.state.serverTests, isEmpty);
      expect(AppEventBus.instance.state.pinging, isFalse);
      await tester.runAsync(() async {
        await tester.tap(find.text(l.pingContinueTest));
        await operation.timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      expect(batches, [1]);
      expect(controller.state.serverTests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  {
    testWidgets('group confirmation cancels safely and covers every batch', (
      tester,
    ) async {
      final batches = await installPing(tester, count: 7);
      final before = controller.servers.first;
      coordinator.state.value = const ConnectionView(
        phase: ConnectionPhase.connected,
      );
      await pumpBrowser(tester, 427, groupPage: true);
      final context = tester.element(find.byType(ServerGroupView));
      final l = AppLocalizations.of(context)!;
      await tester.tap(
        find.widgetWithText(OutlinedButton, l.prototypeTestServers),
      );
      await tester.pumpAndSettle();
      await controller.test(context, controller.servers);
      await tester.pumpAndSettle();
      expect(find.text(l.pingVpnActiveTitle), findsOneWidget);
      expect(batches, isEmpty);
      expect(controller.state.serverTests, isEmpty);
      expect(AppEventBus.instance.state.pinging, isFalse);
      await tester.tap(find.text(l.buttonCancel));
      await tester.pumpAndSettle();
      final unchanged = await tester.runAsync(
        () => db.coreConfigDao.searchRow(before.id),
      );
      expect(unchanged!.delay, before.delay);
      expect(batches, isEmpty);

      late Future<void> operation;
      await tester.runAsync(() async {
        operation = controller.test(
          context,
          controller.servers,
          groupId: controller.groups(l).single.id,
        );
      });
      await tester.pumpAndSettle();
      expect(find.text(l.pingVpnActiveTitle), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text(l.pingContinueTest));
        await operation.timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      expect(batches, [5, 2]);
      expect(find.text(l.pingVpnActiveTitle), findsNothing);
      expect(controller.state.serverTests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a dismissed confirmation never queues a probe', (tester) async {
    final batches = await installPing(tester);
    coordinator.state.value = const ConnectionView(
      phase: ConnectionPhase.connected,
    );
    await pumpBrowser(tester, 427);
    final context = tester.element(find.byType(ServerBrowser));
    final operation = controller.test(context, controller.servers);
    await tester.pumpAndSettle();
    Navigator.of(context, rootNavigator: true).pop();
    await operation;
    await tester.pumpAndSettle();
    expect(batches, isEmpty);
    expect(controller.state.serverTests, isEmpty);
    expect(AppEventBus.instance.state.pinging, isFalse);
  });

  testWidgets('switching away from a retained tab cancels pending probing', (
    tester,
  ) async {
    final batches = await installPing(tester);
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    coordinator.state.value = const ConnectionView(
      phase: ConnectionPhase.connected,
    );
    await pumpBrowser(tester, 427, pageVisibility: visible);
    final context = tester.element(find.byType(ServerBrowser));
    final l = AppLocalizations.of(context)!;
    final operation = controller.test(context, controller.servers);
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pump();
    expect(context.mounted, isTrue);
    expect(controller.isPageActive, isTrue);
    await tester.tap(find.text(l.pingContinueTest));
    await operation;
    await tester.pumpAndSettle();
    expect(batches, isEmpty);
    expect(controller.state.serverTests, isEmpty);
    expect(AppEventBus.instance.state.pinging, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final closeController in [false, true]) {
    testWidgets(
      'leaving the page while confirming skips probing (closed: $closeController)',
      (tester) async {
        final batches = await installPing(tester);
        coordinator.state.value = const ConnectionView(
          phase: ConnectionPhase.connected,
        );
        await pumpBrowser(tester, 427);
        final context = tester.element(find.byType(ServerBrowser));
        final l = AppLocalizations.of(context)!;
        final operation = controller.test(context, controller.servers);
        await tester.pumpAndSettle();
        if (closeController) {
          // A real page disposes its widgets with the controller. Retain the
          // dialog, but remove the search field before releasing its resource.
          Navigator.of(context, rootNavigator: true).replace(
            oldRoute: ModalRoute.of(context)!,
            newRoute: MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Another page')),
            ),
          );
          await tester.pumpAndSettle();
          expect(context.mounted, isFalse);
          await controller.close();
          await tester.tap(find.text(l.pingContinueTest));
        } else {
          final dialogRoute = ModalRoute.of(
            tester.element(find.text(l.pingContinueTest)),
          )!;
          final navigator = Navigator.of(context, rootNavigator: true);
          unawaited(
            navigator.push<void>(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Another page')),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Confirmation and navigation may complete in either order. A still
          // mounted controller does not mean its originating route is active.
          navigator.removeRoute(dialogRoute, true);
        }
        await operation;
        await tester.pumpAndSettle();
        expect(batches, isEmpty);
        expect(controller.state.serverTests, isEmpty);
        expect(AppEventBus.instance.state.pinging, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'latency failure uses destructive color and success clears the message',
    (tester) async {
      await pumpBrowser(tester, 427, groupPage: true);
      AppEventBus.instance.updatePingResults({
        1: const PingBatchResult(false, -1, 'Latency failed'),
      });
      await tester.pumpAndSettle();
      final message = tester.widget<SelectableText>(
        find.descendant(
          of: find.byType(ServerNodeRow).first,
          matching: find.byType(SelectableText),
        ),
      );
      final palette = ColorManager.palette(
        tester.element(find.byType(ServerNodeRow).first),
      );
      expect(message.style!.color, palette.destructive);
      AppEventBus.instance.updatePingResults({
        1: const PingBatchResult(true, 20, ''),
      });
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (locale, width) in const [
    (Locale('en'), 1160.0),
    (Locale('zh'), 390.0),
    (Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), 390.0),
    (Locale('ru'), 1160.0),
    (Locale('fa'), 390.0),
  ]) {
    testWidgets('subscription package fits list and detail ($locale, $width)', (
      tester,
    ) async {
      controller.sources = [
        SubscriptionData(
          panel: 'generic',
          mode: 'appManaged',
          id: 1,
          name: 'Provider subscription with a long descriptive name',
          url: 'https://example.test/subscription',
          hwidEnabled: false,
          timestamp: DateTime(2026, 9, 1),
          uploadBytes: 1024,
          downloadBytes: 2048,
          totalBytes: 0x7fffffffffffffff,
          expireTimestamp: 253402214400,
          userInfoUpdatedAt: DateTime(2026, 9, 1),
        ),
      ];
      controller.servers = [_server(1).copyWith(subId: 1)];
      await pumpBrowser(tester, width, locale: locale);
      expect(find.byType(SubscriptionPackageSummary), findsWidgets);
      expect(tester.takeException(), isNull);
      await pumpBrowser(tester, width, locale: locale, groupPage: true);
      expect(find.byType(SubscriptionPackageDetails), findsOneWidget);
      expect(find.byType(SourceMenu), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('source updates refresh package UI without restricting use', (
    tester,
  ) async {
    final source = SubscriptionData(
      panel: 'generic',
      mode: 'appManaged',
      id: 1,
      name: 'Provider',
      url: 'https://example.test/subscription',
      hwidEnabled: false,
      timestamp: DateTime(2026, 9, 1),
    );
    controller.sources = [source];
    controller.servers = [
      _server(1).copyWith(
        subId: 1,
        data: outboundCompanion({'tag': 'Node 1', 'protocol': 'vless'}).data,
      ),
    ];
    await pumpBrowser(tester, 390, groupPage: true);
    expect(find.byType(SubscriptionPackageDetails), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: find.byType(ServerUseButton),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    controller.sources = [
      source.copyWith(
        uploadBytes: const Value(1024),
        downloadBytes: const Value(2048),
        totalBytes: const Value(1024),
        expireTimestamp: const Value(1),
        userInfoUpdatedAt: Value(DateTime(2026, 9, 2)),
      ),
    ];
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionPackageDetails), findsOneWidget);
    final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    expect(find.textContaining(l.subscriptionPackageExpired), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: find.byType(ServerUseButton),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    controller.sources = [source];
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionPackageDetails), findsNothing);
    expect(find.byType(ServerNodeRow), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final width in [427.0, 1160.0]) {
      testWidgets(
        'node latency colors preserve metadata ($brightness, $width)',
        (tester) async {
          final palette = AppColorTokens.fallback(brightness).palette;
          final samples = [
            (0, palette.runningBadge),
            (500, palette.runningBadge),
            (501, palette.restartingText),
            (1000, palette.restartingText),
            (1001, palette.primaryHover),
            (PingDelayConstants.unknown, palette.mutedForeground),
            (PingDelayConstants.error, palette.mutedForeground),
            (PingDelayConstants.timeout, palette.mutedForeground),
          ];
          controller.servers = [
            for (final (index, (delay, _)) in samples.indexed)
              _server(index + 1).copyWith(delay: delay),
          ];
          await pumpBrowser(
            tester,
            width,
            brightness: brightness,
            groupPage: true,
          );
          final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
          for (final (index, (delay, color)) in samples.indexed) {
            final rowFinder = find.byKey(ValueKey(index + 1));
            await tester.scrollUntilVisible(
              rowFinder,
              120,
              scrollable: find.descendant(
                of: find.byType(ServerGroupView),
                matching: find.byType(Scrollable),
              ),
            );
            final label = controller.health(l, controller.servers[index]);
            final prefix = '${l.manualGroupUngrouped} · ';
            final text = tester.widget<Text>(
              find.descendant(
                of: find.byKey(ValueKey(index + 1)),
                matching: find.text('$prefix$label'),
              ),
            );
            final span = text.textSpan! as TextSpan;
            expect(span.text, prefix);
            expect(text.style!.color, palette.mutedForeground);
            expect(span.children!.single.style!.color, color);
            if (PingDelayConstants.isSuccessful(delay)) {
              for (final background in [
                palette.card,
                palette.selectedSurface,
              ]) {
                final foregroundLuminance = color.computeLuminance() + 0.05;
                final backgroundLuminance =
                    background.computeLuminance() + 0.05;
                final contrast = foregroundLuminance > backgroundLuminance
                    ? foregroundLuminance / backgroundLuminance
                    : backgroundLuminance / foregroundLuminance;
                expect(contrast, greaterThanOrEqualTo(4.5));
              }
            }
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final width in [427.0, 1160.0]) {
    testWidgets('group test can be cancelled without locking menus at $width', (
      tester,
    ) async {
      controller.sources = [
        SubscriptionData(
          panel: 'generic',
          mode: 'appManaged',
          id: 4,
          name: 'Source',
          hwidEnabled: false,
          url: 'https://example.test/sub',
          timestamp: DateTime(2026),
        ),
      ];
      controller.servers = [_server(1).copyWith(subId: 4)];
      await pumpBrowser(tester, width, groupPage: true);
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerGroupView)),
      )!;
      final group = controller.groups(l).single;
      controller.emit(
        controller.state.copyWith(
          serverTests: {
            Object(): (groupId: group.id, cancelling: false),
            Object(): (groupId: null, cancelling: false),
          },
        ),
      );
      AppEventBus.instance.updatePinging(true);
      expect(controller.testingGroup(group), isTrue);
      await tester.pump();
      await tester.pump();

      for (final menu in [find.byType(ServerMenu), find.byType(SourceMenu)]) {
        for (final element in menu.evaluate()) {
          final button = tester.widget<IconButton>(
            find.descendant(
              of: find.byWidget(element.widget),
              matching: find.byType(IconButton),
            ),
          );
          expect(button.onPressed, isNotNull);
          expect(button.icon, isA<Icon>());
          expect((button.icon as Icon).icon, LucideIcons.ellipsis);
        }
      }
      expect(find.byType(ButtonProgressIndicator), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, l.prototypeCancel));
      await tester.pump();
      await tester.pump();
      expect(controller.cancellingGroup(group), isTrue);
      expect(controller.state.serverTests.values.last.cancelling, isFalse);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, l.prototypePleaseWait),
            )
            .onPressed,
        isNull,
      );

      controller.emit(controller.state.copyWith(serverTests: {}));
      AppEventBus.instance.updatePinging(false);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(OutlinedButton, l.prototypeTestServers),
        findsOneWidget,
      );
      expect(find.byType(ButtonProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, groupPage) in [
    (427.0, false),
    (427.0, true),
    (1160.0, false),
    (1160.0, true),
  ]) {
    testWidgets('automatic probing shows loading ($width, group: $groupPage)', (
      tester,
    ) async {
      late Completer<void> started;
      late Completer<void> release;
      late PingService ping;
      var batches = 0;
      final row = await tester.runAsync(() async {
        started = Completer<void>();
        release = Completer<void>();
        ping = PingService.forTesting(
          database: db,
          runBatch: (_, _) async {
            batches++;
            if (!started.isCompleted) started.complete();
            await release.future;
            return const [PingBatchResult(true, 20, '')];
          },
        );
        final id = await db.coreConfigDao.insertRow(
          outboundCompanion({'tag': 'Imported', 'protocol': 'socks'}),
        );
        return db.coreConfigDao.searchRow(id);
      });
      await controller.close();
      controller = _Controller(
        database: db,
        coordinator: coordinator,
        ping: ping,
      )..servers = [row!];
      await pumpBrowser(tester, width, groupPage: groupPage);
      final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      try {
        await tester.runAsync(() async {
          ping.schedulePingConfigIds([row.id]);
          await started.future.timeout(const Duration(seconds: 5));
        });
        await tester.pump();
        await tester.pump();
        expect(ping.isPinging, isTrue);
        expect(AppEventBus.instance.state.pinging, isTrue);
        expect(controller.state.serverTests, isEmpty);
        expect(
          find.byType(ButtonProgressIndicator),
          width > AppLayout.mobileBreakpoint && !groupPage
              ? findsNWidgets(2)
              : findsOneWidget,
        );
        if (groupPage || width > AppLayout.mobileBreakpoint) {
          expect(
            tester
                .widget<IconButton>(
                  find.descendant(
                    of: find.byType(ServerMenu),
                    matching: find.byType(IconButton),
                  ),
                )
                .onPressed,
            isNotNull,
          );
          await tester.runAsync(() async {
            await tester.tap(
              find.widgetWithText(OutlinedButton, l.prototypeTestServers),
            );
          });
          await tester.pump();
          expect(find.byType(ShadToast), findsNothing);
          expect(controller.state.serverTests, hasLength(1));
          expect(batches, 1);
        }
        if (groupPage) {
          // A queued group must not reject single-node requests. Cancelling
          // that group must leave both node requests queued and independent.
          for (var index = 0; index < 2; index++) {
            await tester.runAsync(() async {
              await tester.tap(
                find.byTooltip('${l.prototypeMoreActions}: Imported'),
              );
            });
            await tester.pump(const Duration(seconds: 1));
            await tester.runAsync(() async {
              await tester.tap(find.text(l.prototypeTestAgain));
            });
            await tester.pump(const Duration(seconds: 1));
          }
          expect(controller.state.serverTests, hasLength(3));
          expect(find.byType(ShadToast), findsNothing);
          expect(batches, 1);
          await tester.tap(
            find.widgetWithText(OutlinedButton, l.prototypeCancel),
          );
          await tester.pump();
          expect(
            controller.state.serverTests.values.map((test) => test.cancelling),
            [true, false, false],
          );
        }
      } finally {
        await tester.runAsync(() async {
          release.complete();
          // Wait for the scheduled task's database write and event update.
          await ping
              .pingConfigIds([row.id])
              .timeout(const Duration(seconds: 5));
        });
      }
      await tester.pumpAndSettle();
      expect(
        batches,
        groupPage
            ? 3
            : width > AppLayout.mobileBreakpoint
            ? 2
            : 1,
      );
      expect(controller.state.serverTests, isEmpty);
      expect(find.byType(ButtonProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in const [Locale('en'), Locale('ru'), Locale('fa')]) {
    testWidgets(
      'desktop subscriptions use equal-width cards and independent scrolls: $locale',
      (tester) async {
        await pumpBrowser(tester, 1160, locale: locale);
        final browser = find.byType(ServerBrowser);
        final group = find.byType(ServerGroupView);
        const columnWidth = (1160 - 225 - 56 - 16) / 2;
        expect(group, findsOneWidget);
        expect(tester.getSize(group).width, closeTo(columnWidth, 1));
        expect(
          find.descendant(
            of: browser,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          ),
          findsNWidgets(2),
        );
        expect(find.byType(ServerNodeRow), findsNWidgets(3));
        expect(find.byType(TabBar), findsNothing);
        expect(find.byType(VerticalDivider), findsNothing);
        expect(find.byType(PopupMenuButton<ServerAction>), findsNothing);

        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'compact desktop stacks cards and browsing updates the shared detail',
    (tester) async {
      controller.sources = [
        SubscriptionData(
          panel: 'generic',
          mode: 'appManaged',
          id: 1,
          name: 'First provider',
          url: 'https://example.test/first',
          hwidEnabled: false,
          timestamp: DateTime(2026),
        ),
        SubscriptionData(
          panel: 'generic',
          mode: 'appManaged',
          id: 2,
          name: 'Second provider',
          url: 'https://example.test/second',
          hwidEnabled: false,
          timestamp: DateTime(2026),
        ),
      ];
      controller.servers = [
        _server(1).copyWith(subId: 1),
        _server(2).copyWith(subId: 2),
      ];
      await pumpBrowser(tester, 900);
      final group = find.byType(ServerGroupView);
      expect(tester.getSize(group).width, closeTo(900 - 190 - 56, 1));
      await tester.tap(find.text('Second provider'));
      await tester.pumpAndSettle();
      expect(controller.browsedOnMobile, isFalse);
      expect(tester.widget<ServerGroupView>(group).group.source!.id, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile shows subscriptions without location tabs or labels', (
    tester,
  ) async {
    await pumpBrowser(tester, 427);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(ServerGroupView), findsNothing);
    final l = AppLocalizations.of(tester.element(find.byType(ServerBrowser)))!;
    expect(find.text('outbound'), findsOneWidget);
    expect(find.text(l.countryRegionName('JP')), findsNothing);
    expect(find.text(l.countryRegionName('SG')), findsNothing);
    await tester.tap(find.text(l.manualGroupUngrouped));
    await tester.pumpAndSettle();
    expect(controller.browsedOnMobile, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final width in [427.0, 900.0, 1160.0]) {
    testWidgets('node lists build lazily and scroll independently at $width', (
      tester,
    ) async {
      final mobile = width <= AppLayout.mobileBreakpoint;
      controller.servers = [
        for (var id = 1; id <= 200; id++) _server(id),
        for (var index = 0; index < 20; index++)
          _server(201 + index).copyWith(subId: index + 1),
      ];
      await pumpBrowser(tester, width, groupPage: mobile);
      final group = find.byType(ServerGroupView);
      final rows = find.descendant(
        of: group,
        matching: find.byType(ServerNodeRow),
      );
      final groupScroll = find.descendant(
        of: group,
        matching: find.byType(Scrollable),
      );
      final list = tester.widget<ListView>(
        find.descendant(of: group, matching: find.byType(ListView)),
      );
      expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
      expect(list.shrinkWrap, isFalse);
      expect(rows.evaluate().length, inInclusiveRange(1, 25));
      expect(find.byKey(const ValueKey(200)), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey(200)),
        1000,
        scrollable: groupScroll,
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(200)), findsOneWidget);
      expect(rows.evaluate().length, lessThan(25));
      final last = tester.widget<ServerNodeRow>(
        find.byKey(const ValueKey(200)),
      );
      expect(last.showDivider, isFalse);
      if (!mobile) {
        expect(scroll.offset, 0);
        final position = tester.state<ScrollableState>(groupScroll).position;
        final offset = position.pixels;
        expect(offset, greaterThan(0));
        scroll.jumpTo(200);
        await tester.pumpAndSettle();
        expect(scroll.offset, 200);
        expect(position.pixels, offset);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty server browser replaces browsing controls with actions', (
    tester,
  ) async {
    controller.servers = [];
    await pumpBrowser(tester, 1160);
    final l = AppLocalizations.of(tester.element(find.byType(ServerBrowser)))!;

    expect(find.byType(PageEmptyState), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, l.backupRestoreFrom),
      BackupService.supported ? findsOneWidget : findsNothing,
    );
    final emptyCard = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is ShapeDecoration &&
          (widget.decoration as ShapeDecoration).shape is AppDashedBorder,
    );
    final card = tester.getRect(emptyCard);
    expect(card.top, AppSpacing.desktopPageTop);
    expect(card.left, AppLayout.desktopSidebarWidth + AppSpacing.page);
    expect(
      card.width,
      1160 - AppLayout.desktopSidebarWidth - AppSpacing.page * 2,
    );
    expect(card.height, AppLayout.emptyStateDesktopMinHeight);
    expect(find.text(l.prototypeNoServersYet), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ServerGroupView), findsNothing);
    expect(find.text(l.prototypeAutomaticRecommended), findsNothing);

    await tester.tap(find.text(l.prototypeHowGetServers));
    await tester.pump();
    expect(controller.helpOpened, isTrue);
    await tester.tap(find.text(l.prototypeAddServer));
    await tester.pump();
    expect(controller.addOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop node menu uses the same action dialog and closes without a mutation',
    (tester) async {
      await pumpBrowser(tester, 1160);
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerBrowser)),
      )!;
      await tester.tap(
        find.byTooltip('${l.prototypeMoreActions}: Node 1').first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ServerActionsMenu), findsOneWidget);
      await tester.tap(find.byTooltip(l.prototypeCloseDialog));
      await tester.pumpAndSettle();
      expect(find.byType(ServerActionsMenu), findsNothing);
      expect(controller.servers, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
