import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/details.dart';
import 'package:onexray/pages/servers/import/controller.dart';
import 'package:onexray/pages/servers/import/page.dart';
import 'package:onexray/pages/shared/widgets/outbound_json_editor.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;

import 'fixtures/server_test_router.dart';

void main() {
  late ServerImportController importer;
  late GoRouter router;
  late List<int?> rawEditorIds;
  ServerImportResult? result;
  bool returned = false;

  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
    importer = ServerImportController(loadSubscription: (_) async => null);
    rawEditorIds = [];
    result = null;
    returned = false;
  });

  tearDown(() async {
    router.dispose();
    await importer.close();
  });

  Future<void> open(WidgetTester tester, {WidgetBuilder? home}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    router = serverTestRouter(
      home:
          home ??
          (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await context.pushScoped<ServerImportResult>(
                  AppPageDestination.serversImport,
                );
                returned = true;
              },
              child: const Text('Open add servers'),
            ),
          ),
      extraRoutes: [
        GoRoute(
          path: 'servers-import',
          builder: (_, _) => ServersImportPage(controller: importer),
        ),
        GoRoute(
          path: 'raw-editor',
          builder: (context, state) {
            rawEditorIds.add(state.extra as int?);
            // The production JSON editor returns its saved row ID. This stub
            // checks only the surrounding route/result contract; Raw saving and
            // dirty-draft behavior are covered by the editor's own tests.
            return Scaffold(
              appBar: AppBar(
                leading: const BackButton(),
                title: const Text('Raw editor destination'),
              ),
              body: TextButton(
                onPressed: () => Navigator.of(context).pop(42),
                child: const Text('Finish Raw save'),
              ),
            );
          },
        ),
      ],
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
  }

  testWidgets(
    'Raw creation is an explicit add-server method; cancel returns and save ends the flow',
    (tester) async {
      importer.text.text = 'Retained paste draft';
      await open(tester);
      await tester.tap(find.text('Open add servers'));
      await tester.pumpAndSettle();
      final choice = find.byKey(const ValueKey('server-import-choice-raw'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(find.text('Raw editor destination'), findsOneWidget);
      expect(rawEditorIds, [null]);
      expect(find.byType(OutboundJsonEditor), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ServersImportPage), findsOneWidget);
      expect(importer.state.activeAction, isNull);
      expect(importer.text.text, 'Retained paste draft');
      expect(returned, isFalse);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(rawEditorIds, [null, null]);
      await tester.tap(find.text('Finish Raw save'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result!.count, 0);
      expect(result!.rawCount, 1);
      expect(find.byType(ServersImportPage), findsNothing);
      expect(find.text('Open add servers'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ordinary manual JSON stays a separate outbound flow', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Open add servers'));
    await tester.pumpAndSettle();
    final choice = find.byKey(const ValueKey('server-import-choice-json'));
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(find.byType(ServerImportFormPage), findsOneWidget);
    expect(find.byType(OutboundJsonEditor), findsOneWidget);
    expect(rawEditorIds, isEmpty);
    final l = AppLocalizations.of(
      tester.element(find.byType(ServerImportFormPage)),
    )!;
    expect(find.text(l.prototypeXrayNodeJson), findsOneWidget);
    expect(find.byTooltip(l.prototypeCloseDialog), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ServersImportPage), findsOneWidget);
    expect(returned, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'existing Raw detail still edits its original ID without opening the add-server methods',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final coordinator = ConnectionCoordinator(database: db);
      final servers = ServersController(database: db, coordinator: coordinator);
      addTearDown(() async {
        await servers.close();
        coordinator.dispose();
        await db.close();
      });
      servers.emit(
        servers.state.copyWith(
          rawConfigurations: [
            CoreConfigData(
              id: 17,
              name: 'Existing Raw',
              type: 'raw',
              tags: '',
              subId: 0,
              delay: 0,
              manualSortOrder: 0,
              favorite: false,
              data: base64Encode(utf8.encode('{"outbounds":[]}')),
            ),
          ],
        ),
      );
      await open(
        tester,
        home: (_) => ServerResourcePage(
          params: ServerResourceParams(
            controller: servers,
            resourceId: 17,
            raw: true,
          ),
        ),
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerResourcePage)),
      )!;
      await tester.tap(
        find.widgetWithText(OutlinedButton, l.prototypeEditRawJson),
      );
      await tester.pumpAndSettle();
      expect(rawEditorIds, [17]);
      expect(find.byType(ServersImportPage), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ServerResourcePage), findsOneWidget);
      expect(find.text('Existing Raw'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
