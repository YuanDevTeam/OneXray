import 'dart:math' as math;

import 'package:go_router/go_router.dart';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ContextAlert {
  static Future<void> showPermissionDialog(
    BuildContext context, {
    String? title,
    String? message,
    Future<bool> Function()? openSettings,
  }) async {
    final confirmed = await _showDialog<bool>(
      context: context,
      variant: ShadDialogVariant.alert,
      builder: (ctx) => ShadDialog.alert(
        title: _dialogTitle(
          ctx,
          icon: LucideIcons.shieldAlert,
          title: title ?? AppLocalizations.of(ctx)!.permissionDialogTitle,
        ),
        description: _dialogDescription(
          ctx,
          message ?? AppLocalizations.of(ctx)!.homePageOpenSettings,
        ),
        backgroundColor: _dialogBackground(ctx),
        closeIcon: const SizedBox.shrink(),
        constraints: _dialogConstraints(ctx),
        padding: const EdgeInsets.all(24),
        gap: 8,
        removeBorderRadiusWhenTiny: true,
        titleTextAlign: TextAlign.start,
        descriptionTextAlign: TextAlign.start,
        scrollable: false,
        useSafeArea: false,
        actionsAxis: Axis.vertical,
        actions: [
          _dialogAction(
            ctx,
            AppLocalizations.of(ctx)!.buttonCancel,
            () => Navigator.of(ctx).pop(false),
            outline: true,
            expanded: true,
          ),
          _dialogAction(
            ctx,
            AppLocalizations.of(ctx)!.buttonOpenSettings,
            () => Navigator.of(ctx).pop(true),
            expanded: true,
          ),
        ],
      ),
    );
    if (confirmed == true) {
      Object failure = 'The system settings page could not be opened.';
      try {
        if (await (openSettings ?? openAppSettings)()) return;
      } catch (error) {
        failure = error;
      }
      if (context.mounted) {
        showToast(
          context,
          appFailureMessage(AppLocalizations.of(context)!, failure),
        );
      }
    }
  }

  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    String? content,
    String? confirmLabel,
  }) async {
    final l = AppLocalizations.of(context)!;
    final confirmText = confirmLabel ?? l.buttonOK;
    final confirmed = await _showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: (ctx) => LayoutBuilder(
        builder: (ctx, viewport) {
          final viewportWidth = math.min(
            MediaQuery.sizeOf(ctx).width,
            viewport.maxWidth,
          );
          final width = math.min(520.0, math.max(0.0, viewportWidth - 32));
          final vertical =
              viewportWidth < 560 ||
              _actionWidth(ctx, l.buttonCancel, outline: true) +
                      _actionWidth(ctx, confirmText) +
                      10 >
                  width - 48;
          return ShadDialog(
            title: Semantics(
              header: true,
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  end:
                      AppLayout.touchExtent(
                        40,
                        platform: Theme.of(ctx).platform,
                      ) -
                      16,
                ),
                child: Text(title, style: AppTypography.confirmationTitle),
              ),
            ),
            description: content == null
                ? null
                : SelectionArea(
                    child: Text(
                      content,
                      style: AppTypography.confirmationBody.copyWith(
                        color: ShadTheme.of(ctx).colorScheme.mutedForeground,
                      ),
                    ),
                  ),
            backgroundColor: ShadTheme.of(ctx).colorScheme.card,
            radius: BorderRadius.circular(
              MediaQuery.sizeOf(ctx).width < 640 ? 0 : AppRadii.card,
            ),
            border: Border.all(color: ShadTheme.of(ctx).colorScheme.border),
            constraints: BoxConstraints(
              maxWidth: width,
              maxHeight: MediaQuery.sizeOf(ctx).height * .9,
            ),
            padding: const EdgeInsets.all(24),
            gap: 8,
            actionsGap: 10,
            removeBorderRadiusWhenTiny: true,
            expandActionsWhenTiny: false,
            titleTextAlign: TextAlign.start,
            descriptionTextAlign: TextAlign.start,
            scrollable: true,
            actionsAxis: vertical ? Axis.vertical : Axis.horizontal,
            closeIcon: IconButton(
              autofocus: true,
              tooltip: l.prototypeCloseDialog,
              onPressed: () => Navigator.of(ctx).pop(false),
              style: IconButton.styleFrom(
                minimumSize: Size.square(
                  AppLayout.touchExtent(40, platform: Theme.of(ctx).platform),
                ),
                maximumSize: Size.square(
                  AppLayout.touchExtent(40, platform: Theme.of(ctx).platform),
                ),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(LucideIcons.x, size: 20),
            ),
            actions: [
              _dialogAction(
                ctx,
                l.buttonCancel,
                () => Navigator.of(ctx).pop(false),
                outline: true,
                expanded: vertical,
              ),
              _dialogAction(
                ctx,
                confirmText,
                () => Navigator.of(ctx).pop(true),
                expanded: vertical,
              ),
            ],
          );
        },
      ),
    );
    return confirmed ?? false;
  }

  static void settingsSaved(BuildContext context, {bool closePage = false}) {
    showToast(context, AppLocalizations.of(context)!.prototypeSettingsSaved);
    if (closePage && ModalRoute.of(context)?.isCurrent == true) context.pop();
  }

  static void showToast(BuildContext context, String message) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    final availableWidth = math.max(0.0, size.width - 32);
    final maxWidth = compact ? availableWidth : math.min(420.0, availableWidth);
    final minWidth = compact ? maxWidth : math.min(320.0, maxWidth);
    final colors = ShadTheme.of(context).colorScheme;
    ShadToaster.of(context).show(
      ShadToast(
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.info, size: 18, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        alignment: compact ? Alignment.bottomCenter : Alignment.bottomRight,
        backgroundColor: colors.popover,
        constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 36, 14),
        crossAxisAlignment: CrossAxisAlignment.start,
        showCloseIconOnlyWhenHovered: false,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static Future<T?> _showDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    ShadDialogVariant variant = ShadDialogVariant.primary,
    Color? barrierColor,
  }) {
    return showShadDialog<T>(
      context: context,
      builder: builder,
      variant: variant,
      barrierColor: barrierColor ?? Colors.black.withValues(alpha: .8),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      opaque: false,
    );
  }

  static BoxConstraints _dialogConstraints(BuildContext context) {
    final availableWidth = math.max(0.0, MediaQuery.sizeOf(context).width - 32);
    final maxWidth = math.min(440.0, availableWidth);
    return BoxConstraints(
      minWidth: math.min(320.0, maxWidth),
      maxWidth: maxWidth,
    );
  }

  static Color _dialogBackground(BuildContext context) {
    return ShadTheme.of(context).colorScheme.popover;
  }

  static Widget _dialogDescription(BuildContext context, String content) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.48,
      ),
      child: SingleChildScrollView(
        child: SelectionArea(
          child: Text(
            content,
            textAlign: TextAlign.start,
            style: AppTypography.dialogSubtitle.copyWith(
              color: ShadTheme.of(context).colorScheme.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _dialogTitle(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) {
    final colors = ShadTheme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.start,
              style: AppTypography.dialogTitle,
            ),
          ),
        ),
      ],
    );
  }

  static double _actionWidth(
    BuildContext context,
    String label, {
    bool outline = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: AppTypography.control.copyWith(fontFamily: AppFontFamily.sans),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width.ceilToDouble() + 32 + (outline ? 2 : 0);
    painter.dispose();
    return width;
  }

  static Widget _dialogAction(
    BuildContext context,
    String label,
    VoidCallback onPressed, {
    bool outline = false,
    bool expanded = false,
  }) => ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: AppLayout.touchExtent(
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint
            ? 48
            : 42,
        platform: Theme.of(context).platform,
      ),
    ),
    child: ShadButton.raw(
      variant: outline ? ShadButtonVariant.outline : ShadButtonVariant.primary,
      width: expanded
          ? double.infinity
          : _actionWidth(context, label, outline: outline) - (outline ? 2 : 0),
      height: 0,
      expands: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      onPressed: onPressed,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTypography.control,
      ),
    ),
  );
}
