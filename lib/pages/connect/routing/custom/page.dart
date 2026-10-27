import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/connect/routing/options_form.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/custom/controller.dart';
import 'package:onexray/pages/connect/routing/custom/rule_page.dart';
import 'package:onexray/pages/connect/routing/custom/sections.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/configuration_transfer.dart';
import 'package:onexray/pages/shared/widgets/menu_picker.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CustomRoutingEditorPage extends StatefulWidget {
  final int? profileId;
  final OpenCustomRule openRule;
  final Widget Function(BuildContext, CustomRoutingEditorController)?
  transferTools;
  const CustomRoutingEditorPage({
    super.key,
    this.profileId,
    required this.openRule,
    this.transferTools,
  });

  @override
  State<CustomRoutingEditorPage> createState() =>
      _CustomRoutingEditorPageState();
}

class _CustomRoutingEditorPageState extends State<CustomRoutingEditorPage> {
  late final controller = CustomRoutingEditorController(
    profileId: widget.profileId,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller.setInlineEditing(
      MediaQuery.sizeOf(context).width > AppLayout.mobileBreakpoint,
    );
    if (!_started) {
      _started = true;
      controller.load(context);
    }
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<CustomRoutingEditorController, CustomRoutingEditorState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        final name = state.name.trim();
        return Scaffold(
          appBar: PageAppBar(
            title: Text(name.isEmpty ? l.prototypeCustomRouting : name),
            leading: BackButton(onPressed: () => controller.cancel(context)),
            actions: [
              PageHelpButton(
                title: l.prototypeCustomRouting,
                messages: [l.prototypeCustomImportHint, l.routingCustomDnsHint],
              ),
            ],
          ),
          body: SafeArea(
            child: state.loaded
                ? ExcludeFocus(
                    excluding: state.editingBlocked,
                    child: AbsorbPointer(
                      absorbing: state.editingBlocked,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          mobile ? 14 : 28,
                          mobile ? 12 : AppSpacing.desktopPageTop,
                          mobile ? 14 : 28,
                          mobile ? 18 : AppSpacing.desktopPageBottom,
                        ),
                        child: ResponsiveContent(
                          desktopMaxWidth: AppLayout.routingMaxWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              RoutingCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 13,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: mobile ? 8 : 0,
                                  children: [
                                    widget.transferTools?.call(
                                          context,
                                          controller,
                                        ) ??
                                        ConfigurationTransferTools(
                                          controller: controller.transfer,
                                          disabled: state.busy,
                                        ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              _identity(context, mobile, state),
                              SizedBox(height: mobile ? 12 : 16),
                              Builder(
                                builder: (context) {
                                  final rules = RoutingCard(
                                    key: const ValueKey('custom-rule-list'),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (!mobile)
                                          RoutingCardHeader(
                                            title: l.prototypeRuleList,
                                            description:
                                                l.prototypeRulesMatchInOrder,
                                          ),
                                        RoutingEntryCountRow(
                                          value: state.entryCount,
                                          onChanged: state.editingBlocked
                                              ? null
                                              : controller.setEntryCount,
                                        ),
                                        RoutingSelectionSettingsForm(
                                          value: state.selection,
                                          enabled: !state.editingBlocked,
                                          entryCount: state.entryCount,
                                          onChanged: controller.setSelection,
                                        ),
                                        ReorderableListView.builder(
                                          shrinkWrap: true,
                                          primary: false,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          padding: EdgeInsets.zero,
                                          buildDefaultDragHandles: false,
                                          proxyDecorator:
                                              (child, index, animation) =>
                                                  Material(
                                                    color: ColorManager.palette(
                                                      context,
                                                    ).card,
                                                    elevation: 4,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          AppRadii.control,
                                                        ),
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    child: child,
                                                  ),
                                          onReorderItem: controller.reorder,
                                          itemCount: state.rules.length,
                                          itemBuilder: (context, index) =>
                                              _rule(
                                                context,
                                                index,
                                                mobile,
                                                state,
                                              ),
                                        ),
                                        _fallback(context, mobile),
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: OutlinedButton.icon(
                                            onPressed: state.editingBlocked
                                                ? null
                                                : () => controller.editRule(
                                                    context,
                                                    widget.openRule,
                                                  ),
                                            style: OutlinedButton.styleFrom(
                                              minimumSize:
                                                  const Size.fromHeight(43),
                                              visualDensity: mobile
                                                  ? null
                                                  : VisualDensity.standard,
                                              foregroundColor:
                                                  ColorManager.palette(context)
                                                      .primary,
                                              side: BorderSide(
                                                color: Color.lerp(
                                                  ColorManager.palette(context)
                                                      .border,
                                                  ColorManager.palette(context)
                                                      .primary,
                                                  .55,
                                                )!,
                                              ),
                                              textStyle: AppTypography.ruleAdd,
                                            ),
                                            icon: const Icon(
                                              LucideIcons.plus,
                                              size: 17,
                                            ),
                                            label: Text(l.prototypeAddRule),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  final inline = controller.inlineRule;
                                  return CustomRoutingSections(
                                    rules: rules,
                                    editor: inline == null
                                        ? null
                                        : CustomRoutingRuleForm(
                                            controller: inline,
                                          ),
                                    options: RoutingCard(
                                      child: Column(
                                        children: [
                                          RoutingFakeDnsRow(
                                            value: state.fakeDns,
                                            enabled:
                                                !state.editingBlocked &&
                                                (state.fakeDns ||
                                                    state.sniffing.enabled),
                                            onChanged: controller.setFakeDns,
                                          ),
                                          RoutingFragmentRow(
                                            value: state.fragment,
                                            enabled: !state.editingBlocked,
                                            divider: false,
                                            onChanged: controller.setFragment,
                                          ),
                                        ],
                                      ),
                                    ),
                                    dns: RoutingDnsSettingsForm(
                                      value: state.dns,
                                      enabled: !state.editingBlocked,
                                      onChanged: controller.setDns,
                                    ),
                                    sniffing: RoutingSniffingSettingsForm(
                                      value: state.sniffing,
                                      enabled: !state.editingBlocked,
                                      fakeDns: state.fakeDns,
                                      onChanged: controller.setSniffing,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: state.busy
                        ? const CircularProgressIndicator()
                        : Text(l.prototypeCannotReadCustomRoute),
                  ),
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.error case final error?)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Semantics(
                    liveRegion: true,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height / 4,
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          error,
                          style: AppTypography.actionHelp.copyWith(
                            color: ColorManager.palette(context).destructive,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              PageActionBar(
                children: [
                  if (!mobile)
                    ShadButton.outline(
                      onPressed: () => controller.cancel(context),
                      child: Text(l.prototypeCancel),
                    ),
                  ShadButton(
                    enabled:
                        !state.busy &&
                        state.loaded &&
                        controller.nameError(l) == null,
                    onPressed:
                        state.busy ||
                            !state.loaded ||
                            controller.nameError(l) != null
                        ? null
                        : () => controller.save(context),
                    child: ButtonProgress(
                      busy: state.saving,
                      child: Text(l.prototypeSave),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _identity(
    BuildContext context,
    bool mobile,
    CustomRoutingEditorState state,
  ) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final error = controller.nameError(l);
    final field = ShadInput(
      controller: controller.name,
      enabled: state.loaded && !state.editingBlocked,
      maxLength: 32,
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      style: AppTypography.routeIdentityLabel,
      decoration: error == null
          ? null
          : ShadDecoration(
              border: ShadBorder.all(color: palette.destructive, width: 1),
            ),
    );
    final delete = OutlinedButton.icon(
      onPressed: state.busy ? null : () => controller.delete(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.destructive,
        minimumSize: const Size(0, 38),
        visualDensity: mobile ? null : VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        textStyle: AppTypography.ruleAdd,
      ),
      icon: state.deleting
          ? const ButtonProgressIndicator()
          : const Icon(LucideIcons.trash2, size: 16),
      label: Text(l.prototypeDeleteRoute),
    );
    return RoutingCard(
      padding: mobile
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: mobile ? 10 : 16,
            children: [
              Expanded(
                child: Text(
                  l.prototypeRouteName,
                  style: AppTypography.routeIdentityLabel.copyWith(
                    color: palette.mutedStrong,
                  ),
                ),
              ),
              Flexible(
                flex: 0,
                child: Text(
                  l.prototypeCustomRouteCount(controller.routeCount),
                  style: AppTypography.routeCount.copyWith(
                    color: palette.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
          Row(
            spacing: mobile ? 10 : 16,
            children: [
              Expanded(child: field),
              if (!mobile && state.original?.original != null) delete,
            ],
          ),
          if (error != null)
            Text(
              error,
              style: AppTypography.conditionRelation.copyWith(
                color: palette.destructive,
              ),
            ),
          if (mobile && state.original?.original != null) delete,
        ],
      ),
    );
  }

  Widget _rule(
    BuildContext context,
    int index,
    bool mobile,
    CustomRoutingEditorState state,
  ) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final selected = state.selectedRuleKey == state.ruleKeys[index];
    final action = state.rules[index].action;
    final actionColor = action == RoutingRuleAction.direct
        ? palette.running
        : action == RoutingRuleAction.block
        ? palette.destructive
        : palette.primary;
    final position = l.prototypeChangeRulePosition(
      controller.ruleName(index, l),
    );
    return Container(
      key: ObjectKey(state.ruleKeys[index]),
      constraints: BoxConstraints(minHeight: mobile ? 72 : 68),
      decoration: BoxDecoration(
        color: selected ? palette.selectedSurface : palette.card,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      foregroundDecoration: selected
          ? BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(
                  color: Color.lerp(palette.border, palette.primary, .58)!,
                  width: 2,
                ),
              ),
            )
          : null,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 7 : 10),
      child: Row(
        spacing: 8,
        children: [
          AppMenuButton<int>(
            entries: [
              for (var target = 0; target < state.rules.length; target++)
                AppMenuEntry.item(
                  value: target,
                  title: l.prototypeRulePosition(target + 1),
                ),
            ],
            onSelected: (target) => controller.reorder(index, target),
            triggerBuilder: (open) => ReorderableDelayedDragStartListener(
              index: index,
              enabled: !state.editingBlocked,
              child: Tooltip(
                message: position,
                child: IconButton(
                  onPressed: state.editingBlocked ? null : open,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(28, 36),
                    maximumSize: const Size(28, 36),
                    padding: EdgeInsets.zero,
                    foregroundColor: palette.mutedForeground,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(LucideIcons.gripVertical, size: 17),
                ),
              ),
            ),
          ),
          SizedBox(
            width: mobile ? 18 : 20,
            child: Text(
              (index + 1).toString(),
              textAlign: TextAlign.center,
              style: AppTypography.ruleNumber.copyWith(
                color: palette.mutedStrong,
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: state.editingBlocked
                  ? null
                  : () => controller.editRule(context, widget.openRule, index),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: mobile ? 70 : 66),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 4,
                          children: [
                            Text(
                              controller.ruleName(index, l),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: mobile
                                  ? AppTypography.ruleTitleMobile
                                  : AppTypography.ruleTitleDesktop,
                            ),
                            Text(
                              controller.ruleSummary(index, l),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (mobile
                                          ? AppTypography.ruleSummary
                                          : AppTypography.ruleSummaryDesktop)
                                      .copyWith(color: palette.mutedForeground),
                            ),
                            if (mobile)
                              Text(
                                controller.ruleAction(index, l),
                                style: AppTypography.ruleAction.copyWith(
                                  color: actionColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!mobile)
                        Text(
                          controller.ruleAction(index, l),
                          style: AppTypography.ruleAction.copyWith(
                            color: actionColor,
                          ),
                        ),
                      Icon(
                        LucideIcons.chevronRightDir,
                        size: 17,
                        color: palette.foreground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l.prototypeDelete,
            onPressed: state.editingBlocked
                ? null
                : () => controller.deleteRule(index),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(34),
              maximumSize: const Size.square(34),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: palette.mutedForeground,
            ),
            icon: const Icon(LucideIcons.trash2, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _fallback(BuildContext context, bool mobile) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Container(
      constraints: BoxConstraints(minHeight: mobile ? 62 : 61),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        spacing: 10,
        children: [
          Icon(LucideIcons.globe, size: 19, color: palette.mutedStrong),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  l.prototypeOtherTraffic,
                  style: mobile
                      ? AppTypography.ruleAdd
                      : AppTypography.routingSelectionTitle,
                ),
                Text(
                  l.prototypeWhenNoRuleMatches,
                  style:
                      (mobile
                              ? AppTypography.conditionRelation
                              : AppTypography.ruleSummaryDesktop)
                          .copyWith(color: palette.mutedForeground),
                ),
              ],
            ),
          ),
          Text(
            l.prototypeUseVpn,
            style: AppTypography.ruleAction.copyWith(color: palette.primary),
          ),
        ],
      ),
    );
  }
}
