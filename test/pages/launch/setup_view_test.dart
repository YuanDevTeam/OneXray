import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/launch/setup/page.dart';
import 'package:onexray/pages/launch/setup/widgets.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/launch/setup.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  bool mobile = true,
}) => MaterialApp(
  theme: AppTheme.material(Brightness.light, mobile: mobile),
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  builder: (context, child) => ShadTheme(
    data: AppTheme.shad(Brightness.light, mobile: mobile),
    child: child!,
  ),
  home: child,
);

void _size(WidgetTester tester, bool mobile) {
  tester.view.physicalSize = mobile
      ? const Size(390, 844)
      : const Size(1160, 688);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  for (final locale in const [
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ru'),
    Locale('fa'),
  ]) {
    testWidgets('welcome preserves privacy actions and layout in $locale', (
      tester,
    ) async {
      _size(tester, true);
      final actions = <SetupAction>[];
      await tester.pumpWidget(
        _app(
          SetupView(
            state: const SetupPageState(busy: false),
            requiresInterface: false,
            onAction: actions.add,
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(tester.element(find.byType(SetupView)))!;
      expect(find.byType(ShadCard), findsNothing);
      expect(find.byType(PageAppBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PageAppBar),
          matching: find.text(l.prototypeWelcome),
        ),
        findsOneWidget,
      );
      for (final text in [
        l.prototypeWelcomeSubtitle,
        l.prototypeNoDataCollection,
        l.prototypeBringOwnServers,
      ]) {
        expect(
          find.descendant(
            of: find.byType(SetupBody),
            matching: find.text(text),
          ),
          findsOneWidget,
        );
      }
      expect(
        tester.getTopLeft(find.text(l.prototypeWelcomeSubtitle)).dy,
        closeTo(tester.getBottomLeft(find.byType(PageAppBar)).dy + 16, 1),
      );
      final continueButton = find.descendant(
        of: find.byType(PageActionBar),
        matching: find.widgetWithText(
          FilledButton,
          l.prototypeAgreeAndContinue,
        ),
      );
      expect(continueButton, findsOneWidget);
      expect(
        find.ancestor(of: continueButton, matching: find.byType(Scrollable)),
        findsNothing,
      );
      await tester.ensureVisible(find.text(l.prototypePrivacyPolicy));
      await tester.tap(find.text(l.prototypePrivacyPolicy));
      await tester.tap(find.text(l.prototypeAgreeAndContinue));
      expect(actions, [SetupAction.privacy, SetupAction.acceptPrivacy]);
      expect(tester.takeException(), isNull);
    });

    for (final mobile in [true, false]) {
      testWidgets('combined step fits $locale, mobile=$mobile', (tester) async {
        _size(tester, mobile);
        final actions = <SetupAction>[];
        await tester.pumpWidget(
          _app(
            SetupView(
              state: const SetupPageState(
                step: SetupStep.configuration,
                busy: false,
                localReady: true,
                interfaceName: 'Ethernet',
                regions: ['RU'],
              ),
              requiresInterface: true,
              onAction: actions.add,
            ),
            locale: locale,
            mobile: mobile,
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(tester.element(find.byType(SetupView)))!;
        expect(find.text(l.prototypeXrayOutboundInterface), findsOneWidget);
        expect(find.text('Ethernet'), findsOneWidget);
        expect(find.text(l.prototypeRegionPurpose), findsOneWidget);
        expect(find.text(l.prototypeSetUpVpn), findsNothing);
        expect(find.text(l.prototypeAddServers), findsNothing);
        expect(find.text(l.prototypeVpnPermission), findsNothing);
        expect(find.byType(ShadCard), findsNothing);
        expect(
          find.descendant(
            of: find.byType(PageActionBar),
            matching: find.text(l.prototypeGoToHome),
          ),
          findsOneWidget,
        );
        await tester.drag(
          find.descendant(
            of: find.byType(SetupBody),
            matching: find.byType(SingleChildScrollView),
          ),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(l.prototypeGoToHome));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.prototypeGoToHome));
        expect(actions, [SetupAction.finish]);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final requiresInterface in [true, false]) {
    testWidgets(
      'only applicable platforms require an interface: $requiresInterface',
      (tester) async {
        _size(tester, true);
        final actions = <SetupAction>[];
        await tester.pumpWidget(
          _app(
            SetupView(
              state: const SetupPageState(
                step: SetupStep.configuration,
                busy: false,
                localReady: true,
              ),
              requiresInterface: requiresInterface,
              onAction: actions.add,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Xray outbound interface'),
          requiresInterface ? findsOneWidget : findsNothing,
        );
        expect(find.text('Choose your country or region'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Go to Home'),
              )
              .onPressed,
          requiresInterface ? isNull : isNotNull,
        );
        await tester.tap(find.text('Choose your country or region'));
        expect(actions, [SetupAction.chooseRegion]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'finishing uses button loading and preparation failures allow retry',
    (tester) async {
      _size(tester, true);
      final actions = <SetupAction>[];
      await tester.pumpWidget(
        _app(
          SetupView(
            state: const SetupPageState(
              step: SetupStep.configuration,
              localReady: true,
              activeAction: SetupAction.finish,
            ),
            requiresInterface: false,
            onAction: actions.add,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ButtonProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.pumpWidget(
        _app(
          SetupView(
            state: const SetupPageState(
              step: SetupStep.configuration,
              busy: false,
              failure: SetupFailure('local'),
            ),
            failureText: 'Temporarily unavailable',
            requiresInterface: false,
            onAction: actions.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Temporarily unavailable'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      expect(actions, [SetupAction.retry]);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Go to Home'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
