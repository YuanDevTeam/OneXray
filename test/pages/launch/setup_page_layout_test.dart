import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/launch/setup/page.dart';
import 'package:onexray/pages/launch/setup/selectors.dart';
import 'package:onexray/pages/launch/setup/widgets.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';
import 'package:onexray/service/launch/setup.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _host(
  Widget child, {
  Locale locale = const Locale('en'),
  double scale = 1,
  double keyboard = 0,
}) => MaterialApp(
  theme: AppTheme.light,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: ShadTheme(data: AppTheme.shad(Brightness.light), child: child!),
  ),
  home: child,
);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _footerText(String text) =>
    find.descendant(of: find.byType(PageActionBar), matching: find.text(text));

void main() {
  for (final scenario in const [
    (size: Size(390, 667), scale: 1.5, keyboard: 200.0, locale: Locale('ru')),
    (size: Size(768, 600), scale: 2.0, keyboard: 0.0, locale: Locale('fa')),
    (size: Size(844, 390), scale: 1.5, keyboard: 0.0, locale: Locale('en')),
    (size: Size(1160, 720), scale: 1.0, keyboard: 0.0, locale: Locale('en')),
  ]) {
    for (final step in [SetupStep.welcome, SetupStep.configuration]) {
      testWidgets('setup $step keeps page actions fixed in $scenario', (
        tester,
      ) async {
        _size(tester, scenario.size);
        final actions = <SetupAction>[];
        await tester.pumpWidget(
          _host(
            SetupView(
              state: SetupPageState(
                step: step,
                busy: false,
                localReady: true,
                interfaceName: 'Ethernet',
                regions: const ['RU'],
              ),
              requiresInterface: true,
              onAction: actions.add,
            ),
            locale: scenario.locale,
            scale: scenario.scale,
            keyboard: scenario.keyboard,
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(tester.element(find.byType(SetupView)))!;
        final label = step == SetupStep.welcome
            ? l.prototypeAgreeAndContinue
            : l.prototypeGoToHome;
        final footerAction = _footerText(label);
        final footerRect = tester.getRect(find.byType(PageActionBar));
        expect(find.byType(PageAppBar), findsOneWidget);
        final progress = tester.widget<SetupProgress>(
          find.byType(SetupProgress),
        );
        expect(progress.current, step == SetupStep.welcome ? 0 : 1);
        expect(find.byType(ShadCard), findsNothing);
        expect(footerAction.hitTestable(), findsOneWidget);
        expect(
          tester.getBottomRight(footerAction).dy,
          lessThanOrEqualTo(scenario.size.height - scenario.keyboard),
        );
        expect(
          find.ancestor(of: footerAction, matching: find.byType(Scrollable)),
          findsNothing,
        );
        await tester.drag(
          find.descendant(
            of: find.byType(SetupBody),
            matching: find.byType(SingleChildScrollView),
          ),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(PageActionBar)), footerRect);
        await tester.tap(footerAction);
        expect(actions, [
          step == SetupStep.welcome
              ? SetupAction.acceptPrivacy
              : SetupAction.finish,
        ]);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('wide setup aligns content and actions to the same column', (
    tester,
  ) async {
    _size(tester, const Size(1160, 760));
    await tester.pumpWidget(
      _host(
        SetupView(
          state: const SetupPageState(busy: false),
          requiresInterface: false,
          onAction: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byType(Card).first);
    final action = tester.getRect(find.byType(FilledButton));
    expect(card.right, closeTo(action.right, 1));
    expect(card.left, greaterThan(150));
    expect(card.width, lessThan(760));
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy keeps its return action outside the scrolling text', (
    tester,
  ) async {
    _size(tester, const Size(390, 600));
    var returned = 0;
    var opened = 0;
    await tester.pumpWidget(
      _host(
        SetupPrivacyView(
          failureText: 'The privacy policy could not be opened.',
          onBack: () => returned++,
          onOpenPolicy: () => opened++,
        ),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PageAppBar), findsOneWidget);
    expect(find.byType(ShadCard), findsNothing);
    expect(_footerText('Back').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('Read the full privacy policy'));
    await tester.tap(find.text('Read the full privacy policy'));
    expect(opened, 1);
    await tester.ensureVisible(
      find.text('The privacy policy could not be opened.'),
    );
    expect(_footerText('Back').hitTestable(), findsOneWidget);
    await tester.tap(_footerText('Back'));
    expect(returned, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'interface page cancels without a result and returns a chosen name',
    (tester) async {
      _size(tester, const Size(768, 600));
      String? result;
      var returned = false;
      final router = GoRouter(
        initialLocation: '/setup',
        routes: [
          GoRoute(
            path: '/setup',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await context.push<String>(
                    '/setup/interface',
                    extra: SetupInterfaceParams([
                      for (var i = 0; i < 30; i++)
                        OutboundInterfaceOption('Ethernet $i', const [
                          '192.0.2.1',
                        ], i == 0),
                    ], 'Ethernet 0'),
                  );
                  returned = true;
                },
                child: const Text('Open interface'),
              ),
            ),
          ),
          GoRoute(
            path: '/setup/interface',
            builder: (_, state) => SetupInterfacePage(
              params: state.extra! as SetupInterfaceParams,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: ShadTheme(
              data: AppTheme.shad(Brightness.light),
              child: child!,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open interface'));
      await tester.pumpAndSettle();
      expect(find.byType(PageAppBar), findsOneWidget);
      expect(_footerText('Back').hitTestable(), findsOneWidget);
      await tester.tap(_footerText('Back'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, isNull);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/setup');
      returned = false;
      await tester.tap(find.text('Open interface'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Ethernet 29'),
        300,
        scrollable: find.descendant(
          of: find.byType(SetupInterfacePage),
          matching: find.byType(Scrollable),
        ),
      );
      expect(_footerText('Back').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Ethernet 29'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, 'Ethernet 29');
      expect(router.routerDelegate.currentConfiguration.uri.path, '/setup');
      expect(tester.takeException(), isNull);
    },
  );
}
