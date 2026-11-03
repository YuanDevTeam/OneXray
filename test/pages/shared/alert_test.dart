import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('showPermissionDialog presents a clear settings action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _AlertTestApp(onPressed: ContextAlert.showPermissionDialog),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.shieldAlert), findsOneWidget);
    expect(find.text('Permission Required'), findsOneWidget);
    expect(
      find.text('Permission is denied. Open Settings to allow it?'),
      findsOneWidget,
    );
    expect(find.text('Open system settings'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(ShadDialog), findsNothing);
  });

  for (final size in const [
    Size(390, 844),
    Size(1032, 1376),
    Size(1160, 720),
  ]) {
    testWidgets(
      'generic confirmation uses its own roles and results at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        bool? result;
        var confirmed = 0;
        await tester.pumpWidget(
          _AlertTestApp(
            onPressed: (context) async {
              result = await ContextAlert.showConfirmDialog(
                context,
                title: 'Confirm action',
                content: 'Review the change.',
                confirmLabel: 'Continue',
              );
              if (result!) confirmed++;
            },
          ),
        );
        for (final close in ['Cancel', 'Close dialog', 'Continue']) {
          await tester.tap(find.text('Show'));
          await tester.pumpAndSettle();
          final dialog = tester.widget<ShadDialog>(find.byType(ShadDialog));
          expect(
            dialog.radius,
            BorderRadius.circular(size.width < 640 ? 0 : 18),
          );
          final title = tester.widget<Text>(find.text('Confirm action'));
          final description = tester.widget<Text>(
            find.text('Review the change.'),
          );
          expect(title.style!.fontSize, 20);
          expect(title.style!.fontWeight, FontWeight.w600);
          expect(description.style!.fontSize, 14);
          expect(
            description.style!.color,
            ColorManager.palette(tester.element(find.byType(ShadDialog)))
                .mutedForeground,
          );
          if (close == 'Close dialog') {
            await tester.tap(find.byTooltip(close));
          } else {
            await tester.tap(find.text(close));
          }
          await tester.pumpAndSettle();
          expect(result, close == 'Continue');
          expect(find.byType(ShadDialog), findsNothing);
        }
        expect(confirmed, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('showToast uses the shared Shad toaster', (tester) async {
    await tester.pumpWidget(
      _AlertTestApp(
        onPressed: (context) async {
          ContextAlert.showToast(context, 'Saved');
        },
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    expect(find.byType(ShadToast), findsOneWidget);
    expect(find.byIcon(LucideIcons.info), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final toast = tester.widget<ShadToast>(find.byType(ShadToast));
    expect(toast.alignment, Alignment.bottomRight);
    expect(toast.showCloseIconOnlyWhenHovered, isFalse);
    expect(toast.duration, const Duration(seconds: 2));
  });

  testWidgets('failed system settings launch shows a toast', (tester) async {
    const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      _AlertTestApp(onPressed: ContextAlert.showPermissionDialog),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open system settings'));
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.text('Show')))!;
    expect(
      find.text(
        '${l.resultFailed}\nThe system settings page could not be opened.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('showToast uses a full-width bottom layout on phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      _AlertTestApp(
        onPressed: (context) async {
          ContextAlert.showToast(context, 'Saved');
        },
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    final toast = tester.widget<ShadToast>(find.byType(ShadToast));
    expect(toast.alignment, Alignment.bottomCenter);
    expect(toast.constraints?.minWidth, 358);
    expect(toast.constraints?.maxWidth, 358);
    expect(toast.duration, const Duration(seconds: 2));
  });
}

class _AlertTestApp extends StatelessWidget {
  const _AlertTestApp({required this.onPressed});

  final Future<void> Function(BuildContext context) onPressed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => ShadTheme(
        data: AppTheme.shad(Brightness.light),
        child: ShadToaster(child: child ?? const SizedBox.shrink()),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ShadButton(
              onPressed: () => onPressed(context),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
  }
}
