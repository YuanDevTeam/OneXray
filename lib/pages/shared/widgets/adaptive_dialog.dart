import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme;

/// A modal selection surface, separate from full-page child navigation.
Future<T?> showChoiceDialog<T>(BuildContext context, WidgetBuilder builder) {
  if (MediaQuery.sizeOf(context).width < 700) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: builder(context),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    useRootNavigator: false,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: builder(context),
      ),
    ),
  );
}

/// Shared presentation for prototype-aligned dialogs. System prompts stay native.
Future<T?> showAppDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  double desktopMaxWidth = AppLayout.dialogWidth,
}) => showGeneralDialog<T>(
  context: context,
  useRootNavigator: false,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  // The previous wizard step still owns its barrier while its card is offstage.
  barrierColor: ModalRoute.of(context) is PopupRoute
      ? Colors.transparent
      : Colors.black.withValues(alpha: .8),
  pageBuilder: (context, animation, secondaryAnimation) =>
      AppDialogFrame(desktopMaxWidth: desktopMaxWidth, child: builder(context)),
);

/// The same responsive surface for imperative dialogs and GoRouter pages.
class AppDialogFrame extends StatelessWidget {
  const AppDialogFrame({
    super.key,
    required this.child,
    this.desktopMaxWidth = AppLayout.dialogWidth,
  });

  final Widget child;
  final double desktopMaxWidth;

  @override
  Widget build(BuildContext context) {
    // A wizard may push another dialog step. Keep only the current surface
    // visible so Back restores its state without stacking two modal cards.
    final covered = ModalRoute.of(context)?.isCurrent == false;
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width <= AppLayout.mobileBreakpoint;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafeArea = mobile && keyboard == 0
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;
    return Offstage(
      offstage: covered,
      child: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: mobile
                  ? EdgeInsets.only(bottom: keyboard)
                  : EdgeInsets.fromLTRB(20, 20, 20, 20 + keyboard),
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: mobile ? size.width : desktopMaxWidth,
                    maxHeight: math.min(
                      math.min(
                        AppLayout.dialogMaxHeight + bottomSafeArea,
                        math.max(0, size.height - keyboard - 32),
                      ),
                      bottomSafeArea +
                          size.height *
                              (mobile
                                  ? AppLayout.dialogMobileHeightFactor
                                  : AppLayout.dialogDesktopHeightFactor),
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.actions = const [],
    this.expandLastAction = true,
    this.onBack,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final bool expandLastAction;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final narrow = MediaQuery.sizeOf(context).width < 640;
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final closeSize = AppLayout.touchExtent(
      40,
      platform: Theme.of(context).platform,
    );
    final textAlign = narrow ? TextAlign.center : TextAlign.start;
    final header = Padding(
      padding: EdgeInsetsDirectional.only(end: closeSize - 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null) ...[
            TextButton(
              onPressed: onBack,
              style: TextButton.styleFrom(
                minimumSize: Size.square(
                  AppLayout.touchExtent(
                    40,
                    platform: Theme.of(context).platform,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: AppTypography.control,
              ),
              child: Text(AppLocalizations.of(context)!.prototypeBack),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: textAlign,
                    style: AppTypography.dialogTitle.copyWith(
                      color: palette.foreground,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle!,
                    textAlign: textAlign,
                    style: AppTypography.dialogSubtitle.copyWith(
                      color: palette.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Material(
      color: palette.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(narrow ? 0 : 8),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pinActions =
              mobile &&
              constraints.maxHeight >= 380 &&
              MediaQuery.textScalerOf(context).scale(14) <= 28;
          return Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            header,
                            const SizedBox(height: 8),
                            body,
                            if (!pinActions && actions.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _actions(context),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (pinActions && actions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _actions(context),
                    ],
                  ],
                ),
              ),
              PositionedDirectional(
                top: 8,
                end: 8,
                child: IconButton(
                  autofocus: true,
                  tooltip: AppLocalizations.of(context)!.prototypeCloseDialog,
                  onPressed: onClose ?? () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    foregroundColor: palette.mutedForeground,
                    minimumSize: Size.square(closeSize),
                    maximumSize: Size.square(closeSize),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(LucideIcons.x, size: 20),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _action(
    BuildContext context,
    Widget action, {
    bool intrinsic = false,
  }) {
    final minimum = AppLayout.touchExtent(
      MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint ? 48 : 42,
      platform: Theme.of(context).platform,
    );
    Widget result = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minimum),
      child: action,
    );
    final shad = ShadTheme.maybeOf(context);
    if (shad != null) {
      result = ShadTheme(
        data: shad.copyWith(
          primaryButtonTheme: shad.primaryButtonTheme.copyWith(
            height: 0,
            expands: true,
          ),
          outlineButtonTheme: shad.outlineButtonTheme.copyWith(
            height: 0,
            expands: true,
          ),
          secondaryButtonTheme: shad.secondaryButtonTheme.copyWith(
            height: 0,
            expands: true,
          ),
          destructiveButtonTheme: shad.destructiveButtonTheme.copyWith(
            height: 0,
            expands: true,
          ),
          ghostButtonTheme: shad.ghostButtonTheme.copyWith(
            height: 0,
            expands: true,
          ),
          linkButtonTheme: shad.linkButtonTheme.copyWith(
            height: 0,
            expands: true,
          ),
        ),
        child: result,
      );
    }
    return intrinsic ? IntrinsicWidth(child: result) : result;
  }

  Widget _actions(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 640) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _action(context, actions[index]),
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final action in actions)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: _action(context, action, intrinsic: true),
            ),
        ],
      ),
    );
  }
}
