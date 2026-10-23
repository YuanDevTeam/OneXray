import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/page.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    final palette = brightness == Brightness.light
        ? AppPalette.light
        : AppPalette.dark;

    testWidgets('tunnel status follows live phases in $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
        MaterialApp(
          theme: AppTheme.material(brightness, mobile: true),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => ShadTheme(
            data: AppTheme.shad(brightness, mobile: true),
            child: child!,
          ),
          home: VpnTunnelPane(createController: () => controller),
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(VpnTunnelPane)),
      )!;
      final row = find.byWidgetPredicate(
        (widget) =>
            widget is PolicyValueRow && widget.title == l.prototypeSystemVpn,
      );

      for (final (phase, label, color) in [
        (
          ConnectionPhase.disconnected,
          l.prototypeDisconnected,
          palette.mutedStrong,
        ),
        (
          ConnectionPhase.preparing,
          l.prototypeConnecting,
          palette.restartingText,
        ),
        (
          ConnectionPhase.connecting,
          l.prototypeConnecting,
          palette.restartingText,
        ),
        (ConnectionPhase.connected, l.prototypeConnected, palette.runningText),
        (
          ConnectionPhase.disconnecting,
          l.prototypeDisconnecting,
          palette.restartingText,
        ),
        (
          ConnectionPhase.failed,
          l.prototypeConnectionFailed,
          palette.destructive,
        ),
        (
          ConnectionPhase.disconnected,
          l.prototypeDisconnected,
          palette.mutedStrong,
        ),
      ]) {
        coordinator.state.value = ConnectionView(phase: phase);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: row, matching: find.text(label)),
          findsOneWidget,
        );
        final status = tester.widget<PolicyValueRow>(row);
        expect(status.valueStyle!.color, color);
        expect(status.titleStyle!.color, palette.foreground);
        expect(
          tester
              .widget<Text>(
                find.descendant(of: row, matching: find.text(label)),
              )
              .style!
              .color,
          color,
        );
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: row,
                  matching: find.text(l.prototypeSystemVpn),
                ),
              )
              .style!
              .color,
          palette.foreground,
        );
        final shield = find.descendant(
          of: row,
          matching: find.byIcon(LucideIcons.shield),
        );
        expect(tester.widget<Icon>(shield).color, palette.mutedStrong);
        expect(
          find.descendant(
            of: row,
            matching: find.byIcon(LucideIcons.circleCheck),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });

    test('small status text has sufficient contrast in $brightness', () {
      for (final color in [
        palette.runningText,
        palette.restartingText,
        palette.destructive,
        palette.mutedStrong,
      ]) {
        expect(_contrast(color, palette.card), greaterThanOrEqualTo(4.5));
      }
      expect(
        _contrast(palette.runningText, palette.runningSurface),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}
