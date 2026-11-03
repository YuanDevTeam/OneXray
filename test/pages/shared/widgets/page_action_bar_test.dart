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
  double keyboardInset = 0,
  bool saveEnabled = true,
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
      viewInsets: EdgeInsets.only(bottom: keyboardInset),
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
                onPressed: saveEnabled ? (onSave ?? () {}) : null,
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
                onPressed: saveEnabled ? (onSave ?? () {}) : null,
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
      (TargetPlatform.iOS, 48.0),
      (TargetPlatform.android, 48.0),
    ]) {
      testWidgets(
        '$variant ${platform.name} footer keeps equal buttons and prototype 14px text',
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
          expect(cancel.top - bar.top, closeTo(8, 0.01));
          expect(bar.bottom - cancel.bottom, closeTo(24 + 8, 0.01));
          expect(bar.height, closeTo(buttonHeight + 16 + 24, 0.01));
          for (final key in [_cancel, _save]) {
            final label = tester.widget<RichText>(
              find.descendant(
                of: find.byKey(key),
                matching: find.byType(RichText),
              ),
            );
            expect(label.text.style!.fontSize, 14);
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

    for (final (platform, height) in [
      (TargetPlatform.macOS, 42.0),
      (TargetPlatform.iOS, 44.0),
    ]) {
      testWidgets('$variant wide footer uses natural widths on $platform', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final actions = <String>[];
        await tester.pumpWidget(
          _app(
            shad: shad,
            mobile: false,
            onCancel: () => actions.add('cancel'),
            onSave: () => actions.add('save'),
          ),
        );
        await tester.pumpAndSettle();
        final cancel = tester.getRect(find.byKey(_cancel));
        final save = tester.getRect(find.byKey(_save));
        for (final key in [_cancel, _save]) {
          final bounds = tester.getRect(find.byKey(key));
          final label = tester.getRect(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(RichText),
            ),
          );
          expect(
            bounds.width,
            closeTo(
              label.width +
                  AppSpacing.buttonHorizontal * 2 +
                  (shad && key == _cancel ? 2 : 0),
              .01,
            ),
          );
          expect(bounds.width, lessThan(150));
          expect(bounds.height, height);
        }
        expect(cancel.width, greaterThan(save.width));
        expect(save.left - cancel.right, AppSpacing.actionGap);
        expect(
          save.right,
          (1200 + AppLayout.standardMaxWidth) / 2 - AppSpacing.page,
        );
        expect(
          tester.getSize(find.byType(PageActionBar)).height,
          AppLayout.pageActionMinHeight,
        );
        await tester.tap(find.byKey(_cancel));
        await tester.tap(find.byKey(_save));
        await tester.pump();
        expect(actions, ['cancel', 'save']);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(platform));
    }

    testWidgets(
      '$variant iPad short footer avoids the keyboard and preserves disabled actions',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1032, 360);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var cancels = 0;
        var saves = 0;
        await tester.pumpWidget(
          _app(
            shad: shad,
            mobile: false,
            bottomInset: 20,
            keyboardInset: 160,
            saveEnabled: false,
            onCancel: () => cancels++,
            onSave: () => saves++,
          ),
        );
        await tester.pumpAndSettle();
        final action = tester.getRect(find.byKey(_save));
        expect(action.height, 44);
        expect(action.bottom, lessThanOrEqualTo(360 - 160 - 20));
        expect(find.byKey(_cancel).hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(_save));
        await tester.tap(find.byKey(_cancel));
        await tester.pumpAndSettle();
        expect(saves, 0);
        expect(cancels, 1);
        expect(
          tester.getSize(find.byType(PageActionBar)).height,
          72 + 20 + 160,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
}
