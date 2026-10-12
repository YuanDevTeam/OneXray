import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/servers/import/controller.dart';
import 'package:onexray/pages/servers/subscription/form_view.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  late TextEditingController name, url, secret, public;
  late ServerImportController controller;
  late List<AgeKeyType> generated;
  late int revealed;

  setUp(() {
    controller = ServerImportController(loadSubscription: (_) async => null);
    name = controller.name;
    url = controller.url;
    secret = controller.secretKey;
    public = controller.publicKey;
    generated = [];
    revealed = 0;
  });

  tearDown(() => controller.close());

  Widget form({
    AgeKeyType? generatingKey,
    bool obscure = true,
    bool automaticAllowed = true,
  }) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<ServerImportController, ServerImportPageState>(
      builder: (context, state) => SubscriptionFormView(
        supportText: AppLocalizations.of(context)!
            .prototypeSubscriptionDescription,
        nameLabel: 'Name',
        nameHint: 'Example Service',
        nameController: name,
        urlLabel: 'URL',
        urlController: url,
        urlHint: 'https://provider.example/subscription',
        urlHelper: 'HTTPS only',
        panel: state.panel,
        mode: state.mode,
        automaticModeAllowed: automaticAllowed,
        onPanelChanged: generatingKey == null && !state.busy
            ? controller.setPanel
            : null,
        onModeChanged: generatingKey == null && !state.busy
            ? controller.setMode
            : null,
        hwidTitle: AppLocalizations.of(context)!.subscriptionHwidTitle,
        hwidDescription: AppLocalizations.of(context)!
            .subscriptionHwidDescription,
        hwidEnabled: state.hwidEnabled,
        onHwidChanged: controller.setHwidEnabled,
        encryptionTitle: 'Encryption',
        ageProviderSupportTitle: 'Provider support required',
        ageProviderSupportDescription: 'Enter Age keys only when your provider supports encrypted subscriptions.',
        ageSecretKeyLabel: 'Age Secret Key',
        ageSecretKeyHint: 'AGE-SECRET-KEY-1...',
        ageSecretKeyController: secret,
        agePublicKeyLabel: 'Age Public Key',
        agePublicKeyHint: 'age1...',
        agePublicKeyController: public,
        obscureAgeSecretKey: obscure,
        revealAgeSecretKeyLabel: 'Reveal',
        hideAgeSecretKeyLabel: 'Hide',
        generateAgeKeyLabel: 'Generate',
        generateAgeX25519KeyLabel: 'X25519',
        generateAgeHybridKeyLabel: 'Hybrid (ML-KEM-768 + X25519)',
        clearAgeKeyLabel: 'Clear',
        onToggleAgeSecretKeyVisibility: () => revealed++,
        onGenerateAgeKey: generated.add,
        onClearAgeKey: controller.clearKeys,
        generatingAgeKeyType: generatingKey,
        hasAgeKeys: state.hasAgeKeys,
        ageExpanded: state.ageExpanded,
        onToggleAgeExpanded: controller.toggleAgeExpanded,
      ),
    ),
  );

  Widget app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalePolicy.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, appChild) =>
        ShadTheme(data: AppTheme.shad(Brightness.light), child: appChild!),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: child,
        ),
      ),
    ),
  );

  testWidgets('existing Age keys expose inline actions and busy guards', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    secret.text = 'AGE-SECRET-KEY-1EXISTING';
    public.text = 'age1existing';
    await tester.pumpWidget(app(form()));
    await tester.pumpAndSettle();

    expect(find.textContaining('VMessAEAD / VLESS, Hysteria2'), findsOneWidget);
    expect(find.text('HTTPS only'), findsOneWidget);
    expect(find.byType(ShadInput), findsNWidgets(4));
    expect(
      find.ancestor(
        of: find.byType(SubscriptionFormView),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('X25519'));
    await tester.tap(find.text('X25519'));
    await tester.ensureVisible(find.text('Hybrid (ML-KEM-768 + X25519)'));
    await tester.tap(find.text('Hybrid (ML-KEM-768 + X25519)'));
    expect(generated, [AgeKeyType.x25519, AgeKeyType.hybrid]);
    await tester.tap(find.byTooltip('Reveal'));
    expect(revealed, 1);
    await tester.pumpWidget(app(form(obscure: false)));
    expect(find.byTooltip('Hide'), findsOneWidget);
    expect(
      tester
          .widgetList<ShadInput>(find.byType(ShadInput))
          .firstWhere((input) => input.controller == secret)
          .obscureText,
      isFalse,
    );

    await tester.pumpWidget(app(form(generatingKey: AgeKeyType.hybrid)));
    for (final button in [
      find.widgetWithText(OutlinedButton, 'X25519'),
      find.widgetWithText(OutlinedButton, 'Hybrid (ML-KEM-768 + X25519)'),
      find.widgetWithText(TextButton, 'Clear'),
    ]) {
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
    }
    expect(find.byType(ButtonProgressIndicator), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(OutlinedButton, 'Hybrid (ML-KEM-768 + X25519)'),
        matching: find.byType(ButtonProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(OutlinedButton, 'X25519'),
        matching: find.byType(ButtonProgressIndicator),
      ),
      findsNothing,
    );
    for (final input in tester.widgetList<ShadInput>(find.byType(ShadInput))) {
      expect(
        input.enabled,
        input.controller == name || input.controller == url,
      );
    }
    await tester.tap(find.byTooltip('Reveal'));
    expect(revealed, 2);
    expect(generated, hasLength(2));
    await tester.pumpWidget(app(form()));
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(secret.text, isEmpty);
    expect(public.text, isEmpty);
    expect(find.byType(ShadInput), findsNWidgets(4));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Clear'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (locale, width) in const [
    (Locale('en'), 1000.0),
    (Locale('zh'), 390.0),
    (Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), 390.0),
    (Locale('ru'), 390.0),
    (Locale('fa'), 1000.0),
  ]) {
    testWidgets('format notice and HWID disclosure fit at $width ($locale)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      url.text = 'https://provider.example/list';
      await tester.pumpWidget(app(form(), locale: locale));
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(SubscriptionFormView)),
      )!;
      expect(l.prototypeSubscriptionDescription, contains('VMessAEAD / VLESS'));
      expect(l.prototypeSubscriptionDescription, contains('Hysteria2'));
      final formatNotice = tester.widget<Text>(
        find.text(l.prototypeSubscriptionDescription),
      );
      expect(formatNotice.maxLines, isNull);
      expect(formatNotice.overflow, isNull);
      final disclosure = tester.widget<Text>(
        find.text(l.subscriptionHwidDescription),
      );
      expect(disclosure.maxLines, isNull);
      expect(disclosure.overflow, isNull);
      expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isFalse);
      await tester.ensureVisible(find.text(l.subscriptionHwidTitle));
      await tester.tap(find.text(l.subscriptionHwidTitle));
      await tester.pumpAndSettle();
      expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isTrue);
      url.text = 'https://another.example/sub';
      await tester.pumpAndSettle();
      expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in const [Locale('en'), Locale('fa')]) {
    testWidgets(
      'empty Age is collapsed and loaded keys expand on phone ($locale)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(app(form(), locale: locale));
        await tester.pumpAndSettle();
        expect(find.byType(ShadInput), findsNWidgets(2));
        expect(find.text('Provider support required'), findsOneWidget);
        expect(find.text('Age Secret Key'), findsNothing);
        expect(
          find.ancestor(
            of: find.byType(SubscriptionFormView),
            matching: find.byType(SingleChildScrollView),
          ),
          findsOneWidget,
        );

        // Editing can load keys after the content has already mounted.
        secret.text = 'AGE-SECRET-KEY-1LOADED';
        expect(controller.state.hasAgeKeys, isTrue);
        expect(controller.state.ageExpanded, isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(ShadInput), findsNWidgets(4));
        for (final controller in [url, secret, public]) {
          final input = find.byWidgetPredicate(
            (widget) => widget is ShadInput && widget.controller == controller,
          );
          final editable = find.descendant(
            of: input,
            matching: find.byType(EditableText),
          );
          expect(
            Directionality.of(tester.element(editable)),
            TextDirection.ltr,
          );
        }
        await tester.ensureVisible(find.text('Clear'));
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(find.byType(ShadInput), findsNWidgets(4));
        await tester.ensureVisible(find.text('Encryption'));
        await tester.tap(find.text('Encryption'));
        await tester.pumpAndSettle();
        expect(find.byType(ShadInput), findsNWidgets(2));

        // Either key can reveal a loaded draft; changing a nonempty key does not
        // override a later manual collapse.
        public.text = 'age1loaded';
        await tester.pumpAndSettle();
        expect(find.byType(ShadInput), findsNWidgets(4));
        await tester.tap(find.text('Encryption'));
        await tester.pumpAndSettle();
        public.text = 'age1changed';
        await tester.pumpAndSettle();
        expect(find.byType(ShadInput), findsNWidgets(2));
        expect(public.text, 'age1changed');
        await tester.tap(find.text('Encryption'));
        await tester.pumpAndSettle();
        expect(find.byType(ShadInput), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('panel and new source mode selectors preserve automatic input', (
    tester,
  ) async {
    await tester.pumpWidget(app(form()));
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(
      tester.element(find.byType(SubscriptionFormView)),
    )!;
    expect(controller.state.panel, SubscriptionPanel.generic);
    expect(controller.state.mode, isNull);
    final panel = find.byKey(const ValueKey('subscription-panel'));
    final mode = find.byKey(const ValueKey('subscription-mode'));
    await tester.ensureVisible(panel);
    await tester.tap(panel);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remnawave'));
    await tester.pumpAndSettle();
    expect(controller.state.panel, SubscriptionPanel.remnawave);
    expect(controller.state.mode, isNull);
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.subscriptionModeProviderManaged));
    await tester.pumpAndSettle();
    expect(controller.state.mode, SubscriptionMode.providerManaged);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.subscriptionModeAutomatic));
    await tester.pumpAndSettle();
    expect(controller.state.mode, isNull);
    expect(controller.state.panel, SubscriptionPanel.remnawave);
    controller.emit(controller.state.copyWith(busy: true));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SettingSelect<SubscriptionPanel>>(panel).onChanged,
      isNull,
    );
    controller.setMode(SubscriptionMode.appManaged);
    controller.setPanel(SubscriptionPanel.generic);
    expect(controller.state.mode, isNull);
    expect(controller.state.panel, SubscriptionPanel.remnawave);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stored source mode dropdown offers only explicit modes', (
    tester,
  ) async {
    controller.setMode(SubscriptionMode.providerManaged);
    await tester.pumpWidget(app(form(automaticAllowed: false)));
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(
      tester.element(find.byType(SubscriptionFormView)),
    )!;
    final mode = find.byKey(const ValueKey('subscription-mode'));
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    expect(find.text(l.subscriptionModeAutomatic), findsNothing);
    expect(find.text(l.subscriptionModeAppManaged), findsOneWidget);
    await tester.tap(find.text(l.subscriptionModeAppManaged));
    await tester.pumpAndSettle();
    expect(controller.state.mode, SubscriptionMode.appManaged);
    expect(tester.takeException(), isNull);
  });
}
