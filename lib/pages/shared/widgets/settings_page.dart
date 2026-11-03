import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SettingsPageScaffold extends StatelessWidget {
  final String title;
  final String? description;
  final Widget body;
  final VoidCallback? onSave;
  final bool saveLoading;
  final String? saveLabel;
  final List<Widget> actions;

  const SettingsPageScaffold({
    super.key,
    required this.title,
    this.description,
    required this.body,
    this.onSave,
    this.saveLoading = false,
    this.saveLabel,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageAppBar.forPage(
        context,
        title: Text(title),
        description: description,
        actions: [
          ...actions,
          if (onSave != null || saveLoading) _saveButton(context),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _saveButton(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final icon = saveLoading
        ? const SizedBox.square(
            dimension: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(LucideIcons.save);
    if (compact || saveLabel == null) {
      final button = ShadIconButton(
        icon: icon,
        onPressed: saveLoading ? null : onSave,
      );
      final label = saveLabel;
      return label == null ? button : Tooltip(message: label, child: button);
    }
    return ShadButton(
      leading: icon,
      onPressed: saveLoading ? null : onSave,
      child: Text(saveLabel!),
    );
  }
}

class SettingsPageScroll extends StatelessWidget {
  final Widget child;
  final double desktopMaxWidth;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  const SettingsPageScroll({
    super.key,
    required this.child,
    this.desktopMaxWidth = AppLayout.standardMaxWidth,
    this.padding = const EdgeInsetsDirectional.only(bottom: 24),
    this.alignment = AlignmentDirectional.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: padding,
      child: ResponsiveContent(
        desktopMaxWidth: desktopMaxWidth,
        alignment: alignment,
        child: child,
      ),
    );
  }
}

class SettingsChoiceIndicator extends StatelessWidget {
  final bool selected;

  const SettingsChoiceIndicator({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? primary : Colors.transparent,
        border: Border.all(
          color: selected ? primary : ColorManager.border(context),
        ),
        shape: BoxShape.circle,
      ),
      child: selected
          ? Icon(
              LucideIcons.check,
              size: 13,
              color: Theme.of(context).colorScheme.onPrimary,
            )
          : null,
    );
  }
}

class SettingsChoiceRow extends StatelessWidget {
  final String title;
  final String? description;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onTap;

  const SettingsChoiceRow({
    super.key,
    required this.title,
    this.description,
    this.leading,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: title,
      subtitle: description,
      leading: leading,
      onTap: onTap,
      trailing: SettingsChoiceIndicator(selected: selected),
    );
  }
}

class AppConfirmationDialog extends StatelessWidget {
  final String title;
  final String? subject;
  final String content;
  final String cancelLabel;
  final String confirmLabel;
  final bool destructive;
  final bool expandConfirm;
  final bool barrierDismissible;

  const AppConfirmationDialog({
    super.key,
    required this.title,
    this.subject,
    required this.content,
    required this.cancelLabel,
    required this.confirmLabel,
    this.destructive = false,
    this.expandConfirm = false,
    this.barrierDismissible = true,
  });

  Future<bool> show(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: barrierDismissible,
        useSafeArea: false,
        barrierColor: Colors.black.withValues(alpha: .45),
        builder: (_) => this,
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width <= AppLayout.mobileBreakpoint;
    final closeSize = AppLayout.touchExtent(
      40,
      platform: Theme.of(context).platform,
    );
    final buttonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(
          0,
          AppLayout.touchExtent(
            mobile
                ? AppLayout.mobileButtonMinHeight
                : AppLayout.buttonMinHeight,
            platform: Theme.of(context).platform,
          ),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.buttonHorizontal),
      ),
      textStyle: WidgetStatePropertyAll(AppTypography.control),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
    final confirm = FilledButton(
      onPressed: () => Navigator.pop(context, true),
      style:
          (destructive
                  ? buttonStyle.merge(AppTheme.destructiveButton(context))
                  : buttonStyle)
              .copyWith(
                shape: const WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppRadii.cta),
                    ),
                  ),
                ),
              ),
      child: Text(confirmLabel, textAlign: TextAlign.center),
    );
    final cancel = OutlinedButton(
      onPressed: () => Navigator.pop(context, false),
      style: buttonStyle.copyWith(
        side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
          ),
        ),
      ),
      child: Text(cancelLabel, textAlign: TextAlign.center),
    );
    return SafeArea(
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            size.width < 640 ? 0 : AppRadii.card,
          ),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(520.0, math.max(0.0, size.width - 32)),
            maxHeight: math.min(
              AppLayout.dialogMaxHeight,
              size.height *
                  (mobile
                      ? AppLayout.dialogMobileHeightFactor
                      : AppLayout.dialogDesktopHeightFactor),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pinActions =
                  constraints.maxHeight >= 380 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 28;
              final actions = LayoutBuilder(
                builder: (context, constraints) {
                  double naturalWidth(String label) {
                    final painter = TextPainter(
                      text: TextSpan(
                        text: label,
                        style: AppTypography.control.copyWith(
                          fontFamily: AppFontFamily.sans,
                        ),
                      ),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout();
                    final width =
                        painter.width + AppSpacing.buttonHorizontal * 2;
                    painter.dispose();
                    return width;
                  }

                  final vertical =
                      size.width < 560 ||
                      naturalWidth(cancelLabel) +
                              naturalWidth(confirmLabel) +
                              10 >
                          constraints.maxWidth;
                  if (vertical) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [cancel, const SizedBox(height: 10), confirm],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(child: cancel),
                      const SizedBox(width: 10),
                      Flexible(child: confirm),
                    ],
                  );
                },
              );
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
                                Padding(
                                  padding: EdgeInsetsDirectional.only(
                                    end: closeSize - 16,
                                  ),
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      title,
                                      style: AppTypography.confirmationTitle
                                          .copyWith(color: palette.foreground),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (subject != null) ...[
                                  Text(
                                    subject!,
                                    style: AppTypography.confirmationSubject
                                        .copyWith(color: palette.foreground),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                Text(
                                  content,
                                  style: AppTypography.confirmationBody
                                      .copyWith(color: palette.mutedForeground),
                                ),
                                if (!pinActions) ...[
                                  const SizedBox(height: 8),
                                  actions,
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (pinActions) const SizedBox(height: 8),
                        if (pinActions) actions,
                      ],
                    ),
                  ),
                  PositionedDirectional(
                    top: 8,
                    end: 8,
                    child: IconButton(
                      autofocus: true,
                      tooltip: AppLocalizations.of(context)!
                          .prototypeCloseDialog,
                      onPressed: () => Navigator.pop(context, false),
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
        ),
      ),
    );
  }
}
