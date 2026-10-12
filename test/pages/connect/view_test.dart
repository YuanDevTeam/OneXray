import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/traffic_format.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/connect/view.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_empty_state.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/traffic.dart';
import 'package:onexray/service/settings/backup/service.dart';

void main() {
  test('connection traffic keeps byte conversion and prototype precision', () {
    expect(formatTraffic(0, connection: true), '0 B');
    expect(formatTraffic(1024, connection: true), '1 KB');
    expect(formatTraffic(1536, connection: true), '1.5 KB');
    expect(
      formatTraffic((2.34 * 1024 * 1024).round(), connection: true),
      '2.34 MB',
    );
    expect(formatTraffic(1536), '1.5 KiB');
  });

  Widget screen({
    ConnectionView view = const ConnectionView(),
    bool hasServers = true,
    bool expert = false,
    String? runningPath,
    bool methodEnabled = true,
    VoidCallback? onMethod,
    String method = 'Smart Routing',
    String? methodDetail,
    List<CoreConfigData> raws = const [],
    VoidCallback? onAddServers,
    VoidCallback? onExpert,
  }) => ConnectView(
    view: view,
    hasServers: hasServers,
    expert: expert,
    raws: raws,
    activeRawId: null,
    location: 'Automatic selection',
    runningPath: runningPath,
    method: method,
    methodDetail: methodDetail,
    methodEnabled: methodEnabled,
    onConnection: () {},
    onAddServers: onAddServers ?? () {},
    onExpert: (_) => onExpert?.call(),
    onServer: () {},
    onMethod: onMethod ?? () {},
    onWhy: () {},
    onRawAdd: () {},
    onRawSelect: (_) {},
    onRawActions: (_) {},
  );

  Widget app(
    Widget child, {
    Locale locale = const Locale('en'),
    double scale = 1,
  }) => MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalePolicy.localizationsDelegates,
    builder: (context, child) => LayoutBuilder(
      builder: (context, constraints) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: constraints.biggest,
          textScaler: TextScaler.linear(scale),
        ),
        child: ShadTheme(data: AppTheme.shad(Brightness.light), child: child!),
      ),
    ),
    home: Scaffold(body: child),
  );

  testWidgets(
    'provider traffic method is a read-only explanation on mobile and desktop',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var choices = 0;
      for (final width in [390.0, 1160.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        await tester.pumpWidget(
          app(
            screen(
              method: 'Provider configuration',
              methodDetail: 'App routing preferences are kept.',
              methodEnabled: false,
              onMethod: () => choices++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = find.text('Provider configuration');
        final choice = find
            .ancestor(of: title, matching: find.byType(InkWell))
            .first;
        expect(tester.widget<InkWell>(choice).onTap, isNull);
        expect(
          find.descendant(
            of: choice,
            matching: find.byIcon(LucideIcons.chevronRightDir),
          ),
          findsNothing,
        );
        await tester.tap(title);
        expect(choices, 0);
        expect(find.text('App routing preferences are kept.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'connection traffic is read-only with complete values and units',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final view = ConnectionView(
        phase: ConnectionPhase.connected,
        metricsAvailable: true,
        downloadSpeed: (248.72 * 1024).round(),
        uploadSpeed: (32.8 * 1024).round(),
        traffic: ConnectionTraffic(
          uplink: (158.91 * 1024).round(),
          downlink: (999.99 * 1024 * 1024).round(),
          sampledAtMs: 0,
        ),
      );
      for (final (width, scale, locale) in [
        (1160.0, 1.0, const Locale('en')),
        (901.0, 1.0, const Locale('en')),
        (390.0, 1.0, const Locale('en')),
        (320.0, 1.0, const Locale('en')),
        (1160.0, 1.3, const Locale('ru')),
        (390.0, 1.3, const Locale('fa')),
      ]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(
          app(
            width > AppLayout.mobileBreakpoint
                ? Row(
                    children: [
                      const SizedBox(width: AppLayout.desktopSidebarWidth),
                      Expanded(child: screen(view: view)),
                    ],
                  )
                : screen(view: view),
            locale: locale,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(ConnectView)),
        )!;
        final title = find.text(l.prototypeTraffic);
        expect(title, findsOneWidget);
        expect(
          find.ancestor(of: title, matching: find.byType(InkWell)),
          findsNothing,
        );
        final card = find
            .ancestor(of: title, matching: find.byType(Card))
            .first;
        expect(
          find.descendant(
            of: card,
            matching: find.byIcon(LucideIcons.chevronRightDir),
          ),
          findsNothing,
        );
        for (final value in [
          '248.72 KB/s',
          '32.8 KB/s',
          '158.91 KB',
          '999.99 MB',
        ]) {
          expect(find.text(value), findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(value),
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '$value must not be truncated at $width / $scale / $locale',
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final expert in [false, true]) {
    testWidgets('desktop connection shares one panel, expert=$expert', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1160, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(screen(expert: expert)));
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('desktop-connection-panel'));
      final traffic = find.byKey(const ValueKey('desktop-traffic-panel'));
      final panelRect = tester.getRect(panel);
      final trafficRect = tester.getRect(traffic);
      expect(panelRect.top, AppSpacing.desktopPageTop);
      expect(trafficRect.top, panelRect.top);
      expect(trafficRect.left - panelRect.right, 16);
      expect(panelRect.width / trafficRect.width, closeTo(1.04, .001));
      expect(panelRect.height, closeTo(trafficRect.height, .001));
      expect(
        find.descendant(of: panel, matching: find.text('Disconnected')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('Expert mode')),
        findsOneWidget,
      );
      final connectButton = find.widgetWithText(FilledButton, 'Connect');
      expect(
        tester.getSize(connectButton).width,
        AppLayout.connectDesktopButtonWidth,
      );
      expect(
        tester.getSize(connectButton).height,
        AppLayout.connectDesktopButtonMinHeight,
      );
      expect(
        tester.widget<TrafficReadout>(find.byType(TrafficReadout)).desktop,
        isTrue,
      );
      expect(
        find.text('Why this connection?'),
        expert ? findsNothing : findsOneWidget,
      );
      expect(find.text('Add Raw JSON'), expert ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact desktop stacks panels while mobile stays unchanged', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(850, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(screen()));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('desktop-connection-panel'));
    final traffic = find.byKey(const ValueKey('desktop-traffic-panel'));
    expect(tester.getRect(traffic).top - tester.getRect(panel).bottom, 16);
    expect(tester.getSize(traffic).width, tester.getSize(panel).width);
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(traffic, findsNothing);
    expect(
      tester.widget<TrafficReadout>(find.byType(TrafficReadout)).desktop,
      isFalse,
    );
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Connect')).height,
      AppLayout.connectButtonMinHeight,
    );
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    const Locale('en'),
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    const Locale('ru'),
    const Locale('fa'),
  ]) {
    final width = locale.languageCode == 'en' || locale.languageCode == 'fa'
        ? 1160.0
        : 390.0;
    testWidgets('connection layout ${locale.toLanguageTag()} at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(screen(), locale: locale, scale: 1.3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(ConnectView));
      final l = AppLocalizations.of(context)!;
      expect(find.text(l.prototypeCurrentSpeed), findsOneWidget);
      expect(find.text(l.prototypeServers), findsOneWidget);
      expect(
        Directionality.of(context),
        locale.languageCode == 'fa' ? TextDirection.rtl : TextDirection.ltr,
      );
    });
    testWidgets(
      'connected path and selection reset notice ${locale.toLanguageTag()}',
      (tester) async {
        const path = 'Singapore 03 + Japan 02 → United States 01';
        await tester.pumpWidget(
          app(
            screen(
              view: const ConnectionView(
                phase: ConnectionPhase.connected,
                issue: 'selectionReset',
              ),
              runningPath: path,
            ),
            locale: locale,
          ),
        );
        final l = AppLocalizations.of(
          tester.element(find.byType(ConnectView)),
        )!;
        expect(find.text(path), findsOneWidget);
        expect(
          find.text(l.prototypeNameActive(l.prototypeAutomaticSelection)),
          findsOneWidget,
        );
        expect(find.text(l.prototypeConnectionFailed), findsNothing);
        expect(find.text(l.prototypeCheckNetwork), findsNothing);
        expect(find.text(l.prototypeConnected), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty normal state still offers expert configuration', (
    tester,
  ) async {
    var switched = false;
    await tester.pumpWidget(
      app(screen(hasServers: false, onExpert: () => switched = true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use a complete Raw JSON configuration'));
    expect(switched, isTrue);
  });

  testWidgets('connection empty state uses the server page layout', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final (size, locale) in [
      (const Size(1160, 800), const Locale('zh')),
      (const Size(760, 600), const Locale('ru')),
      (const Size(1160, 800), const Locale('fa')),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        app(
          Scaffold(
            appBar: AppBar(title: const Text('Connect')),
            body: screen(hasServers: false),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PageEmptyState), findsOneWidget);
      final l = AppLocalizations.of(
        tester.element(find.byType(PageEmptyState)),
      )!;
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
      final bodyTop = tester.getBottomLeft(find.byType(AppBar)).dy;
      expect(card.center.dx, closeTo(size.width / 2, .5));
      expect(card.top, bodyTop + AppSpacing.desktopPageTop);
      expect(
        card.width,
        size.width.clamp(0.0, AppLayout.standardMaxWidth) - AppSpacing.page * 2,
      );
      expect(card.height, AppLayout.emptyStateDesktopMinHeight);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'empty state actions stay reachable in short and mobile windows',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in [const Size(760, 240), const Size(390, 600)]) {
        var added = false;
        var switched = false;
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          app(
            screen(
              hasServers: false,
              onAddServers: () => added = true,
              onExpert: () => switched = true,
            ),
            scale: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        for (final action in [
          find.widgetWithText(FilledButton, 'Add servers'),
          find.widgetWithText(
            TextButton,
            'Use a complete Raw JSON configuration',
          ),
        ]) {
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          await tester.tap(action);
        }
        expect(added, isTrue);
        expect(switched, isTrue);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('platform errors are not presented as permission requests', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        screen(
          view: ConnectionView(
            phase: ConnectionPhase.failed,
            issue: 'nativeStatusFailed',
            permission: PlatformPermissionResult(
              kind: PlatformPermissionKind.appleVpn,
              state: PlatformPermissionState.failed,
            ),
          ),
        ),
      ),
    );
    final l = AppLocalizations.of(tester.element(find.byType(ConnectView)))!;

    expect(find.text(l.prototypeTemporarilyUnavailable), findsOneWidget);
    expect(find.text(l.prototypeVpnPermissionRequired), findsNothing);
  });

  testWidgets('missing desktop interface shows the interface prompt', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        screen(
          view: const ConnectionView(
            phase: ConnectionPhase.disconnected,
            issue: 'interfaceRequired',
          ),
        ),
      ),
    );
    final l = AppLocalizations.of(tester.element(find.byType(ConnectView)))!;

    expect(find.text(l.prototypeChooseInterfaceNotice), findsOneWidget);
    expect(find.text(l.prototypeCheckNetwork), findsNothing);
  });

  testWidgets(
    'connection status shows resolver counts instead of a network error',
    (tester) async {
      await tester.pumpWidget(
        app(
          screen(
            view: const ConnectionView(
              issue: 'insufficientHealthyServers',
              error: ConnectionResolutionException(
                ConnectionResolutionFailure.insufficientHealthyServers,
                requiredCount: 3,
                availableCount: 1,
              ),
            ),
          ),
        ),
      );
      final l = AppLocalizations.of(tester.element(find.byType(ConnectView)))!;
      expect(find.text('${l.prototypeNotEnoughServers} (1/3)'), findsOneWidget);
      expect(find.text(l.prototypeCheckNetwork), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all legacy Raw configurations remain visible; add hidden at 3+',
    (tester) async {
      final raws = List.generate(
        4,
        (index) => CoreConfigData(
          id: index + 1,
          name: 'Legacy ${index + 1}',
          type: 'raw',
          tags: '',
          delay: -1,
          subId: 0,
          favorite: false,
        ),
      );
      await tester.pumpWidget(app(screen(expert: true, raws: raws)));
      await tester.pumpAndSettle();
      for (final row in raws) {
        expect(find.text(row.name), findsOneWidget);
      }
      expect(find.text('Add Raw JSON'), findsNothing);
      expect(find.text('Why this connection?'), findsNothing);
    },
  );

  testWidgets('page footer stays compact and fixed while content scrolls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: List.generate(40, (i) => ListTile(title: Text('Row $i'))),
          ),
          bottomNavigationBar: PageActionBar(
            children: [
              TextButton(onPressed: () {}, child: const Text('Cancel')),
              FilledButton(onPressed: () {}, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
    final before = tester.getRect(find.text('Save'));
    expect(before.top, greaterThan(650));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Save')), before);
    expect(
      tester.getSize(find.byType(PageActionBar)).height,
      greaterThanOrEqualTo(AppLayout.mobilePageActionMinHeight),
    );
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(AppLayout.pageActionButtonMinHeight),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(FilledButton)).width,
      greaterThanOrEqualTo(AppLayout.pageActionButtonMinWidth),
    );
    expect(
      tester.getSize(find.byType(PageActionBar)).height,
      greaterThanOrEqualTo(AppLayout.pageActionMinHeight),
    );
    expect(tester.takeException(), isNull);
  });
}
