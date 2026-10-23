import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class PolicyDetailScaffold extends StatelessWidget {
  final String title;
  final PolicyEditorController controller;
  final Widget body;
  final bool canSave;
  final EdgeInsetsGeometry contentPadding;
  final List<String> help;

  const PolicyDetailScaffold({
    super.key,
    required this.title,
    required this.controller,
    required this.body,
    this.canSave = true,
    this.contentPadding = const EdgeInsetsDirectional.only(bottom: 24),
    this.help = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: PageAppBar(
        title: Text(title),
        leading: BackButton(onPressed: () => controller.cancel(context)),
        actions: [
          if (help.isNotEmpty) PageHelpButton(title: title, messages: help),
        ],
      ),
      body: SafeArea(
        child: SettingsPageScroll(
          desktopMaxWidth: AppLayout.advancedMaxWidth,
          padding: contentPadding,
          child: body,
        ),
      ),
      bottomNavigationBar: PolicyActions(
        controller: controller,
        canSave: canSave,
        cancel: () => controller.cancel(context),
        save: () => controller.save(context),
        cancelLabel: l.prototypeCancel,
      ),
    );
  }
}

class PolicyActions extends StatelessWidget {
  final PolicyEditorController controller;
  final bool canSave;
  final VoidCallback cancel;
  final VoidCallback save;
  final String cancelLabel;
  final IconData? cancelIcon;
  final bool root;
  const PolicyActions({
    super.key,
    required this.controller,
    required this.cancel,
    required this.save,
    required this.cancelLabel,
    this.cancelIcon,
    this.root = false,
    this.canSave = true,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width <= AppLayout.mobileBreakpoint;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height / 4,
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ),
        PageActionBar(
          maxWidth: AppLayout.advancedMaxWidth,
          expandDesktop: true,
          horizontalPadding: mobile
              ? (root ? 15 : null)
              : AppSpacing.advancedDesktopGutter(width),
          spacing: root || !mobile ? 13 : AppSpacing.actionGap,
          children: [
            OutlinedButton(
              onPressed: root && controller.blocked ? null : cancel,
              child: cancelIcon == null
                  ? Text(cancelLabel)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cancelIcon, size: 16),
                        const SizedBox(width: 8),
                        Flexible(child: Text(cancelLabel)),
                      ],
                    ),
            ),
            FilledButton(
              onPressed:
                  controller.blocked || controller.runtimeBusy || !canSave
                  ? null
                  : save,
              child: ButtonProgress(
                busy: controller.busy,
                child: Text(controller.saveLabel(l)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class PolicyToggle extends StatelessWidget {
  final PolicyEditorController controller;
  final String? section;
  final String field;
  final String title;
  final String? subtitle;
  final bool supported;
  const PolicyToggle({
    super.key,
    required this.controller,
    required this.field,
    required this.title,
    this.section,
    this.subtitle,
    this.supported = true,
  });

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return SettingRow(
      title: title,
      subtitle: subtitle,
      titleMaxLines: 4,
      minHeight: mobile ? 52 : 56,
      titleStyle: mobile
          ? AppTypography.settingsFieldTitle
          : AppTypography.settingsRow,
      contentPadding: EdgeInsets.symmetric(
        horizontal: mobile ? 13 : 14,
        vertical: 10,
      ),
      trailing: ShadSwitch(
        value:
            (section == null
                    ? controller.value
                    : controller.group(section!))[field]
                as bool,
        onChanged: controller.blocked || !supported
            ? null
            : (value) => controller.update(field, value, section: section),
      ),
    );
  }
}

class PolicyValueRow extends StatelessWidget {
  final String title;
  final String value;
  final Widget? leading;
  final double? minHeight;
  final TextStyle? titleStyle;
  final TextStyle? valueStyle;
  final TextDirection? valueTextDirection;

  const PolicyValueRow({
    super.key,
    required this.title,
    required this.value,
    this.leading,
    this.minHeight,
    this.titleStyle,
    this.valueStyle,
    this.valueTextDirection = TextDirection.ltr,
  });

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final padding = EdgeInsets.symmetric(
      horizontal: mobile ? 13 : 14,
      vertical: mobile ? 9 : 10,
    );
    final labelStyle =
        (mobile
                ? AppTypography.settingsValueLabel
                : AppTypography.desktopSettingsValueLabel)
            .merge(titleStyle);
    final textStyle =
        (mobile
                ? AppTypography.settingsValue
                : AppTypography.desktopSettingsValue)
            .copyWith(color: ColorManager.primaryText(context))
            .merge(valueStyle);
    final renderedTitleStyle = AppTypography.rowTitle
        .copyWith(color: ColorManager.primaryText(context))
        .merge(labelStyle);
    final renderedValueStyle = AppTypography.code
        .copyWith(color: ColorManager.secondaryText(context))
        .merge(textStyle);
    final height = minHeight ?? (mobile ? 46.0 : 50.0);
    return SelectionArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available =
              constraints.maxWidth -
              padding.horizontal -
              (leading == null ? 0 : 31) -
              11;
          final stacked =
              _policyTextWidth(context, title, renderedTitleStyle) >
                  available * 5 / 9 ||
              _policyTextWidth(
                    context,
                    value,
                    renderedValueStyle,
                    direction: valueTextDirection,
                  ) >
                  available * 4 / 9;
          if (!stacked) {
            return SettingRow(
              title: title,
              value: value,
              leading: leading,
              decorateLeading: false,
              minHeight: height,
              contentPadding: padding,
              titleStyle: labelStyle,
              valueStyle: textStyle,
              valueTextDirection: valueTextDirection,
            );
          }
          return ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: padding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leading != null) ...[
                    IconTheme.merge(
                      data: IconThemeData(
                        size: 20,
                        color: ColorManager.secondaryText(context),
                      ),
                      child: leading!,
                    ),
                    const SizedBox(width: 11),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: renderedTitleStyle),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          style: renderedValueStyle,
                          textDirection: valueTextDirection,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

double _policyTextWidth(
  BuildContext context,
  String text,
  TextStyle style, {
  TextDirection? direction,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: direction ?? Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.localeOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
