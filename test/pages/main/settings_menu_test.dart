import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/adaptive_shell.dart';
import 'package:onexray/pages/main/dialog_page.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/menu/settings/service.dart';

void main() {
  testWidgets('Settings preserves its subpage and drafts in other branches', (
    tester,
  ) async {
    final harness = _MenuHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('connect-draft')),
      'Unsaved connection draft',
    );
    await harness.menu.receive();
    await tester.pumpAndSettle();
    expect(harness.location, '/settings');
    unawaited(harness.router.push<void>('/settings/details'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-details-draft')),
      'Unsaved Settings draft',
    );
    for (var i = 0; i < 3; i++) {
      await harness.menu.receive();
      await tester.pumpAndSettle();
      expect(harness.location, '/settings/details');
      expect(find.text('Unsaved Settings draft'), findsOneWidget);
    }
    harness.router.pop();
    await tester.pumpAndSettle();
    expect(harness.location, '/settings');
    expect(harness.router.canPop(), isFalse);
    await tester.tap(find.byKey(const ValueKey('primary-navigation-connect')));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved connection draft'), findsOneWidget);
    await harness.menu.receive();
    await tester.pumpAndSettle();
    expect(harness.location, '/settings');
    expect(harness.shown, 5);
    expect(tester.takeException(), isNull);
  });

  for (final root in [false, true]) {
    for (final requestFocus in [false, true]) {
      testWidgets(
        'unfocused confirmation keeps ${root ? "root" : "branch"} modal ($requestFocus)',
        (tester) async {
          final harness = _MenuHarness();
          addTearDown(harness.dispose);
          await tester.pumpWidget(harness.app());
          await tester.pumpAndSettle();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          final closed = showDialog<void>(
            context: tester.element(find.text('connect-content')),
            useRootNavigator: root,
            requestFocus: requestFocus,
            builder: (_) =>
                const AlertDialog(title: Text('No-input confirmation')),
          );
          await tester.pumpAndSettle();
          await harness.menu.receive();
          await tester.pumpAndSettle();
          expect(find.text('No-input confirmation'), findsOneWidget);
          expect(harness.location, '/connect');
          expect(harness.shown, 1);
          Navigator.of(tester.element(find.byType(AlertDialog))).pop();
          await tester.pumpAndSettle();
          await closed;
          expect(harness.location, '/connect');
          await harness.menu.receive();
          await tester.pumpAndSettle();
          expect(harness.location, '/settings');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('a routed editor and nested confirmation are not replaced', (
    tester,
  ) async {
    final harness = _MenuHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    unawaited(harness.router.push<void>('/connect/server-editor'));
    await tester.pumpAndSettle();
    final closed = showDialog<void>(
      context: tester.element(find.text('Editor modal')),
      requestFocus: false,
      useRootNavigator: false,
      builder: (_) => const AlertDialog(title: Text('Discard changes?')),
    );
    await tester.pumpAndSettle();
    await harness.menu.receive();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(harness.location, '/connect/server-editor');
    Navigator.of(
      tester.element(find.widgetWithText(AlertDialog, 'Discard changes?')),
    ).pop();
    await tester.pumpAndSettle();
    await closed;
    await harness.menu.receive();
    await tester.pumpAndSettle();
    expect(find.text('Editor modal'), findsOneWidget);
    expect(harness.location, '/connect/server-editor');
    harness.router.pop();
    await tester.pumpAndSettle();
    expect(harness.location, '/connect');
    await tester.pumpAndSettle();
    expect(harness.location, '/connect');
    await harness.menu.receive();
    await tester.pumpAndSettle();
    expect(harness.location, '/settings');
    expect(tester.takeException(), isNull);
  });

  for (final fail in [false, true]) {
    testWidgets(
      'initialization ${fail ? "failure" : "wait"} does not accept deferred navigation',
      (tester) async {
        final ready = Completer<void>();
        final harness = _MenuHarness(initializeServices: (_) => ready.future);
        addTearDown(harness.dispose);
        await tester.pumpWidget(harness.app());
        await tester.pump();
        await harness.menu.receive();
        expect(harness.shown, 1);
        expect(harness.location, '/connect');
        if (fail) {
          ready.completeError(StateError('Initialization failed'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('service-initialization-retry')),
            findsOneWidget,
          );
          await harness.menu.receive();
          await tester.pumpAndSettle();
          expect(harness.location, '/connect');
        } else {
          ready.complete();
          await tester.pumpAndSettle();
          expect(harness.location, '/connect');
          await harness.menu.receive();
          await tester.pumpAndSettle();
          expect(harness.location, '/settings');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'disposing the shell while restoring the window cancels navigation',
    (tester) async {
      final focused = Completer<void>();
      final harness = _MenuHarness(showMainWindow: () => focused.future);
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      final opening = harness.menu.receive();
      await tester.pumpWidget(const SizedBox.shrink());
      focused.complete();
      await opening;
      await tester.pump();
      expect(harness.location, '/connect');
      expect(tester.takeException(), isNull);
    },
  );
}

class _MenuHarness {
  _MenuHarness({
    Future<void> Function(BuildContext)? initializeServices,
    Future<void> Function()? showMainWindow,
  }) {
    menu = MacOSSettingsMenuService.forTesting(
      commands: commands.stream,
      showMainWindow: () async {
        shown++;
        await showMainWindow?.call();
      },
    )..initialize();
    router = GoRouter(
      initialLocation: '/connect',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AdaptiveMainShell(
            navigationShell: shell,
            settingsMenuService: menu,
            initializeServices: initializeServices ?? (_) async {},
          ),
          branches: [
            for (final primary in AppPrimaryDestination.values)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: primary.rootPath,
                    builder: (_, _) => _DraftView(name: primary.name),
                    routes: [
                      GoRoute(
                        path: 'details',
                        builder: (_, _) =>
                            _DraftView(name: '${primary.name}-details'),
                      ),
                      GoRoute(
                        path: AppPageDestination.serverEditor.segment,
                        pageBuilder: (_, state) => AppDialogPage<void>(
                          key: state.pageKey,
                          builder: (_) =>
                              const AlertDialog(title: Text('Editor modal')),
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
  }

  final commands = StreamController<void>.broadcast(sync: true);
  final eventBus = AppEventBus();
  late final MacOSSettingsMenuService menu;
  late final GoRouter router;
  var shown = 0;

  String get location =>
      router.routerDelegate.currentConfiguration.last.matchedLocation;

  Widget app() => BlocProvider.value(
    value: eventBus,
    child: MaterialApp.router(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      routerConfig: router,
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );

  Future<void> dispose() async {
    await menu.dispose();
    await commands.close();
    router.dispose();
    await eventBus.close();
  }
}

class _DraftView extends StatelessWidget {
  const _DraftView({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text('$name-content'),
        TextField(key: ValueKey('$name-draft')),
      ],
    ),
  );
}
