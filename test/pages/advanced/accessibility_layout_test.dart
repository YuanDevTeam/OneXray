import 'package:drift/native.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/page.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/page.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _app(
  Widget page, {
  Locale locale = const Locale('zh'),
  double scale = 1,
  bool mobile = true,
}) => MaterialApp(
  theme: AppTheme.material(Brightness.light, mobile: mobile),
  locale: locale,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: ShadTheme(
      data: AppTheme.shad(Brightness.light, mobile: mobile),
      child: child!,
    ),
  ),
  home: page,
);

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void _expectCompleteText(WidgetTester tester, Finder finder) {
  final richText = find.descendant(of: finder, matching: find.byType(RichText));
  expect(richText, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(richText);
  final diagnostic =
      'text=${paragraph.text.toPlainText()} '
      'size=${paragraph.size} constraints=${paragraph.constraints} '
      'style=${paragraph.text.style} '
      'scaler=${tester.widget<RichText>(richText).textScaler}';
  expect(paragraph.didExceedMaxLines, isFalse);
  for (final box in paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  )) {
    expect(box.left, greaterThanOrEqualTo(-.5));
    expect(
      box.right,
      lessThanOrEqualTo(paragraph.size.width + .5),
      reason: diagnostic,
    );
    expect(box.top, greaterThanOrEqualTo(-.5));
    expect(
      box.bottom,
      lessThanOrEqualTo(paragraph.size.height + .5),
      reason: diagnostic,
    );
  }
}

void main() {
  for (final locale in [const Locale('zh'), const Locale('ru')]) {
    for (final scale in [1.0, 3.2]) {
      testWidgets(
        'fixed Advanced tabs fit $locale at $scale on a small phone',
        (tester) async {
          _size(tester, const Size(375, 667));
          await tester.pumpWidget(
            _app(
              const AdvancedPageView(
                tunnel: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text('tunnel-body-start'),
                      SizedBox(height: 1000),
                      Text('tunnel-body-end'),
                    ],
                  ),
                ),
                xray: Text('xray-body'),
              ),
              locale: locale,
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          final l = AppLocalizations.of(
            tester.element(find.byType(AdvancedPageView)),
          )!;
          final tabs = find.byType(TabBar);
          final tabBounds = tester.getRect(tabs);
          for (final label in [
            l.prototypeVpnTunnel,
            l.prototypeXrayRuntimeDiagnostics,
          ]) {
            _expectCompleteText(tester, find.text(label));
            final labelBounds = tester.getRect(find.text(label));
            expect(labelBounds.top, greaterThanOrEqualTo(tabBounds.top));
            expect(labelBounds.bottom, lessThanOrEqualTo(tabBounds.bottom));
          }
          expect(
            tester.getTopLeft(find.text('tunnel-body-start')).dy,
            greaterThanOrEqualTo(tabBounds.bottom),
          );
          await tester.drag(
            find
                .ancestor(
                  of: find.text('tunnel-body-start'),
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
            const Offset(0, -180),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(tabs), tabBounds);
          await tester.ensureVisible(
            find.text(l.prototypeXrayRuntimeDiagnostics),
          );
          await tester.tap(find.text(l.prototypeXrayRuntimeDiagnostics));
          await tester.pumpAndSettle();
          expect(find.text('xray-body'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('large phone status text wraps completely without ellipsis', (
    tester,
  ) async {
    _size(tester, const Size(375, 667));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final coordinator = ConnectionCoordinator(
      database: db,
      statusEvents: const Stream.empty(),
    );
    final controller = PolicyEditorController(
      draft: PolicyEditorDraft(ConnectionConfiguration()),
      service: PolicyEditorService(
        coordinator: coordinator,
        platform: ConnectionPlatform.ios,
      ),
    );
    addTearDown(() async {
      await controller.close();
      coordinator.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      _app(VpnTunnelPane(createController: () => controller), scale: 3.2),
    );
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(VpnTunnelPane)))!;
    final title = find.text(l.prototypeSystemVpn);
    for (final (phase, label) in [
      (ConnectionPhase.disconnected, l.prototypeDisconnected),
      (ConnectionPhase.connecting, l.prototypeConnecting),
      (ConnectionPhase.connected, l.prototypeConnected),
      (ConnectionPhase.disconnecting, l.prototypeDisconnecting),
      (ConnectionPhase.failed, l.prototypeConnectionFailed),
    ]) {
      coordinator.state.value = ConnectionView(phase: phase);
      await tester.pumpAndSettle();
      _expectCompleteText(tester, title);
      _expectCompleteText(tester, find.text(label));
      expect(
        tester.getTopLeft(find.text(label)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ordinary desktop values retain the compact horizontal row', (
    tester,
  ) async {
    _size(tester, const Size(1160, 720));
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: PolicyValueRow(title: 'Version', value: '26.11.1'),
        ),
        locale: const Locale('en'),
        mobile: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingRow), findsOneWidget);
    expect(
      tester.getCenter(find.text('Version')).dy,
      tester.getCenter(find.text('26.11.1')).dy,
    );
    _expectCompleteText(tester, find.text('26.11.1'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
