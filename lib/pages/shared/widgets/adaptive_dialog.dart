import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';

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
      : ColorManager.palette(context).overlay,
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
          Positioned.fill(
            child: IgnorePointer(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: AppLayout.dialogBlur,
                  sigmaY: AppLayout.dialogBlur,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          SafeArea(
            top: !mobile,
            bottom: !mobile,
            child: Padding(
              padding: mobile
                  ? EdgeInsets.only(bottom: keyboard)
                  : EdgeInsets.fromLTRB(20, 20, 20, 20 + keyboard),
              child: Align(
                alignment: mobile ? Alignment.bottomCenter : Alignment.center,
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
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final radius = mobile
        ? const BorderRadius.vertical(
            top: Radius.circular(AppRadii.mobileDialog),
          )
        : const BorderRadius.all(Radius.circular(AppRadii.dialog));
    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      // Extend the surface beneath system gestures; inset only its content.
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: mobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      constraints: BoxConstraints(
                        minHeight: mobile
                            ? AppLayout.dialogMobileHeaderMinHeight
                            : AppLayout.dialogHeaderMinHeight,
                      ),
                      padding: mobile
                          ? const EdgeInsets.fromLTRB(16, 17, 16, 14)
                          : const EdgeInsets.fromLTRB(21, 20, 21, 17),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: palette.border),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (onBack != null) ...[
                            TextButton(
                              onPressed: onBack,
                              style: TextButton.styleFrom(
                                minimumSize: Size.square(
                                  AppLayout.touchExtent(
                                    34,
                                    platform: Theme.of(context).platform,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: AppTypography.dialogBack,
                              ),
                              child: Text(
                                AppLocalizations.of(context)!.prototypeBack,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: mobile
                                      ? AppTypography.dialogTitle
                                      : AppTypography.confirmationDesktopTitle,
                                ),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle!,
                                    style: AppTypography.dialogSubtitle
                                        .copyWith(
                                          color: palette.mutedForeground,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            autofocus: true,
                            tooltip: AppLocalizations.of(context)!
                                .prototypeCloseDialog,
                            onPressed:
                                onClose ?? () => Navigator.of(context).pop(),
                            style: IconButton.styleFrom(
                              foregroundColor: palette.mutedStrong,
                              minimumSize: Size.square(
                                AppLayout.touchExtent(
                                  AppLayout.dialogCloseSize,
                                  platform: Theme.of(context).platform,
                                ),
                              ),
                              maximumSize: Size.square(
                                AppLayout.touchExtent(
                                  AppLayout.dialogCloseSize,
                                  platform: Theme.of(context).platform,
                                ),
                              ),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(LucideIcons.x, size: 20),
                          ),
                        ],
                      ),
                    ),
                    body,
                    if (!mobile && actions.isNotEmpty)
                      _actions(context, mobile: false),
                  ],
                ),
              ),
            ),
            if (mobile && actions.isNotEmpty) _actions(context, mobile: true),
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, {required bool mobile}) {
    final palette = ColorManager.palette(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 16 : 20,
        vertical: mobile ? 12 : 14,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (var index = 0; index < actions.length; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.actionGap),
              if (mobile && expandLastAction && index == actions.length - 1)
                Expanded(child: actions[index])
              else if (mobile && expandLastAction)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.62,
                  ),
                  child: IntrinsicWidth(child: actions[index]),
                )
              else
                Flexible(child: actions[index]),
            ],
          ],
        ),
      ),
    );
  }
}
