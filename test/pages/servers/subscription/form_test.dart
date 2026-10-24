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
        nameErrorText: controller.subscriptionFieldError(
          AppLocalizations.of(context)!,
          SubscriptionFormField.name,
        ),
        nameFocusNode: controller.subscriptionFocusNode(
          SubscriptionFormField.name,
        ),
        urlLabel: 'URL',
        urlController: url,
        userAgentController: controller.userAgent,
        urlHint: 'https://provider.example/subscription',
        urlHelper: 'HTTPS only',
        urlErrorText: controller.subscriptionFieldError(
          AppLocalizations.of(context)!,
          SubscriptionFormField.url,
        ),
        urlFocusNode: controller.subscriptionFocusNode(
          SubscriptionFormField.url,
        ),
        userAgentErrorText: controller.subscriptionFieldError(
          AppLocalizations.of(context)!,
          SubscriptionFormField.userAgent,
        ),
        userAgentFocusNode: controller.subscriptionFocusNode(
          SubscriptionFormField.userAgent,
        ),
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
        ageKeyPairErrorText: state.incompleteKeys
            ? AppLocalizations.of(context)!.prototypeAgeBothKeysRequired
            : null,
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

  Widget app(
    Widget child, {
    Locale locale = const Locale('en'),
    TargetPlatform? platform,
  }) => MaterialApp(
    theme: AppTheme.light.copyWith(platform: platform),
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

  Future<void> toggleAdvanced(WidgetTester tester) async {
    final advanced = find.byKey(const ValueKey('subscription-advanced'));
    await tester.ensureVisible(advanced);
    await tester.tap(advanced);
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('visible field labels retain the $platform traversal policy', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        name.text = 'Provider';
        await tester.pumpWidget(app(form(), platform: platform));
        await tester.pumpAndSettle();
        final heading = find.text('Name');
        final excluded = find.ancestor(
          of: heading,
          matching: find.byType(ExcludeSemantics),
        );
        expect(
          excluded,
          platform == TargetPlatform.macOS ? findsNothing : findsOneWidget,
        );
        if (platform == TargetPlatform.macOS) {
          expect(tester.getSemantics(heading).getSemanticsData().label, 'Name');
        }
        final editable = find.byWidgetPredicate(
          (widget) => widget is EditableText && widget.controller == name,
        );
        final data = tester.getSemantics(editable).getSemanticsData();
        expect(data.label, 'Name');
        expect(data.value, 'Provider');
        expect(data.flagsCollection.isTextField, isTrue);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('editable semantics retain field names after entering values', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      name.text = 'Provider';
      url.text = 'https://provider.example/subscription';
      controller.userAgent.text = 'Example/1.0';
      await tester.pumpWidget(app(form()));
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(SubscriptionFormView)),
      )!;
      Finder editable(TextEditingController field) => find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.controller == field,
      );
      for (final (field, label) in [
        (name, 'Name'),
        (url, 'URL'),
        (controller.userAgent, l.subscriptionUserAgentTitle),
      ]) {
        await tester.ensureVisible(editable(field));
        final data = tester.getSemantics(editable(field)).getSemanticsData();
        expect(data.label, label);
        expect(data.value, field.text);
        expect(data.flagsCollection.isTextField, isTrue);
        await tester.enterText(editable(field), '');
        await tester.pump();
        expect(
          tester.getSemantics(editable(field)).getSemanticsData().label,
          label,
        );
      }
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Age key semantics keep labels and conceal the secret', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      secret.text = 'AGE-SECRET-KEY-1EXAMPLE';
      public.text = 'age1example';
      await tester.pumpWidget(app(form()));
      await tester.pumpAndSettle();
      final editable = find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.controller == secret,
      );
      await tester.ensureVisible(editable);
      var data = tester.getSemantics(editable).getSemanticsData();
      expect(data.label, 'Age Secret Key');
      expect(data.flagsCollection.isObscured, isTrue);
      expect(data.value, isNot(contains(secret.text)));
      await tester.pumpWidget(app(form(obscure: false)));
      await tester.pumpAndSettle();
      data = tester.getSemantics(editable).getSemanticsData();
      expect(data.label, 'Age Secret Key');
      expect(data.flagsCollection.isObscured, isFalse);
      expect(data.value, secret.text);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'field errors follow editing and blur without marking an empty draft',
    (tester) async {
      try {
        await tester.pumpWidget(app(form()));
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(SubscriptionFormView)),
        )!;
        Finder input(TextEditingController field) => find.byWidgetPredicate(
          (widget) => widget is ShadInput && widget.controller == field,
        );
        expect(find.text(l.validationNameRequired), findsNothing);
        expect(find.text(l.validationUrlRequired), findsNothing);
        expect(controller.canSubmit(ServerImportAction.subscription), isFalse);

        controller
            .subscriptionFocusNode(SubscriptionFormField.name)
            .requestFocus();
        await tester.pump();
        controller
            .subscriptionFocusNode(SubscriptionFormField.url)
            .requestFocus();
        await tester.pump();
        expect(find.text(l.validationNameRequired), findsOneWidget);
        expect(find.text(l.validationUrlRequired), findsNothing);
        expect(
          tester.widget<ShadInput>(input(name)).decoration!.hasError,
          isTrue,
        );

        await tester.enterText(input(name), 'Provider');
        await tester.pump();
        expect(find.text(l.validationNameRequired), findsNothing);
        // URL was visited before leaving it to edit the name.
        expect(find.text(l.validationUrlRequired), findsOneWidget);
        await tester.enterText(input(url), 'http://provider.example/list');
        await tester.pump(const Duration(seconds: 3));
        expect(find.text(l.validationUrlInvalid), findsOneWidget);
        expect(
          tester.widget<ShadInput>(input(url)).decoration!.hasError,
          isTrue,
        );
        expect(controller.canSubmit(ServerImportAction.subscription), isFalse);
        expect(controller.state.error, isNull);

        await tester.enterText(input(url), 'https://provider.example/list');
        await tester.pump();
        expect(find.text(l.validationUrlInvalid), findsNothing);
        expect(controller.canSubmit(ServerImportAction.subscription), isTrue);
        final userAgentFocus = controller.subscriptionFocusNode(
          SubscriptionFormField.userAgent,
        );
        await tester.ensureVisible(input(controller.userAgent));
        await tester.pumpAndSettle();
        await tester.tap(input(controller.userAgent));
        await tester.pumpAndSettle();
        expect(userAgentFocus.hasFocus, isTrue);
        await tester.enterText(input(controller.userAgent), 'Example/示例');
        await tester.pumpAndSettle();
        expect(userAgentFocus.hasFocus, isTrue);
        expect(find.text(l.subscriptionUserAgentInvalid), findsNothing);
        await tester.ensureVisible(input(url));
        await tester.pumpAndSettle();
        await tester.tap(input(url));
        await tester.pumpAndSettle();
        expect(userAgentFocus.hasFocus, isFalse);
        expect(
          controller.subscriptionFocusNode(SubscriptionFormField.url).hasFocus,
          isTrue,
        );
        expect(find.text(l.subscriptionUserAgentInvalid), findsOneWidget);
        expect(controller.canSubmit(ServerImportAction.subscription), isFalse);
        await tester.enterText(input(controller.userAgent), '');
        await tester.pump();
        expect(find.text(l.subscriptionUserAgentInvalid), findsNothing);
        expect(controller.canSubmit(ServerImportAction.subscription), isTrue);
        expect(controller.state.error, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
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

    expect(find.text('HTTPS only'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ShadInput && widget.controller == secret,
      ),
      findsOneWidget,
    );
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
        input.controller == name ||
            input.controller == url ||
            input.controller == controller.userAgent,
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
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ShadInput && widget.controller == secret,
      ),
      findsOneWidget,
    );
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
    testWidgets(
      'subscription explanations open without changing the draft at $width ($locale)',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        url.text = 'https://provider.example/list';
        await tester.pumpWidget(app(form(), locale: locale));
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(SubscriptionFormView)),
        )!;
        expect(
          l.prototypeSubscriptionDescription,
          contains('VMessAEAD / VLESS'),
        );
        expect(l.prototypeSubscriptionDescription, contains('Hysteria2'));
        await toggleAdvanced(tester);
        for (final (title, message) in [
          (l.subscriptionPanelTitle, l.prototypeSubscriptionDescription),
          (l.subscriptionHwidTitle, l.subscriptionHwidDescription),
        ]) {
          expect(find.text(message), findsNothing);
          final help = find.byTooltip('${l.pageHelp} · $title');
          await tester.ensureVisible(help);
          await tester.tap(help);
          await tester.pumpAndSettle();
          expect(find.text(message), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip(l.prototypeCloseDialog));
          await tester.pumpAndSettle();
          expect(url.text, 'https://provider.example/list');
        }
        expect(
          tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value,
          isFalse,
        );
        await tester.ensureVisible(find.text(l.subscriptionHwidTitle));
        await tester.tap(find.text(l.subscriptionHwidTitle));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value,
          isTrue,
        );
        url.text = 'https://another.example/sub';
        await tester.pumpAndSettle();
        expect(
          tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final locale in const [Locale('en'), Locale('fa')]) {
    testWidgets(
      'empty Age is collapsed and loaded keys expand on phone ($locale)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(app(form(), locale: locale));
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) => widget is ShadInput && widget.controller == secret,
          ),
          findsNothing,
        );
        expect(find.text('Provider support required'), findsNothing);
        expect(find.byType(ShadSwitch), findsNothing);
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
        expect(find.text('Provider support required'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is ShadInput && widget.controller == secret,
          ),
          findsOneWidget,
        );
        for (final fieldController in [
          url,
          controller.userAgent,
          secret,
          public,
        ]) {
          final input = find.byWidgetPredicate(
            (widget) =>
                widget is ShadInput && widget.controller == fieldController,
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
        expect(find.text('Provider support required'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is ShadInput && widget.controller == secret,
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Encryption'));
        await tester.tap(find.text('Encryption'));
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) => widget is ShadInput && widget.controller == secret,
          ),
          findsNothing,
        );

        // Either key can reveal a loaded draft; changing a nonempty key does not
        // override a later manual collapse.
        public.text = 'age1loaded';
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) => widget is ShadInput && widget.controller == secret,
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Encryption'));
        await tester.pumpAndSettle();
        public.text = 'age1changed';
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) => widget is ShadInput && widget.controller == secret,
          ),
          findsNothing,
        );
        expect(public.text, 'age1changed');
        await tester.tap(find.text('Encryption'));
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) => widget is ShadInput && widget.controller == secret,
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('manually collapsing Advanced preserves configured drafts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    name.text = 'Example provider';
    url.text = 'https://provider.example/list';
    controller.userAgent.text = 'OneXrayAudit/1.0';
    secret.text = 'AGE-SECRET-KEY-1EXISTING';
    public.text = 'age1existing';
    controller.setHwidEnabled(true);
    await tester.pumpWidget(app(form()));
    await tester.pumpAndSettle();
    Finder input(TextEditingController field) => find.byWidgetPredicate(
      (widget) => widget is ShadInput && widget.controller == field,
    );
    expect(input(secret), findsOneWidget);
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isTrue);

    await toggleAdvanced(tester);
    expect(input(secret), findsNothing);
    expect(input(public), findsNothing);
    expect(find.byType(ShadSwitch), findsNothing);
    for (final field in [name, url, controller.userAgent]) {
      expect(input(field), findsOneWidget);
    }

    name.text = 'Renamed provider';
    await tester.pumpAndSettle();
    expect(input(secret), findsNothing);
    expect(controller.state.hwidEnabled, isTrue);
    expect(url.text, 'https://provider.example/list');
    expect(controller.userAgent.text, 'OneXrayAudit/1.0');
    expect(secret.text, 'AGE-SECRET-KEY-1EXISTING');
    expect(public.text, 'age1existing');

    await toggleAdvanced(tester);
    expect(input(secret), findsOneWidget);
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isTrue);
    controller.setHwidEnabled(false);
    controller.clearKeys();
    await tester.pumpAndSettle();
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isFalse);
    expect(find.text('Provider support required'), findsOneWidget);
    expect(input(secret), findsOneWidget);
    expect(secret.text, isEmpty);
    expect(public.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HWID loaded after mounting automatically reveals Advanced', (
    tester,
  ) async {
    url.text = 'https://provider.example/list';
    await tester.pumpWidget(app(form()));
    await tester.pumpAndSettle();
    expect(find.byType(ShadSwitch), findsNothing);
    expect(find.text('Provider support required'), findsNothing);

    controller.setHwidEnabled(true);
    await tester.pumpAndSettle();
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isTrue);
    expect(find.text('Provider support required'), findsOneWidget);
    expect(find.text('Age Secret Key'), findsNothing);

    await toggleAdvanced(tester);
    name.text = 'Renamed provider';
    await tester.pumpAndSettle();
    expect(find.byType(ShadSwitch), findsNothing);
    expect(controller.state.hwidEnabled, isTrue);
    controller.setHwidEnabled(false);
    await tester.pumpAndSettle();
    expect(find.byType(ShadSwitch), findsNothing);
    controller.setHwidEnabled(true);
    await tester.pumpAndSettle();
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isTrue);
    expect(tester.takeException(), isNull);
  });

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
