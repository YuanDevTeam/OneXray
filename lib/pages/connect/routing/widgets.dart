import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/app_switch.dart';

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
    this.divider = false,
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
      leading: Semantics(
        label: l.routingFakeDns,
        child: AppSwitch(value: value, enabled: enabled, onChanged: onChanged),
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
    this.divider = false,
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
      leading: Semantics(
        label: l.routingFragment,
        child: AppSwitch(value: value, enabled: enabled, onChanged: onChanged),
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
  final IconData? icon;
  final String? description;
  final List<String> help;

  const RoutingCardHeader({
    super.key,
    required this.title,
    this.icon,
    this.description,
    this.help = const [],
  });

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final titleText = Text(
      title,
      style: AppTypography.routingCardTitle.copyWith(color: palette.foreground),
    );
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 18, 16),
            child: Padding(
              padding: EdgeInsetsDirectional.only(end: help.isEmpty ? 0 : 58),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 24),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: icon == null
                          ? titleText
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Icon(
                                    icon,
                                    size: 19,
                                    color: palette.primaryText,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: titleText),
                              ],
                            ),
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
            ),
          ),
          if (help.isNotEmpty)
            PositionedDirectional(
              top: 4,
              end: 18,
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: PageHelpButton(title: title, messages: help),
                ),
              ),
            ),
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
    child: ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: AppLayout.touchExtent(
          38,
          platform: Theme.of(context).platform,
        ),
      ),
      child: Center(
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: AppTypography.rowValue,
          decoration: InputDecoration(
            hintText: hint,
            isCollapsed: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintStyle: AppTypography.rowValue.copyWith(
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
  final Widget? leading;
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
    this.leading,
    this.description,
    this.help,
    this.value,
    this.trailing,
    this.below,
    this.onTap,
    this.enabled = true,
    this.divider = false,
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
      constraints: BoxConstraints(minHeight: mobile ? 56 : 48),
      padding: EdgeInsetsDirectional.symmetric(horizontal: 18, vertical: 10),
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
                          leading ?? Icon(icon, size: 20, color: foreground),
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
                leading ??
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

  const RoutingControlFrame({super.key, required this.child, this.clip = true});
  final bool clip;

  @override
  Widget build(BuildContext context) => Material(
    color: ColorManager.palette(context).card,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: ColorManager.palette(context).border),
      borderRadius: BorderRadius.circular(AppRadii.control),
    ),
    clipBehavior: clip ? Clip.antiAlias : Clip.none,
    child: Padding(padding: const EdgeInsets.all(1), child: child),
  );
}

class EntryCountPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  final bool fullWidth;

  const EntryCountPicker({
    super.key,
    required this.value,
    this.onChanged,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final extent = AppLayout.touchExtent(
      34,
      platform: Theme.of(context).platform,
    );

    Widget segment(int count) => Semantics(
      label: l.prototypeUseEntryServers(count),
      selected: value == count,
      button: true,
      enabled: onChanged != null,
      child: Tooltip(
        message: l.prototypeUseEntryServers(count),
        excludeFromSemantics: true,
        child: SizedBox(
          width: fullWidth ? null : extent,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onChanged == null ? null : () => onChanged!(count),
              child: Container(
                constraints: BoxConstraints(minHeight: extent),
                decoration: BoxDecoration(
                  color: value == count
                      ? palette.selectedSurface
                      : palette.muted,
                  borderRadius: BorderRadiusDirectional.horizontal(
                    start: Radius.circular(
                      count == 1 ? AppRadii.control - 1 : 0,
                    ),
                    end: Radius.circular(count == 3 ? AppRadii.control - 1 : 0),
                  ),
                ),
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
    );

    Widget picker(double segmentWidth) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTapUp: onChanged == null
          ? null
          : (details) {
              final logicalX = Directionality.of(context) == TextDirection.rtl
                  ? segmentWidth * 3 + 1 - details.localPosition.dx
                  : details.localPosition.dx - 1;
              final index = logicalX ~/ segmentWidth;
              onChanged!(
                index < 0
                    ? 1
                    : index > 2
                    ? 3
                    : index + 1,
              );
            },
      child: RoutingControlFrame(
        clip: false,
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (final count in const [1, 2, 3])
              if (fullWidth)
                Expanded(child: segment(count))
              else
                segment(count),
          ],
        ),
      ),
    );

    if (!fullWidth) return picker(extent);
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumWidth = extent * 3 + 2;
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : minimumWidth;
        final width = availableWidth < minimumWidth
            ? minimumWidth
            : availableWidth;
        final child = SizedBox(width: width, child: picker((width - 2) / 3));
        return availableWidth < minimumWidth
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: child,
              )
            : child;
      },
    );
  }
}

class RoutingEntryCountRow extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  final bool fullWidth;

  const RoutingEntryCountRow({
    super.key,
    required this.value,
    this.onChanged,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (fullWidth) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.routingEntryCountLabel,
                    style: AppTypography.fieldLabel.copyWith(
                      color: onChanged == null
                          ? Theme.of(context).disabledColor
                          : ColorManager.palette(context).foreground,
                    ),
                  ),
                ),
                PageHelpButton(
                  title: l.routingEntryCountLabel,
                  messages: [l.prototypeAutomaticEntryServersHint],
                ),
              ],
            ),
            const SizedBox(height: 8),
            EntryCountPicker(
              value: value,
              onChanged: onChanged,
              fullWidth: true,
            ),
          ],
        ),
      );
    }
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
