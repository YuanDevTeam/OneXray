import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/language/locale.dart';

void main() {
  for (final (platform, minimum) in [
    (TargetPlatform.iOS, 44.0),
    (TargetPlatform.android, 48.0),
  ]) {
    testWidgets('$platform keeps touch targets in a wide window', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(956, 440));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var selection = '';
      var backs = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.material(Brightness.light),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  SettingSelect<String>(
                    value: 'first',
                    entries: const {'first': 'First', 'second': 'Second'},
                    onChanged: (value) => selection = value!,
                  ),
                  TextButton(
                    onPressed: () => showAppDialog<void>(
                      context,
                      (_) => AppDialog(
                        title: 'Touch controls',
                        onBack: () => backs++,
                        body: const SizedBox(height: 40),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final select = find.byType(SettingSelect<String>);
      expect(tester.getSize(select).height, greaterThanOrEqualTo(minimum));
      final selectRect = tester.getRect(select);
      await tester.tapAt(selectRect.bottomLeft + const Offset(2, -2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();
      expect(selection, 'second');

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final back = find.widgetWithText(TextButton, 'Back');
      final close = find.byTooltip('Close dialog');
      for (final target in [back, close]) {
        final size = tester.getSize(target);
        expect(size.width, greaterThanOrEqualTo(minimum));
        expect(size.height, greaterThanOrEqualTo(minimum));
      }
      await tester.tapAt(tester.getRect(back).topLeft + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(backs, 1);
      await tester.tapAt(
        tester.getRect(close).bottomRight - const Offset(2, 2),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(backs, 1);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }
}
