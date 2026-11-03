import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadButton;

const _size = Size(390, 844);
const _safeBottom = 34.0;

Future<void> _openDialog(
  WidgetTester tester,
  WidgetBuilder dialog, {
  required ValueNotifier<double> keyboard,
  Size size = _size,
  double safeBottom = _safeBottom,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.material(Brightness.light, mobile: true),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => ValueListenableBuilder<double>(
        valueListenable: keyboard,
        builder: (context, inset, _) => MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: EdgeInsets.only(bottom: math.max(0, safeBottom - inset)),
            viewPadding: EdgeInsets.only(bottom: safeBottom),
            viewInsets: EdgeInsets.only(bottom: inset),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppDialog<void>(context, dialog),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [
    Size(390, 844),
    Size(1032, 1376),
    Size(1160, 720),
  ]) {
    testWidgets('ordinary dialog follows the prototype surface at $size', (
      tester,
    ) async {
      final keyboard = ValueNotifier(0.0);
      addTearDown(keyboard.dispose);
      await _openDialog(
        tester,
        (context) => AppDialog(
          title: 'Dialog title',
          subtitle: 'Supporting description',
          body: const SizedBox(height: 80),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
        keyboard: keyboard,
        size: size,
        safeBottom: 0,
      );
      final surface = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AppDialog),
              matching: find.byType(Material),
            )
            .first,
      );
      final palette = ColorManager.palette(
        tester.element(find.byType(AppDialog)),
      );
      expect(surface.color, palette.background);
      expect(
        (surface.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(size.width < 640 ? 0 : 8),
      );
      final title = tester.widget<Text>(find.text('Dialog title'));
      final description = tester.widget<Text>(
        find.text('Supporting description'),
      );
      expect(title.style!.fontSize, 16);
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(description.style!.fontSize, 13);
      expect(description.style!.color, palette.mutedForeground);
      final surfaceRect = tester.getRect(
        find
            .descendant(
              of: find.byType(AppDialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(surfaceRect.center.dy, closeTo(size.height / 2, .01));
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
    });
  }

  testWidgets('short dialog scrolls large action labels without shrinking', (
    tester,
  ) async {
    final keyboard = ValueNotifier(0.0);
    addTearDown(keyboard.dispose);
    var calls = 0;
    const label = 'Apply the saved configuration and reconnect';
    await _openDialog(
      tester,
      (context) => ShadTheme(
        data: AppTheme.shad(Brightness.light, mobile: true),
        child: AppDialog(
          title: 'Changes',
          body: const SizedBox(height: 1000),
          actions: [
            ShadButton(
              onPressed: () {
                calls++;
                Navigator.pop(context);
              },
              child: const Text(label),
            ),
          ],
        ),
      ),
      keyboard: keyboard,
      size: const Size(390, 360),
      safeBottom: 0,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    expect(find.text(label).hitTestable(), findsOneWidget);
    expect(
      DefaultTextStyle.of(tester.element(find.text(label))).style.fontSize,
      14,
    );
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(AppDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wizard hides the covered card and restores its live draft', (
    tester,
  ) async {
    final keyboard = ValueNotifier(0.0);
    addTearDown(keyboard.dispose);
    var disposed = 0;
    var customCloseCalls = 0;
    await _openDialog(
      tester,
      (context) => AppDialog(
        title: 'First step',
        body: _DraftField(onDispose: () => disposed++),
        actions: [
          FilledButton(
            onPressed: () => showAppDialog<void>(
              context,
              (context) => AppDialog(
                title: 'Second step',
                body: const SizedBox(height: 100),
                onBack: () => Navigator.of(context).pop(),
                onClose: () {
                  customCloseCalls++;
                  Navigator.of(context).pop();
                },
              ),
            ),
            child: const Text('Next'),
          ),
        ],
      ),
      keyboard: keyboard,
    );
    await tester.enterText(find.byType(TextField), 'Draft to preserve');
    final originalState = tester.state(find.byType(_DraftField));

    for (final useBack in [true, false]) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.byType(AppDialog, skipOffstage: false), findsNWidgets(2));
      expect(find.text('First step'), findsNothing);
      expect(find.text('Second step'), findsOneWidget);
      expect(disposed, 0);
      expect(
        tester.state(find.byType(_DraftField, skipOffstage: false)),
        same(originalState),
      );

      final l = AppLocalizations.of(tester.element(find.byType(AppDialog)))!;
      await tester.tap(
        useBack
            ? find.text(l.prototypeBack)
            : find.byTooltip(l.prototypeCloseDialog),
      );
      await tester.pumpAndSettle();
      expect(find.text('First step'), findsOneWidget);
      expect(find.text('Second step'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Draft to preserve',
      );
      expect(tester.state(find.byType(_DraftField)), same(originalState));
      expect(disposed, 0);
    }
    expect(customCloseCalls, 1);
    final l = AppLocalizations.of(tester.element(find.byType(AppDialog)))!;
    await tester.tap(find.byTooltip(l.prototypeCloseDialog));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(disposed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard keeps centered modal and actions inside the usable area',
    (tester) async {
      final keyboard = ValueNotifier(0.0);
      addTearDown(keyboard.dispose);
      await _openDialog(
        tester,
        (context) => AppDialog(
          title: 'Editor',
          body: const SizedBox(height: 1000),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
        keyboard: keyboard,
      );

      for (final inset in [0.0, 300.0, 0.0]) {
        keyboard.value = inset;
        await tester.pumpAndSettle();
        final surface = find
            .descendant(
              of: find.byType(AppDialog),
              matching: find.byType(Material),
            )
            .first;
        expect(
          tester.getRect(surface).bottom,
          lessThanOrEqualTo(_size.height - math.max(inset, _safeBottom)),
        );
        expect(
          tester.getRect(surface).center.dy,
          closeTo((_size.height - math.max(inset, _safeBottom)) / 2, .01),
        );
        if (inset == 0) {
          expect(
            tester.getRect(surface).height - _safeBottom,
            closeTo(
              math.min(
                AppLayout.dialogMaxHeight,
                _size.height * AppLayout.dialogMobileHeightFactor,
              ),
              0.01,
            ),
          );
        }
        expect(
          tester.getRect(find.byType(FilledButton)).bottom,
          lessThanOrEqualTo(_size.height - math.max(inset, _safeBottom)),
        );
        expect(tester.getRect(surface).top, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
    },
  );
}

class _DraftField extends StatefulWidget {
  const _DraftField({required this.onDispose});
  final VoidCallback onDispose;

  @override
  State<_DraftField> createState() => _DraftFieldState();
}

class _DraftFieldState extends State<_DraftField> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: controller);
}
