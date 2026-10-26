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

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) => MaterialApp(
  theme: AppTheme.material(Brightness.light, mobile: true),
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: ShadTheme(
      data: AppTheme.shad(
        Brightness.light,
        mobile: true,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Finder _switch(String title) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is RoutingSettingRow && widget.title == title,
  ),
  matching: find.byType(ShadSwitch),
);

Finder _dnsPolicyPicker() => find.descendant(
  of: find.byKey(const ValueKey('dns-non-address-policy')),
  matching: find.byType(OutlinedButton),
);

void main() {
  for (final directEnabled in [true, false]) {
    testWidgets(
      'DNS record policy choices save with direct DNS enabled=$directEnabled',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var value = const RoutingDnsSettings();
        Map<String, dynamic>? saved;
        await tester.pumpWidget(
          _app(
            StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  RoutingDnsSettingsForm(
                    value: value,
                    directEnabled: directEnabled,
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
        expect(value.nonAddressPolicy, NonAddressDnsPolicy.proxy);
        expect(
          tester.getSemantics(_dnsPolicyPicker()).label,
          '${l.routingDnsNonAddress}: ${l.routingDnsNonAddressProxy}',
        );
        expect(
          find.byKey(const ValueKey('dns-direct-0')),
          directEnabled ? findsOneWidget : findsNothing,
        );
        expect(
          tester.widget<OutlinedButton>(_dnsPolicyPicker()).onPressed,
          isNotNull,
        );
        for (final (policy, label) in [
          (NonAddressDnsPolicy.direct, l.routingDnsNonAddressDirect),
          (NonAddressDnsPolicy.empty, l.routingDnsNonAddressEmpty),
          (NonAddressDnsPolicy.proxy, l.routingDnsNonAddressProxy),
        ]) {
          await tester.ensureVisible(_dnsPolicyPicker());
          await tester.tap(_dnsPolicyPicker());
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(MenuItemButton, label));
          await tester.pumpAndSettle();
          expect(value.nonAddressPolicy, policy);
          expect(
            tester.getSemantics(_dnsPolicyPicker()).label,
            '${l.routingDnsNonAddress}: $label',
          );
          expect(
            find.descendant(of: _dnsPolicyPicker(), matching: find.text(label)),
            findsOneWidget,
          );
          final save = find.widgetWithText(TextButton, 'Save DNS');
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(RoutingDnsSettings.fromJson(saved!).nonAddressPolicy, policy);
        }
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'DNS address editing saves fallback lists, global cache and exit policy',
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
      final fallback = find.byKey(const ValueKey('dns-proxy-1'));
      final address = find.descendant(
        of: fallback,
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(address);
      await tester.enterText(address, 'https://dns.example/dns-query');
      await tester.pumpAndSettle();
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final extraFallback = find.byKey(const ValueKey('dns-proxy-2'));
      final extraAddress = find.descendant(
        of: extraFallback,
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(extraAddress);
      await tester.enterText(extraAddress, '9.9.9.9');
      await tester.pumpAndSettle();
      expect(
        value.effectiveProxyResolvers.map((resolver) => resolver.address),
        ['8.8.8.8', 'https://dns.example/dns-query', '9.9.9.9'],
      );
      final delete = find.descendant(
        of: extraFallback,
        matching: find.byTooltip(l.prototypeDelete),
      );
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(value.effectiveProxyResolvers, hasLength(2));
      expect(value.effectiveDirectResolvers, hasLength(1));
      await tester.ensureVisible(_switch(l.routingDnsSameExitOnly));
      await tester.tap(_switch(l.routingDnsSameExitOnly));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_switch(l.routingDnsCache));
      await tester.tap(_switch(l.routingDnsCache));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(TextButton, 'Save DNS');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final restored = RoutingDnsSettings.fromJson(saved!);
      expect(
        restored.effectiveProxyResolvers.map((resolver) => resolver.address),
        ['8.8.8.8', 'https://dns.example/dns-query'],
      );
      expect(restored.directAddress, '8.8.8.8');
      expect(restored.sameExitOnly, true);
      expect(restored.disableCache, true);
      expect(find.byType(TextField), findsNWidgets(3));
      for (final removed in [
        'Timeout and cache overrides',
        'Resolver timeout (ms)',
        'Inherit',
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

  testWidgets('sniffing form saves switches and retains disabled preferences', (
    tester,
  ) async {
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
                child: const Text('Save sniffing'),
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
    await tester.ensureVisible(_switch(l.routingSniffingRouteOnly));
    await tester.tap(_switch(l.routingSniffingRouteOnly));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l.routingSniffingMore));
    await tester.tap(find.text(l.routingSniffingMore));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_switch(l.routingSniffingMetadataOnly));
    await tester.tap(_switch(l.routingSniffingMetadataOnly));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_switch(l.routingSniffingEnabled));
    await tester.tap(_switch(l.routingSniffingEnabled));
    await tester.pumpAndSettle();
    expect(value.enabled, false);
    expect(value.routeOnly, true);
    expect(value.metadataOnly, true);
    expect(
      tester.widget<ShadSwitch>(_switch(l.routingSniffingRouteOnly)).enabled,
      false,
    );
    expect(
      tester.widget<ShadSwitch>(_switch(l.routingSniffingMetadataOnly)).enabled,
      false,
    );
    final save = find.widgetWithText(TextButton, 'Save sniffing');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final restored = RoutingSniffingSettings.fromJson(saved!);
    expect(restored.enabled, false);
    expect(restored.routeOnly, true);
    expect(restored.metadataOnly, true);
    expect(saved, isNot(contains('domainsExcluded')));
    expect(saved, isNot(contains('ipsExcluded')));
    expect(find.text('Excluded domains', skipOffstage: false), findsNothing);
    expect(find.text('Excluded IPs', skipOffstage: false), findsNothing);
    expect(find.byType(TextField, skipOffstage: false), findsNothing);
    expect(
      find.byType(RawAutocomplete<String>, skipOffstage: false),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'import replaces a focused resolver address without applying stale input',
    (tester) async {
      var value = const RoutingDnsSettings(
        proxyResolvers: [
          RoutingDnsResolver(address: '8.8.8.8'),
          RoutingDnsResolver(address: '1.1.1.1'),
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
                      '{"outbounds":[{}],"dns":{"servers":[{"tag":"app-dns-proxy","address":"8.8.8.8"},{"tag":"app-dns-proxy","address":"9.9.9.9"}]}}',
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
      final resolver = find.byKey(const ValueKey('dns-proxy-1'));
      final address = find.descendant(
        of: resolver,
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(address);
      await tester.enterText(address, '1.0.0.1');
      await tester.pumpAndSettle();
      expect(value.effectiveProxyResolvers[1].address, '1.0.0.1');
      // Invoke the public import action without moving focus to reproduce a
      // toolbar import while the original address field still owns focus.
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Import replacement'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(address).controller!.text, '9.9.9.9');
      final editable = find.descendant(
        of: resolver,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, true);
      await tester.enterText(address, '8.8.4.4');
      await tester.pumpAndSettle();
      expect(value.effectiveProxyResolvers[1].address, '8.8.4.4');
      expect(value.effectiveProxyResolvers.first.address, '8.8.8.8');
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('routing options fit mobile scaled text ($locale)', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 667);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              RoutingSelectionSettingsForm(
                value: const RoutingSelectionSettings(type: 'leastPing'),
                entryCount: 1,
                onChanged: (_) {},
              ),
              RoutingDnsSettingsForm(
                value: const RoutingDnsSettings(),
                directEnabled: false,
                onChanged: (_) {},
              ),
              RoutingSniffingSettingsForm(
                value: const RoutingSniffingSettings(),
                onChanged: (_) {},
              ),
            ],
          ),
          locale: locale,
          textScale: 1.5,
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
      await tester.ensureVisible(_dnsPolicyPicker());
      expect(find.text(l.routingDnsNonAddressHint), findsNothing);
      await tester.tap(_dnsPolicyPicker());
      await tester.pumpAndSettle();
      for (final label in [
        l.routingDnsNonAddressProxy,
        l.routingDnsNonAddressDirect,
        l.routingDnsNonAddressEmpty,
      ]) {
        expect(find.widgetWithText(MenuItemButton, label), findsOneWidget);
      }
      await tester.tap(
        find.widgetWithText(MenuItemButton, l.routingDnsNonAddressEmpty),
      );
      await tester.pumpAndSettle();
      final help = find.byTooltip('${l.pageHelp} · ${l.routingDnsNonAddress}');
      await tester.ensureVisible(help);
      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(find.text(l.routingDnsNonAddressHint), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
