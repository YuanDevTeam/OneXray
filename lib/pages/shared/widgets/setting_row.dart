import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/menu_picker.dart';
import 'package:onexray/pages/shared/widgets/section.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SettingSection extends StatelessWidget {
  final String title;
  final String? description;
  final IconData? icon;
  final Widget? action;
  final List<Widget> children;
  final bool separated;
  final EdgeInsetsGeometry padding;
  final bool descriptionBelow;
  final double dividerIndent;
  final double? headerInset;

  const SettingSection({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.action,
    required this.children,
    this.separated = true,
    this.padding = const EdgeInsetsDirectional.fromSTEB(16, 11, 16, 11),
    this.descriptionBelow = false,
    this.dividerIndent = 16,
    this.headerInset,
  });

  @override
  Widget build(BuildContext context) {
    return SectionView(
      title: title,
      description: description,
      icon: icon,
      action: action,
      padding: padding,
      descriptionBelow: descriptionBelow,
      headerInset: headerInset,
      child: Column(
        children: _buildSettingChildren(
          context,
          children,
          separated,
          dividerIndent: dividerIndent,
        ),
      ),
    );
  }
}

List<Widget> _buildSettingChildren(
  BuildContext context,
  List<Widget> children,
  bool separated, {
  double dividerIndent = 16,
}) {
  if (!separated || children.length < 2) {
    return children;
  }
  final views = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) {
      views.add(
        Divider(
          // Full-width prototype separators sit within the row heights.
          height: dividerIndent == 0 ? 0 : 1,
          indent: dividerIndent,
          color: ColorManager.border(context),
        ),
      );
    }
    views.add(children[i]);
  }
  return views;
}

class SettingRow extends StatelessWidget {
  final String title;
  final String? value;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool showChevron;
  final int titleMaxLines;
  final int valueMaxLines;
  final double minHeight;
  final EdgeInsetsGeometry contentPadding;
  final TextStyle? titleStyle;
  final TextStyle? valueStyle;
  final TextStyle? subtitleStyle;
  final Widget? titleTrailing;
  final bool decorateLeading;
  final TextDirection? valueTextDirection;
  final TextDirection? titleTextDirection;

  const SettingRow({
    super.key,
    required this.title,
    this.value,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.showChevron = false,
    this.titleMaxLines = 2,
    this.valueMaxLines = 1,
    this.minHeight = 62,
    this.contentPadding = const EdgeInsetsDirectional.symmetric(
      horizontal: 13,
      vertical: 10,
    ),
    this.titleStyle,
    this.valueStyle,
    this.subtitleStyle,
    this.titleTrailing,
    this.decorateLeading = true,
    this.valueTextDirection,
    this.titleTextDirection,
  });

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: onTap == null
            ? minHeight
            : AppLayout.touchExtent(
                minHeight,
                platform: Theme.of(context).platform,
              ),
      ),
      child: Padding(
        padding: contentPadding,
        child: Row(
          children: [
            if (leading != null) ...[
              if (decorateLeading)
                Container(
                  width: 31,
                  height: 31,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ColorManager.tagBackground(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: IconTheme.merge(
                    data: _iconTheme(context),
                    child: leading!,
                  ),
                )
              else
                IconTheme.merge(data: _iconTheme(context), child: leading!),
              const SizedBox(width: 11),
            ],
            Expanded(flex: value == null ? 1 : 5, child: _title(context)),
            if (value != null) ...[
              const SizedBox(width: 11),
              Expanded(flex: 4, child: _value(context)),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 7),
              IconTheme.merge(data: _iconTheme(context), child: trailing!),
            ] else if (showChevron) ...[
              const SizedBox(width: 7),
              IconTheme.merge(
                data: _iconTheme(context),
                child: const Icon(LucideIcons.chevronRightDir),
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null || !enabled) {
      return content;
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: content),
    );
  }

  Widget _title(BuildContext context) {
    final color = enabled
        ? ColorManager.primaryText(context)
        : Theme.of(context).disabledColor;
    final effectiveTitleStyle = AppTypography.rowTitle
        .copyWith(color: color)
        .merge(titleStyle)
        .copyWith(color: enabled ? titleStyle?.color ?? color : color);
    final effectiveSubtitleStyle = AppTypography.supporting
        .copyWith(color: ColorManager.secondaryText(context))
        .merge(subtitleStyle);
    final label = Text(
      title,
      maxLines: titleMaxLines,
      overflow: TextOverflow.ellipsis,
      style: effectiveTitleStyle,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (titleTrailing == null)
          if (titleTextDirection == null)
            label
          else
            Directionality(
              textDirection: titleTextDirection!,
              child: SizedBox(width: double.infinity, child: label),
            )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: label),
              const SizedBox(width: 8),
              titleTrailing!,
            ],
          ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: effectiveSubtitleStyle,
          ),
        ] else if (subtitleWidget != null) ...[
          const SizedBox(height: 4),
          subtitleWidget!,
        ],
      ],
    );
  }

  Widget _value(BuildContext context) {
    return Text(
      value!,
      maxLines: valueMaxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: Directionality.of(context) == TextDirection.ltr
          ? TextAlign.right
          : TextAlign.left,
      textDirection: valueTextDirection,
      style: AppTypography.code
          .copyWith(color: ColorManager.secondaryText(context))
          .merge(valueStyle),
    );
  }

  IconThemeData _iconTheme(BuildContext context) {
    return IconThemeData(size: 20, color: ColorManager.secondaryText(context));
  }
}

class SwitchSettingRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SwitchSettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: title,
      subtitle: subtitle,
      leading: leading,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: ShadSwitch(
        value: value,
        enabled: onChanged != null,
        onChanged: onChanged,
      ),
    );
  }
}

/// Compact, inline selection used by settings fields.
class SettingSelect<T extends Object> extends StatelessWidget {
  const SettingSelect({
    super.key,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.textStyle,
    this.minHeight = 38,
  });
  final T value;
  final Map<T, String> entries;
  final ValueChanged<T?>? onChanged;
  final TextStyle? textStyle;
  final double minHeight;

  @override
  Widget build(BuildContext context) => AppMenuButton<T>(
    entries: entries.entries
        .map(
          (entry) => AppMenuEntry<T>.item(value: entry.key, title: entry.value),
        )
        .toList(),
    onSelected: (value) => onChanged?.call(value),
    triggerBuilder: (open) => InkWell(
      onTap: onChanged == null ? null : open,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: BoxConstraints(
          minHeight: AppLayout.touchExtent(
            minHeight,
            platform: Theme.of(context).platform,
          ),
          minWidth: AppLayout.touchExtent(
            0,
            platform: Theme.of(context).platform,
          ),
          maxWidth: MediaQuery.sizeOf(context).width * .48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: ColorManager.border(context)),
          borderRadius: BorderRadius.circular(6),
          color: ColorManager.surface(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                entries[value] ?? '$value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (textStyle ?? AppTypography.settingsSelect).copyWith(
                  color: onChanged == null
                      ? Theme.of(context).disabledColor
                      : ColorManager.primaryText(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronDown,
              size: 14,
              color: ColorManager.secondaryText(context),
            ),
          ],
        ),
      ),
    ),
  );
}
