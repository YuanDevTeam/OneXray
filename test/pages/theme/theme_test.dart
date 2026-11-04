import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  group('AppTheme', () {
    test('light Material and Shad themes share the prototype palette', () {
      const tokens = AppColorTokens.light;
      final palette = tokens.palette;
      final material = AppTheme.light;
      final shad = AppTheme.shadColorScheme(Brightness.light);

      expect(material.scaffoldBackgroundColor, palette.background);
      expect(material.colorScheme.primary, palette.primary);
      expect(material.colorScheme.onPrimary, palette.primaryForeground);
      expect(material.colorScheme.surface, palette.card);
      expect(material.colorScheme.onSurface, palette.foreground);
      expect(material.iconTheme.color, palette.foreground);
      expect(material.colorScheme.error, palette.destructive);
      expect(material.colorScheme.outline, palette.border);
      expect(material.appBarTheme.backgroundColor, isNull);
      expect(material.appBarTheme.foregroundColor, isNull);
      expect(material.appBarTheme.toolbarHeight, isNull);
      expect(material.appBarTheme.centerTitle, isNull);
      expect(material.appBarTheme.titleTextStyle?.fontSize, 22);
      expect(material.appBarTheme.titleTextStyle?.fontWeight, FontWeight.w400);
      expect(
        material.appBarTheme.titleTextStyle?.fontFamily,
        AppFontFamily.sans,
      );
      expect(
        material.appBarTheme.titleTextStyle?.fontFamilyFallback,
        AppFontFamily.sansFallback,
      );
      expect(material.appBarTheme.titleTextStyle?.color, palette.foreground);
      expect(material.appBarTheme.titleSpacing, isNull);
      expect(material.appBarTheme.actionsPadding, isNull);
      expect(material.appBarTheme.elevation, isNull);
      expect(material.appBarTheme.scrolledUnderElevation, isNull);
      expect(material.appBarTheme.surfaceTintColor, isNull);
      expect(material.appBarTheme.iconTheme, isNull);
      expect(material.appBarTheme.actionsIconTheme, isNull);
      expect(material.appBarTheme.systemOverlayStyle, isNull);
      expect(material.navigationRailTheme.backgroundColor, palette.sidebar);
      expect(material.navigationBarTheme.height, isNull);
      expect(material.tabBarTheme.labelStyle?.fontSize, 14);
      expect(material.tabBarTheme.unselectedLabelStyle?.fontSize, 14);

      expect(shad.background, palette.background);
      expect(shad.foreground, palette.foreground);
      expect(shad.card, palette.card);
      expect(shad.primary, palette.primary);
      expect(shad.secondary, palette.secondary);
      expect(shad.muted, palette.muted);
      expect(shad.accent, palette.accent);
      expect(shad.destructive, palette.destructive);
      expect(shad.border, palette.border);
      expect(shad.input, palette.input);
      expect(shad.ring, palette.ring);
      expect(shad.custom['running'], palette.running);
      expect(shad.custom['runningText'], palette.runningText);
    });

    test('dark Material and Shad themes share the mapped opaque borders', () {
      const tokens = AppColorTokens.dark;
      final palette = tokens.palette;
      final material = AppTheme.dark;
      final shad = AppTheme.shadColorScheme(Brightness.dark);

      expect(material.brightness, Brightness.dark);
      expect(material.colorScheme.primary, palette.primary);
      expect(material.colorScheme.surface, palette.card);
      expect(material.iconTheme.color, palette.foreground);
      expect(material.dividerTheme.color, palette.border);
      expect(
        material.navigationBarTheme.backgroundColor,
        palette.card.withValues(alpha: 0.96),
      );
      expect(material.appBarTheme.systemOverlayStyle, isNull);
      expect(material.appBarTheme.titleTextStyle?.color, palette.foreground);

      expect(shad.background, palette.background);
      expect(shad.card, palette.card);
      expect(shad.popover, palette.popover);
      expect(shad.border, palette.border);
      expect(shad.input, palette.input);
      expect(material.colorScheme.outline, shad.border);
      expect(palette.border, const Color(0xFF35363E));
      expect(palette.input, const Color(0xFF50525B));
      expect(palette.primary, const Color(0xFF91B3FF));
      expect(palette.primarySolid, const Color(0xFF3268EF));
      expect(palette.foreground, const Color(0xFFF2F3F5));
    });

    test(
      'typography keeps size, rounded weight and platform glyph fallback',
      () {
        final material = AppTheme.light;
        final shad = AppTheme.shad(Brightness.light);

        expect(material.textTheme.bodyMedium?.fontFamily, AppFontFamily.sans);
        expect(material.textTheme.bodyMedium?.fontSize, 14);
        expect(material.textTheme.bodySmall?.fontSize, 13);
        expect(material.textTheme.labelSmall?.fontSize, 13);
        expect(material.textTheme.titleLarge?.fontSize, 16);
        expect(shad.textTheme.family, AppFontFamily.sans);
        expect(shad.textTheme.p.fontSize, 14);
        expect(shad.textTheme.small.fontSize, 14);
        expect(shad.textTheme.muted.fontSize, 13);
        expect(AppTypography.pageTitle.fontSize, 26);
        expect(AppTypography.pageTitle.fontWeight, FontWeight.w600);
        expect(AppTypography.panelTitle.fontSize, 16);
        expect(AppTypography.supporting.fontSize, 13);
        expect(AppTypography.navigationLabel.fontSize, 14);
        expect(AppTypography.badge.fontSize, 13);
        expect(AppTypography.code.fontSize, 12);
        expect(AppTypography.metric.fontSize, 22);
        for (final (style, size, weight) in [
          (AppTypography.connectStatusTitle, 26, FontWeight.w600),
          (AppTypography.connectButton, 14, FontWeight.w600),
          (AppTypography.connectCaption, 12, FontWeight.w600),
          (AppTypography.connectChoiceLabel, 12, FontWeight.w500),
          (AppTypography.connectChoiceTitle, 14, FontWeight.w600),
          (AppTypography.connectChoiceMeta, 12, FontWeight.w600),
          (AppTypography.connectTrafficTitle, 15, FontWeight.w700),
          (AppTypography.connectTrafficGroupTitle, 12, FontWeight.w500),
          (AppTypography.connectTrafficValue, 15, FontWeight.w600),
          (AppTypography.connectRawTitle, 12, FontWeight.w700),
          (AppTypography.connectRawCount, 12, FontWeight.w600),
          (AppTypography.dialogTitle, 16, FontWeight.w600),
          (AppTypography.confirmationTitle, 20, FontWeight.w600),
          (AppTypography.dialogSubtitle, 13, FontWeight.w400),
        ]) {
          expect(style.fontSize, size);
          expect(style.fontWeight, weight);
          expect(style.height, 1.45);
          expect(style.fontVariations, isNull);
          expect(style.letterSpacing, isNull);
          expect(style.fontFeatures, isNull);
          expect(style.fontFamily, isNull);
          expect(style.fontFamilyFallback, AppFontFamily.sansFallback);
        }
        expect(AppFontFamily.sans, 'packages/shadcn_ui/Geist');
        expect(AppFontFamily.mono, 'packages/shadcn_ui/GeistMono');
        expect(
          material.textTheme.bodyMedium?.fontFamilyFallback,
          AppFontFamily.sansFallback,
        );
        expect(shad.textTheme.p.fontFamilyFallback, AppFontFamily.sansFallback);
      },
    );

    test(
      'both themes keep solid button colors separate from interactive text',
      () {
        for (final brightness in Brightness.values) {
          final palette = AppColorTokens.fallback(brightness).palette;
          final material = AppTheme.material(brightness);
          final shad = AppTheme.shad(brightness);
          final filled = material.filledButtonTheme.style!;
          expect(filled.backgroundColor!.resolve({}), palette.primarySolid);
          expect(
            filled.backgroundColor!.resolve({WidgetState.hovered}),
            palette.primarySolidHover,
          );
          expect(filled.foregroundColor!.resolve({}), Colors.white);
          expect(
            material.textButtonTheme.style!.foregroundColor!.resolve({}),
            palette.primaryText,
          );
          expect(shad.primaryButtonTheme.backgroundColor, palette.primarySolid);
          expect(
            shad.primaryButtonTheme.hoverBackgroundColor,
            palette.primarySolidHover,
          );
          expect(shad.primaryButtonTheme.foregroundColor, Colors.white);
          expect(
            shad.destructiveButtonTheme.backgroundColor,
            palette.destructiveSolid,
          );
          expect(shad.destructiveButtonTheme.foregroundColor, Colors.white);
          expect(shad.outlineButtonTheme.foregroundColor, palette.foreground);
          expect(
            shad.inputTheme.style!.fontSize,
            material.textTheme.bodyMedium!.fontSize,
          );
          expect(
            shad.switchTheme.checkedTrackColor,
            material.switchTheme.trackColor!.resolve({WidgetState.selected}),
          );
          expect(
            shad.switchTheme.uncheckedTrackColor,
            material.switchTheme.trackColor!.resolve({}),
          );
          expect(shad.switchTheme.thumbColor, Colors.white);
          expect(shad.switchTheme.width, 44);
          expect(shad.switchTheme.height, 26);
          expect(shad.switchTheme.margin, 3);
          expect(material.dialogTheme.barrierColor, palette.overlay);
          expect(
            material.navigationRailTheme.indicatorColor,
            palette.selectedSurface,
          );
          expect(
            material.navigationRailTheme.selectedLabelTextStyle!.fontWeight,
            AppTypography.selectedNavigationLabel.fontWeight,
          );
          final input =
              material.inputDecorationTheme.border! as OutlineInputBorder;
          expect(input.borderRadius, BorderRadius.circular(AppRadii.control));
        }
      },
    );

    test('mobile theme keeps standard AppBar and native navigation sizing', () {
      final material = AppTheme.material(Brightness.light, mobile: true);
      final shad = AppTheme.shad(Brightness.light, mobile: true);
      expect(material.appBarTheme.titleTextStyle?.fontSize, 22);
      expect(material.appBarTheme.titleTextStyle?.fontWeight, FontWeight.w400);
      expect(
        material.appBarTheme.titleTextStyle?.fontFamily,
        AppFontFamily.sans,
      );
      expect(material.appBarTheme.centerTitle, isNull);
      expect(material.appBarTheme.toolbarHeight, isNull);
      expect(material.appBarTheme.titleSpacing, isNull);
      expect(material.appBarTheme.actionsPadding, isNull);
      final navigation = material.navigationBarTheme;
      expect(navigation.height, isNull);
      expect(navigation.indicatorColor, Colors.transparent);
      expect(navigation.iconTheme!.resolve({})!.size, isNull);
      expect(
        navigation.iconTheme!.resolve({})!.color,
        AppPalette.light.mutedStrong,
      );
      expect(navigation.labelTextStyle!.resolve({})!.fontSize, isNull);
      expect(
        navigation.labelTextStyle!.resolve({})!.fontWeight,
        FontWeight.w400,
      );
      expect(
        navigation.labelTextStyle!.resolve({WidgetState.selected})!.fontWeight,
        FontWeight.w600,
      );
      expect(
        material.filledButtonTheme.style!.minimumSize!.resolve({}),
        Size.square(AppLayout.touchExtent(AppLayout.mobileButtonMinHeight)),
      );
      expect(
        shad.buttonSizesTheme.regular!.height,
        AppLayout.touchExtent(AppLayout.mobileButtonMinHeight),
      );
    });

    test('color accessors map to semantic prototype tokens', () {
      const tokens = AppColorTokens.light;
      final palette = tokens.palette;

      expect(tokens.surface, palette.card);
      expect(tokens.surfaceBorder, palette.border);
      expect(tokens.primaryText, palette.foreground);
      expect(tokens.secondaryText, palette.mutedForeground);
      expect(tokens.tagBackground, palette.muted);
    });
  });

  testWidgets('connection button keeps prototype colors and disabled opacity', (
    tester,
  ) async {
    expect(
      const AppDashedBorder().copyWith(side: const BorderSide(width: 2)),
      isA<AppDashedBorder>(),
    );
    for (final brightness in Brightness.values) {
      final palette = AppColorTokens.fallback(brightness).palette;
      late ButtonStyle primary;
      late ButtonStyle destructive;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.material(brightness, mobile: true),
          home: Builder(
            builder: (context) {
              primary = AppTheme.connectionButton(context, destructive: false);
              destructive = AppTheme.connectionButton(
                context,
                destructive: true,
              );
              return Scaffold(
                body: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: AppDashedBorder(
                      side: BorderSide(color: palette.borderStrong),
                      borderRadius: BorderRadius.circular(AppRadii.card),
                    ),
                  ),
                  child: FilledButton(
                    onPressed: () {},
                    style: primary,
                    child: const Text('Connect'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(primary.backgroundColor!.resolve({}), palette.primarySolid);
      expect(
        primary.backgroundColor!.resolve({WidgetState.disabled}),
        Color.alphaBlend(
          palette.primarySolid.withValues(alpha: 0.52),
          palette.card,
        ),
      );
      expect(
        destructive.backgroundColor!.resolve({}),
        palette.destructiveSolid,
      );
      expect(
        destructive.backgroundColor!.resolve({WidgetState.hovered}),
        palette.destructiveSolidHover,
      );
      expect(
        primary.overlayColor!.resolve({WidgetState.pressed}),
        Colors.transparent,
      );
      expect(primary.textStyle!.resolve({})!.fontSize, 14);
      expect(tester.getSize(find.byType(FilledButton)).height, 48);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('toolbar buttons share height and shape while loading', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      Rect? idleOutline;
      for (final busy in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.material(brightness),
            home: Scaffold(
              appBar: PageAppBar(
                title: const Text('Servers'),
                actions: [
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: busy
                        ? const ButtonProgressIndicator()
                        : const Icon(LucideIcons.refreshCw),
                    label: const Text('Updates & sources'),
                  ),
                  const SizedBox(width: AppSpacing.actionGap),
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(LucideIcons.plus),
                    label: const Text('Add server'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final outline = find.descendant(
          of: find.byType(OutlinedButton),
          matching: find.byType(Material),
        );
        final filled = find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(Material),
        );
        final outlineRect = tester.getRect(outline);
        final filledRect = tester.getRect(filled);
        expect(
          outlineRect.height,
          AppLayout.touchExtent(AppLayout.buttonMinHeight),
        );
        expect(outlineRect.height, filledRect.height);
        expect(outlineRect.top, filledRect.top);
        final outlineShape =
            tester.widget<Material>(outline).shape! as RoundedRectangleBorder;
        final filledShape =
            tester.widget<Material>(filled).shape! as RoundedRectangleBorder;
        expect(filledShape.borderRadius, BorderRadius.circular(AppRadii.cta));
        expect(
          outlineShape.borderRadius,
          BorderRadius.circular(AppRadii.control),
        );
        if (busy) {
          expect(outlineRect.height, idleOutline!.height);
          expect(outlineRect.top, idleOutline.top);
        } else {
          idleOutline = outlineRect;
        }
        expect(tester.takeException(), isNull);
      }
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'scaled Shad footer fits text and avoids keyboard and safe area',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const scale = TextScaler.linear(2);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.material(Brightness.dark, mobile: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: scale,
              padding: const EdgeInsets.only(bottom: 34),
              viewPadding: const EdgeInsets.only(bottom: 34),
              viewInsets: const EdgeInsets.only(bottom: 240),
            ),
            child: ShadTheme(
              data: AppTheme.shad(
                Brightness.dark,
                mobile: true,
                textScaler: scale,
              ),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: ListView(
              children: List.generate(
                30,
                (i) => ListTile(title: Text('Row $i')),
              ),
            ),
            bottomNavigationBar: PageActionBar(
              children: [
                ShadButton.outline(
                  onPressed: () {},
                  child: const Text('Cancel'),
                ),
                ShadButton(onPressed: () {}, child: const Text('Save')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final save = find.byType(ShadButton).last;
      final rect = tester.getRect(save);
      expect(
        rect.height,
        greaterThanOrEqualTo(AppLayout.pageActionButtonMinHeight),
      );
      expect(rect.bottom, lessThanOrEqualTo(800 - 240 - 34));
      expect(
        tester.getSize(find.text('Save')).height,
        greaterThanOrEqualTo(26),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(save), rect);
      expect(tester.takeException(), isNull);
    },
  );
}
