import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';

Future<T?> showConnectDialog<T>(BuildContext context, WidgetBuilder builder) =>
    showAppDialog<T>(context, builder);

Future<bool> showDestructiveConfirmationDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String warning,
  required String confirmLabel,
}) async =>
    await showAppDialog<bool>(context, (dialogContext) {
      final l = AppLocalizations.of(dialogContext)!;
      return AppDialog(
        title: title,
        subtitle: subtitle,
        expandLastAction: false,
        body: ConnectCallout(
          icon: LucideIcons.circleAlert,
          text: warning,
          warning: true,
        ),
        actions: [
          ConnectDialogButton(
            label: l.prototypeCancel,
            secondary: true,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          ConnectDialogButton(
            label: confirmLabel,
            icon: LucideIcons.trash2,
            destructive: true,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      );
    }) ??
    false;

Future<bool> showApplyAndReconnectDialog(
  BuildContext context, {
  required String label,
}) async {
  final l = AppLocalizations.of(context)!;
  return await showAppDialog<bool>(
        context,
        (dialogContext) => AppDialog(
          title: l.prototypeApplyChange,
          subtitle: l.prototypeReconnectNotice,
          body: ConnectCallout(
            icon: LucideIcons.refreshCw,
            text: l.prototypeWillUseName(label),
          ),
          actions: [
            ConnectDialogButton(
              label: l.prototypeCancel,
              secondary: true,
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
            ConnectDialogButton(
              label: l.prototypeApplyAndReconnect,
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
      ) ==
      true;
}

typedef ConnectDialog = AppDialog;

class ConnectDialogButton extends StatelessWidget {
  const ConnectDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.destructive = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary;
  final bool destructive;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy || icon != null) ...[
          if (busy) const ButtonProgressIndicator() else Icon(icon, size: 16),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    if (secondary) {
      return OutlinedButton(
        onPressed: onPressed,
        style: ButtonStyle(
          side: WidgetStatePropertyAll(BorderSide(color: palette.borderStrong)),
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: destructive ? AppTheme.destructiveButton(context) : null,
      child: child,
    );
  }
}

class ConnectCallout extends StatelessWidget {
  const ConnectCallout({
    super.key,
    required this.icon,
    required this.text,
    this.warning = false,
  });
  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warning ? palette.destructiveSurface : palette.muted,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: icon == LucideIcons.lockKeyhole ? 17 : 21,
            color: warning ? palette.destructive : palette.primary,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: AppTypography.dialogCallout.copyWith(
                color: warning ? palette.destructive : palette.mutedStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> showCustomRoutingModeDialog(BuildContext context) =>
    showAppDialog<bool>(context, (dialogContext) {
      final l = AppLocalizations.of(dialogContext)!;
      return AppDialog(
        title: l.prototypeNewCustomRoute,
        onClose: () => Navigator.pop(dialogContext),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MethodOption(
                title: l.routingNormalConfiguration,
                description: l.prototypeCustomRoutingDescription,
                selected: false,
                onPressed: () => Navigator.pop(dialogContext, false),
              ),
              const SizedBox(height: 12),
              _MethodOption(
                title: l.routingAdvancedJson,
                description: l.routingAdvancedSummary,
                selected: false,
                onPressed: () => Navigator.pop(dialogContext, true),
              ),
            ],
          ),
        ),
      );
    });

class _MethodOption extends StatelessWidget {
  const _MethodOption({
    required this.title,
    required this.description,
    required this.selected,
    required this.onPressed,
  });
  final String title, description;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      decoration: BoxDecoration(
        color: selected ? palette.selectedSurface : palette.card,
        border: Border.all(
          color: selected
              ? Color.lerp(palette.border, palette.primary, 0.48)!
              : palette.border,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              selected: selected,
              child: TextButton(
                onPressed: onPressed,
                style: TextButton.styleFrom(
                  foregroundColor: palette.foreground,
                  minimumSize: const Size(0, 80),
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 0, 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: palette.selectedSurface,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        LucideIcons.shieldCheck,
                        size: 21,
                        color: palette.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppTypography.dialogOptionTitle),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: AppTypography.dialogOptionDescription
                                .copyWith(color: palette.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            selected ? LucideIcons.circleCheck : LucideIcons.arrowRightDir,
            size: selected ? 21 : 18,
            color: selected ? palette.running : palette.foreground,
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

class ConnectExplanation extends StatelessWidget {
  const ConnectExplanation({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 22, color: ColorManager.palette(context).primary),
      const SizedBox(width: 12),
      Expanded(child: Text(text, style: AppTypography.dialogBody)),
    ],
  );
}
