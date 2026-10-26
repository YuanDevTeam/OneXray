import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSwitch;

class RoutingFakeDnsRow extends StatelessWidget {
  final bool value;
  final bool enabled;
  final bool divider;
  final ValueChanged<bool> onChanged;

  const RoutingFakeDnsRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return RoutingSettingRow(
      icon: LucideIcons.network,
      title: l.routingFakeDns,
      help: l.routingFakeDnsHint,
      enabled: enabled,
      divider: divider,
      trailing: Semantics(
        label: l.routingFakeDns,
        child: ShadSwitch(value: value, enabled: enabled, onChanged: onChanged),
      ),
    );
  }
}

class RoutingFragmentRow extends StatelessWidget {
  final bool value;
  final bool enabled;
  final bool divider;
  final ValueChanged<bool> onChanged;

  const RoutingFragmentRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return RoutingSettingRow(
      icon: LucideIcons.scissors,
      title: l.routingFragment,
      help: l.routingFragmentHint,
      enabled: enabled,
      divider: divider,
      trailing: Semantics(
        label: l.routingFragment,
        child: ShadSwitch(value: value, enabled: enabled, onChanged: onChanged),
      ),
    );
  }
}

class RoutingCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const RoutingCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class RoutingCardHeader extends StatelessWidget {
  final String title;
  final String? description;
  final List<String> help;

  const RoutingCardHeader({
    super.key,
    required this.title,
    this.description,
    this.help = const [],
  });

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(18, 10, 18, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.routingCardTitle.copyWith(
                      color: palette.foreground,
                    ),
                  ),
                ),
                if (help.isNotEmpty)
                  PageHelpButton(title: title, messages: help),
              ],
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: AppTypography.routingCardDescription.copyWith(
                color: palette.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class RoutingSearchField extends StatelessWidget {
  final String hint;
  final String label;
  final TextEditingController? controller;
  final ValueChanged<String> onChanged;

  const RoutingSearchField({
    super.key,
    required this.hint,
    required this.label,
    this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: SizedBox(
      height: 38,
      child: Center(
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: AppTypography.routingSelectionInput,
          decoration: InputDecoration(
            hintText: hint,
            isCollapsed: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintStyle: AppTypography.routingSelectionInput.copyWith(
              color: ColorManager.palette(context).mutedForeground,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The compact field row shared by Smart and Custom routing settings.
class RoutingSettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? help;
  final String? value;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;
  final bool enabled;
  final bool divider;

  const RoutingSettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.help,
    this.value,
    this.trailing,
    this.below,
    this.onTap,
    this.enabled = true,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final palette = ColorManager.palette(context);
    final navigation = value != null;
    final foreground = enabled
        ? palette.foreground
        : Theme.of(context).disabledColor;
    final copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                style:
                    (mobile
                            ? AppTypography.routingRowTitleMobile
                            : AppTypography.routingRowTitle)
                        .copyWith(color: foreground),
              ),
            ),
            if (help != null) PageHelpButton(title: title, messages: [help!]),
          ],
        ),
        if (description != null && !(mobile && navigation)) ...[
          const SizedBox(height: 4),
          Text(
            description!,
            style: AppTypography.routingRowDescription.copyWith(
              color: palette.mutedForeground,
            ),
          ),
        ],
      ],
    );
    final content = Container(
      constraints: BoxConstraints(
        minHeight: mobile
            ? (navigation
                  ? 64
                  : description == null
                  ? 56
                  : 69)
            : (description == null ? 60 : 74),
      ),
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: mobile ? 13 : 17,
        vertical: 11,
      ),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mobile && navigation)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 20, color: foreground),
                          const SizedBox(width: 13),
                          Expanded(child: copy),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 33,
                          top: 6,
                        ),
                        child: Text(
                          value!,
                          style: AppTypography.routingRowValue.copyWith(
                            color: palette.mutedStrong,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 13),
                trailing ??
                    Icon(
                      LucideIcons.chevronRightDir,
                      size: 18,
                      color: palette.mutedForeground,
                    ),
              ],
            )
          else
            Row(
              children: [
                Icon(icon, size: mobile ? 20 : 22, color: foreground),
                const SizedBox(width: 13),
                Expanded(flex: navigation ? 2 : 1, child: copy),
                if (!mobile && value != null) ...[
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: AppTypography.routingRowValue.copyWith(
                        color: palette.mutedStrong,
                      ),
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: 13),
                  trailing!,
                ] else if (navigation) ...[
                  const SizedBox(width: 13),
                  Icon(
                    LucideIcons.chevronRightDir,
                    size: 18,
                    color: palette.mutedForeground,
                  ),
                ],
              ],
            ),
          if (below != null)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: (mobile ? 20 : 22) + 13,
                top: 15,
              ),
              child: below!,
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: enabled ? onTap : null, child: content),
    );
  }
}

/// Paints one outline in front of child backgrounds, including the corners.
class RoutingControlFrame extends StatelessWidget {
  final Widget child;

  const RoutingControlFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Material(
    color: ColorManager.palette(context).card,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: ColorManager.palette(context).border),
      borderRadius: BorderRadius.circular(AppRadii.control),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.all(1), child: child),
  );
}

class EntryCountPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;

  const EntryCountPicker({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final extent = AppLayout.touchExtent(
      34,
      platform: Theme.of(context).platform,
    );
    return RoutingControlFrame(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final count in const [1, 2, 3])
            Semantics(
              label: l.prototypeUseEntryServers(count),
              selected: value == count,
              button: true,
              enabled: onChanged != null,
              child: Tooltip(
                message: l.prototypeUseEntryServers(count),
                excludeFromSemantics: true,
                child: SizedBox(
                  width: extent,
                  child: Material(
                    color: value == count
                        ? palette.selectedSurface
                        : palette.muted,
                    child: InkWell(
                      onTap: onChanged == null ? null : () => onChanged!(count),
                      child: Container(
                        constraints: BoxConstraints(minHeight: extent),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        foregroundDecoration: BoxDecoration(
                          border: count < 3
                              ? BorderDirectional(
                                  end: BorderSide(color: palette.border),
                                )
                              : null,
                        ),
                        child: Center(
                          heightFactor: 1,
                          child: ExcludeSemantics(
                            child: Text(
                              '$count',
                              style: AppTypography.routingCount.copyWith(
                                color: onChanged == null
                                    ? Theme.of(context).disabledColor
                                    : value == count
                                    ? palette.primaryText
                                    : palette.mutedStrong,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RoutingEntryCountRow extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;

  const RoutingEntryCountRow({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final picker = Align(
      alignment: AlignmentDirectional.centerStart,
      child: EntryCountPicker(value: value, onChanged: onChanged),
    );
    return RoutingSettingRow(
      icon: LucideIcons.zap,
      title: l.prototypeAutomaticEntryServers,
      help: l.prototypeAutomaticEntryServersHint,
      enabled: onChanged != null,
      below: mobile ? picker : null,
      trailing: mobile ? null : picker,
    );
  }
}
