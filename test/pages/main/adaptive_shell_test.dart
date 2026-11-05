import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/main/adaptive_shell.dart';
import 'package:onexray/pages/main/dialog_page.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/main/url.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

void main() {
  test('primary destinations use product names and URLs', () {
    expect(AppPrimaryDestination.values.map((route) => route.name), [
      'connect',
      'servers',
      'routing',
      'tunnel',
      'xray',
      'settings',
    ]);
    expect(AppPrimaryDestination.values.map((route) => route.rootPath), [
      '/connect',
      '/servers',
      '/routing',
      '/tunnel',
      '/xray',
      '/settings',
    ]);
    expect(
      AppPrimaryDestination.fromPath('/xray/routing-data'),
      AppPrimaryDestination.xray,
    );
  });

  test('all business pages share one registry inside each tab', () {
    final routes = RouterPath.router.configuration.routes;
    expect(routes.whereType<GoRoute>().map((route) => route.path), [
      '/splash',
      '/setup',
      '/setup/privacy',
      '/setup/interface',
      '/setup/region',
      '/privacy',
      '/firstRun',
      '/advanced',
      '/advanced/:page',
    ]);
    final shell = routes.whereType<StatefulShellRoute>().single;
    for (final branch in shell.branches) {
      final root = branch.routes.single as GoRoute;
      final children = root.routes.cast<GoRoute>();
      expect(
        children.map((route) => route.path),
        unorderedEquals(
          AppPageDestination.values
              .where(
                (route) =>
                    (AppPlatform.isAndroid ||
                        route != AppPageDestination.androidAutomation) &&
                    (AppPlatform.isDesktop ||
                        route != AppPageDestination.localApi),
              )
              .map((route) => route.segment),
        ),
      );
      for (final route in children) {
        expect(
          route.parentNavigatorKey,
          null,
          reason: '${root.path}/${route.path} must stay in its source tab',
        );
      }
    }
    expect(
      AppPrimaryDestination.values.map((tab) => tab.page),
      everyElement(isIn(AppPageDestination.values)),
    );
  });

  testWidgets('shared navigation breakpoints preserve the update flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final eventBus = AppEventBus();
    addTearDown(eventBus.close);
    eventBus.updateAppUpdateInfo(
      AppUpdateInfo(
        currentVersion: '26.7.3',
        latestVersion: '26.8.0',
        releaseNotes: 'Release notes',
        releaseUri: Uri.parse('https://example.com/release'),
        updateUri: Uri.parse('https://example.com/update'),
        destination: AppUpdateDestination.githubRelease,
      ),
    );

    final rootKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: AppPrimaryDestination.connect.rootPath,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, navigationShell) => AdaptiveMainShell(
            navigationShell: navigationShell,
            hasActiveModal: (_) => false,
            initializeServices: (_) async {},
          ),
          branches: [
            for (final primary in AppPrimaryDestination.values)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: primary.rootPath,
                    builder: (_, _) =>
                        Center(child: Text('${primary.name}-content')),
                    routes: [
                      GoRoute(
                        path: AppPageDestination.appUpdate.segment,
                        pageBuilder: (_, state) => AppDialogPage<void>(
                          key: state.pageKey,
                          builder: (_) =>
                              const Center(child: Text('update-dialog')),
                        ),
                      ),
                      GoRoute(
                        path: 'details',
                        builder: (_, _) => const Center(child: Text('details')),
                      ),
                      GoRoute(
                        path: 'popup',
                        pageBuilder: (context, state) => AppDialogPage<void>(
                          key: state.pageKey,
                          useSafeArea: false,
                          builder: (context) => AppDialogFrame(
                            child: AppDialog(
                              title: 'tab-popup',
                              body: const SizedBox(height: 100),
                              actions: [
                                TextButton(
                                  onPressed: () => showAppDialog<void>(
                                    context,
                                    (context) => AppDialog(
                                      title: 'nested-popup',
                                      body: const SizedBox(height: 100),
                                      actions: [
                                        TextButton(
                                          onPressed: () => context.pop(),
                                          child: const Text('back-popup'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  child: const Text('next-popup'),
                                ),
                                FilledButton(
                                  onPressed: () => context.pop(),
                                  child: const Text('close-popup'),
                                ),
                              ],
                            ),
                          ),
                        ),
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

    await tester.pumpWidget(
      BlocProvider.value(
        value: eventBus,
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final desktopNavigation = find.byKey(
      const ValueKey('primary-desktop-navigation'),
    );
    expect(find.text('connect-content'), findsOneWidget);
    expect(find.text('OneXray'), findsOneWidget);
    final sidebarLocalizations = AppLocalizations.of(
      tester.element(desktopNavigation),
    )!;
    expect(find.text(sidebarLocalizations.navigationTagline), findsOneWidget);
    expect(find.text(sidebarLocalizations.navigationWorkspace), findsOneWidget);
    expect(
      find.text(sidebarLocalizations.navigationSystemAndCore),
      findsOneWidget,
    );
    final palette = ColorManager.palette(tester.element(desktopNavigation));
    expect(tester.widget<Container>(desktopNavigation).color, palette.sidebar);
    expect(
      tester.getSize(desktopNavigation).width,
      AppLayout.desktopSidebarWidth,
    );
    final content = find.byKey(const ValueKey('primary-content'));
    expect(tester.widget<ColoredBox>(content).color, palette.background);
    expect(
      tester.getRect(content),
      Rect.fromLTRB(AppLayout.desktopSidebarWidth, 0, 1200, 800),
    );
    expect(
      find.ancestor(of: content, matching: find.byType(ClipRRect)),
      findsNothing,
    );
    final desktopConnect = find.byKey(
      const ValueKey('primary-navigation-connect'),
    );
    expect(
      tester.widget<Semantics>(desktopConnect).properties.selected,
      isTrue,
    );
    expect(
      tester.getSize(desktopConnect).height,
      AppLayout.touchExtent(
        AppSpacing.sidebarRowHeight,
        platform: Theme.of(tester.element(desktopConnect)).platform,
      ),
    );
    expect(
      tester.getSize(desktopConnect).width,
      AppLayout.desktopSidebarWidth - AppSpacing.sidebarHorizontal * 2,
    );
    final selectedDesktopSurface = tester.widget<Material>(
      find
          .descendant(of: desktopConnect, matching: find.byType(Material))
          .first,
    );
    expect(selectedDesktopSurface.color, palette.card);
    expect(
      selectedDesktopSurface.borderRadius,
      BorderRadius.circular(AppRadii.control),
    );
    expect(selectedDesktopSurface.shape, isNull);
    expect(
      tester
          .widget<Icon>(
            find.descendant(of: desktopConnect, matching: find.byType(Icon)),
          )
          .size,
      18,
    );
    router.go('/servers/details');
    await tester.pumpAndSettle();
    await tester.tap(desktopConnect);
    await tester.pumpAndSettle();
    unawaited(router.push<void>('/connect/details'));
    await tester.pumpAndSettle();
    for (final primary in [
      AppPrimaryDestination.servers,
      AppPrimaryDestination.connect,
    ]) {
      await tester.tap(
        find.byKey(ValueKey('primary-navigation-${primary.name}')),
      );
      await tester.pumpAndSettle();
      expect(
        GoRouterState.of(tester.element(find.text('details'))).uri.path,
        '${primary.rootPath}/details',
      );
      expect(router.canPop(), true);
    }
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('connect-content'), findsOneWidget);
    for (final width in [900.0, 721.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(desktopNavigation).width,
        AppLayout.compactSidebarWidth,
      );
      expect(find.text('OneXray'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(const Size(720, 800));
    await tester.pumpAndSettle();
    expect(desktopNavigation, findsNothing);
    final navigation = find.byKey(const ValueKey('primary-mobile-navigation'));
    final connectDestination = find.byKey(
      const ValueKey('primary-navigation-connect'),
    );
    expect(navigation, findsOneWidget);
    final navigationCard = tester.widget<Container>(navigation);
    expect(navigationCard.margin, const EdgeInsets.fromLTRB(12, 0, 12, 10));
    expect(navigationCard.padding, const EdgeInsets.all(6));
    final decoration = navigationCard.decoration! as BoxDecoration;
    expect(decoration.color, palette.card);
    expect(decoration.borderRadius, BorderRadius.circular(22));
    expect(
      find.descendant(of: navigation, matching: find.byType(InkWell)),
      findsNWidgets(5),
    );
    expect(
      find.byKey(const ValueKey('primary-navigation-settings')),
      findsNothing,
    );
    expect(
      tester.widget<Semantics>(connectDestination).properties.label,
      'Connect',
    );
    expect(
      tester.widget<Semantics>(connectDestination).properties.selected,
      isTrue,
    );
    expect(tester.getSize(connectDestination).height, 56);
    final selectedMobileSurface = tester.widget<Material>(
      find
          .descendant(of: connectDestination, matching: find.byType(Material))
          .first,
    );
    expect(selectedMobileSurface.color, palette.primarySolid);
    final mobileLabel = tester.widget<Text>(
      find.descendant(of: connectDestination, matching: find.byType(Text)),
    );
    expect(mobileLabel.style!.fontSize, 11);
    expect(mobileLabel.style!.color, palette.primaryForeground);
    expect(
      mobileLabel.style!.fontWeight,
      AppTypography.selectedMobileNavigationLabel.fontWeight,
    );
    expect(find.byType(Badge), findsNothing);
    router.go('/settings');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(navigation, findsNothing);
    for (final path in ['/settings', '/settings/details']) {
      router.go(path);
      await tester.pumpAndSettle();
      final root = path == '/settings';
      final content = root ? 'settings-content' : 'details';
      expect(navigation, findsNothing);
      expect(find.text(content), findsOneWidget);

      final branchNavigator = Navigator.of(tester.element(find.text(content)));
      final closed = router.push<void>('/settings/popup');
      await tester.pumpAndSettle();
      expect(find.text('tab-popup'), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(AppDialog))),
        same(branchNavigator),
      );
      expect(rootKey.currentState!.canPop(), false);
      expect(navigation, findsNothing);
      expect(find.text(content), findsOneWidget);
      await tester.tap(find.text('next-popup'));
      await tester.pumpAndSettle();
      expect(find.text('tab-popup'), findsNothing);
      expect(find.text('nested-popup'), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(AppDialog))),
        same(branchNavigator),
      );
      expect(rootKey.currentState!.canPop(), false);
      await tester.tap(find.text('back-popup'));
      await tester.pumpAndSettle();
      expect(find.text('tab-popup'), findsOneWidget);
      await tester.tap(find.text('close-popup'));
      await tester.pumpAndSettle();
      await closed;

      expect(find.byType(AppDialog), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, path);
      expect(navigation, findsNothing);
      expect(find.text(content), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    // A declarative popup location has the root, not the previous detail, below it.
    router.go('/settings/popup');
    await tester.pumpAndSettle();
    expect(find.text('tab-popup'), findsOneWidget);
    expect(find.text('settings-content'), findsOneWidget);
    expect(navigation, findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(find.text('settings-content'), findsOneWidget);
    expect(navigation, findsNothing);
    expect(tester.takeException(), isNull);

    router.go('/settings/details');
    await tester.pumpAndSettle();
    expect(navigation, findsNothing);
    expect(find.text('details'), findsOneWidget);
    router.go('/connect');
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(901, 800));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(desktopNavigation).width,
      AppLayout.desktopSidebarWidth,
    );
    await tester.tap(find.text('Update available'));
    await tester.pumpAndSettle();

    expect(find.text('update-dialog'), findsOneWidget);
    expect(rootKey.currentState!.canPop(), isFalse);
    expect(
      GoRouterState.of(tester.element(find.text('update-dialog'))).uri.path,
      '/connect/app-update',
    );
    expect(router.routeInformationProvider.value.uri.path, '/connect');
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('connect-content'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/connect');
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final (scale, locale, brightness) in const [
      (1.0, Locale('en'), Brightness.light),
      (2.0, Locale('ru'), Brightness.light),
      (2.0, Locale('fa'), Brightness.dark),
    ]) {
      testWidgets(
        'inset mobile navigation stays reachable on $platform in $locale at $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(390, 360));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final eventBus = AppEventBus();
          addTearDown(eventBus.close);
          final router = _navigationFixture();
          addTearDown(router.dispose);
          const padding = EdgeInsets.only(top: 24, bottom: 21);
          await tester.pumpWidget(
            BlocProvider.value(
              value: eventBus,
              child: MaterialApp.router(
                theme: AppTheme.material(brightness, mobile: true),
                locale: locale,
                routerConfig: router,
                localizationsDelegates: AppLocalePolicy.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    padding: padding,
                    viewPadding: padding,
                  ),
                  child: child!,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final navigation = find.byKey(
            const ValueKey('primary-mobile-navigation'),
          );
          final palette = ColorManager.palette(tester.element(navigation));
          final rect = tester.getRect(navigation);
          expect(rect.bottom, lessThanOrEqualTo(360 - padding.bottom));
          expect(rect.top, greaterThanOrEqualTo(padding.top));
          expect(
            Directionality.of(tester.element(navigation)),
            locale.languageCode == 'fa' ? TextDirection.rtl : TextDirection.ltr,
          );
          final destinations = AppPrimaryDestination.values.where(
            (primary) => primary != AppPrimaryDestination.settings,
          );
          for (final primary in destinations) {
            final destination = find.byKey(
              ValueKey('primary-navigation-${primary.name}'),
            );
            final size = tester.getSize(destination);
            expect(
              size.width,
              greaterThanOrEqualTo(
                AppLayout.touchExtent(0, platform: platform),
              ),
            );
            expect(size.height, greaterThanOrEqualTo(56));
            expect(
              size.height,
              closeTo(
                tester
                    .getSize(
                      find.byKey(const ValueKey('primary-navigation-connect')),
                    )
                    .height,
                .01,
              ),
            );
            final labelRect = tester.getRect(
              find.descendant(of: destination, matching: find.byType(Text)),
            );
            final iconRect = tester.getRect(
              find.descendant(of: destination, matching: find.byType(Icon)),
            );
            final destinationRect = tester.getRect(destination);
            expect(
              size.height,
              greaterThanOrEqualTo(
                iconRect.height + 5 + labelRect.height + 12 - .01,
              ),
            );
            expect(labelRect.left, greaterThanOrEqualTo(destinationRect.left));
            expect(labelRect.right, lessThanOrEqualTo(destinationRect.right));
            expect(
              labelRect.bottom,
              lessThanOrEqualTo(destinationRect.bottom - 6 + .01),
            );
            final semantics = tester.getSemantics(destination);
            expect(
              semantics.getSemanticsData().hasAction(SemanticsAction.tap),
              isTrue,
            );
            semantics.owner!.performAction(semantics.id, SemanticsAction.tap);
            await tester.pumpAndSettle();
            expect(
              router.routeInformationProvider.value.uri.path,
              primary.rootPath,
            );
            expect(find.text('${primary.name}-content'), findsOneWidget);
            expect(
              tester.widget<Semantics>(destination).properties.selected,
              isTrue,
            );
            final surface = tester.widget<Material>(
              find
                  .descendant(of: destination, matching: find.byType(Material))
                  .first,
            );
            expect(surface.color, palette.primarySolid);
            await tester.tap(destination);
            await tester.pumpAndSettle();
            expect(
              router.routeInformationProvider.value.uri.path,
              primary.rootPath,
            );
            expect(tester.takeException(), isNull);
          }
          final destinationHeight = tester
              .getSize(find.byKey(const ValueKey('primary-navigation-connect')))
              .height;
          expect(
            destinationHeight,
            scale > 1 ? greaterThan(56) : greaterThanOrEqualTo(56),
          );
          if (locale.languageCode == 'fa') {
            expect(
              tester
                  .getCenter(
                    find.byKey(const ValueKey('primary-navigation-connect')),
                  )
                  .dx,
              greaterThan(
                tester
                    .getCenter(
                      find.byKey(const ValueKey('primary-navigation-xray')),
                    )
                    .dx,
              ),
            );
          }
          expect(tester.takeException(), isNull);
        },
        semanticsEnabled: true,
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }

  for (final (scale, locale, landscapePadding) in const [
    (1.0, Locale('en'), EdgeInsets.only(left: 59, bottom: 21)),
    (2.0, Locale('ru'), EdgeInsets.only(left: 59, bottom: 21)),
    (2.0, Locale('fa'), EdgeInsets.only(right: 59, bottom: 21)),
  ]) {
    testWidgets(
      'landscape navigation remains reachable in $locale at $scale text scale',
      (tester) async {
        const landscape = Size(952, 426.7);
        await tester.binding.setSurfaceSize(landscape);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var padding = landscapePadding;
        final eventBus = AppEventBus();
        addTearDown(eventBus.close);
        eventBus.updateAppUpdateInfo(
          AppUpdateInfo(
            currentVersion: '26.10.4',
            latestVersion: '26.10.5',
            releaseNotes: 'Release notes',
            releaseUri: Uri.parse('https://example.com/release'),
            updateUri: Uri.parse('https://example.com/update'),
            destination: AppUpdateDestination.githubRelease,
          ),
        );
        final router = GoRouter(
          initialLocation: '/connect',
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (_, _, shell) => AdaptiveMainShell(
                navigationShell: shell,
                hasActiveModal: (_) => false,
                initializeServices: (_) async {},
              ),
              branches: [
                for (final primary in AppPrimaryDestination.values)
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: primary.rootPath,
                        builder: (_, _) =>
                            Center(child: Text('${primary.name}-content')),
                        routes: [
                          GoRoute(
                            path: 'details',
                            builder: (_, _) =>
                                Center(child: Text('${primary.name}-details')),
                          ),
                          GoRoute(
                            path: AppPageDestination.appUpdate.segment,
                            pageBuilder: (_, state) => AppDialogPage<void>(
                              key: state.pageKey,
                              builder: (_) =>
                                  const Center(child: Text('update-dialog')),
                            ),
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
        await tester.pumpWidget(
          BlocProvider.value(
            value: eventBus,
            child: MaterialApp.router(
              theme: AppTheme.material(Brightness.light, mobile: true),
              locale: locale,
              routerConfig: router,
              localizationsDelegates: AppLocalePolicy.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  padding: padding,
                  viewPadding: padding,
                ),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final sidebar = find.byKey(
          const ValueKey('primary-desktop-navigation'),
        );
        final sidebarRect = tester.getRect(sidebar);
        expect(sidebarRect.width, AppLayout.desktopSidebarWidth);
        expect(sidebarRect.left, greaterThanOrEqualTo(padding.left));
        expect(
          sidebarRect.right,
          lessThanOrEqualTo(landscape.width - padding.right),
        );
        expect(
          tester.getSize(find.text('OneXray')).height,
          lessThan(50 * scale),
        );

        for (final primary in AppPrimaryDestination.values) {
          final destination = find.byKey(
            ValueKey('primary-navigation-${primary.name}'),
          );
          await tester.ensureVisible(destination);
          await tester.pumpAndSettle();
          final rect = tester.getRect(destination);
          expect(rect.top, greaterThanOrEqualTo(padding.top));
          expect(
            rect.bottom,
            lessThanOrEqualTo(landscape.height - padding.bottom),
          );
          await tester.tap(destination);
          await tester.pumpAndSettle();
          expect(find.text('${primary.name}-content'), findsOneWidget);
          expect(
            tester.widget<Semantics>(destination).properties.selected,
            isTrue,
          );
          expect(tester.takeException(), isNull);
        }

        final l = AppLocalizations.of(tester.element(sidebar))!;
        final update = find.text(l.appUpdateAvailable);
        await tester.ensureVisible(update);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(update).bottom,
          lessThanOrEqualTo(landscape.height - padding.bottom),
        );
        await tester.tap(update);
        await tester.pumpAndSettle();
        expect(find.text('update-dialog'), findsOneWidget);
        router.pop();
        await tester.pumpAndSettle();

        router.go('/connect/details');
        await tester.pumpAndSettle();
        final settings = find.byKey(
          const ValueKey('primary-navigation-settings'),
        );
        await tester.ensureVisible(settings);
        await tester.pumpAndSettle();
        await tester.tap(settings);
        await tester.pumpAndSettle();
        unawaited(router.push<void>('/settings/details'));
        await tester.pumpAndSettle();

        padding = const EdgeInsets.only(top: 59, bottom: 34);
        await tester.binding.setSurfaceSize(const Size(426.7, 952));
        await tester.pumpAndSettle();
        expect(sidebar, findsNothing);
        expect(
          find.byKey(const ValueKey('primary-mobile-navigation')),
          findsNothing,
        );
        expect(find.text('settings-details'), findsOneWidget);
        expect(
          GoRouterState.of(tester.element(find.text('settings-details')))
              .uri
              .path,
          '/settings/details',
        );

        padding = landscapePadding;
        await tester.binding.setSurfaceSize(landscape);
        await tester.pumpAndSettle();
        expect(sidebar, findsOneWidget);
        expect(find.text('settings-details'), findsOneWidget);
        final connect = find.byKey(
          const ValueKey('primary-navigation-connect'),
        );
        await tester.ensureVisible(connect);
        await tester.pumpAndSettle();
        await tester.tap(connect);
        await tester.pumpAndSettle();
        expect(find.text('connect-details'), findsOneWidget);
        expect(
          GoRouterState.of(tester.element(find.text('connect-details')))
              .uri
              .path,
          '/connect/details',
        );
        expect(router.canPop(), isTrue);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  for (final width in [390.0, 1200.0]) {
    testWidgets('root pages can be pushed within any tab ($width)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final eventBus = AppEventBus();
      addTearDown(eventBus.close);
      final rootKey = GlobalKey<NavigatorState>();
      late StatefulNavigationShell shell;
      Widget content(AppPageDestination page) => Scaffold(
        appBar: AppBar(title: Text('page-${page.segment}')),
        body: const SizedBox(),
      );
      final router = GoRouter(
        navigatorKey: rootKey,
        initialLocation: '/connect',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, navigationShell) {
              shell = navigationShell;
              return AdaptiveMainShell(
                navigationShell: navigationShell,
                hasActiveModal: (_) => false,
                initializeServices: (_) async {},
              );
            },
            branches: [
              for (final tab in AppPrimaryDestination.values)
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: tab.rootPath,
                      builder: (_, _) => content(tab.page),
                      routes: [
                        for (final page in AppPageDestination.values)
                          GoRoute(
                            path: page.segment,
                            builder: (_, _) => content(page),
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
      await tester.pumpWidget(
        BlocProvider.value(
          value: eventBus,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final tab in AppPrimaryDestination.values) {
        router.go(tab.rootPath);
        await tester.pumpAndSettle();
        final navigator = Navigator.of(tester.element(find.byType(AppBar)));
        final stack = [tab.page];
        for (final page in [
          ...AppPrimaryDestination.values.map((tab) => tab.page),
          AppPageDestination.smartRouting,
          AppPageDestination.routingData,
        ]) {
          final context = tester.element(find.byType(AppBar));
          unawaited(context.pushScoped(page));
          stack.add(page);
          await tester.pumpAndSettle();
          final next = tester.element(find.byType(AppBar));
          expect(
            GoRouterState.of(next).uri.path,
            '${tab.rootPath}/${page.segment}',
          );
          expect(next.currentPrimaryDestination, tab);
          expect(Navigator.of(next), same(navigator));
          expect(shell.currentIndex, tab.index);
          expect(rootKey.currentState!.canPop(), isFalse);
          expect(find.byType(BackButton), findsOneWidget);
          if (width < AppLayout.mobileBreakpoint) {
            expect(
              find.byKey(const ValueKey('primary-mobile-navigation')),
              findsNothing,
            );
          }
        }
        while (stack.length > 1) {
          await tester.tap(find.byType(BackButton));
          stack.removeLast();
          await tester.pumpAndSettle();
          expect(find.text('page-${stack.last.segment}'), findsOneWidget);
          expect(shell.currentIndex, tab.index);
        }
        expect(router.canPop(), isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('business pages wait for services and allow a local retry', (
    tester,
  ) async {
    var attempts = 0;
    final ready = Completer<void>();
    final eventBus = AppEventBus();
    addTearDown(eventBus.close);
    final router = GoRouter(
      initialLocation: AppPrimaryDestination.connect.rootPath,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, navigationShell) => AdaptiveMainShell(
            navigationShell: navigationShell,
            hasActiveModal: (_) => false,
            initializeServices: (_) {
              attempts++;
              if (attempts == 1) {
                return Future<void>.error(StateError('fixture'));
              }
              return ready.future;
            },
          ),
          branches: [
            for (final primary in AppPrimaryDestination.values)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: primary.rootPath,
                    builder: (_, _) => Text('${primary.name}-content'),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      BlocProvider.value(
        value: eventBus,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('connect-content'), findsNothing);
    expect(
      find.byKey(const ValueKey('primary-mobile-navigation')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('primary-desktop-navigation')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('service-initialization-retry')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('service-initialization-retry')),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('connect-content'), findsNothing);
    expect(
      find.byKey(const ValueKey('primary-mobile-navigation')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('primary-desktop-navigation')),
      findsNothing,
    );

    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('connect-content'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('primary-desktop-navigation')),
      findsOneWidget,
    );
    expect(attempts, 2);
  });

  testWidgets(
    'iOS edge swipe pops the detail without losing its primary branch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final eventBus = AppEventBus();
      addTearDown(eventBus.close);
      final router = GoRouter(
        initialLocation: AppPrimaryDestination.connect.rootPath,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => AdaptiveMainShell(
              navigationShell: shell,
              hasActiveModal: (_) => false,
              initializeServices: (_) async {},
            ),
            branches: [
              for (final primary in AppPrimaryDestination.values)
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: primary.rootPath,
                      builder: (context, _) => Scaffold(
                        body: Center(
                          child: TextButton(
                            onPressed: () =>
                                context.pushScoped(AppPageDestination.language),
                            child: Text('open-${primary.name}'),
                          ),
                        ),
                      ),
                      routes: [
                        GoRoute(
                          path: AppPageDestination.language.segment,
                          builder: (_, _) => Scaffold(
                            appBar: AppBar(
                              title: Text('detail-${primary.name}'),
                            ),
                          ),
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
      await tester.pumpWidget(
        BlocProvider.value(
          value: eventBus,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.material(Brightness.light, mobile: true),
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final primary in AppPrimaryDestination.values) {
        if (primary == AppPrimaryDestination.settings) {
          router.go(primary.rootPath);
        } else {
          await tester.tap(
            find.byKey(ValueKey('primary-navigation-${primary.name}')),
          );
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('open-${primary.name}'));
        await tester.pumpAndSettle();
        final route = ModalRoute.of(
          tester.element(find.text('detail-${primary.name}')),
        )!;
        expect(route.settings, isA<MaterialPage<void>>());
        expect(route.popGestureEnabled, isTrue);

        await tester.dragFrom(const Offset(1, 400), const Offset(330, 0));
        await tester.pumpAndSettle();

        expect(find.text('detail-${primary.name}'), findsNothing);
        expect(find.text('open-${primary.name}'), findsOneWidget);
        expect(
          router.routeInformationProvider.value.uri.path,
          primary.rootPath,
        );
        if (primary == AppPrimaryDestination.settings) {
          expect(
            find.byKey(const ValueKey('primary-mobile-navigation')),
            findsNothing,
          );
        } else {
          expect(
            tester
                .widget<Semantics>(
                  find.byKey(ValueKey('primary-navigation-${primary.name}')),
                )
                .properties
                .selected,
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

GoRouter _navigationFixture() => GoRouter(
  initialLocation: AppPrimaryDestination.connect.rootPath,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AdaptiveMainShell(
        navigationShell: shell,
        hasActiveModal: (_) => false,
        initializeServices: (_) async {},
      ),
      branches: [
        for (final primary in AppPrimaryDestination.values)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: primary.rootPath,
                builder: (_, _) =>
                    Center(child: Text('${primary.name}-content')),
              ),
            ],
          ),
      ],
    ),
  ],
);
