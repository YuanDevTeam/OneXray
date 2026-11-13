import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/settings/app_icon/controller.dart';
import 'package:onexray/pages/settings/app_icon/page.dart';
import 'package:onexray/pages/settings/language/controller.dart';
import 'package:onexray/pages/settings/language/page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  Widget app(Locale locale, Widget child) => MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalePolicy.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => ShadTheme(
      data: AppTheme.shad(Brightness.light, mobile: true),
      child: child ?? const SizedBox.shrink(),
    ),
    home: Scaffold(body: child),
  );

  test('language selection stays a draft until save', () async {
    final bus = AppEventBus();
    final initial = bus.state.languageCode;
    final controller = LanguageController();
    controller.updateLanguageCode(LanguageCode.fa);
    expect(controller.state.languageCode, LanguageCode.fa);
    expect(bus.state.languageCode, initial);
    await controller.close();
    expect(bus.state.languageCode, initial);
    await bus.close();
  });

  for (final locale in const [
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('en'),
    Locale('ru'),
    Locale('fa'),
  ]) {
    for (final size in const [
      Size(390, 844),
      Size(1032, 1376),
      Size(1160, 720),
    ]) {
      testWidgets(
        'settings language and icon choices fit ${locale.toLanguageTag()} at $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          LanguageCode? language;
          await tester.pumpWidget(
            app(
              locale,
              LanguageChoiceView(
                selected: LanguageCode.zh,
                onSelected: (value) => language = value,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byType(ShadSelect<LanguageCode>));
          await tester.pumpAndSettle();
          for (final label in ['简体中文', '繁體中文', 'English', 'Русский', 'فارسی']) {
            expect(find.text(label), findsWidgets);
          }
          await tester.tap(find.text('فارسی').last);
          await tester.pumpAndSettle();
          expect(language, LanguageCode.fa);
          expect(tester.takeException(), isNull);

          AppIcon? icon;
          await tester.pumpWidget(
            app(
              locale,
              Builder(
                builder: (context) => AppIconChoiceView(
                  selected: AppIcon.primary,
                  useDockIconAssets: false,
                  onSelected: (value) => icon = value,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(AppIconChoiceView)),
          )!;
          expect(find.text(l10n.settingsHomeScreenIcon), findsOneWidget);
          final icons = find.byType(Image);
          expect(icons, findsOneWidget);
          expect(tester.getSize(icons.first), const Size(96, 96));
          await tester.tap(find.byType(ShadSelect<AppIcon>));
          await tester.pumpAndSettle();
          for (final option in AppIcon.values) {
            expect(find.text(appIconLabel(l10n, option)), findsWidgets);
          }
          await tester.tap(find.text(l10n.prototypeIconBlack).last);
          await tester.pumpAndSettle();
          expect(icon, AppIcon.black);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
