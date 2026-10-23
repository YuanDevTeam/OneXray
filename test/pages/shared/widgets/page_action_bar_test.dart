import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _cancel = Key('footer-cancel');
const _save = Key('footer-save');

Widget _app({
  required bool shad,
  bool mobile = true,
  double bottomInset = 0,
  String saveLabel = 'Save',
  VoidCallback? onCancel,
  VoidCallback? onSave,
}) => MaterialApp(
  theme: AppTheme.material(Brightness.light, mobile: mobile),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.noScaling,
      padding: EdgeInsets.only(bottom: bottomInset),
      viewPadding: EdgeInsets.only(bottom: bottomInset),
    ),
    child: ShadTheme(
      data: AppTheme.shad(Brightness.light, mobile: mobile),
      child: child!,
    ),
  ),
  home: Scaffold(
    body: const SizedBox.expand(),
    bottomNavigationBar: PageActionBar(
      children: shad
          ? [
              ShadButton.outline(
                key: _cancel,
                onPressed: onCancel ?? () {},
                child: const Text('Cancel'),
              ),
              ShadButton(
                key: _save,
                onPressed: onSave ?? () {},
                child: Text(saveLabel),
              ),
            ]
          : [
              OutlinedButton(
                key: _cancel,
                onPressed: onCancel ?? () {},
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: _save,
                onPressed: onSave ?? () {},
                child: Text(saveLabel),
              ),
            ],
    ),
  ),
);

void main() {
  for (final shad in [false, true]) {
    final variant = shad ? 'Shad' : 'Material';

    for (final (platform, buttonHeight) in [
      (TargetPlatform.iOS, 46.0),
      (TargetPlatform.android, 48.0),
    ]) {
      testWidgets(
        '$variant ${platform.name} footer keeps equal buttons and 12px text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(427, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final actions = <String>[];
          await tester.pumpWidget(
            _app(
              shad: shad,
              bottomInset: 24,
              onCancel: () => actions.add('cancel'),
              onSave: () => actions.add('save'),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            MediaQuery.sizeOf(tester.element(find.byType(PageActionBar))).width,
            427,
          );
          final bar = tester.getRect(find.byType(PageActionBar));
          final cancel = tester.getRect(find.byKey(_cancel));
          final save = tester.getRect(find.byKey(_save));
          expect(cancel.width, closeTo(save.width, 0.01));
          expect(cancel.height, buttonHeight);
          expect(save.height, buttonHeight);
          expect(save.left - cancel.right, AppSpacing.actionGap);
          expect(cancel.top - bar.top, closeTo(9, 0.01));
          expect(bar.bottom - cancel.bottom, closeTo(24 + 9, 0.01));
          expect(bar.height, closeTo(buttonHeight + 18 + 24, 0.01));
          for (final key in [_cancel, _save]) {
            final label = tester.widget<RichText>(
              find.descendant(
                of: find.byKey(key),
                matching: find.byType(RichText),
              ),
            );
            expect(label.text.style!.fontSize, 12);
          }
          await tester.tap(find.byKey(_cancel));
          await tester.tap(find.byKey(_save));
          await tester.pump();
          expect(actions, ['cancel', 'save']);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({platform}),
      );
    }

    testWidgets(
      '$variant mobile footer contains the approved Russian label',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(427, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        // Exact approved app_ru.arb text; this checks wrapping, not translation.
        const label = 'Сохранить и переподключить';
        await tester.pumpWidget(_app(shad: shad, saveLabel: label));
        await tester.pumpAndSettle();

        final button = tester.getRect(find.byKey(_save));
        final text = tester.getRect(find.text(label));
        expect(text.left, greaterThanOrEqualTo(button.left));
        expect(text.right, lessThanOrEqualTo(button.right));
        expect(text.top, greaterThanOrEqualTo(button.top));
        expect(text.bottom, lessThanOrEqualTo(button.bottom));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );

    testWidgets('$variant desktop footer preserves compact right alignment', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(_app(shad: shad, mobile: false));
      await tester.pumpAndSettle();

      final cancel = tester.getRect(find.byKey(_cancel));
      final save = tester.getRect(find.byKey(_save));
      expect(cancel.width, AppLayout.pageActionButtonMinWidth);
      expect(save.width, AppLayout.pageActionButtonMinWidth);
      expect(save.left - cancel.right, AppSpacing.actionGap);
      expect(
        save.right,
        (1200 + AppLayout.standardMaxWidth) / 2 - AppSpacing.page,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
