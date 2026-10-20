import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/menus.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';

const _open = Key('open-server-menu');
const _size = Size(390, 844);
const _bottomInset = 34.0;

Future<void> _pumpMenu(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  ValueChanged<ServerAction?>? onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.material(Brightness.light, mobile: true),
      locale: locale,
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.noScaling,
          padding: const EdgeInsets.only(bottom: _bottomInset),
          viewPadding: const EdgeInsets.only(bottom: _bottomInset),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: _open,
            onPressed: () async {
              final action = await showServerActionsMenu(
                context,
                name: 'Singapore 03',
                canMove: true,
                source: AppLocalizations.of(context)!.prototypeManualAdditions,
              );
              onResult?.call(action);
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

String _label(AppLocalizations l, ServerAction action) => switch (action) {
  ServerAction.edit => l.prototypeEditServer,
  ServerAction.test => l.prototypeTestAgain,
  ServerAction.copy => l.prototypeSaveAsLocalServer,
  ServerAction.share => l.prototypeShareServer,
  ServerAction.move => l.manualGroupMove,
  ServerAction.delete => l.prototypeDelete,
};

void main() {
  for (final action in ServerAction.values) {
    testWidgets('one mobile tap returns $action and closes the menu', (
      tester,
    ) async {
      final results = <ServerAction?>[];
      await _pumpMenu(tester, onResult: results.add);
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerActionsMenu)),
      )!;

      await tester.tap(find.text(_label(l, action)));
      await tester.pumpAndSettle();
      expect(results, [action]);
      expect(find.byType(ServerActionsMenu), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('closing the mobile menu returns null', (tester) async {
    final results = <ServerAction?>[];
    await _pumpMenu(tester, onResult: results.add);
    final l = AppLocalizations.of(
      tester.element(find.byType(ServerActionsMenu)),
    )!;
    await tester.tap(find.byTooltip(l.prototypeCloseDialog));
    await tester.pumpAndSettle();
    expect(results, [null]);
    expect(find.byType(ServerActionsMenu), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [
    Locale('en'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('fa'),
  ]) {
    testWidgets('$locale menu fits and paints the bottom safe area', (
      tester,
    ) async {
      await _pumpMenu(tester, locale: locale);
      final menu = find.byType(ServerActionsMenu);
      final l = AppLocalizations.of(tester.element(menu))!;
      final surface = find
          .descendant(
            of: find.byType(AppDialog),
            matching: find.byType(Material),
          )
          .first;
      final bounds = tester.getRect(surface);
      expect(MediaQuery.sizeOf(tester.element(menu)), _size);
      expect(bounds.width, _size.width);
      expect(bounds.bottom, _size.height);
      expect(tester.widget<Material>(surface).color, AppPalette.light.card);
      final lastRow = find
          .ancestor(
            of: find.text(l.prototypeDelete),
            matching: find.byType(InkWell),
          )
          .first;
      expect(tester.getRect(lastRow).bottom, _size.height - _bottomInset);
      expect(
        Directionality.of(tester.element(menu)),
        locale.languageCode == 'fa' ? TextDirection.rtl : TextDirection.ltr,
      );
      for (final text
          in find
              .descendant(of: menu, matching: find.byType(Text))
              .evaluate()) {
        final textBounds = tester.getRect(find.byWidget(text.widget));
        expect(textBounds.left, greaterThanOrEqualTo(bounds.left));
        expect(textBounds.right, lessThanOrEqualTo(bounds.right));
        expect(textBounds.top, greaterThanOrEqualTo(bounds.top));
        expect(
          textBounds.bottom,
          lessThanOrEqualTo(_size.height - _bottomInset),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
