import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/custom/rule_controller.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/menu_picker.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class CustomRoutingRulePage extends StatefulWidget {
  final RoutingRuleState? rule;
  const CustomRoutingRulePage({super.key, this.rule});

  @override
  State<CustomRoutingRulePage> createState() => _CustomRoutingRulePageState();
}

class _CustomRoutingRulePageState extends State<CustomRoutingRulePage> {
  late final controller = CustomRoutingRuleController(rule: widget.rule);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (widget.rule == null) {
        controller.name.text = AppLocalizations.of(context)!.prototypeNewRule;
      }
    }
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return BlocProvider.value(
      value: controller,
      child: Scaffold(
        appBar: PageAppBar(title: Text(l.prototypeEditRule)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              mobile ? 14 : 28,
              12,
              mobile ? 14 : 28,
              18,
            ),
            child: ResponsiveContent(
              desktopMaxWidth: 800,
              child: CustomRoutingRuleForm(controller: controller),
            ),
          ),
        ),
        bottomNavigationBar: PageActionBar(
          children: [
            ShadButton.outline(
              onPressed: () => controller.cancel(context),
              child: Text(l.prototypeCancel),
            ),
            ShadButton(
              onPressed: () => controller.save(context),
              child: Text(l.prototypeSave),
            ),
          ],
        ),
      ),
    );
  }
}

/// The same field composition can be hosted beside a wide-screen rule list.
class CustomRoutingRuleForm extends StatelessWidget {
  final CustomRoutingRuleController controller;
  const CustomRoutingRuleForm({super.key, required this.controller});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<CustomRoutingRuleController, CustomRoutingRuleState>(
        bloc: controller,
        builder: (context, state) {
          final l = AppLocalizations.of(context)!;
          final palette = ColorManager.palette(context);
          final mobile =
              MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
          return RoutingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!mobile)
                  RoutingCardHeader(
                    title: l.prototypeEditRule,
                    description: l.prototypeRuleEditHint,
                  ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: mobile ? 12 : 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: palette.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 7,
                    children: [
                      Text(
                        l.prototypeRuleName,
                        style: AppTypography.routeIdentityLabel.copyWith(
                          color: palette.mutedStrong,
                        ),
                      ),
                      ShadInput(
                        controller: controller.name,
                        constraints: const BoxConstraints(minHeight: 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        style: AppTypography.routeIdentityLabel,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    mobile ? 12 : 16,
                    14,
                    mobile ? 12 : 16,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.prototypeMatchWhen,
                        style: AppTypography.conditionTitle.copyWith(
                          color: palette.mutedStrong,
                        ),
                      ),
                      const SizedBox(height: 8),
                      RoutingControlFrame(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _conditions(
                              context,
                              state,
                              RoutingRuleCondition.domains,
                            ),
                            const Divider(),
                            _conditions(
                              context,
                              state,
                              RoutingRuleCondition.ips,
                            ),
                            const Divider(),
                            _ConditionField(
                              icon: LucideIcons.terminal,
                              title: l.prototypeTargetPort,
                              summary: state.port.trim().isEmpty
                                  ? l.prototypeNotSet
                                  : state.port,
                              open: state.expandedConditions.contains(
                                RoutingRuleCondition.port,
                              ),
                              onToggle: () => controller.toggleCondition(
                                RoutingRuleCondition.port,
                              ),
                              child: _input(
                                context,
                                controller: controller.port,
                                hint: '80, 443, 1000-2000',
                              ),
                            ),
                            const Divider(),
                            _ConditionField(
                              icon: LucideIcons.wifi,
                              title: l.prototypeNetworkType,
                              summary: state.network == 'any'
                                  ? l.prototypeAny
                                  : state.network.toUpperCase(),
                              open: state.expandedConditions.contains(
                                RoutingRuleCondition.network,
                              ),
                              onToggle: () => controller.toggleCondition(
                                RoutingRuleCondition.network,
                              ),
                              child: _network(context, state),
                            ),
                            const Divider(),
                            _moreConditions(context, state),
                          ],
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 7,
                        children: [
                          Icon(
                            LucideIcons.info,
                            size: 14,
                            color: palette.mutedForeground,
                          ),
                          Expanded(
                            child: Text(
                              l.prototypeRuleConditionsHint,
                              style: AppTypography.conditionRelation.copyWith(
                                color: palette.mutedForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    mobile ? 12 : 16,
                    14,
                    mobile ? 12 : 16,
                    14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.prototypeThen,
                        style: AppTypography.conditionTitle.copyWith(
                          color: palette.mutedStrong,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _actions(context, state),
                      if (state.action == RoutingRuleAction.proxy)
                        Padding(
                          padding: const EdgeInsets.only(top: 9),
                          child: Text(
                            l.prototypeVpnRuleHint,
                            style: AppTypography.actionHelp.copyWith(
                              color: palette.mutedForeground,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _conditions(
    BuildContext context,
    CustomRoutingRuleState state,
    RoutingRuleCondition condition,
  ) {
    final l = AppLocalizations.of(context)!;
    final domain = condition == RoutingRuleCondition.domains;
    final entries = controller.entries(condition);
    final stateValues = domain ? state.domains : state.ips;
    final title = domain
        ? l.prototypeWebsitesDomains
        : l.prototypeIpAddressesRanges;
    final values = stateValues
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(', ');
    return _ConditionField(
      key: ValueKey(condition),
      icon: domain ? LucideIcons.globe : LucideIcons.network,
      title: title,
      summary: values.isEmpty ? l.prototypeNotSet : values,
      open: state.expandedConditions.contains(condition),
      onToggle: () => controller.toggleCondition(condition),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 7,
        children: [
          for (final (entryIndex, entry) in entries.indexed)
            Row(
              key: ObjectKey(entry),
              spacing: 7,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => RawAutocomplete<String>(
                      textEditingController: entry.text,
                      focusNode: entry.focus,
                      optionsBuilder: (value) =>
                          controller.suggestions(value.text, domain),
                      fieldViewBuilder: (context, text, focus, submit) =>
                          Semantics(
                            label: '$title ${entryIndex + 1}',
                            child: _input(
                              context,
                              controller: text,
                              focus: focus,
                              hint: domain
                                  ? l.prototypeDomainGeositeRule
                                  : l.prototypeIpCidrGeoipRule,
                              onSubmitted: (_) => submit(),
                            ),
                          ),
                      optionsViewBuilder: (context, select, options) => Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Material(
                          elevation: 4,
                          color: ColorManager.palette(context).card,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadii.control,
                            ),
                            side: BorderSide(
                              color: ColorManager.palette(context).border,
                            ),
                          ),
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 240),
                              child: ListView(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                children: [
                                  for (final (index, option) in options.indexed)
                                    InkWell(
                                      onTap: () => select(option),
                                      child: ColoredBox(
                                        color:
                                            AutocompleteHighlightedOption.of(
                                                  context,
                                                ) ==
                                                index
                                            ? ColorManager.palette(context)
                                                  .selectedSurface
                                            : ColorManager.palette(context)
                                                  .card,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            option,
                                            textDirection: TextDirection.ltr,
                                            style: AppTypography.routingInput,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (entries.length > 1 || stateValues[entryIndex].isNotEmpty)
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      tooltip: l.prototypeRemoveEntry,
                      onPressed: () => controller.removeValue(condition, entry),
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(34),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: ColorManager.palette(context)
                            .mutedForeground,
                      ),
                      icon: const Icon(LucideIcons.trash2, size: 15),
                    ),
                  )
                else
                  const SizedBox(width: 34),
              ],
            ),
          TextButton.icon(
            onPressed: () => controller.addValue(condition),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: AppTypography.actionHelp,
            ),
            icon: const Icon(LucideIcons.plus, size: 15),
            label: Text(l.prototypeAddAnother),
          ),
        ],
      ),
    );
  }

  Widget _moreConditions(BuildContext context, CustomRoutingRuleState state) {
    final l = AppLocalizations.of(context)!;
    final summaries = [
      if (state.protocols.isNotEmpty) l.routingRuleProtocol,
      if (state.localOS.isNotEmpty) l.routingRuleLocalOS,
    ];
    final platforms = {
      'android': 'Android',
      'ios': 'iOS',
      'darwin': 'macOS',
      'windows': 'Windows',
      'linux': 'Linux',
    };
    return _ConditionField(
      key: const ValueKey('custom-more-conditions'),
      icon: LucideIcons.listFilter,
      title: l.routingRuleMoreConditions,
      summary: summaries.isEmpty ? l.prototypeNotSet : summaries.join(' · '),
      open: state.moreConditions,
      onToggle: controller.toggleMoreConditions,
      contentPadding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConditionField(
            key: const ValueKey(RoutingRuleCondition.protocol),
            icon: LucideIcons.network,
            title: l.routingRuleProtocol,
            summary: state.protocols.isEmpty
                ? l.prototypeAny
                : state.protocols.join(', '),
            open: state.expandedConditions.contains(
              RoutingRuleCondition.protocol,
            ),
            onToggle: () =>
                controller.toggleCondition(RoutingRuleCondition.protocol),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 7,
              children: [
                _help(context, l.routingRuleProtocolHint),
                _choices(context, RoutingRuleCondition.protocol, {
                  'http': 'HTTP',
                  'tls': 'TLS',
                  'quic': 'QUIC',
                  'bittorrent': 'BitTorrent',
                }, state.protocols),
              ],
            ),
          ),
          const Divider(),
          _ConditionField(
            key: const ValueKey(RoutingRuleCondition.localOS),
            icon: LucideIcons.monitor,
            title: l.routingRuleLocalOS,
            summary: state.localOS.isEmpty
                ? l.prototypeAny
                : state.localOS
                      .map((value) => platforms[value] ?? value)
                      .join(', '),
            open: state.expandedConditions.contains(
              RoutingRuleCondition.localOS,
            ),
            onToggle: () =>
                controller.toggleCondition(RoutingRuleCondition.localOS),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 7,
              children: [
                _help(context, l.routingRuleLocalOSHint),
                _choices(
                  context,
                  RoutingRuleCondition.localOS,
                  platforms,
                  state.localOS,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _help(BuildContext context, String text) => Text(
    text,
    style: AppTypography.actionHelp.copyWith(
      color: ColorManager.palette(context).mutedForeground,
    ),
  );

  Widget _choices(
    BuildContext context,
    RoutingRuleCondition condition,
    Map<String, String> labels,
    List<String> selected,
  ) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final value in {...labels.keys, ...selected})
        FilterChip(
          label: Text(labels[value] ?? value),
          labelStyle: AppTypography.routingInput,
          selected: selected.contains(value),
          onSelected: (_) => controller.toggleChoice(condition, value),
        ),
    ],
  );

  Widget _input(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    FocusNode? focus,
    ValueChanged<String>? onSubmitted,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: ShadInput(
      controller: controller,
      focusNode: focus,
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      style: AppTypography.routingInput,
      placeholder: Text(hint),
      placeholderStyle: AppTypography.routingInput.copyWith(
        color: ColorManager.palette(context).mutedForeground,
      ),
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: onSubmitted,
    ),
  );

  Widget _network(BuildContext context, CustomRoutingRuleState state) {
    final l = AppLocalizations.of(context)!;
    final labels = {'any': l.prototypeAny, 'tcp': 'TCP', 'udp': 'UDP'};
    return AppMenuButton<String>(
      entries: [
        for (final entry in labels.entries)
          AppMenuEntry.item(value: entry.key, title: entry.value),
      ],
      onSelected: controller.setNetwork,
      triggerBuilder: (open) => OutlinedButton(
        onPressed: open,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: AppTypography.routingInput,
        ),
        child: Row(
          children: [
            Expanded(child: Text(labels[state.network] ?? state.network)),
            const Icon(LucideIcons.chevronDown, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, CustomRoutingRuleState state) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final actions = {
      RoutingRuleAction.proxy: l.prototypeUseVpn,
      RoutingRuleAction.direct: l.prototypeDirect,
      RoutingRuleAction.block: l.prototypeBlock,
    };
    return RoutingControlFrame(
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (final (index, action) in actions.entries.indexed) ...[
              if (index > 0) const VerticalDivider(width: 1),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: state.action == action.key,
                  child: Material(
                    color: state.action == action.key
                        ? palette.selectedSurface
                        : palette.muted,
                    child: InkWell(
                      onTap: () => controller.setAction(action.key),
                      child: Container(
                        constraints: BoxConstraints(
                          minHeight: AppLayout.touchExtent(
                            38,
                            platform: Theme.of(context).platform,
                          ),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        child: Text(
                          action.value,
                          textAlign: TextAlign.center,
                          style:
                              (state.action == action.key
                                      ? AppTypography.selectedActionOption
                                      : AppTypography.actionOption)
                                  .copyWith(
                                    color: state.action == action.key
                                        ? palette.primaryText
                                        : palette.foreground,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConditionField extends StatelessWidget {
  const _ConditionField({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.open,
    required this.onToggle,
    required this.child,
    this.contentPadding = const EdgeInsetsDirectional.fromSTEB(39, 0, 10, 10),
  });
  final IconData icon;
  final String title;
  final String summary;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            onTap: onToggle,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              color: open ? palette.surfaceHover : palette.card,
              child: Row(
                spacing: 10,
                children: [
                  Icon(icon, size: 18, color: palette.mutedStrong),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        Text(title, style: AppTypography.conditionTitle),
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.conditionSummary.copyWith(
                            color: palette.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    open
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRightDir,
                    size: 17,
                    color: palette.foreground,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open) Padding(padding: contentPadding, child: child),
      ],
    );
  }
}
