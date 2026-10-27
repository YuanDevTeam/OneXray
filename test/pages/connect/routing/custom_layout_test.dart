import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/custom/rule_controller.dart';
import 'package:onexray/pages/connect/routing/custom/rule_page.dart';
import 'package:onexray/pages/connect/routing/custom/sections.dart';
import 'package:onexray/pages/connect/routing/options_form.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme;

const _rules = ValueKey('rules');
const _options = ValueKey('options');

void main() {
  late RoutingDnsSettings dns;
  late RoutingSniffingSettings sniffing;

  setUp(() {
    dns = const RoutingDnsSettings();
    sniffing = const RoutingSniffingSettings();
  });

  Future<void> pumpSections(
    WidgetTester tester, {
    required double width,
    double windowWidth = 1440,
    CustomRoutingRuleController? editor,
    Locale locale = const Locale('en'),
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(windowWidth, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.material(brightness),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: ShadTheme(data: AppTheme.shad(brightness), child: child!),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: StatefulBuilder(
                  builder: (context, setState) => CustomRoutingSections(
                    rules: const RoutingCard(
                      key: _rules,
                      child: SizedBox(height: 180),
                    ),
                    editor: editor == null
                        ? null
                        : CustomRoutingRuleForm(controller: editor),
                    options: RoutingCard(
                      key: _options,
                      child: Column(
                        children: [
                          RoutingFakeDnsRow(value: false, onChanged: (_) {}),
                          RoutingFragmentRow(
                            value: false,
                            onChanged: (_) {},
                            divider: false,
                          ),
                        ],
                      ),
                    ),
                    dns: RoutingDnsSettingsForm(
                      value: dns,
                      onChanged: (value) => setState(() => dns = value),
                    ),
                    sniffing: RoutingSniffingSettingsForm(
                      value: sniffing,
                      onChanged: (value) => setState(() => sniffing = value),
                    ),
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

  testWidgets('desktop settings use two columns without reserving an editor', (
    tester,
  ) async {
    for (final width in [1220.0, 876.0, 743.0, 720.0]) {
      await pumpSections(tester, width: width);
      final rules = tester.getRect(find.byKey(_rules));
      final dns = tester.getRect(find.byType(RoutingDnsSettingsForm));
      final options = tester.getRect(find.byKey(_options));
      final sniffing = tester.getRect(find.byType(RoutingSniffingSettingsForm));
      expect(rules.width, width);
      expect(dns.top, options.top);
      expect(dns.right, lessThan(options.left));
      expect(sniffing.left, options.left);
      expect(sniffing.top, greaterThan(options.bottom));
      expect(tester.takeException(), isNull);
    }

    // A desktop viewport can have narrow content after its sidebar and gutters.
    await pumpSections(tester, width: 680);
    final dns = tester.getRect(find.byType(RoutingDnsSettingsForm));
    final options = tester.getRect(find.byKey(_options));
    final sniffing = tester.getRect(find.byType(RoutingSniffingSettingsForm));
    expect(dns.width, 680);
    expect(dns.top, greaterThan(options.bottom));
    expect(sniffing.top, greaterThan(dns.bottom));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('resizing keeps DNS focus, selection and expanded sniffing', (
    tester,
  ) async {
    await pumpSections(tester, width: 900);
    final l = AppLocalizations.of(
      tester.element(find.byType(CustomRoutingSections)),
    )!;
    final more = find.widgetWithText(TextButton, l.routingSniffingMore);
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();

    final input = find.descendant(
      of: find.byKey(const ValueKey('dns-proxy-0')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, 'https://resolver.example/dns-query');
    await tester.pumpAndSettle();
    final textController = tester.widget<TextField>(input).controller!;
    const selection = TextSelection(baseOffset: 8, extentOffset: 16);
    textController.selection = selection;

    for (final width in [680.0, 743.0, 1220.0]) {
      await pumpSections(tester, width: width);
      expect(tester.widget<TextField>(input).controller, same(textController));
      expect(textController.selection, selection);
      expect(
        dns.effectiveProxyResolvers.first.address,
        'https://resolver.example/dns-query',
      );
      final editable = find.descendant(
        of: input,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      expect(find.text(l.routingSniffingMetadataOnly), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'rule editing and settings adapt independently with scaled text',
    (tester) async {
      final editor = CustomRoutingRuleController();
      addTearDown(editor.close);
      await pumpSections(tester, width: 900, editor: editor);
      final ruleInput = find
          .descendant(
            of: find.byType(CustomRoutingRuleForm),
            matching: find.byType(EditableText),
          )
          .first;
      await tester.ensureVisible(ruleInput);
      await tester.enterText(ruleInput, 'Edited rule');
      await tester.pumpAndSettle();
      const selection = TextSelection(baseOffset: 0, extentOffset: 6);
      editor.name.selection = selection;
      for (final (width, locale, scale, brightness) in const [
        (1220.0, Locale('zh'), 1.0, Brightness.light),
        (900.0, Locale('en'), 1.0, Brightness.light),
        (876.0, Locale('ru'), 1.6, Brightness.dark),
        (743.0, Locale('fa'), 1.6, Brightness.light),
        (680.0, Locale('zh'), 2.0, Brightness.dark),
      ]) {
        await pumpSections(
          tester,
          width: width,
          windowWidth: width < 400 ? 390 : 1440,
          editor: editor,
          locale: locale,
          textScale: scale,
          brightness: brightness,
        );
        final rules = tester.getRect(find.byKey(_rules));
        final form = tester.getRect(find.byType(CustomRoutingRuleForm));
        if (width >= 876) {
          expect(form.top, rules.top);
          expect(form.left, greaterThan(rules.right));
          expect(form.width, rules.width);
          expect(form.width, (width - 16) / 2);
        } else {
          expect(form.top, greaterThan(rules.bottom));
        }
        expect(editor.name.text, 'Edited rule');
        expect(editor.name.selection, selection);
        expect(
          tester.widget<EditableText>(ruleInput).focusNode.hasFocus,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      }
      expect(editor.draftRule.ruleTag, 'Edited rule');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
