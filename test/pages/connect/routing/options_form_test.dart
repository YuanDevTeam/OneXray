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
    'DNS fallback editing keeps separate exits and finite cache options',
    (tester) async {
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
      final add = find.text(l.routingDnsAddFallback).first;
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(value.effectiveProxyResolvers, hasLength(2));
      expect(value.effectiveDirectResolvers, hasLength(1));
      final addedAddress = find
          .descendant(
            of: find.byKey(const ValueKey('dns-proxy-1')),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(addedAddress, 'https://dns.example/dns-query');
      await tester.pumpAndSettle();
      expect(
        value.effectiveProxyResolvers[1].address,
        'https://dns.example/dns-query',
      );
      expect(value.directAddress, '8.8.8.8');
      await tester.ensureVisible(find.text(l.routingDnsAdvanced));
      await tester.tap(find.text(l.routingDnsAdvanced));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ShadSwitch>(_switch(l.routingDnsParallel)).enabled,
        false,
      );
      await tester.ensureVisible(_switch(l.routingDnsSameExitOnly));
      await tester.tap(_switch(l.routingDnsSameExitOnly));
      await tester.pumpAndSettle();
      expect(value.sameExitOnly, true);
      expect(
        tester.widget<ShadSwitch>(_switch(l.routingDnsParallel)).enabled,
        true,
      );
      await tester.ensureVisible(_switch(l.routingDnsServeStale));
      await tester.tap(_switch(l.routingDnsServeStale));
      await tester.pumpAndSettle();
      expect(value.serveStale, true);
      expect(value.serveExpiredTTL, 300);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('FakeDNS keeps sniffing enabled and disables concurrent DNS', (
    tester,
  ) async {
    var sniffing = const RoutingSniffingSettings();
    var dns = const RoutingDnsSettings(
      sameExitOnly: true,
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
              RoutingSniffingSettingsForm(
                value: sniffing,
                fakeDns: true,
                onChanged: (value) => setState(() => sniffing = value),
              ),
              RoutingDnsSettingsForm(
                value: dns,
                fakeDns: true,
                onChanged: (value) => setState(() => dns = value),
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
    expect(
      tester.widget<ShadSwitch>(_switch(l.routingSniffingEnabled)).enabled,
      false,
    );
    expect(find.text(l.routingSniffingFakeDnsHint), findsOneWidget);
    await tester.ensureVisible(find.text(l.routingDnsAdvanced));
    await tester.tap(find.text(l.routingDnsAdvanced));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ShadSwitch>(_switch(l.routingDnsParallel)).enabled,
      false,
    );
    expect(sniffing.enabled, true);
    expect(dns.directAddress, '8.8.8.8');
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled DNS concurrency retains its saved preference', (
    tester,
  ) async {
    var value = const RoutingDnsSettings(
      sameExitOnly: true,
      enableParallelQuery: true,
      proxyResolvers: [
        RoutingDnsResolver(address: '8.8.8.8'),
        RoutingDnsResolver(address: '1.1.1.1'),
      ],
    );
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
    await tester.ensureVisible(_switch(l.routingDnsSameExitOnly));
    await tester.tap(_switch(l.routingDnsSameExitOnly));
    await tester.pumpAndSettle();
    expect(value.sameExitOnly, false);
    expect(value.enableParallelQuery, true);
    expect(value.effectiveJson()['enableParallelQuery'], false);
    await tester.ensureVisible(find.text(l.routingDnsAdvanced));
    await tester.tap(find.text(l.routingDnsAdvanced));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ShadSwitch>(_switch(l.routingDnsParallel)).enabled,
      false,
    );
    expect(
      tester.widget<ShadSwitch>(_switch(l.routingDnsParallel)).value,
      true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid DNS numeric input is rejected instead of becoming defaults',
    (tester) async {
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
      await tester.enterText(timeout, '1000');
      await tester.pumpAndSettle();
      expect(value.effectiveProxyResolvers.first.timeoutMs, 1000);
      expect(value.validate, returnsNormally);
      final ttl = find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == l.routingDnsStaleTtl,
          )
          .first;
      await tester.ensureVisible(ttl);
      await tester.enterText(ttl, '1.5');
      await tester.pumpAndSettle();
      expect(value.effectiveProxyResolvers.first.serveExpiredTTL, -1);
      expect(value.validate, throwsFormatException);
      await tester.enterText(ttl, '');
      await tester.pumpAndSettle();
      expect(value.effectiveProxyResolvers.first.serveExpiredTTL, isNull);
      expect(value.validate, returnsNormally);
      await tester.ensureVisible(find.text(l.routingDnsAdvanced));
      await tester.tap(find.text(l.routingDnsAdvanced));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_switch(l.routingDnsServeStale));
      await tester.tap(_switch(l.routingDnsServeStale));
      await tester.pumpAndSettle();
      final rootTtl = find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == l.routingDnsStaleTtl,
          )
          .last;
      await tester.ensureVisible(rootTtl);
      await tester.enterText(rootTtl, 'invalid');
      await tester.pumpAndSettle();
      expect(value.serveExpiredTTL, -1);
      expect(value.validate, throwsFormatException);
      await tester.enterText(rootTtl, '300');
      await tester.pumpAndSettle();
      expect(value.validate, returnsNormally);
      expect(tester.takeException(), isNull);
    },
  );

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
