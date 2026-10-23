import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/options_form.dart';
import 'package:onexray/pages/connect/routing/smart/controller.dart';
import 'package:onexray/pages/connect/routing/smart/page.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/routing/smart/editor.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSwitch, ShadTheme;

const _primary = ValueKey('smart-routing-primary');
const _secondary = ValueKey('smart-routing-secondary');

void main() {
  late AppDatabase database;
  late ConnectionCoordinator coordinator;
  late SmartRoutingEditorController controller;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(database: database);
    controller = SmartRoutingEditorController(
      service: SmartRoutingEditorService(
        database: database,
        coordinator: coordinator,
      ),
    );
    controller.emit(
      SmartRoutingEditorState(
        original: SmartRoutingEditorDraft(
          configuration: ConnectionConfiguration(),
          regions: RegionCatalog.fromJson(
            {'geosite': <String, dynamic>{}, 'geoip': <String, dynamic>{}},
            geositeCodes: [],
            geoipCodes: [],
          ),
        ),
        busy: false,
      ),
    );
  });

  tearDown(() async {
    await controller.close();
    coordinator.dispose();
    await database.close();
  });

  Future<void> pumpContent(
    WidgetTester tester, {
    required double windowWidth,
    required double contentWidth,
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(windowWidth, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final scaler = TextScaler.linear(textScale);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.material(Brightness.light),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: ShadTheme(
            data: AppTheme.shad(Brightness.light, textScaler: scaler),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: contentWidth,
                child:
                    BlocBuilder<
                      SmartRoutingEditorController,
                      SmartRoutingEditorState
                    >(
                      bloc: controller,
                      builder: (context, state) => SmartRoutingEditorContent(
                        controller: controller,
                        state: state,
                        openRegions: (_, _) async => null,
                        openFinalExit: (_, _) async => null,
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder header(String title) => find.byWidgetPredicate(
    (widget) => widget is RoutingCardHeader && widget.title == title,
  );

  testWidgets(
    'default iPad and desktop groups balance both columns',
    (tester) async {
      final iPad = defaultTargetPlatform == TargetPlatform.iOS;
      final contentWidth = iPad ? 743.0 : 1000.0;
      await pumpContent(
        tester,
        windowWidth: iPad ? 1024 : 1440,
        contentWidth: contentWidth,
      );
      final primary = tester.getRect(find.byKey(_primary));
      final secondary = tester.getRect(find.byKey(_secondary));
      expect(primary.top, closeTo(secondary.top, 0.01));
      expect(primary.width, closeTo((contentWidth - 16) / 2, 0.01));
      expect(primary.width, closeTo(secondary.width, 0.01));
      final taller = primary.height > secondary.height
          ? primary.height
          : secondary.height;
      expect(
        (primary.height - secondary.height).abs() / taller,
        lessThan(0.25),
        reason:
            'Content $contentWidth: left ${primary.height}, '
            'right ${secondary.height}',
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(SmartRoutingEditorContent)),
      )!;
      expect(
        find.descendant(
          of: find.byKey(_primary),
          matching: header(l.routingDnsSettings),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_secondary),
          matching: header(l.prototypeRoutingPreview),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.macOS}),
  );

  testWidgets('a wide window with narrow content keeps the reading order', (
    tester,
  ) async {
    await pumpContent(tester, windowWidth: 1440, contentWidth: 680);
    expect(find.byKey(_primary), findsNothing);
    expect(find.byKey(_secondary), findsNothing);
    final l = AppLocalizations.of(
      tester.element(find.byType(SmartRoutingEditorContent)),
    )!;
    final titles = [
      l.smartRoutingDirectAndBlock,
      l.smartRoutingProxyConnection,
      l.routingDnsSettings,
      l.routingSniffingSettings,
      l.prototypeRoutingPreview,
    ];
    for (var index = 1; index < titles.length; index++) {
      expect(
        tester.getTopLeft(header(titles[index])).dy,
        greaterThan(tester.getBottomLeft(header(titles[index - 1])).dy),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'routing edits survive width and language changes with scaled text',
    (tester) async {
      final original = controller.state.original!.configuration.encode();
      await pumpContent(
        tester,
        windowWidth: 1024,
        contentWidth: 743,
        locale: const Locale('ru'),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
      final l = AppLocalizations.of(
        tester.element(find.byType(SmartRoutingEditorContent)),
      )!;
      final dnsInput = find.descendant(
        of: find.byKey(const ValueKey('dns-proxy-0')),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(dnsInput);
      await tester.enterText(dnsInput, 'https://resolver.example/dns-query');
      await tester.pumpAndSettle();
      final fakeDns = find.descendant(
        of: find.byType(RoutingFakeDnsRow),
        matching: find.byType(ShadSwitch),
      );
      await tester.ensureVisible(fakeDns);
      await tester.tap(fakeDns);
      await tester.pumpAndSettle();
      expect(controller.state.draft.fakeDns, isTrue);

      final count = find.descendant(
        of: find.byType(EntryCountPicker),
        matching: find.text('2'),
      );
      await tester.ensureVisible(count);
      await tester.tap(count);
      await tester.pumpAndSettle();
      final selection = find
          .descendant(
            of: find.byType(RoutingSelectionSettingsForm),
            matching: find.byType(OutlinedButton),
          )
          .first;
      await tester.ensureVisible(selection);
      await tester.tap(selection);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, l.routingSelectionLeastPing),
      );
      await tester.pumpAndSettle();
      expect(controller.state.draft.selection.type, 'leastPing');
      expect(controller.state.draft.entryCount, 2);
      final draft = controller.state.draft.toJson();

      await pumpContent(
        tester,
        windowWidth: 1440,
        contentWidth: 680,
        locale: const Locale('fa'),
        textScale: 2,
      );
      expect(find.byKey(_primary), findsNothing);
      expect(controller.state.draft.toJson(), draft);
      expect(
        tester.widget<TextField>(dnsInput).controller!.text,
        'https://resolver.example/dns-query',
      );
      final fa = AppLocalizations.of(
        tester.element(find.byType(SmartRoutingEditorContent)),
      )!;
      final sniffing = find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is RoutingSettingRow &&
              widget.title == fa.routingSniffingEnabled,
        ),
        matching: find.byType(ShadSwitch),
      );
      expect(tester.widget<ShadSwitch>(sniffing).value, isTrue);
      expect(tester.widget<ShadSwitch>(sniffing).enabled, isFalse);
      expect(tester.takeException(), isNull);

      await pumpContent(
        tester,
        windowWidth: 1440,
        contentWidth: 1000,
        locale: const Locale('fa'),
        textScale: 1.6,
      );
      expect(find.byKey(_primary), findsOneWidget);
      expect(find.byKey(_secondary), findsOneWidget);
      expect(controller.state.draft.toJson(), draft);
      expect(controller.state.original!.configuration.encode(), original);
      expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
