import 'package:flutter/foundation.dart';

/// Shared logical-pixel values mapped from the approved prototype theme.
/// Keep platform safe areas and text scaling outside these constants.
abstract final class AppLayout {
  /// Touch requirements follow the input platform, including wide phone windows.
  static double touchExtent(double size, {TargetPlatform? platform}) {
    final minimum = switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.iOS => 44.0,
      TargetPlatform.android => 48.0,
      _ => 0.0,
    };
    return size < minimum ? minimum : size;
  }

  static const macOSTitlebarHeight = 28.0;
  static const mobileBreakpoint = 720.0;
  static const compactDesktopBreakpoint = 900.0;
  static const desktopSidebarWidth = 225.0;
  static const compactSidebarWidth = 190.0;
  static const standardMaxWidth = 1120.0;
  static const advancedMaxWidth = 980.0;
  static const settingsMaxWidth = 1176.0;
  static const routingMaxWidth = 1220.0;
  static const routingEditorMaxWidth = 760.0;
  static const contentBreakpoint = 840.0;
  static const pageActionMinHeight = 72.0;
  static const mobilePageActionMinHeight = 64.0;
  static const pageActionButtonMinHeight = 46.0;
  static const pageActionButtonMinWidth = 150.0;
  static const buttonMinHeight = 40.0;
  static const mobileButtonMinHeight = 42.0;
  static const setupContentMaxWidth = 760.0;
  static const setupProgressMaxWidth = 840.0;
  static const setupFooterMaxWidth = 1200.0;
  static const setupFooterMinHeight = 80.0;
  static const setupFooterButtonWidth = 210.0;
  static const switchWidth = 42.0;
  static const switchHeight = 24.0;
  static const switchThumbMargin = 2.0;
  static const emptyStateDesktopMinHeight = 520.0;
  static const emptyStateTextMaxWidth = 420.0;
  static const connectStatusMinHeight = 158.0;
  static const connectDesktopStatusMinHeight = 256.0;
  static const connectDesktopButtonWidth = 228.0;
  static const connectDesktopButtonMinHeight = 54.0;
  static const connectDesktopExpertRowMinHeight = 54.0;
  static const connectDesktopChoiceMinHeight = 72.0;
  static const connectDesktopTrafficGroupMinHeight = 165.0;
  static const connectDesktopRawEmptyMinHeight = 204.0;
  static const connectDesktopPanelViewportInset = 102.0;
  static const connectButtonMinHeight = 45.0;
  static const connectExpertRowMinHeight = 47.0;
  static const connectChoiceMinHeight = 49.0;
  static const connectTrafficGroupMinHeight = 80.0;
  static const dialogWidth = 540.0;
  static const sourcesDialogWidth = 730.0;
  static const dialogMaxHeight = 820.0;
  static const dialogMobileHeightFactor = 0.9;
  static const dialogDesktopHeightFactor = 0.86;
  static const dialogHeaderMinHeight = 88.0;
  static const dialogMobileHeaderMinHeight = 80.0;
  static const dialogBlur = 3.0;
  static const dialogCloseSize = 36.0;
}

abstract final class AppSpacing {
  static double advancedDesktopGutter(double viewportWidth) =>
      (viewportWidth * .04).clamp(28.0, 48.0);
  static const page = 28.0;
  static const desktopPageTop = 43.0;
  static const desktopPageBottom = 42.0;
  static const sidebarHorizontal = 17.0;
  static const sidebarVertical = 36.0;
  static const macOSSidebarVertical = 16.0;
  static const macOSSidebarBrandBottom = 24.0;
  static const sidebarBrandStart = 24.0;
  static const sidebarCompactBrandStart = 14.0;
  static const sidebarBrandTop = 5.0;
  static const sidebarBrandBottom = 40.0;
  static const sidebarRowHeight = 50.0;
  static const sidebarRowGap = 7.0;
  static const mobilePage = 14.0;
  static const mobileHeaderHorizontal = 16.0;
  static const connectPageHorizontal = 15.0;
  static const connectPageTop = 4.0;
  static const connectPageBottom = 22.0;
  static const controlHorizontal = 12.0;
  static const buttonHorizontal = 15.0;
  static const controlVertical = 10.0;
  static const actionGap = 10.0;
  static const actionRunGap = 8.0;
  static const setupDesktopHorizontal = 40.0;
  static const setupDesktopTop = 28.0;
}

abstract final class AppRadii {
  static const small = 4.0;
  static const card = 8.0;
  static const control = 7.0;
  static const compact = 6.0;
  static const chip = 5.0;
  static const indicator = 3.0;
  static const pill = 999.0;
  static const dialog = 12.0;
  static const mobileDialog = 15.0;
}
