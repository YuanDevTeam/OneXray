import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:macos_window_utils/window_manipulator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/desktop_window.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  for (final (width, height, scale, locale) in const [
    (390.0, 844.0, 1.0, Locale('zh')),
    (1032.0, 1376.0, 1.0, Locale('zh')),
    (1160.0, 720.0, 1.0, Locale('zh')),
    (390.0, 844.0, 2.0, Locale('ru')),
    (390.0, 844.0, 2.0, Locale('fa')),
  ]) {
    testWidgets(
      'page header preserves title, description and actions at $width/$scale/$locale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, height);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var actions = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.material(Brightness.light, mobile: width <= 720),
            locale: locale,
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: locale.languageCode == 'fa'
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                appBar: PageAppBar.forPage(
                  context,
                  title: const Text('Настройки подключения'),
                  description:
                      'Параметры соединения и данные этого устройства.',
                  actions: [
                    IconButton(
                      key: const Key('page-action'),
                      icon: const Icon(Icons.add),
                      onPressed: () => actions++,
                    ),
                  ],
                ),
                body: const SizedBox(
                  key: Key('page-body'),
                  width: double.infinity,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = find.text('Настройки подключения');
        final description = find.text(
          'Параметры соединения и данные этого устройства.',
        );
        expect(title, findsOneWidget);
        expect(description, findsOneWidget);
        expect(
          tester.getRect(description).top,
          greaterThanOrEqualTo(tester.getRect(title).bottom),
        );
        expect(
          tester.getRect(find.byKey(const Key('page-body'))).top,
          greaterThanOrEqualTo(tester.getRect(description).bottom),
        );
        expect(
          tester.getRect(title).left,
          greaterThanOrEqualTo(width <= 720 ? 16 : 28),
        );
        expect(
          tester.getRect(title).right,
          lessThanOrEqualTo(width - (width <= 720 ? 16 : 28)),
        );
        expect(
          find.ancestor(
            of: title,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.header == true,
            ),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('page-action')));
        await tester.pumpAndSettle();
        expect(actions, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final inline in [false, true]) {
    testWidgets('compact mobile heading action opts into one row: $inline', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.material(Brightness.light, mobile: true),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              appBar: PageAppBar.forPage(
                context,
                title: const Text('服务器'),
                description: '',
                inlineHeadingAction: inline,
                headingAction: FilledButton.icon(
                  key: const Key('compact-heading-action'),
                  onPressed: () => actions++,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('导入'),
                ),
              ),
              body: const SizedBox(
                key: Key('compact-page-body'),
                width: double.infinity,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final heading = find.byKey(const ValueKey('page-heading'));
      final title = find.descendant(of: heading, matching: find.text('服务器'));
      final action = find.byKey(const Key('compact-heading-action'));
      final titleBounds = tester.getRect(title);
      final actionBounds = tester.getRect(action);
      expect(tester.widget<Text>(title).maxLines, isNull);
      expect(action.hitTestable(), findsOneWidget);
      if (inline) {
        expect(titleBounds.overlaps(actionBounds), isFalse);
        expect(titleBounds.center.dy, closeTo(actionBounds.center.dy, .01));
        expect(titleBounds.right, lessThanOrEqualTo(actionBounds.left));
        expect(
          tester.getRect(find.byKey(const Key('compact-page-body'))).top,
          lessThanOrEqualTo(132),
        );
      } else {
        expect(actionBounds.top, greaterThanOrEqualTo(titleBounds.bottom + 16));
      }
      expect(actionBounds.right, lessThanOrEqualTo(390 - 16));
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(actions, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in [const Locale('ru'), const Locale('fa')]) {
    testWidgets(
      'inline heading wraps long identity and preserves short viewport actions: $locale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 360);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var imports = 0;
        var saves = 0;
        const titleText = 'Настройки подключения — Tokyo Singapore — настройки';
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.material(Brightness.light, mobile: true),
            locale: locale,
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: Directionality(
                textDirection: locale.languageCode == 'fa'
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                appBar: PageAppBar.forPage(
                  context,
                  title: const Text(titleText),
                  description: '',
                  inlineHeadingAction: true,
                  headingAction: TextButton(
                    key: const Key('inline-import'),
                    onPressed: () => imports++,
                    child: const Text('Import'),
                  ),
                ),
                body: const SizedBox.expand(key: Key('inline-page-body')),
                bottomNavigationBar: PageActionBar(
                  children: [
                    FilledButton(
                      key: const Key('inline-save'),
                      onPressed: () => saves++,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final heading = find.byKey(const ValueKey('page-heading'));
        final title = find.descendant(
          of: heading,
          matching: find.text(titleText),
        );
        expect(tester.widget<Text>(title).maxLines, isNull);
        expect(
          tester.widget<Text>(title).overflow,
          isNot(TextOverflow.ellipsis),
        );
        final titleBounds = tester.getRect(title);
        expect(titleBounds.left, greaterThanOrEqualTo(16));
        expect(titleBounds.right, lessThanOrEqualTo(374));
        expect(
          tester.getSize(find.byKey(const Key('inline-page-body'))).height,
          greaterThanOrEqualTo(80),
        );
        final headingScrollable = find.descendant(
          of: heading,
          matching: find.byType(Scrollable),
        );
        expect(
          tester
              .state<ScrollableState>(headingScrollable)
              .position
              .maxScrollExtent,
          greaterThan(0),
        );
        final action = find.byKey(const Key('inline-import'));
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        await tester.tap(action);
        await tester.tap(find.byKey(const Key('inline-save')));
        await tester.pumpAndSettle();
        expect(imports, 1);
        expect(saves, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final height in [844.0, 360.0]) {
    testWidgets(
      'long legal resource heading keeps content and footer reachable at 390x$height/2x',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(390, height);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fileName = '${List.filled(176, 'a').join()}.dat';
        expect(fileName.length, 180);
        expect(GeoDataInput.canonicalFileName(fileName), fileName);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        var headingActions = 0;
        var bodyActions = 0;
        var saves = 0;
        var backs = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.material(Brightness.light, mobile: true),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: ShadTheme(
                data: AppTheme.shad(Brightness.light, mobile: true),
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                appBar: PageAppBar.forPage(
                  context,
                  title: Text(fileName),
                  description: 'Resource source and update settings.',
                  leading: BackButton(onPressed: () => backs++),
                  headingAction: TextButton(
                    key: const Key('resource-heading-action'),
                    onPressed: () => headingActions++,
                    child: const Text('Update'),
                  ),
                ),
                body: ListView(
                  key: const Key('resource-body'),
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      key: const Key('resource-source'),
                      controller: controller,
                      decoration: const InputDecoration(labelText: 'Source'),
                    ),
                    const SizedBox(height: 160),
                    TextButton(
                      key: const Key('resource-body-action'),
                      onPressed: () => bodyActions++,
                      child: const Text('Details'),
                    ),
                  ],
                ),
                bottomNavigationBar: PageActionBar(
                  children: [
                    FilledButton(
                      key: const Key('resource-save'),
                      onPressed: () => saves++,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final heading = find.byKey(const ValueKey('page-heading'));
        final title = find.descendant(
          of: heading,
          matching: find.text(fileName),
        );
        expect(title, findsOneWidget);
        expect(tester.widget<Text>(title).maxLines, isNull);
        expect(
          tester.widget<Text>(title).overflow,
          isNot(TextOverflow.ellipsis),
        );
        final headingScrollable = find.descendant(
          of: heading,
          matching: find.byType(Scrollable),
        );
        expect(
          tester
              .state<ScrollableState>(headingScrollable)
              .position
              .maxScrollExtent,
          greaterThan(0),
        );
        final body = find.byKey(const Key('resource-body'));
        expect(tester.getSize(body).height, greaterThanOrEqualTo(80));
        final footer = tester.getRect(find.byType(PageActionBar));
        expect(footer.top, greaterThanOrEqualTo(tester.getRect(body).bottom));
        expect(footer.bottom, lessThanOrEqualTo(height));

        await tester.scrollUntilVisible(
          find.byKey(const Key('resource-heading-action')),
          120,
          scrollable: headingScrollable,
          maxScrolls: 60,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('resource-heading-action')));
        await tester.pumpAndSettle();
        expect(headingActions, 1);

        final source = find.byKey(const Key('resource-source'));
        await tester.ensureVisible(source);
        await tester.pumpAndSettle();
        await tester.enterText(source, 'https://example.test/resource.dat');
        await tester.pumpAndSettle();
        final bodyScrollable = find.descendant(
          of: body,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('resource-body-action')),
          100,
          scrollable: bodyScrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('resource-body-action')));
        await tester.tap(find.byKey(const Key('resource-save')));
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(bodyActions, 1);
        expect(saves, 1);
        expect(backs, 1);
        expect(controller.text, 'https://example.test/resource.dat');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('imperative routes under GoRouter keep page bars responsive', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var useUnownedPage = false;
    final router = GoRouter(
      initialLocation: '/connect',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/connect',
                  builder: (context, _) => Scaffold(
                    appBar: const PageAppBar(title: Text('Connection root')),
                    body: TextButton(
                      onPressed: () {
                        final route = useUnownedPage
                            ? const MaterialPage<void>(
                                key: ValueKey('unowned-preview'),
                                child: Scaffold(
                                  appBar: PageAppBar(title: Text('Preview')),
                                ),
                              ).createRoute(context)
                            : MaterialPageRoute<void>(
                                builder: (_) => const Scaffold(
                                  appBar: PageAppBar(title: Text('Preview')),
                                ),
                              );
                        unawaited(Navigator.of(context).push<void>(route));
                      },
                      child: const Text('Open preview'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerApp(router));
    await tester.pumpAndSettle();
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(PageAppBar))).width,
      390,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-action')),
      findsOneWidget,
    );
    // Neither an ordinary MaterialPageRoute nor a Page-backed route created
    // outside GoRouter owns a GoRouterState association.
    for (final pageBacked in [false, true]) {
      useUnownedPage = pageBacked;
      await tester.tap(find.text('Open preview'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Preview'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-settings-action')),
        findsNothing,
      );
      expect(router.routerDelegate.currentConfiguration.uri.path, '/connect');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile-settings-action')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('only five actual phone roots offer scoped Settings navigation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/connect',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            for (final primary in AppPrimaryDestination.values)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: primary.rootPath,
                    builder: (_, _) =>
                        Scaffold(appBar: PageAppBar(title: Text(primary.name))),
                    routes: [
                      for (final child in ['settings', 'detail'])
                        GoRoute(
                          path: child,
                          builder: (_, _) =>
                              Scaffold(appBar: PageAppBar(title: Text(child))),
                        ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerApp(router));
    await tester.pumpAndSettle();
    final gear = find.byKey(const ValueKey('mobile-settings-action'));
    for (final primary in AppPrimaryDestination.values) {
      router.go(primary.rootPath);
      await tester.pumpAndSettle();
      if (primary == AppPrimaryDestination.settings) {
        expect(gear, findsNothing);
      } else {
        expect(gear, findsOneWidget);
        await tester.tap(gear);
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.last.matchedLocation,
          '${primary.rootPath}/settings',
        );
        expect(gear, findsNothing);
        router.pop();
        await tester.pumpAndSettle();
        expect(gear, findsOneWidget);
      }
      unawaited(router.push<void>('${primary.rootPath}/detail'));
      await tester.pumpAndSettle();
      expect(gear, findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('page bar preserves themed sizing and tabs', (tester) async {
    final theme = AppTheme.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          appBarTheme: theme.appBarTheme.copyWith(toolbarHeight: 64),
        ),
        home: const DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: PageAppBar(
              title: Text('Advanced'),
              bottom: TabBar(
                tabs: [
                  Tab(text: 'Tunnel'),
                  Tab(text: 'Xray'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(
      tester.getSize(find.byType(AppBar)).height,
      64 + tabs.preferredSize.height,
    );
    expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor, isNull);
  });

  testWidgets(
    'page bar keeps explicit callbacks and automatic back navigation',
    (tester) async {
      var leadingCalls = 0;
      var actionCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              appBar: PageAppBar(
                title: const Text('Root'),
                leading: BackButton(onPressed: () => leadingCalls++),
                actions: [
                  IconButton(
                    key: const Key('action'),
                    onPressed: () => actionCalls++,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      appBar: PageAppBar(title: Text('Detail')),
                    ),
                  ),
                ),
                child: const Text('Open detail'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(BackButton));
      await tester.tap(find.byKey(const Key('action')));
      expect(leadingCalls, 1);
      expect(actionCalls, 1);
      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Detail'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Root'), findsOneWidget);
      expect(leadingCalls, 1);
    },
  );

  testWidgets('macOS toolbar hitboxes follow push and pop transitions', (
    tester,
  ) async {
    final rectangles = <String, Rect>{};
    const channel = MethodChannel('macos_window_utils/window_manipulator');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      final args = call.arguments as Map<Object?, Object?>?;
      if (call.method == 'updateToolbarPassthroughView') {
        rectangles[args!['id'] as String] = Rect.fromLTWH(
          (args['x'] as num).toDouble(),
          (args['y'] as num).toDouble(),
          (args['width'] as num).toDouble(),
          (args['height'] as num).toDouble(),
        );
      } else if (call.method == 'removeToolbarPassthroughView') {
        rectangles.remove(args!['id']);
      }
      return null;
    });
    await WindowManipulator.initialize(enableWindowDelegate: false);
    final navigator = GlobalKey<NavigatorState>();
    const rootAction = Key('root-action');
    const detailAction = Key('detail-action');
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        builder: (context, child) => MacOSWindowInsets(
          titlebarHeight: 28,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(padding: EdgeInsets.zero),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: PageAppBar.forPage(
              context,
              title: const Text('Root'),
              actions: [
                IconButton(
                  key: rootAction,
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: PageAppBar.forPage(
            context,
            title: const Text('Detail'),
            actions: [
              IconButton(
                key: detailAction,
                onPressed: () {},
                icon: const Icon(Icons.save),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      rectangles.values,
      contains(tester.getRect(find.byType(BackButton))),
    );
    expect(
      rectangles.values,
      contains(tester.getRect(find.byKey(detailAction))),
    );
    expect(rectangles, hasLength(2));

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(rectangles.values, contains(tester.getRect(find.byKey(rootAction))));
    expect(rectangles, hasLength(1));

    showDialog<void>(
      context: tester.element(find.byKey(rootAction)),
      builder: (_) => const AlertDialog(title: Text('Dialog')),
    );
    await tester.pumpAndSettle();
    expect(rectangles, isEmpty);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(rectangles.values, contains(tester.getRect(find.byKey(rootAction))));
    expect(rectangles, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(rectangles, isEmpty);
  });
}

Widget _routerApp(GoRouter router) => MaterialApp.router(
  routerConfig: router,
  theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
  locale: const Locale('en'),
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
);
