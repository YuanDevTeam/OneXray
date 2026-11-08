import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/advanced/xray/controller.dart';
import 'package:onexray/pages/advanced/xray/fields.dart';
import 'package:onexray/pages/advanced/xray/log/settings.dart';
import 'package:onexray/pages/advanced/xray/page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
  });
  for (final (mobile, systemExtension) in [
    (true, false),
    (true, true),
    (false, false),
    (false, true),
  ]) {
    testWidgets(
      'Xray logs use an isolated page: systemExtension=$systemExtension, mobile=$mobile',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = mobile
            ? const Size(427, 900)
            : const Size(1160, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final coordinator = ConnectionCoordinator(database: db);
        final root = _Controller(
          coordinator: coordinator,
          systemExtension: systemExtension,
        );
        Widget app(Widget child) => MaterialApp(
          theme: AppTheme.material(Brightness.light, mobile: mobile),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => ShadTheme(
            data: AppTheme.shad(Brightness.light, mobile: mobile),
            child: ShadToaster(child: child!),
          ),
          home: child,
        );
        await tester.pumpWidget(
          app(
            XrayRuntimePage(
              createController: () => root,
              onDiagnostics: (_) {},
              onGeodata: (_) {},
              onUpdates: (_) {},
              onSpeedTest: (_) async {},
              onConfig: (_, _) {},
              onLogSettings: (_) async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(XrayRuntimePage)),
        )!;
        expect(find.byType(PageActionBar), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w is SettingRow && w.title == l.prototypeLogs,
          ),
          systemExtension ? findsNothing : findsOneWidget,
        );
        for (final text in [
          l.prototypeRecordXrayLogs,
          l.prototypeErrorLogLevel,
          l.prototypeRecordDnsQueries,
          l.prototypeHideLogIpAddresses,
          l.prototypeAccessLog,
          l.prototypeErrorLog,
          l.prototypeRestoreDefaults,
          l.prototypeSave,
        ]) {
          expect(find.text(text), findsNothing);
        }
        for (final text in [
          l.prototypeRuntimeStatus,
          l.prototypeRoutingData,
          l.prototypeDataUpdates,
          l.prototypeSpeedTest,
          l.prototypeRecentXrayConfiguration,
          l.xrayChecksAndDiagnostics,
          l.xrayConnectionResources,
          l.xraySharingInterfaces,
        ]) {
          expect(find.text(text), findsOneWidget);
        }
        final core = find.byKey(const ValueKey('xray-core-runtime'));
        expect(tester.widget<SettingRow>(core).title, 'Xray-core');
        expect(tester.widget<SettingRow>(core).subtitle, '26.10.31');
        expect(
          find.descendant(of: core, matching: find.byType(ShadBadge)),
          findsOneWidget,
        );
        expect(find.text(l.prototypeVersion), findsNothing);
        expect(
          tester
              .widget<SettingRow>(
                find.byKey(const ValueKey('xray-current-connection')),
              )
              .subtitle,
          l.xrayNotRunning,
        );
        final checks = find.byWidgetPredicate(
          (w) => w is SettingSection && w.title == l.xrayChecksAndDiagnostics,
        );
        for (final title in [
          l.xrayDiagnostics,
          l.prototypeRecentXrayConfiguration,
          if (!systemExtension) l.prototypeLogs,
        ]) {
          expect(
            find.descendant(
              of: checks,
              matching: find.byWidgetPredicate(
                (w) => w is SettingRow && w.title == title,
              ),
            ),
            findsOneWidget,
          );
        }
        final resources = find.byWidgetPredicate(
          (w) => w is SettingSection && w.title == l.xrayConnectionResources,
        );
        for (final title in [
          l.prototypeRoutingData,
          l.prototypeDataUpdates,
          l.prototypeSpeedTest,
        ]) {
          expect(
            find.descendant(
              of: resources,
              matching: find.byWidgetPredicate(
                (w) => w is SettingRow && w.title == title,
              ),
            ),
            findsOneWidget,
          );
        }
        expect(find.byType(SettingSection), findsNWidgets(4));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        late _Controller detail;
        var viewerCalls = 0;
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('open-log-settings'),
                  onPressed: () => Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => XrayLogSettingsPage(
                        createController: () => detail = _Controller(
                          coordinator: coordinator,
                          systemExtension: systemExtension,
                        ),
                        onLog: (_, _) => viewerCalls++,
                      ),
                    ),
                  ),
                  child: const Text('Open logs'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('open-log-settings')));
        await tester.pumpAndSettle();
        final visibility = systemExtension ? findsNothing : findsOneWidget;
        for (final text in [
          l.prototypeRecordXrayLogs,
          l.prototypeErrorLogLevel,
          l.prototypeRecordDnsQueries,
          l.prototypeHideLogIpAddresses,
          l.prototypeAccessLog,
          l.prototypeErrorLog,
          l.prototypeRestoreDefaults,
          l.prototypeSave,
        ]) {
          expect(find.text(text), visibility);
        }
        expect(find.byType(PageActionBar), visibility);
        if (systemExtension) {
          expect(find.text(l.logsUnavailableSystemExtension), findsOneWidget);
          expect(viewerCalls, 0);
        } else {
          final preference = find.byWidgetPredicate(
            (widget) =>
                widget is XrayToggleField &&
                widget.title == l.prototypeRecordXrayLogs,
          );
          expect(preference, findsOneWidget);
          expect(
            tester.widget<XrayToggleField>(preference).description,
            l.xrayRecordLogsHint,
          );
          final field = find.byKey(const ValueKey('xray-log-level-field'));
          final select = find.descendant(
            of: field,
            matching: find.byType(SettingSelect<String>),
          );
          expect(
            tester.getSize(select).width,
            closeTo(tester.getSize(field).width, 1),
          );
          expect(detail.dirty, isFalse);
          await tester.tap(find.widgetWithText(FilledButton, l.prototypeSave));
          await tester.pumpAndSettle();
          expect(find.text(l.prototypeSettingsSaved), findsOneWidget);
          expect(find.byType(XrayLogSettingsPage), findsNothing);
          expect(detail.saving, isFalse);
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('open-log-settings')));
          await tester.pumpAndSettle();
          final original = detail.base;
          final restore = find.text(l.prototypeRestoreDefaults);
          await tester.ensureVisible(restore);
          await tester.pumpAndSettle();
          await tester.tap(restore);
          await tester.pumpAndSettle();
          expect(find.text(l.settingsDefaultsRestored), findsOneWidget);
          expect(find.text(l.prototypeSettingsSaved), findsNothing);
          expect(detail.logsEnabled, isFalse);
          expect(detail.base, same(original));
          expect(detail.dirty, isTrue);
          // Wait for the existing bottom toast before using the footer.
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
          expect(find.text(l.settingsDefaultsRestored), findsNothing);
          await tester.tap(
            find.widgetWithText(OutlinedButton, l.prototypeCancel),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('open-log-settings')));
          await tester.pumpAndSettle();
          expect(detail.logsEnabled, isTrue);
          expect(detail.dirty, isFalse);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        coordinator.dispose();
        await db.close();
      },
    );
  }
}

class _Controller extends XrayRuntimeController {
  _Controller({required super.coordinator, required this.systemExtension});
  final bool systemExtension;

  // This UI fixture supplies the same public metadata getter as production.
  // The real reader can still publish unknown native metadata asynchronously.
  @override
  String get xrayVersion => '26.10.31';

  @override
  Future<void> load({bool showLoading = true}) async {
    final configuration = ConnectionConfiguration(
      policy: PlatformPolicy.fromJson({
        'log': {'enabled': true},
      }),
    );
    emit(
      state.copyWith(
        base: configuration,
        log: configuration.policy.toJson()['log'] as Map<String, dynamic>,
        systemExtension: systemExtension,
        loading: false,
      ),
    );
  }
}
