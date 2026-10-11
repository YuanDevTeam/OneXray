import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/options_form.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/routing/custom/document.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSwitch, ShadTheme;

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: AppTheme.material(Brightness.light, mobile: true),
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  builder: (context, child) => ShadTheme(
    data: AppTheme.shad(Brightness.light, mobile: true),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Finder _switch(String title) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is RoutingSettingRow && widget.title == title,
  ),
  matching: find.byType(ShadSwitch),
);

void main() {
  testWidgets(
    'DNS fallback editing saves separate exits, timeout and cache overrides',
    (tester) async {
      var value = const RoutingDnsSettings();
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                RoutingDnsSettingsForm(
                  value: value,
                  onChanged: (updated) => setState(() => value = updated),
                ),
                TextButton(
                  onPressed: () => saved = value.toJson(),
                  child: const Text('Save DNS'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(RoutingDnsSettingsForm)),
      )!;
      final add = find.text(l.routingDnsAddFallback).first;
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(value.effectiveProxyResolvers, hasLength(2));
      expect(value.effectiveDirectResolvers, hasLength(1));
      final fallback = find.byKey(const ValueKey('dns-proxy-1'));
      final addedAddress = find
          .descendant(of: fallback, matching: find.byType(TextField))
          .first;
      await tester.enterText(addedAddress, 'https://dns.example/dns-query');
      await tester.pumpAndSettle();
      final options = find.descendant(
        of: fallback,
        matching: find.text(l.routingDnsResolverOptions),
      );
      await tester.ensureVisible(options);
      await tester.tap(options);
      await tester.pumpAndSettle();
      final timeout = find.descendant(
        of: fallback,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == l.routingDnsTimeout,
        ),
      );
      await tester.ensureVisible(timeout);
      await tester.enterText(timeout, '2500');
      await tester.pumpAndSettle();
      final inherit = find.descendant(
        of: fallback,
        matching: find.text(l.routingOptionInherit),
      );
      await tester.ensureVisible(inherit);
      await tester.tap(inherit);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.routingOptionOff).last);
      await tester.pumpAndSettle();
      expect(value.effectiveProxyResolvers[1].disableCache, true);
      expect(value.disableCache, false);
      await tester.ensureVisible(_switch(l.routingDnsSameExitOnly));
      await tester.tap(_switch(l.routingDnsSameExitOnly));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_switch(l.routingDnsCache));
      await tester.tap(_switch(l.routingDnsCache));
      await tester.pumpAndSettle();
      expect(value.sameExitOnly, true);
      expect(value.disableCache, true);
      expect(value.directAddress, '8.8.8.8');
      expect(value.effectiveDirectResolvers.first.disableCache, isNull);
      final save = find.widgetWithText(TextButton, 'Save DNS');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final restored = RoutingDnsSettings.fromJson(saved!);
      expect(
        restored.effectiveProxyResolvers[1].address,
        'https://dns.example/dns-query',
      );
      expect(restored.effectiveProxyResolvers[1].timeoutMs, 2500);
      expect(restored.effectiveProxyResolvers[1].disableCache, true);
      expect(restored.sameExitOnly, true);
      expect(restored.disableCache, true);
      expect(restored.directAddress, '8.8.8.8');
      for (final removed in [
        'Expected IPs',
        'Unexpected IPs',
        'Use expired cached answers',
        'Expired cache lifetime (seconds)',
        'Query fallback DNS concurrently',
      ]) {
        expect(find.text(removed, skipOffstage: false), findsNothing);
      }
      expect(
        find.byType(RawAutocomplete<String>, skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('FakeDNS keeps sniffing enabled', (tester) async {
    var sniffing = const RoutingSniffingSettings();
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => RoutingSniffingSettingsForm(
            value: sniffing,
            fakeDns: true,
            onChanged: (value) => setState(() => sniffing = value),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(
      tester.element(find.byType(RoutingSniffingSettingsForm)),
    )!;
    expect(
      tester.widget<ShadSwitch>(_switch(l.routingSniffingEnabled)).enabled,
      false,
    );
    expect(find.text(l.routingSniffingFakeDnsHint), findsOneWidget);
    expect(sniffing.enabled, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sniffing completion generates plain geodata exclusions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RoutingSniffingSettingsForm(
          value: const RoutingSniffingSettings(),
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(
      tester.element(find.byType(RoutingSniffingSettingsForm)),
    )!;
    for (final entry in {
      l.routingSniffingDomainsExcluded: 'geosite:CN',
      l.routingSniffingIpsExcluded: 'geoip:CN',
    }.entries) {
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == entry.key,
      );
      final autocomplete = tester.widget<RawAutocomplete<String>>(
        find.ancestor(
          of: field,
          matching: find.byType(RawAutocomplete<String>),
        ),
      );
      expect(
        await autocomplete.optionsBuilder(
          const TextEditingValue(
            text: '',
            selection: TextSelection.collapsed(offset: 0),
          ),
        ),
        isEmpty,
      );
      expect(autocomplete.displayStringForOption(entry.value), entry.value);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('sniffing form saves comma-containing regex as one exclusion', (
    tester,
  ) async {
    const regex = r'regexp:^api[0-9]{1,3}\.example\.com$';
    const other = 'full:other.example.com';
    var value = const RoutingSniffingSettings();
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              RoutingSniffingSettingsForm(
                value: value,
                onChanged: (updated) => setState(() => value = updated),
              ),
              TextButton(
                onPressed: () => saved = value.toJson(),
                child: const Text('Save exclusions'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(
      tester.element(find.byType(RoutingSniffingSettingsForm)),
    )!;
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == l.routingSniffingDomainsExcluded,
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, '$regex\n$other\n');
    await tester.pumpAndSettle();
    expect(value.domainsExcluded, [regex, other]);
    expect(
      tester.widget<TextField>(field).controller!.text,
      '$regex\n$other\n',
    );
    final save = find.widgetWithText(TextButton, 'Save exclusions');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved!['domainsExcluded'], [regex, other]);
    expect(RoutingSniffingSettings.fromJson(saved!).domainsExcluded, [
      regex,
      other,
    ]);

    // Selecting a completion at the start replaces the whole current line,
    // rather than treating the comma inside the regex quantifier as a boundary.
    final autocomplete = tester.widget<RawAutocomplete<String>>(
      find.ancestor(of: field, matching: find.byType(RawAutocomplete<String>)),
    );
    expect(
      await autocomplete.optionsBuilder(
        const TextEditingValue(
          text: '$regex\n$other',
          selection: TextSelection.collapsed(offset: 0),
        ),
      ),
      isEmpty,
    );
    expect(
      autocomplete.displayStringForOption('geosite:CN'),
      'geosite:CN\n$other',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid DNS timeout is rejected instead of becoming a default', (
    tester,
  ) async {
    var value = const RoutingDnsSettings();
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => RoutingDnsSettingsForm(
            value: value,
            onChanged: (updated) => setState(() => value = updated),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(
      tester.element(find.byType(RoutingDnsSettingsForm)),
    )!;
    await tester.tap(find.text(l.routingDnsResolverOptions).first);
    await tester.pumpAndSettle();
    final timeout = find
        .byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == l.routingDnsTimeout,
        )
        .first;
    await tester.ensureVisible(timeout);
    await tester.enterText(timeout, 'abc');
    await tester.pumpAndSettle();
    expect(value.effectiveProxyResolvers.first.timeoutMs, -1);
    expect(value.validate, throwsFormatException);
    await tester.enterText(timeout, '1.5');
    await tester.pumpAndSettle();
    expect(value.effectiveProxyResolvers.first.timeoutMs, -1);
    expect(value.validate, throwsFormatException);
    await tester.enterText(timeout, '1000');
    await tester.pumpAndSettle();
    expect(value.effectiveProxyResolvers.first.timeoutMs, 1000);
    expect(value.validate, returnsNormally);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'import replaces a focused resolver field without applying stale input',
    (tester) async {
      var value = const RoutingDnsSettings(
        proxyResolvers: [
          RoutingDnsResolver(address: '8.8.8.8'),
          RoutingDnsResolver(address: '1.1.1.1', timeoutMs: 1000),
        ],
      );
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                RoutingDnsSettingsForm(
                  value: value,
                  onChanged: (updated) => setState(() => value = updated),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    value = RoutingProfileDocument.parse(
                      '{"outbounds":[{}],"dns":{"servers":[{"tag":"app-dns-proxy","address":"8.8.8.8"},{"tag":"app-dns-proxy","address":"9.9.9.9","timeoutMs":2500}]}}',
                    ).state.dns;
                  }),
                  child: const Text('Import replacement'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(RoutingDnsSettingsForm)),
      )!;
      final resolver = find.byKey(const ValueKey('dns-proxy-1'));
      final options = find.descendant(
        of: resolver,
        matching: find.text(l.routingDnsResolverOptions),
      );
      await tester.ensureVisible(options);
      await tester.tap(options);
      await tester.pumpAndSettle();
      final timeout = find.descendant(
        of: resolver,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == l.routingDnsTimeout,
        ),
      );
      await tester.ensureVisible(timeout);
      await tester.enterText(timeout, '1200');
      await tester.pumpAndSettle();
      expect(value.effectiveProxyResolvers[1].timeoutMs, 1200);
      // Invoke the public import action without moving focus to reproduce a
      // toolbar import while the original form still owns keyboard focus.
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Import replacement'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(timeout).controller!.text, '2500');
      expect(tester.widget<TextField>(timeout).focusNode!.hasFocus, true);
      await tester.enterText(timeout, '2750');
      await tester.pumpAndSettle();
      expect(value.effectiveProxyResolvers[1].address, '9.9.9.9');
      expect(value.effectiveProxyResolvers[1].timeoutMs, 2750);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in const [Locale('en'), Locale('zh'), Locale('fa')]) {
    testWidgets('routing options fit mobile scaled text ($locale)', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: Column(
                children: [
                  RoutingSelectionSettingsForm(
                    value: const RoutingSelectionSettings(type: 'leastPing'),
                    entryCount: 1,
                    onChanged: (_) {},
                  ),
                  RoutingDnsSettingsForm(
                    value: const RoutingDnsSettings(),
                    onChanged: (_) {},
                  ),
                  RoutingSniffingSettingsForm(
                    value: const RoutingSniffingSettings(),
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(RoutingSelectionSettingsForm)),
      )!;
      expect(find.text(l.routingSelectionSingleHint), findsOneWidget);
      await tester.ensureVisible(find.text(l.routingSelectionProbeSettings));
      await tester.tap(find.text(l.routingSelectionProbeSettings));
      await tester.pumpAndSettle();
      expect(find.text(l.routingSelectionProbeUrl), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
