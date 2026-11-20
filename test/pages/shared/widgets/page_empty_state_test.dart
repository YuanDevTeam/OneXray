import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/shared/widgets/page_empty_state.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/backup/service.dart';
import 'package:onexray/service/settings/language/locale.dart';

void main() {
  for (final (tab, width, locale) in const [
    (AppPrimaryDestination.connect, 320.0, Locale('en')),
    (AppPrimaryDestination.servers, 390.0, Locale('zh')),
    (
      AppPrimaryDestination.connect,
      390.0,
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    ),
    (AppPrimaryDestination.servers, 320.0, Locale('ru')),
    (AppPrimaryDestination.connect, 320.0, Locale('fa')),
    (AppPrimaryDestination.servers, 1160.0, Locale('en')),
  ]) {
    testWidgets(
      'empty ${tab.name} opens backup in its own tab ($locale / $width)',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = GoRouter(
          initialLocation: tab.rootPath,
          routes: [
            GoRoute(
              path: tab.rootPath,
              builder: (_, _) =>
                  Scaffold(body: PageEmptyState(onAddServers: () {})),
              routes: [
                GoRoute(
                  path: AppPageDestination.backup.segment,
                  builder: (context, _) {
                    expect(context.currentPrimaryDestination, tab);
                    return Scaffold(
                      appBar: AppBar(title: const Text('Backup destination')),
                    );
                  },
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(PageEmptyState)),
        )!;
        final restore = find.widgetWithText(
          OutlinedButton,
          l.backupRestoreFrom,
        );
        if (!BackupService.supported) {
          expect(restore, findsNothing);
          return;
        }
        await tester.ensureVisible(restore);
        await tester.tap(restore);
        await tester.pumpAndSettle();
        final destination = find.text('Backup destination');
        expect(destination, findsOneWidget);
        expect(
          GoRouterState.of(tester.element(destination)).uri.path,
          '${tab.rootPath}/backup',
        );
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(PageEmptyState), findsOneWidget);
        expect(
          GoRouterState.of(tester.element(find.byType(PageEmptyState)))
              .uri
              .path,
          tab.rootPath,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
