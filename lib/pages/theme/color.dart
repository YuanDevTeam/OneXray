import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/constants.dart';

@immutable
class AppPalette {
  // The confirmation overlay is shared by both prototype themes.
  static const restoreOverlay = Color.fromRGBO(5, 12, 30, 0.4);

  const AppPalette({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.popover,
    required this.popoverForeground,
    required this.primary,
    required this.primaryHover,
    required this.primaryText,
    required this.primarySolid,
    required this.primarySolidHover,
    required this.primaryForeground,
    required this.surfaceHover,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.mutedStrong,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.destructiveSolid,
    required this.destructiveSolidHover,
    required this.destructiveForeground,
    required this.border,
    required this.borderStrong,
    required this.input,
    required this.ring,
    required this.selection,
    required this.scannerBackground,
    required this.overlay,
    required this.header,
    required this.brand,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarPrimary,
    required this.sidebarPrimaryForeground,
    required this.sidebarAccent,
    required this.sidebarAccentForeground,
    required this.sidebarBorder,
    required this.sidebarRing,
    required this.selectedSurface,
    required this.running,
    required this.runningText,
    required this.runningBadge,
    required this.runningBadgeForeground,
    required this.runningForeground,
    required this.runningSurface,
    required this.restarting,
    required this.restartingText,
    required this.warningSurface,
    required this.destructiveSurface,
    required this.chart1,
    required this.chart2,
    required this.chart3,
    required this.chart4,
    required this.chart5,
  });

  // Semantic mapping of references/onexray-app-prototype/src/theme/tokens.json.
  // Interactive colors and solid button fills differ in the dark theme.
  static const light = AppPalette(
    background: Color(0xFFFEFEFE),
    foreground: Color(0xFF0E1020),
    card: Color(0xFFFEFEFE),
    cardForeground: Color(0xFF0E1020),
    popover: Color(0xFFFEFEFE),
    popoverForeground: Color(0xFF0E1020),
    primary: Color(0xFF1F6AF9),
    primaryHover: Color(0xFF185BD8),
    primaryText: Color(0xFF185BD8),
    primarySolid: Color(0xFF1F6AF9),
    primarySolidHover: Color(0xFF185BD8),
    primaryForeground: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFF4F7FA),
    secondary: Color(0xFFFEFEFE),
    secondaryForeground: Color(0xFF0E1020),
    muted: Color(0xFFF8FAFC),
    mutedForeground: Color(0xFF6F7688),
    mutedStrong: Color(0xFF565D6D),
    accent: Color(0xFFEEF5FF),
    accentForeground: Color(0xFF1F6AF9),
    destructive: Color(0xFFCF2828),
    destructiveSolid: Color(0xFFCF2828),
    destructiveSolidHover: Color(0xFFB82020),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFFDAE0E5),
    borderStrong: Color(0xFFCBD3DC),
    input: Color(0xFFDAE0E5),
    ring: Color(0xFF1F6AF9),
    selection: Color(0xFFEEF5FF),
    scannerBackground: Color(0xFF101B35),
    overlay: Color.fromRGBO(9, 17, 29, 0.48),
    header: Color(0xFFFEFEFE),
    brand: Color(0xFF071B55),
    sidebar: Color(0xFFF8FAFC),
    sidebarForeground: Color(0xFF565D6D),
    sidebarPrimary: Color(0xFF1F6AF9),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFFE4ECF7),
    sidebarAccentForeground: Color(0xFF133D70),
    sidebarBorder: Color(0xFFDAE0E5),
    sidebarRing: Color(0xFF1F6AF9),
    selectedSurface: Color(0xFFEEF5FF),
    running: Color(0xFF1FA04E),
    runningText: Color(0xFF15803D),
    runningBadge: Color(0xFF047857),
    runningBadgeForeground: Color(0xFFFFFFFF),
    runningForeground: Color(0xFF10141B),
    runningSurface: Color(0xFFEDF9F1),
    restarting: Color(0xFF9A6500),
    restartingText: Color(0xFF9A6500),
    warningSurface: Color(0xFFFFF7E6),
    destructiveSurface: Color(0xFFFFF1F1),
    chart1: Color(0xFF2584F5),
    chart2: Color(0xFF0BAA6B),
    chart3: Color(0xFFD98B00),
    chart4: Color(0xFFE54151),
    chart5: Color(0xFF8C54B2),
  );

  static const dark = AppPalette(
    background: Color(0xFF10151E),
    foreground: Color(0xFFF2F5F8),
    card: Color(0xFF10151E),
    cardForeground: Color(0xFFF2F5F8),
    popover: Color(0xFF10151E),
    popoverForeground: Color(0xFFF2F5F8),
    primary: Color(0xFF69A5FF),
    primaryHover: Color(0xFF8AB8FF),
    primaryText: Color(0xFF8AB8FF),
    primarySolid: Color(0xFF1F6AF9),
    primarySolidHover: Color(0xFF185BD8),
    primaryForeground: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFF1C2532),
    secondary: Color(0xFF10151E),
    secondaryForeground: Color(0xFFF2F5F8),
    muted: Color(0xFF151C27),
    mutedForeground: Color(0xFF9AA6B6),
    mutedStrong: Color(0xFFC2CAD5),
    accent: Color(0xFF172D4C),
    accentForeground: Color(0xFF69A5FF),
    destructive: Color(0xFFFF6262),
    destructiveSolid: Color(0xFFCF2828),
    destructiveSolidHover: Color(0xFFB82020),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFF2B3543),
    borderStrong: Color(0xFF3A4655),
    input: Color(0xFF2B3543),
    ring: Color(0xFF69A5FF),
    selection: Color(0xFF172D4C),
    scannerBackground: Color(0xFF101B35),
    overlay: Color.fromRGBO(9, 17, 29, 0.48),
    header: Color(0xFF10151E),
    brand: Color(0xFFA9CAFF),
    sidebar: Color(0xFF151C27),
    sidebarForeground: Color(0xFFC2CAD5),
    sidebarPrimary: Color(0xFF69A5FF),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFF1B232F),
    sidebarAccentForeground: Color(0xFFDDEDFF),
    sidebarBorder: Color(0xFF2B3543),
    sidebarRing: Color(0xFF69A5FF),
    selectedSurface: Color(0xFF172D4C),
    running: Color(0xFF55D484),
    runningText: Color(0xFF55D484),
    runningBadge: Color(0xFF6EE7B7),
    runningBadgeForeground: Color(0xFF052E16),
    runningForeground: Color(0xFF060B14),
    runningSurface: Color(0xFF163623),
    restarting: Color(0xFFF4BD5F),
    restartingText: Color(0xFFF4BD5F),
    warningSurface: Color(0xFF3A2D17),
    destructiveSurface: Color(0xFF3B1D21),
    chart1: Color(0xFF2584F5),
    chart2: Color(0xFF0BAA6B),
    chart3: Color(0xFFD98B00),
    chart4: Color(0xFFE54151),
    chart5: Color(0xFF8C54B2),
  );

  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color popover;
  final Color popoverForeground;
  final Color primary;
  final Color primaryHover;
  // Opaque small text on selectedSurface, independent of interaction state.
  final Color primaryText;
  final Color primarySolid;
  final Color primarySolidHover;
  // Foregrounds pair with solid fills, not the dark theme's interactive colors.
  final Color primaryForeground;
  final Color surfaceHover;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color mutedStrong;
  final Color accent;
  final Color accentForeground;
  final Color destructive;
  final Color destructiveSolid;
  final Color destructiveSolidHover;
  final Color destructiveForeground;
  final Color border;
  final Color borderStrong;
  final Color input;
  final Color ring;
  final Color selection;
  final Color scannerBackground;
  final Color overlay;
  final Color header;
  final Color sidebar;
  final Color brand;
  final Color sidebarForeground;
  final Color sidebarPrimary;
  final Color sidebarPrimaryForeground;
  final Color sidebarAccent;
  final Color sidebarAccentForeground;
  final Color sidebarBorder;
  final Color sidebarRing;
  final Color selectedSurface;
  final Color running;
  final Color runningText;
  final Color runningBadge;
  final Color runningBadgeForeground;
  final Color runningForeground;
  final Color runningSurface;
  final Color restarting;
  final Color restartingText;
  final Color warningSurface;
  final Color destructiveSurface;
  final Color chart1;
  final Color chart2;
  final Color chart3;
  final Color chart4;
  final Color chart5;

  static AppPalette lerp(AppPalette begin, AppPalette end, double t) {
    Color color(Color a, Color b) => Color.lerp(a, b, t) ?? b;

    return AppPalette(
      background: color(begin.background, end.background),
      foreground: color(begin.foreground, end.foreground),
      card: color(begin.card, end.card),
      cardForeground: color(begin.cardForeground, end.cardForeground),
      popover: color(begin.popover, end.popover),
      popoverForeground: color(begin.popoverForeground, end.popoverForeground),
      primary: color(begin.primary, end.primary),
      primaryHover: color(begin.primaryHover, end.primaryHover),
      primaryText: color(begin.primaryText, end.primaryText),
      primarySolid: color(begin.primarySolid, end.primarySolid),
      primarySolidHover: color(begin.primarySolidHover, end.primarySolidHover),
      primaryForeground: color(begin.primaryForeground, end.primaryForeground),
      surfaceHover: color(begin.surfaceHover, end.surfaceHover),
      secondary: color(begin.secondary, end.secondary),
      secondaryForeground: color(
        begin.secondaryForeground,
        end.secondaryForeground,
      ),
      muted: color(begin.muted, end.muted),
      mutedForeground: color(begin.mutedForeground, end.mutedForeground),
      mutedStrong: color(begin.mutedStrong, end.mutedStrong),
      accent: color(begin.accent, end.accent),
      accentForeground: color(begin.accentForeground, end.accentForeground),
      destructive: color(begin.destructive, end.destructive),
      destructiveSolid: color(begin.destructiveSolid, end.destructiveSolid),
      destructiveSolidHover: color(
        begin.destructiveSolidHover,
        end.destructiveSolidHover,
      ),
      destructiveForeground: color(
        begin.destructiveForeground,
        end.destructiveForeground,
      ),
      border: color(begin.border, end.border),
      borderStrong: color(begin.borderStrong, end.borderStrong),
      input: color(begin.input, end.input),
      ring: color(begin.ring, end.ring),
      selection: color(begin.selection, end.selection),
      scannerBackground: color(begin.scannerBackground, end.scannerBackground),
      overlay: color(begin.overlay, end.overlay),
      header: color(begin.header, end.header),
      sidebar: color(begin.sidebar, end.sidebar),
      brand: color(begin.brand, end.brand),
      sidebarForeground: color(begin.sidebarForeground, end.sidebarForeground),
      sidebarPrimary: color(begin.sidebarPrimary, end.sidebarPrimary),
      sidebarPrimaryForeground: color(
        begin.sidebarPrimaryForeground,
        end.sidebarPrimaryForeground,
      ),
      sidebarAccent: color(begin.sidebarAccent, end.sidebarAccent),
      sidebarAccentForeground: color(
        begin.sidebarAccentForeground,
        end.sidebarAccentForeground,
      ),
      sidebarBorder: color(begin.sidebarBorder, end.sidebarBorder),
      sidebarRing: color(begin.sidebarRing, end.sidebarRing),
      selectedSurface: color(begin.selectedSurface, end.selectedSurface),
      running: color(begin.running, end.running),
      runningText: color(begin.runningText, end.runningText),
      runningBadge: color(begin.runningBadge, end.runningBadge),
      runningBadgeForeground: color(
        begin.runningBadgeForeground,
        end.runningBadgeForeground,
      ),
      runningForeground: color(begin.runningForeground, end.runningForeground),
      runningSurface: color(begin.runningSurface, end.runningSurface),
      restarting: color(begin.restarting, end.restarting),
      restartingText: color(begin.restartingText, end.restartingText),
      warningSurface: color(begin.warningSurface, end.warningSurface),
      destructiveSurface: color(
        begin.destructiveSurface,
        end.destructiveSurface,
      ),
      chart1: color(begin.chart1, end.chart1),
      chart2: color(begin.chart2, end.chart2),
      chart3: color(begin.chart3, end.chart3),
      chart4: color(begin.chart4, end.chart4),
      chart5: color(begin.chart5, end.chart5),
    );
  }
}

class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens(this.palette);

  static const light = AppColorTokens(AppPalette.light);
  static const dark = AppColorTokens(AppPalette.dark);

  final AppPalette palette;

  Color get surface => palette.card;
  Color get surfaceBorder => palette.border;
  Color get primaryText => palette.foreground;
  Color get secondaryText => palette.mutedForeground;
  Color get tagBackground => palette.muted;
  Color get selectedBackground => palette.selectedSurface;

  static AppColorTokens fallback(Brightness brightness) {
    return brightness == Brightness.light ? light : dark;
  }

  @override
  AppColorTokens copyWith({AppPalette? palette}) {
    return AppColorTokens(palette ?? this.palette);
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) {
      return this;
    }
    return AppColorTokens(AppPalette.lerp(palette, other.palette, t));
  }
}

class ColorManager {
  static AppColorTokens tokens(BuildContext context) {
    return Theme.of(context).extension<AppColorTokens>() ??
        AppColorTokens.fallback(Theme.of(context).brightness);
  }

  static AppPalette palette(BuildContext context) => tokens(context).palette;

  static Color surface(BuildContext context) => tokens(context).surface;

  static Color primaryText(BuildContext context) => tokens(context).primaryText;

  static Color secondaryText(BuildContext context) {
    return tokens(context).secondaryText;
  }

  static Color nodeLatency(BuildContext context, int delay) {
    final colors = palette(context);
    if (!PingDelayConstants.isSuccessful(delay)) return colors.mutedForeground;
    // These tones remain legible as small text on normal and selected cards.
    return delay <= 500
        ? colors.runningBadge
        : delay <= 1000
        ? colors.restartingText
        : colors.primaryHover;
  }

  static Color tagBackground(BuildContext context) {
    return tokens(context).tagBackground;
  }

  static Color border(BuildContext context) => tokens(context).surfaceBorder;

  static Color selected(BuildContext context) {
    return tokens(context).selectedBackground;
  }
}
