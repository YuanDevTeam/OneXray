import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';

const _open = Key('open-confirmation');
const _filename =
    'OneXray-connection-configurations-servers-subscriptions-Age-private-keys-'
    'custom-routing-and-Raw-JSON.log';

enum _Action { exportLog, restore, exportConfiguration, clear }

// The same arguments as restore, log/configuration export and data-clear pages.
AppConfirmationDialog _dialog(AppLocalizations l, _Action action) =>
    AppConfirmationDialog(
      title: switch (action) {
        _Action.exportLog => l.prototypeExport,
        _Action.restore => l.backupRestoreTitle,
        _Action.exportConfiguration =>
          l.prototypeExportOriginalConfigurationQuestion,
        _Action.clear => l.prototypeClearAllDataQuestion,
      },
      subject: action == _Action.exportLog ? _filename : null,
      content: switch (action) {
        _Action.exportLog => l.prototypeLocalLogNotice,
        _Action.restore => [
          l.backupCreatedAt('2026-09-03 09:00'),
          l.backupSummary(3, 1, 1, 1),
          l.backupPendingCount(2),
          l.backupRestoreWarning,
        ].join('\n\n'),
        _Action.exportConfiguration =>
          l.prototypeExportOriginalConfigurationWarning,
        _Action.clear => l.prototypeClearAllDataWarning,
      },
      cancelLabel: l.prototypeCancel,
      confirmLabel: switch (action) {
        _Action.exportLog => l.prototypeExport,
        _Action.restore => l.backupRestore,
        _Action.exportConfiguration => l.prototypeExport,
        _Action.clear => l.prototypeConfirmClearData,
      },
      destructive: action == _Action.restore || action == _Action.clear,
      barrierDismissible: action != _Action.clear,
    );

Future<void> _pumpDialog(
  WidgetTester tester, {
  required _Action action,
  Locale locale = const Locale('en'),
  double width = 427,
  ValueChanged<bool>? onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.material(
        Brightness.light,
        mobile: width <= AppLayout.mobileBreakpoint,
      ),
      locale: locale,
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: _open,
            onPressed: () async {
              final confirmed = await _dialog(
                AppLocalizations.of(context)!,
                action,
              ).show(context);
              onResult?.call(confirmed);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_open));
  await tester.pumpAndSettle();
}

Finder get _surface => find
    .descendant(of: find.byType(Dialog), matching: find.byType(Material))
    .first;

void main() {
  for (final (width, action) in [
    (427.0, _Action.clear),
    (1200.0, _Action.exportConfiguration),
  ]) {
    testWidgets('$action footer matches the $width px layout', (tester) async {
      await _pumpDialog(
        tester,
        action: action,
        locale: const Locale('zh'),
        width: width,
      );
      final mobile = width <= AppLayout.mobileBreakpoint;
      final surface = tester.getRect(_surface);
      final cancel = tester.getRect(find.byType(OutlinedButton));
      final confirm = tester.getRect(find.byType(FilledButton));
      expect(surface.width, closeTo(mobile ? width - 38 : 540, 0.01));
      expect(surface.center.dx, closeTo(width / 2, 0.01));
      expect(confirm.right, closeTo(surface.right - (mobile ? 16 : 20), 1));
      expect(confirm.left - cancel.right, closeTo(10, 0.01));
      expect(cancel.height, AppLayout.touchExtent(mobile ? 42 : 40));
      expect(confirm.height, AppLayout.touchExtent(mobile ? 42 : 40));
      final label = tester.getRect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(Text),
        ),
      );
      expect(
        confirm.width,
        closeTo(label.width + AppSpacing.buttonHorizontal * 2, 0.01),
      );
      expect(cancel.left, greaterThan(surface.left + (mobile ? 16 : 20)));
      expect(tester.takeException(), isNull);
    });
  }

  // One representative per App action, plus the RTL long-filename layout.
  for (final (action, locale, width) in [
    (
      _Action.exportLog,
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      390.0,
    ),
    (_Action.restore, const Locale('ru'), 390.0),
    (_Action.exportConfiguration, const Locale('en'), 1200.0),
    (_Action.clear, const Locale('zh'), 427.0),
    (_Action.exportLog, const Locale('fa'), 390.0),
  ]) {
    testWidgets('$locale $action stays readable and confirms the action', (
      tester,
    ) async {
      bool? result;
      await _pumpDialog(
        tester,
        action: action,
        locale: locale,
        width: width,
        onResult: (confirmed) => result = confirmed,
      );
      final dialog = tester.widget<AppConfirmationDialog>(
        find.byType(AppConfirmationDialog),
      );
      final surface = tester.getRect(_surface);
      expect(
        Directionality.of(tester.element(find.byType(AppConfirmationDialog))),
        locale.languageCode == 'fa' ? TextDirection.rtl : TextDirection.ltr,
      );
      for (final text in [
        dialog.title,
        if (dialog.subject != null) dialog.subject!,
        dialog.content,
      ]) {
        final matches = find.text(text);
        for (var i = 0; i < matches.evaluate().length; i++) {
          final bounds = tester.getRect(matches.at(i));
          expect(bounds.left, greaterThanOrEqualTo(surface.left));
          expect(bounds.right, lessThanOrEqualTo(surface.right));
          expect(bounds.top, greaterThanOrEqualTo(surface.top));
          expect(bounds.bottom, lessThanOrEqualTo(surface.bottom));
        }
      }
      for (final type in [OutlinedButton, FilledButton]) {
        final button = find.byType(type);
        final bounds = tester.getRect(button);
        final label = tester.getRect(
          find.descendant(of: button, matching: find.byType(Text)),
        );
        expect(label.left, greaterThanOrEqualTo(bounds.left));
        expect(label.right, lessThanOrEqualTo(bounds.right));
        expect(label.top, greaterThanOrEqualTo(bounds.top));
        expect(label.bottom, lessThanOrEqualTo(bounds.bottom));
      }
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.byType(AppConfirmationDialog), findsNothing);
      expect(find.byKey(_open), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'cancel and close return false; only confirmation runs the action',
    (tester) async {
      bool? result;
      var actionCalls = 0;
      await _pumpDialog(
        tester,
        action: _Action.clear,
        onResult: (confirmed) {
          result = confirmed;
          if (confirmed) actionCalls++;
        },
      );
      for (final dismiss in [OutlinedButton, IconButton]) {
        await tester.tap(find.byType(dismiss));
        await tester.pumpAndSettle();
        expect(find.byType(AppConfirmationDialog), findsNothing);
        expect(result, isFalse);
        expect(actionCalls, 0);
        result = null;
        await tester.tap(find.byKey(_open));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(actionCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backdrop does not dismiss a destructive confirmation', (
    tester,
  ) async {
    bool? result;
    await _pumpDialog(
      tester,
      action: _Action.clear,
      onResult: (confirmed) => result = confirmed,
    );

    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byType(AppConfirmationDialog), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
