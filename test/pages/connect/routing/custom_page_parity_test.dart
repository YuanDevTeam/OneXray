import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/custom/controller.dart';
import 'package:onexray/pages/connect/routing/custom/page.dart';
import 'package:onexray/pages/connect/routing/options_form.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:onexray/pages/shared/widgets/configuration_transfer.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/routing/custom/editor.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  for (final width in [390.0, 1032.0, 1160.0]) {
    testWidgets(
      'normal routing groups keep their real draft actions at $width',
      (tester) async {
        final bus = AppEventBus();
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final coordinator = _LayoutCoordinator(db);
        final service = _LayoutService(database: db, coordinator: coordinator);
        final controller = CustomRoutingEditorController(service: service);
        addTearDown(() async {
          await controller.close();
          coordinator.dispose();
          await db.close();
          await bus.close();
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var ruleRequests = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.material(Brightness.light, mobile: width <= 720),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) => ShadTheme(
              data: AppTheme.shad(Brightness.light, mobile: width <= 720),
              child: ShadToaster(child: child!),
            ),
            home: CustomRoutingEditorPage(
              createController: () => controller,
              openRule: (_, _) async {
                ruleRequests++;
                return RoutingRuleState(ruleTag: 'Added rule');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.state.loaded, isTrue);
        final l = AppLocalizations.of(
          tester.element(find.byType(CustomRoutingEditorPage)),
        )!;
        final header = tester.widget<PageAppBar>(find.byType(PageAppBar));
        expect((header.title as Text).data, l.routingNormalCreateTitle);
        expect(header.description, isNull);
        expect(find.text(l.routingNormalDescription), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text(l.routingNormalDescription),
          ),
          findsNothing,
        );

        final identity = find.byKey(const ValueKey('custom-identity'));
        final rules = find.byKey(const ValueKey('custom-rule-list'));
        final proxy = find.byKey(const ValueKey('custom-proxy-settings'));
        final dns = find.byType(RoutingDnsSettingsForm);
        final sniffing = find.byType(RoutingSniffingSettingsForm);
        final transfer = find.byKey(const ValueKey('custom-transfer-tools'));
        final sections = [identity, rules, proxy, dns, sniffing, transfer];
        for (var index = 1; index < sections.length; index++) {
          final before = tester.getRect(sections[index - 1]);
          final after = tester.getRect(sections[index]);
          expect(after.top - before.bottom, closeTo(20, .01));
          expect(after.left, closeTo(before.left, .01));
          expect(after.width, closeTo(before.width, .01));
        }
        expect(
          find.descendant(
            of: rules,
            matching: find.byType(RoutingEntryCountRow),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: proxy, matching: find.byType(RoutingFragmentRow)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: sniffing,
            matching: find.byType(RoutingFakeDnsRow),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: transfer,
            matching: find.byType(ConfigurationTransferTools),
          ),
          findsOneWidget,
        );
        final count = find.byType(SettingSelect<int>);
        final selection = find.descendant(
          of: find.byType(RoutingSelectionSettingsForm),
          matching: find.byType(OutlinedButton),
        );
        expect(
          tester.getSize(count).width,
          closeTo(tester.getSize(selection).width, .01),
        );

        await tester.ensureVisible(count);
        await tester.tap(count);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(MenuItemButton, l.prototypeUseEntryServers(3)),
        );
        await tester.pumpAndSettle();
        expect(controller.state.entryCount, 3);
        expect(controller.profileState.entryCount, 3);

        final fragment = find.descendant(
          of: find.byType(RoutingFragmentRow),
          matching: find.byType(AppSwitch),
        );
        await tester.ensureVisible(fragment);
        await tester.tap(fragment);
        await tester.pump();
        expect(controller.state.fragment, isTrue);
        final fakeDns = find.descendant(
          of: find.byType(RoutingFakeDnsRow),
          matching: find.byType(AppSwitch),
        );
        await tester.ensureVisible(fakeDns);
        await tester.tap(fakeDns);
        await tester.pump();
        expect(controller.state.fakeDns, isTrue);
        expect(controller.state.sniffing.enabled, isTrue);

        final add = find.descendant(
          of: rules,
          matching: find.widgetWithText(OutlinedButton, l.prototypeAddRule),
        );
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pump();
        expect(ruleRequests, 1);
        expect(controller.state.rules.single.ruleTag, 'Added rule');
        expect(service.saves, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _LayoutCoordinator extends ConnectionCoordinator {
  _LayoutCoordinator(AppDatabase database) : super(database: database);

  @override
  Future<ConnectionConfiguration> get configuration async =>
      ConnectionConfiguration();
}

class _LayoutService extends CustomRoutingEditorService {
  _LayoutService({required super.database, required super.coordinator});
  int saves = 0;

  @override
  Future<CustomRoutingEditorDraft> load(int? id) async =>
      CustomRoutingEditorDraft(
        state: RoutingProfileState(name: 'Layout draft'),
      );

  @override
  Future<List<RoutingProfileData>> get rows async => [];

  @override
  Future<int?> save(
    CustomRoutingEditorDraft draft, {
    required Future<bool> Function() confirmReconnect,
    ConfigurationImportDraft? imported,
  }) async {
    saves++;
    return null;
  }
}
