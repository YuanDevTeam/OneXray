import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

abstract final class AppTheme {
  static ThemeData get light => material(Brightness.light);

  static ThemeData get dark => material(Brightness.dark);

  static const actionListTile = ListTileThemeData(
    minTileHeight: 68,
    minLeadingWidth: 20,
    horizontalTitleGap: 13,
    contentPadding: EdgeInsets.symmetric(horizontal: 18),
  );

  static ThemeData material(Brightness brightness, {bool mobile = false}) =>
      _build(
        brightness: brightness,
        colors: AppColorTokens.fallback(brightness),
        mobile: mobile,
      );

  static AppBarTheme appBarTheme({
    required AppPalette palette,
    required Brightness brightness,
    required bool mobile,
  }) => AppBarTheme(
    backgroundColor: palette.header,
    foregroundColor: palette.foreground,
    iconTheme: IconThemeData(color: palette.mutedStrong),
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleSpacing: mobile ? AppSpacing.mobileHeaderHorizontal : AppSpacing.page,
    actionsPadding: EdgeInsetsDirectional.only(
      end: mobile ? AppSpacing.mobileHeaderHorizontal : AppSpacing.page,
    ),
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: palette.header,
      statusBarIconBrightness: brightness == Brightness.light
          ? Brightness.dark
          : Brightness.light,
      statusBarBrightness: brightness,
    ),
    shape: Border(bottom: BorderSide(color: palette.border)),
  );

  static ThemeData secondaryPage(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: appBarTheme(
        palette: ColorManager.palette(context),
        brightness: theme.brightness,
        mobile: MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint,
      ),
    );
  }

  static ThemeData pageActions(BuildContext context) {
    final theme = Theme.of(context);
    final style = ButtonStyle(
      textStyle: WidgetStatePropertyAll(AppTypography.pageAction),
      minimumSize: WidgetStatePropertyAll(
        Size(
          0,
          AppLayout.touchExtent(
            AppLayout.pageActionButtonMinHeight,
            platform: theme.platform,
          ),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
    return theme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: style.merge(theme.filledButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: style.merge(theme.outlinedButtonTheme.style),
      ),
      textButtonTheme: TextButtonThemeData(
        style: style.merge(theme.textButtonTheme.style),
      ),
    );
  }

  static ShadThemeData pageActionsShad(BuildContext context) {
    final theme =
        ShadTheme.maybeOf(context) ??
        shad(Theme.of(context).brightness, mobile: true);
    final height = math.max(
      AppLayout.touchExtent(
        AppLayout.pageActionButtonMinHeight,
        platform: Theme.of(context).platform,
      ),
      MediaQuery.textScalerOf(context)
                  .scale(AppTypography.pageAction.fontSize!) *
              2 +
          12,
    );
    return theme.copyWith(
      primaryButtonTheme: theme.primaryButtonTheme.copyWith(
        textStyle: AppTypography.pageAction,
        expands: true,
      ),
      outlineButtonTheme: theme.outlineButtonTheme.copyWith(
        textStyle: AppTypography.pageAction,
        expands: true,
        // Shad's 1px outline is outside the content constraints.
        height: height - 2,
      ),
      destructiveButtonTheme: theme.destructiveButtonTheme.copyWith(
        textStyle: AppTypography.pageAction,
        expands: true,
      ),
      buttonSizesTheme: theme.buttonSizesTheme.copyWith(
        regular: ShadButtonSizeTheme(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      ),
    );
  }

  static ButtonStyle destructiveButton(BuildContext context) {
    final palette = ColorManager.palette(context);
    return ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(palette.destructiveForeground),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? palette.destructiveSolidHover
            : palette.destructiveSolid,
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }

  static ButtonStyle connectionButton(
    BuildContext context, {
    required bool destructive,
  }) {
    final palette = ColorManager.palette(context);
    final fill = destructive ? palette.destructiveSolid : palette.primarySolid;
    final hover = destructive
        ? palette.destructiveSolidHover
        : palette.primarySolidHover;
    final foreground = destructive
        ? palette.destructiveForeground
        : palette.primaryForeground;
    Color disabled(Color color) =>
        Color.alphaBlend(color.withValues(alpha: 0.52), palette.card);

    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabled(fill);
        return states.contains(WidgetState.hovered) ? hover : fill;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? disabled(foreground)
            : foreground,
      ),
      minimumSize: const WidgetStatePropertyAll(
        Size(0, AppLayout.connectButtonMinHeight),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.compact)),
        ),
      ),
      textStyle: WidgetStatePropertyAll(AppTypography.connectButton),
      elevation: const WidgetStatePropertyAll(0),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
  }

  static ShadThemeData shad(
    Brightness brightness, {
    bool mobile = false,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final palette = AppColorTokens.fallback(brightness).palette;
    // Shad buttons use a tight height. Grow it with the scaled label instead of
    // constraining larger system text to the prototype's minimum height.
    final buttonHeight = math.max(
      AppLayout.touchExtent(
        mobile ? AppLayout.mobileButtonMinHeight : AppLayout.buttonMinHeight,
      ),
      textScaler.scale(AppTypography.control.fontSize!) +
          AppSpacing.controlVertical * 2,
    );
    return ShadThemeData(
      brightness: brightness,
      colorScheme: shadColorScheme(brightness),
      radius: const BorderRadius.all(Radius.circular(AppRadii.control)),
      textTheme: AppTypography.shad,
      primaryButtonTheme: ShadButtonTheme(
        backgroundColor: palette.primarySolid,
        hoverBackgroundColor: palette.primarySolidHover,
        foregroundColor: palette.primaryForeground,
        hoverForegroundColor: palette.primaryForeground,
        textStyle: AppTypography.control,
      ),
      destructiveButtonTheme: ShadButtonTheme(
        backgroundColor: palette.destructiveSolid,
        hoverBackgroundColor: palette.destructiveSolidHover,
        foregroundColor: palette.destructiveForeground,
        hoverForegroundColor: palette.destructiveForeground,
        textStyle: AppTypography.control,
      ),
      outlineButtonTheme: ShadButtonTheme(
        backgroundColor: palette.card,
        hoverBackgroundColor: palette.surfaceHover,
        foregroundColor: palette.foreground,
        hoverForegroundColor: palette.foreground,
        textStyle: AppTypography.control,
      ),
      secondaryButtonTheme: ShadButtonTheme(textStyle: AppTypography.control),
      ghostButtonTheme: ShadButtonTheme(
        hoverBackgroundColor: palette.surfaceHover,
        textStyle: AppTypography.control,
      ),
      linkButtonTheme: ShadButtonTheme(
        foregroundColor: palette.primary,
        hoverForegroundColor: palette.primaryHover,
        textStyle: AppTypography.control,
      ),
      inputTheme: ShadInputTheme(
        decoration: ShadDecoration(
          color: palette.card,
          // Prototype :focus-visible: 3px, 30% primary, with a 2px gap.
          secondaryFocusedBorder: ShadBorder.all(
            color: palette.primary.withValues(alpha: .3),
            width: 3,
            offset: 5,
            radius: BorderRadius.circular(AppRadii.control + 5),
          ),
        ),
        style: AppTypography.rowValue.copyWith(color: palette.foreground),
        placeholderStyle: AppTypography.rowValue.copyWith(
          color: palette.mutedForeground,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.controlHorizontal,
          vertical: AppSpacing.controlVertical,
        ),
      ),
      switchTheme: ShadSwitchTheme(
        width: AppLayout.switchWidth,
        height: AppLayout.switchHeight,
        margin: AppLayout.switchThumbMargin,
        duration: const Duration(milliseconds: 140),
        thumbColor: palette.primaryForeground,
        checkedTrackColor: palette.primary,
        uncheckedTrackColor: palette.borderStrong,
      ),
      radioTheme: ShadRadioTheme(
        // Shad adds the border outside its content size: 15 + 1 + 1 = 17.
        size: 15,
        circleSize: 10,
        color: palette.primary,
        decoration: ShadDecoration(
          border: ShadBorder.all(color: palette.mutedForeground, width: 1),
        ),
      ),
      buttonSizesTheme: ShadButtonSizesTheme(
        regular: ShadButtonSizeTheme(
          height: buttonHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.controlHorizontal,
            vertical: AppSpacing.controlVertical,
          ),
        ),
        sm: ShadButtonSizeTheme(
          height: math.max(
            36,
            textScaler.scale(AppTypography.control.fontSize!),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.controlHorizontal,
          ),
        ),
      ),
    );
  }

  static ShadColorScheme shadColorScheme(Brightness brightness) {
    final palette = AppColorTokens.fallback(brightness).palette;
    return ShadColorScheme(
      background: palette.background,
      foreground: palette.foreground,
      card: palette.card,
      cardForeground: palette.cardForeground,
      popover: palette.popover,
      popoverForeground: palette.popoverForeground,
      primary: palette.primary,
      primaryForeground: brightness == Brightness.dark
          ? palette.background
          : palette.primaryForeground,
      secondary: palette.secondary,
      secondaryForeground: palette.secondaryForeground,
      muted: palette.muted,
      mutedForeground: palette.mutedForeground,
      accent: palette.accent,
      accentForeground: palette.accentForeground,
      destructive: palette.destructive,
      destructiveForeground: brightness == Brightness.dark
          ? palette.background
          : palette.destructiveForeground,
      border: palette.border,
      input: palette.input,
      ring: palette.ring,
      selection: palette.selection,
      custom: {
        'chart1': palette.chart1,
        'chart2': palette.chart2,
        'chart3': palette.chart3,
        'chart4': palette.chart4,
        'chart5': palette.chart5,
        'running': palette.running,
        'runningText': palette.runningText,
        'restarting': palette.restarting,
        'restartingText': palette.restartingText,
      },
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required AppColorTokens colors,
    required bool mobile,
  }) {
    final palette = colors.palette;
    final inversePalette = brightness == Brightness.light
        ? AppPalette.dark
        : AppPalette.light;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: palette.primary,
      onPrimary: brightness == Brightness.dark
          ? palette.background
          : palette.primaryForeground,
      primaryContainer: palette.accent,
      onPrimaryContainer: palette.accentForeground,
      primaryFixed: palette.primarySolid,
      primaryFixedDim: palette.accent,
      onPrimaryFixed: palette.primaryForeground,
      onPrimaryFixedVariant: palette.accentForeground,
      secondary: palette.secondary,
      onSecondary: palette.secondaryForeground,
      secondaryContainer: palette.muted,
      onSecondaryContainer: palette.secondaryForeground,
      secondaryFixed: palette.secondary,
      secondaryFixedDim: palette.muted,
      onSecondaryFixed: palette.secondaryForeground,
      onSecondaryFixedVariant: palette.mutedForeground,
      tertiary: palette.running,
      onTertiary: palette.runningForeground,
      tertiaryContainer: palette.runningSurface,
      onTertiaryContainer: palette.foreground,
      error: palette.destructive,
      onError: brightness == Brightness.dark
          ? palette.background
          : palette.destructiveForeground,
      errorContainer: palette.destructiveSurface,
      onErrorContainer: palette.destructive,
      surface: palette.card,
      onSurface: palette.foreground,
      surfaceDim: palette.background,
      surfaceBright: palette.card,
      surfaceContainerLowest: palette.card,
      surfaceContainerLow: palette.background,
      surfaceContainer: palette.secondary,
      surfaceContainerHigh: palette.muted,
      surfaceContainerHighest: palette.accent,
      onSurfaceVariant: palette.mutedForeground,
      outline: palette.border,
      outlineVariant: palette.input,
      shadow: Colors.black,
      scrim: palette.overlay,
      inverseSurface: palette.foreground,
      onInverseSurface: palette.background,
      inversePrimary: inversePalette.primary,
      surfaceTint: Colors.transparent,
    );
    final roundedRectangle = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
    );
    final borderedRectangle = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: BorderSide(color: palette.border),
    );
    final textTheme = AppTypography.material.apply(
      bodyColor: palette.foreground,
      displayColor: palette.foreground,
    );
    final minimumButtonSize = Size.square(
      AppLayout.touchExtent(
        mobile ? AppLayout.mobileButtonMinHeight : AppLayout.buttonMinHeight,
      ),
    );
    Color disabledButtonColor(Color color) =>
        Color.alphaBlend(color.withValues(alpha: 0.52), palette.card);
    final primaryButtonStyle =
        FilledButton.styleFrom(
          foregroundColor: palette.primaryForeground,
          disabledForegroundColor: disabledButtonColor(
            palette.primaryForeground,
          ),
          disabledBackgroundColor: disabledButtonColor(palette.primarySolid),
          minimumSize: minimumButtonSize,
          visualDensity: VisualDensity.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.buttonHorizontal,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: roundedRectangle,
          textStyle: AppTypography.control,
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return disabledButtonColor(palette.primarySolid);
            }
            return states.contains(WidgetState.hovered)
                ? palette.primarySolidHover
                : palette.primarySolid;
          }),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? palette.ring.withValues(alpha: .18)
                : Colors.transparent,
          ),
        );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: AppFontFamily.sans,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: [colors],
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      disabledColor: palette.mutedForeground.withValues(alpha: 0.5),
      focusColor: palette.ring.withValues(alpha: 0.18),
      hoverColor: palette.surfaceHover,
      highlightColor: palette.accent,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.primary,
        selectionColor: palette.selection,
        selectionHandleColor: palette.primary,
      ),
      appBarTheme: appBarTheme(
        palette: palette,
        brightness: brightness,
        mobile: mobile,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.card,
        modalBarrierColor: palette.overlay,
        shape: roundedRectangle,
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.07),
        elevation: 0,
        shape: borderedRectangle,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.popover,
        surfaceTintColor: Colors.transparent,
        barrierColor: palette.overlay,
        shape: borderedRectangle,
        titleTextStyle: AppTypography.panelTitle.copyWith(
          color: palette.popoverForeground,
        ),
        contentTextStyle: AppTypography.rowValue.copyWith(
          color: palette.mutedForeground,
        ),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: palette.border,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: primaryButtonStyle.copyWith(
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: primaryButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: palette.foreground,
              backgroundColor: palette.card,
              disabledForegroundColor: palette.mutedForeground,
              minimumSize: minimumButtonSize,
              visualDensity: VisualDensity.standard,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.buttonHorizontal,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: palette.input),
              shape: roundedRectangle,
              textStyle: AppTypography.control,
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.hovered)
                      ? palette.borderStrong
                      : palette.input,
                ),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered)
                    ? palette.surfaceHover
                    : palette.card,
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: palette.primary,
              disabledForegroundColor: disabledButtonColor(palette.primary),
              minimumSize: minimumButtonSize,
              shape: roundedRectangle,
              textStyle: AppTypography.control,
            ).copyWith(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return disabledButtonColor(palette.primary);
                }
                return states.contains(WidgetState.hovered)
                    ? palette.primaryHover
                    : palette.primary;
              }),
            ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.foreground,
          disabledForegroundColor: palette.mutedForeground,
          minimumSize: minimumButtonSize,
          shape: roundedRectangle,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.transparent,
        prefixIconColor: palette.mutedForeground,
        suffixIconColor: palette.mutedForeground,
        labelStyle: AppTypography.rowValue.copyWith(
          color: palette.mutedForeground,
        ),
        floatingLabelStyle: AppTypography.rowValue.copyWith(
          color: palette.primary,
        ),
        hintStyle: AppTypography.rowValue.copyWith(
          color: palette.mutedForeground,
        ),
        helperStyle: AppTypography.supporting.copyWith(
          color: palette.mutedForeground,
        ),
        errorStyle: AppTypography.supporting.copyWith(
          color: palette.destructive,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.controlHorizontal,
          vertical: AppSpacing.controlVertical,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: palette.input),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: palette.input),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: palette.ring),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: palette.destructive),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: palette.destructive),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(palette.popover),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: 0.12),
          ),
          elevation: const WidgetStatePropertyAll(6),
          side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
          shape: WidgetStatePropertyAll(roundedRectangle),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(AppTypography.rowValue),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? palette.mutedForeground
                : palette.popoverForeground,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? palette.mutedForeground.withValues(alpha: 0.5)
                : palette.mutedForeground,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered)
                ? palette.surfaceHover
                : Colors.transparent,
          ),
          shape: WidgetStatePropertyAll(roundedRectangle),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.popover,
        surfaceTintColor: Colors.transparent,
        textStyle: AppTypography.rowValue.copyWith(
          color: palette.popoverForeground,
        ),
        shape: borderedRectangle,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: AppTypography.rowValue.copyWith(color: palette.foreground),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(palette.popover),
          side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
          shape: WidgetStatePropertyAll(roundedRectangle),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
            borderSide: BorderSide(color: palette.input),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: palette.primary,
        unselectedLabelColor: palette.mutedForeground,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        indicatorColor: palette.primary,
        dividerColor: palette.border,
        overlayColor: WidgetStatePropertyAll(
          palette.accent.withValues(alpha: 0.72),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.card.withValues(alpha: 0.96),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? palette.sidebarPrimary
                : palette.mutedStrong,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? palette.primary
                : palette.mutedStrong,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: palette.sidebar,
        indicatorColor: palette.selectedSurface,
        selectedIconTheme: IconThemeData(color: palette.sidebarPrimary),
        unselectedIconTheme: IconThemeData(color: palette.mutedForeground),
        selectedLabelTextStyle: AppTypography.selectedNavigationLabel.copyWith(
          color: palette.primary,
        ),
        unselectedLabelTextStyle: AppTypography.navigationLabel.copyWith(
          color: palette.mutedStrong,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(palette.primaryForeground),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.primary
              : palette.borderStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(colorScheme.onPrimary),
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? palette.primary
                : palette.mutedForeground,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.indicator),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.primary
              : palette.mutedForeground,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.muted,
        selectedColor: palette.accent,
        disabledColor: palette.muted.withValues(alpha: 0.5),
        labelStyle: AppTypography.supporting.copyWith(
          color: palette.foreground,
        ),
        secondaryLabelStyle: AppTypography.supporting.copyWith(
          color: palette.accentForeground,
        ),
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: palette.foreground,
        iconColor: palette.mutedForeground,
        selectedColor: palette.primary,
        selectedTileColor: palette.selectedSurface,
        titleTextStyle: AppTypography.rowTitle.copyWith(
          color: palette.foreground,
        ),
        subtitleTextStyle: AppTypography.supporting.copyWith(
          color: palette.mutedForeground,
        ),
        leadingAndTrailingTextStyle: AppTypography.supporting.copyWith(
          color: palette.mutedForeground,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.popover,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadii.compact),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        textStyle: AppTypography.supporting.copyWith(
          color: palette.popoverForeground,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.foreground,
        contentTextStyle: AppTypography.rowValue.copyWith(
          color: palette.background,
        ),
        actionTextColor: inversePalette.primary,
        shape: roundedRectangle,
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: palette.muted,
        circularTrackColor: palette.muted,
      ),
      iconTheme: IconThemeData(color: palette.foreground),
    );
  }
}

class AppDashedBorder extends RoundedRectangleBorder {
  const AppDashedBorder({super.side, super.borderRadius});

  @override
  AppDashedBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => AppDashedBorder(
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    final path = getOuterPath(
      rect.deflate(side.width / 2),
      textDirection: textDirection,
    );
    final paint = side.toPaint();
    for (final metric in path.computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 7) {
        canvas.drawPath(
          metric.extractPath(offset, math.min(offset + 4, metric.length)),
          paint,
        );
      }
    }
  }
}
