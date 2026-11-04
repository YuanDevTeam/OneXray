import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/menus.dart';
import 'package:onexray/pages/servers/sort.dart';
import 'package:onexray/pages/servers/subscription/user_info.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/pages/shared/widgets/page_empty_state.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/pages/servers/details.dart';
import 'package:onexray/pages/servers/sources.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:onexray/pages/main/navigation.dart';

enum _ServerBrowserTab { nodes, configurations, subscriptions }

class ServerBrowser extends StatefulWidget {
  const ServerBrowser({
    super.key,
    required this.controller,
    required this.scroll,
  });
  final ServersController controller;
  final ScrollController scroll;
  @override
  State<ServerBrowser> createState() => _ServerBrowserState();
}

class _ServerBrowserState extends State<ServerBrowser> {
  ServersController get controller => widget.controller;
  _ServerBrowserTab tab = _ServerBrowserTab.nodes;
  int sourceId = -1;
  bool favoritesOnly = false;
  int get filterSourceId =>
      sourceId > 0 && !controller.sources.any((source) => source.id == sourceId)
      ? -1
      : sourceId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final gutter = mobile ? AppSpacing.mobilePage : AppSpacing.page;
    if (controller.servers.isEmpty &&
        controller.sources.isEmpty &&
        controller.rawConfigurations.isEmpty &&
        controller.catalog.manualGroups.isEmpty) {
      final empty = PageEmptyState(
        title: l.prototypeNoServersYet,
        description: l.prototypeAddProviderSubscriptionHint,
        primaryLabel: l.prototypeAddServer,
        onPrimary: () => controller.addServers(context),
        secondaryLabel: l.prototypeHowGetServers,
        onSecondary: () => controller.openServerHelp(context),
        scrollController: widget.scroll,
      );
      if (MediaQuery.sizeOf(context).width > AppLayout.mobileBreakpoint) {
        return empty;
      }
      return Column(
        children: [
          Expanded(child: empty),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextButton.icon(
              onPressed: () => context.pushScoped(
                AppPageDestination.serverManualGroups,
                extra: controller,
              ),
              icon: const Icon(LucideIcons.folder, size: 18),
              label: Text(l.manualGroupsTitle),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
          child: ShadTabs<_ServerBrowserTab>(
            key: const ValueKey('server-resource-tabs'),
            value: tab,
            scrollable: true,
            tabBarAlignment: Directionality.of(context) == TextDirection.rtl
                ? Alignment.centerRight
                : Alignment.centerLeft,
            onChanged: (value) => setState(() => tab = value),
            tabs: [
              ShadTab(
                value: _ServerBrowserTab.nodes,
                content: const SizedBox.shrink(),
                height: 48,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Text(l.serverNodesTab),
                    Text(
                      '${controller.servers.where((row) => !controller.providerRow(row)).length}',
                      style: AppTypography.supporting,
                    ),
                  ],
                ),
              ),
              ShadTab(
                value: _ServerBrowserTab.configurations,
                content: const SizedBox.shrink(),
                height: 48,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Text(l.serverCompleteConfigurationsTab),
                    Text(
                      '${controller.servers.where(controller.providerRow).length + controller.rawConfigurations.length}',
                      style: AppTypography.supporting,
                    ),
                  ],
                ),
              ),
              ShadTab(
                value: _ServerBrowserTab.subscriptions,
                content: const SizedBox.shrink(),
                height: 48,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Text(l.prototypeSubscriptions),
                    Text(
                      '${controller.sources.length}',
                      style: AppTypography.supporting,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: tab == _ServerBrowserTab.subscriptions
              ? SingleChildScrollView(
                  controller: widget.scroll,
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 28),
                  child: _subscriptions(context),
                )
              : _resources(
                  context,
                  complete: tab == _ServerBrowserTab.configurations,
                ),
        ),
      ],
    );
  }

  Widget _search(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return TextField(
      key: const ValueKey('server-search'),
      controller: controller.search,
      onChanged: controller.searchChanged,
      style: AppTypography.rowValue,
      decoration: InputDecoration(
        hintText: l.prototypeSearchSubscriptionsServers,
        prefixIcon: const Icon(LucideIcons.search, size: 18),
        suffixIcon: controller.search.text.isEmpty
            ? null
            : IconButton(
                key: const ValueKey('server-search-clear'),
                tooltip: l.prototypeClear,
                onPressed: controller.search.clear,
                icon: const Icon(LucideIcons.x, size: 18),
              ),
      ),
    );
  }

  bool _matchesSource(CoreConfigData row) =>
      filterSourceId == -1 || row.subId == filterSourceId;
  bool _matchesRaw(CoreConfigData row) {
    final query = controller.query.trim().toLowerCase();
    return (filterSourceId == -1 || filterSourceId == 0) &&
        (query.isEmpty ||
            row.name.toLowerCase().contains(query) ||
            AppLocalizations.of(context)!.xrayRawPageTitle
                .toLowerCase()
                .contains(query));
  }

  Widget _resources(BuildContext context, {required bool complete}) {
    final l = AppLocalizations.of(context)!;
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final gutter = mobile ? AppSpacing.mobilePage : AppSpacing.page;
    final gap = mobile ? 12.0 : 16.0;
    final ordinary = controller.servers
        .where((row) => controller.providerRow(row) == complete)
        .where(_matchesSource)
        .where((row) => controller.matches(l, row))
        .where((row) => complete || !favoritesOnly || row.favorite)
        .toList();
    final raw = complete
        ? controller.rawConfigurations.where(_matchesRaw).toList()
        : <CoreConfigData>[];
    final count = ordinary.length + raw.length;
    final validSource = filterSourceId;
    final filtered =
        controller.query.trim().isNotEmpty ||
        validSource != -1 ||
        (!complete && favoritesOnly);
    final palette = ColorManager.palette(context);
    return CustomScrollView(
      controller: widget.scroll,
      key: PageStorageKey(('server-resources', complete)),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 10),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _search(context),
                SizedBox(height: gap),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 140),
                      child: ShadSelect<int>(
                        key: ValueKey(('server-source-filter', validSource)),
                        initialValue: validSource,
                        selectedOptionBuilder: (_, value) => Text(
                          value == -1
                              ? l.serverAllSources
                              : value == 0
                              ? l.prototypeManualAdditions
                              : controller.sources
                                    .firstWhere((source) => source.id == value)
                                    .name,
                        ),
                        options: [
                          ShadOption(
                            value: -1,
                            child: Text(l.serverAllSources),
                          ),
                          ShadOption(
                            value: 0,
                            child: Text(l.prototypeManualAdditions),
                          ),
                          for (final source in controller.sources)
                            ShadOption(
                              value: source.id,
                              child: Text(source.name),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => sourceId = value);
                        },
                      ),
                    ),
                    if (!complete) ...[
                      ServerSortButton(controller: controller),
                      IconButton(
                        tooltip: l.prototypeFavorites,
                        isSelected: favoritesOnly,
                        onPressed: () =>
                            setState(() => favoritesOnly = !favoritesOnly),
                        icon: const Icon(LucideIcons.star, size: 18),
                      ),
                      const AppActivityIndicator(
                        key: ValueKey('server-probe-activity'),
                        downloading: false,
                      ),
                      if (!mobile)
                        OutlinedButton.icon(
                          onPressed: () => controller.choose(
                            context,
                            const ServerSelection.automatic(),
                          ),
                          icon: const Icon(LucideIcons.shuffle, size: 17),
                          label: Text(l.prototypeAutomaticSelection),
                        ),
                      if (!mobile)
                        OutlinedButton.icon(
                          onPressed: () => controller.choose(
                            context,
                            const ServerSelection.source(0),
                          ),
                          icon: const Icon(LucideIcons.layers, size: 17),
                          label: Text(l.prototypeManualAdditions),
                        ),
                    ] else
                      FilledButton.icon(
                        onPressed: () => controller.editRaw(context),
                        icon: const Icon(LucideIcons.plus, size: 17),
                        label: Text(l.prototypeAddRawJson),
                      ),
                  ],
                ),
                if (!complete && !filtered) ...[
                  SizedBox(height: gap),
                  SettingRow(
                    title: l.manualGroupsTitle,
                    subtitle: l.manualGroupCount(
                      controller.catalog.manualGroups.length,
                    ),
                    leading: const Icon(LucideIcons.folder, size: 19),
                    onTap: () => context.pushScoped(
                      AppPageDestination.serverManualGroups,
                      extra: controller,
                    ),
                  ),
                ],
                SizedBox(height: gap),
                Text(
                  complete
                      ? l.providerConfigurationCount(count)
                      : l.prototypeServerCount(count),
                  style: AppTypography.supporting.copyWith(
                    color: palette.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (count == 0)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            sliver: SliverToBoxAdapter(
              child: SettingSection(
                title: '',
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          filtered
                              ? l.serverNoMatchingResources
                              : complete
                              ? l.prototypeNoRawJson
                              : l.prototypeNoServersYet,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        if (filtered)
                          TextButton(
                            key: const ValueKey('server-search-reset'),
                            onPressed: () {
                              controller.search.clear();
                              setState(() {
                                sourceId = -1;
                                favoritesOnly = false;
                              });
                            },
                            child: Text(l.prototypeClear),
                          )
                        else
                          TextButton(
                            onPressed: () => complete
                                ? controller.editRaw(context)
                                : controller.addServers(context),
                            child: Text(
                              complete
                                  ? l.prototypeAddRawJson
                                  : l.prototypeAddServer,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (count > 0)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            sliver: DecoratedSliver(
              decoration: BoxDecoration(
                color: palette.card,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              sliver: SliverList.builder(
                itemCount: count + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      child: Text(
                        complete
                            ? l.serverCompleteConfigurationsTab
                            : l.serverNodesTab,
                        style: AppTypography.sectionTitle,
                      ),
                    );
                  }
                  if (index == count + 1) return const SizedBox(height: 18);
                  final resourceIndex = index - 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: resourceIndex < ordinary.length
                        ? ServerNodeRow(
                            key: ValueKey((
                              'server',
                              ordinary[resourceIndex].id,
                            )),
                            controller: controller,
                            row: ordinary[resourceIndex],
                            showDivider: false,
                          )
                        : ServerRawRow(
                            key: ValueKey((
                              'raw',
                              raw[resourceIndex - ordinary.length].id,
                            )),
                            controller: controller,
                            row: raw[resourceIndex - ordinary.length],
                          ),
                  );
                },
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  Widget _subscriptions(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _search(context),
        const SizedBox(height: 18),
        ServerSourcesView(controller: controller),
      ],
    ),
  );
}

class ServerManualGroupsPage extends StatelessWidget {
  const ServerManualGroupsPage({super.key, required this.controller});
  final ServersController controller;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ServersController, ServersPageState>(
    bloc: controller,
    builder: (context, state) {
      final l = AppLocalizations.of(context)!;
      final groups = controller
          .groups(l, filter: false)
          .where((group) => group.manual)
          .toList();
      return Scaffold(
        appBar: PageAppBar.forPage(
          context,
          title: Text(l.manualGroupsTitle),
          description: l.manualGroupsDescription,
        ),
        body: SafeArea(
          child: ResponsiveContent(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint
                    ? 16
                    : 28,
                16,
                MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint
                    ? 16
                    : 28,
                28,
              ),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => controller.createManualGroup(context),
                      icon: const Icon(LucideIcons.folderPlus, size: 17),
                      label: Text(l.manualGroupNew),
                    ),
                    ManualGroupOrderButton(
                      controller: controller,
                      showLabel: true,
                    ),
                    OutlinedButton.icon(
                      onPressed: () => controller.choose(
                        context,
                        const ServerSelection.automatic(),
                      ),
                      icon: const Icon(LucideIcons.shuffle, size: 17),
                      label: Text(l.prototypeAutomaticSelection),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => controller.choose(
                        context,
                        const ServerSelection.source(0),
                      ),
                      icon: const Icon(LucideIcons.layers, size: 17),
                      label: Text(l.prototypeManualAdditions),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SettingSection(
                  title: l.manualGroupsTitle,
                  description: l.manualGroupsUngroupedFirst,
                  padding: EdgeInsets.zero,
                  dividerIndent: 0,
                  children: [
                    if (groups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l.manualGroupEmpty),
                      ),
                    for (final group in groups)
                      SettingRow(
                        title: group.name,
                        subtitle: l.prototypeServerCount(group.rows.length),
                        leading: const Icon(LucideIcons.folder, size: 19),
                        trailing: group.manualGroupId == null
                            ? null
                            : IconButton(
                                tooltip:
                                    '${l.prototypeMoreActions}: ${group.name}',
                                onPressed: controller.manualGroupBusy(group)
                                    ? null
                                    : () => controller.openManualGroupMenu(
                                        context,
                                        group,
                                      ),
                                icon: const Icon(
                                  LucideIcons.ellipsis,
                                  size: 18,
                                ),
                              ),
                        onTap: () =>
                            controller.browse(context, group, mobile: true),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ServerRawRow extends StatelessWidget {
  const ServerRawRow({super.key, required this.controller, required this.row});
  final ServersController controller;
  final CoreConfigData row;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final selected =
        controller.configuration.connection.expert &&
        controller.configuration.connection.rawId == row.id;
    final running =
        controller.connectionView.phase == ConnectionPhase.connected &&
        controller.connectionView.runtime?.configuration.connection.expert ==
            true &&
        controller.connectionView.runtime?.configuration.connection.rawId ==
            row.id;
    final palette = ColorManager.palette(context);
    return Material(
      color: selected || running ? palette.selectedSurface : palette.card,
      borderRadius: BorderRadius.circular(AppRadii.control),
      clipBehavior: Clip.antiAlias,
      child: SettingRow(
        title: row.name,
        subtitle: l.xrayRawPageTitle,
        leading: const Icon(LucideIcons.fileJson, size: 19),
        titleTrailing: selected || running
            ? Icon(
                running ? LucideIcons.activity : LucideIcons.circleCheck,
                size: 16,
                color: ColorManager.palette(context).primary,
              )
            : null,
        onTap: () => context.pushScoped(
          AppPageDestination.serverResource,
          extra: ServerResourceParams(
            controller: controller,
            resourceId: row.id,
            raw: true,
          ),
        ),
      ),
    );
  }
}

class ServerGroupView extends StatelessWidget {
  final ServersController controller;
  final ServerGroup group;
  final bool groupPage;
  final bool embedded;
  const ServerGroupView({
    super.key,
    required this.controller,
    required this.group,
    this.groupPage = false,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final card = _card(context, mobile);
    if (embedded) {
      return card;
    }
    return Padding(
      padding: mobile
          ? const EdgeInsets.fromLTRB(16, 16, 16, 28)
          : const EdgeInsets.fromLTRB(
              AppSpacing.page,
              16,
              AppSpacing.page,
              AppSpacing.desktopPageBottom,
            ),
      child: card,
    );
  }

  Widget _card(BuildContext context, bool mobile) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final package = group.source == null
        ? null
        : SubscriptionUserInfo.fromSubscription(group.source!);
    final headerCount = package == null ? 1 : 2;
    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: ListView.builder(
          key: PageStorageKey('servers:${group.id}'),
          primary: !embedded,
          padding: EdgeInsets.zero,
          itemCount:
              headerCount +
              (group.visibleRows.isEmpty ? 1 : group.visibleRows.length),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Container(
                constraints: const BoxConstraints(minHeight: 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 15,
                ),
                child: mobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _heading(context, mobile),
                          const SizedBox(height: 12),
                          _actions(context, mobile),
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth,
                              ),
                              child: _heading(context, mobile),
                            ),
                            _actions(context, mobile),
                          ],
                        ),
                      ),
              );
            }
            if (index == 1 && package != null) {
              return SubscriptionPackageDetails(info: package);
            }
            if (group.visibleRows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 28,
                ),
                child: group.source != null && group.rows.isEmpty
                    ? Column(
                        children: [
                          Text(
                            controller.providerGroup(group)
                                ? l.subscriptionModeProviderManaged
                                : l.subscriptionModeAppManaged,
                            textAlign: TextAlign.center,
                            style: AppTypography.rowTitle,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.subscriptionModeNoCacheTitle,
                            textAlign: TextAlign.center,
                            style: AppTypography.rowValue.copyWith(
                              color: palette.mutedForeground,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.subscriptionModeNeedsRefresh,
                            textAlign: TextAlign.center,
                            style: AppTypography.serverDetail.copyWith(
                              color: palette.mutedForeground,
                            ),
                          ),
                        ],
                      )
                    : group.manual && group.rows.isEmpty
                    ? Column(
                        children: [
                          Text(
                            l.manualGroupEmpty,
                            textAlign: TextAlign.center,
                            style: AppTypography.rowValue,
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => controller.addServers(context),
                            icon: const Icon(LucideIcons.plus, size: 16),
                            label: Text(l.prototypeAddServer),
                          ),
                        ],
                      )
                    : Text(
                        l.prototypeNoServersYet,
                        textAlign: TextAlign.center,
                        style: AppTypography.rowValue.copyWith(
                          color: palette.mutedForeground,
                        ),
                      ),
              );
            }
            final rowIndex = index - headerCount;
            final row = group.visibleRows[rowIndex];
            return Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                0,
                18,
                rowIndex == group.visibleRows.length - 1 ? 18 : 0,
              ),
              child: ServerNodeRow(
                key: ValueKey(row.id),
                controller: controller,
                row: row,
                detail: controller.sourceName(l, row),
                showDivider: false,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, bool mobile) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final label = Padding(
      padding: EdgeInsets.only(top: mobile ? 4 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            controller.summary(l, group),
            style: AppTypography.serverGroupSummary.copyWith(
              color: palette.mutedForeground,
            ),
          ),
          if (controller.providerGroup(group)) ...[
            const SizedBox(height: 4),
            Text(
              l.providerChooseConfigurationHint,
              style: AppTypography.serverDetail.copyWith(
                color: palette.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
    return Row(
      mainAxisSize: mobile ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(
          group.source == null ? LucideIcons.folder : LucideIcons.rss,
          size: 20,
          color: palette.mutedForeground,
        ),
        const SizedBox(width: 13),
        if (mobile) Expanded(child: label) else Flexible(child: label),
      ],
    );
  }

  Widget _actions(BuildContext context, bool mobile) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final testing = controller.testingGroup(group);
    final cancelling = controller.cancellingGroup(group);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!controller.providerGroup(group))
          OutlinedButton(
            onPressed: testing
                ? cancelling
                      ? null
                      : () => controller.cancelTest(group.id)
                : group.rows.isEmpty || group.rows.any(controller.serverBusy)
                ? null
                : () => controller.test(context, group.rows, groupId: group.id),
            style: OutlinedButton.styleFrom(
              minimumSize: Size(
                0,
                AppLayout.touchExtent(
                  mobile
                      ? AppLayout.mobileButtonMinHeight
                      : AppLayout.buttonMinHeight,
                  platform: Theme.of(context).platform,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              foregroundColor: palette.foreground,
              backgroundColor: palette.card,
              side: BorderSide(color: palette.borderStrong),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              textStyle: AppTypography.serverGroupAction,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppActivityBuilder(
                  builder: (context, activity) => activity.pinging
                      ? const ButtonProgressIndicator()
                      : const Icon(LucideIcons.refreshCw, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  testing
                      ? cancelling
                            ? l.prototypePleaseWait
                            : l.prototypeCancel
                      : l.prototypeTestServers,
                ),
              ],
            ),
          ),
        if (group.manual && group.rows.length > 1)
          Tooltip(
            message: controller.query.trim().isNotEmpty
                ? l.manualOrderClearSearch
                : l.manualServerOrder,
            child: OutlinedButton.icon(
              onPressed:
                  controller.query.trim().isNotEmpty ||
                      controller.manualGroupBusy(group)
                  ? null
                  : () => controller.openServerOrder(context, group),
              icon: const Icon(LucideIcons.listOrdered, size: 16),
              label: Text(l.manualServerOrder),
            ),
          ),
        if (!controller.providerGroup(group) && group.selection != null)
          ServerUseButton(controller: controller, group: group),
        if (group.manualGroupId != null)
          IconButton(
            tooltip: '${l.prototypeMoreActions}: ${group.name}',
            onPressed: controller.manualGroupBusy(group)
                ? null
                : () => controller.openManualGroupMenu(
                    context,
                    group,
                    closeAfterDeletion: groupPage,
                  ),
            icon: const Icon(LucideIcons.ellipsis, size: 18),
          ),
        if (group.source != null)
          SizedBox(
            width: 36,
            child: SourceMenu(controller: controller, source: group.source!),
          ),
      ],
    );
  }
}

class ServerUseButton extends StatelessWidget {
  final ServersController controller;
  final ServerGroup group;
  final bool inline;
  const ServerUseButton({
    super.key,
    required this.controller,
    required this.group,
    this.inline = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (controller.providerGroup(group)) {
      final VoidCallback? browse = group.visibleRows.isEmpty
          ? null
          : () => controller.browse(
              context,
              group,
              mobile:
                  MediaQuery.sizeOf(context).width <=
                  AppLayout.mobileBreakpoint,
            );
      if (inline) {
        return IconButton(
          tooltip: l.providerChooseConfiguration,
          onPressed: browse,
          icon: const Icon(LucideIcons.list, size: 18),
        );
      }
      return OutlinedButton.icon(
        onPressed: browse,
        icon: const Icon(LucideIcons.list, size: 16),
        label: Text(l.providerChooseConfiguration),
      );
    }
    final selection = group.selection;
    if (selection == null) return const SizedBox.shrink();
    final count = controller.entryCount(selection);
    final enabled = controller.canUse(group);
    final selected = controller.selected(selection);
    final VoidCallback? choose = controller.busy || !enabled
        ? null
        : () => controller.choose(context, selection);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final palette = ColorManager.palette(context);
    return Semantics(
      label: '${l.prototypeUseEntryServers(count)}: ${group.name}',
      button: true,
      selected: selected,
      enabled: choose != null,
      onTap: choose,
      excludeSemantics: true,
      child: Tooltip(
        message: enabled
            ? l.prototypeUseEntryServers(count)
            : l.prototypeNotEnoughServers,
        child: Opacity(
          opacity: choose == null ? .52 : 1,
          child: OutlinedButton(
            onPressed: choose,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(
                0,
                AppLayout.touchExtent(
                  mobile
                      ? AppLayout.mobileButtonMinHeight
                      : inline
                      ? 32
                      : 36,
                  platform: Theme.of(context).platform,
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: !mobile && inline ? 7 : 9,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
              foregroundColor: selected ? palette.primary : palette.foreground,
              backgroundColor: selected
                  ? palette.selectedSurface
                  : palette.card,
              side: BorderSide(
                color: selected
                    ? Color.lerp(palette.border, palette.primary, .48)!
                    : inline
                    ? palette.border
                    : palette.borderStrong,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              textStyle: inline
                  ? AppTypography.serverUseLabel
                  : AppTypography.serverGroupAction,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.selectingGroup(selection))
                  const ButtonProgressIndicator()
                else
                  Icon(
                    selected ? LucideIcons.circleCheck : LucideIcons.zap,
                    size: inline ? 15 : 16,
                  ),
                const SizedBox(width: 6),
                Text(l.prototypeUse),
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    color: selected
                        ? palette.primarySolid
                        : palette.surfaceHover,
                  ),
                  child: Text(
                    '$count',
                    style:
                        (inline
                                ? AppTypography.serverUseCount
                                : AppTypography.serverGroupUseCount)
                            .copyWith(
                              color: selected
                                  ? palette.primaryForeground
                                  : palette.mutedStrong,
                            ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ServerNodeRow extends StatelessWidget {
  final ServersController controller;
  final CoreConfigData row;
  final String? detail;
  final bool showDivider;
  const ServerNodeRow({
    super.key,
    required this.controller,
    required this.row,
    this.detail,
    this.showDivider = false,
  });

  @override
  Widget build(
    BuildContext context,
  ) => BlocSelector<AppEventBus, AppEventBusState, PingBatchResult?>(
    bloc: AppEventBus.instance,
    selector: (state) => state.pingFailures[row.id],
    builder: (context, failure) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          context,
          running: controller.runningEntries.contains(row.id),
          chosen: controller.chosen(row),
          enabled: controller.canChoose(row),
          protocol: controller.protocol(row),
        ),
        if (failure != null && row.type == 'outbound')
          ExpansionTile(
            key: PageStorageKey(('server-ping-failure', row.id, failure)),
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            iconColor: ColorManager.palette(context).destructive,
            collapsedIconColor: ColorManager.palette(context).destructive,
            title: Text(
              '${AppLocalizations.of(context)!.prototypeSpeedTest} · ${AppLocalizations.of(context)!.resultFailed}',
              style: AppTypography.settingsDetailNote.copyWith(
                color: ColorManager.palette(context).destructive,
              ),
            ),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SelectableText(
                  appFailureMessage(
                    AppLocalizations.of(context)!,
                    failure.error,
                    operation: AppLocalizations.of(context)!.prototypeSpeedTest,
                  ),
                  key: PageStorageKey('server-ping-diagnostic-${row.id}'),
                  style: AppTypography.settingsDetailNote.copyWith(
                    color: ColorManager.palette(context).destructive,
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _row(
    BuildContext context, {
    required bool running,
    required bool chosen,
    required bool enabled,
    required String protocol,
  }) {
    final l = AppLocalizations.of(context)!;
    final p = ColorManager.palette(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 300;
        return Column(
          children: [
            Material(
              color: chosen || running ? p.selectedSurface : p.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.control),
                side: chosen || running
                    ? BorderSide(color: p.primary.withValues(alpha: .2))
                    : BorderSide.none,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.pushScoped(
                  AppPageDestination.serverResource,
                  extra: ServerResourceParams(
                    controller: controller,
                    resourceId: row.id,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 0, 12),
                  child: Row(
                    children: [
                      Icon(
                        controller.providerRow(row)
                            ? LucideIcons.fileJson
                            : LucideIcons.server,
                        size: 20,
                        color: chosen || running
                            ? p.primaryText
                            : p.mutedForeground,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              controller.serverName(row),
                              style: AppTypography.serverNodeTitle.copyWith(
                                color: chosen || running
                                    ? p.primaryText
                                    : p.foreground,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (protocol.isNotEmpty) protocol,
                                detail ?? controller.sourceName(l, row),
                              ].join(' · '),
                              style: AppTypography.metadata.copyWith(
                                color: p.mutedForeground,
                              ),
                            ),
                            if (compact && !controller.providerRow(row)) ...[
                              const SizedBox(height: 4),
                              Text(
                                controller.health(l, row),
                                style: AppTypography.metadata.copyWith(
                                  color: ColorManager.nodeLatency(
                                    context,
                                    row.delay,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!compact && !controller.providerRow(row))
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 88),
                            child: Text(
                              controller.health(l, row),
                              textAlign: TextAlign.end,
                              style: AppTypography.metadata.copyWith(
                                color: ColorManager.nodeLatency(
                                  context,
                                  row.delay,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (running || chosen)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: 8,
                            end: 4,
                          ),
                          child: Icon(
                            running
                                ? LucideIcons.activity
                                : LucideIcons.circleCheck,
                            size: 17,
                            color: p.primary,
                          ),
                        ),
                      if (!controller.providerRow(row))
                        IconButton(
                          tooltip: row.favorite
                              ? l.prototypeRemoveFavorite
                              : l.prototypeAddFavorite,
                          onPressed: controller.serverBusy(row)
                              ? null
                              : () => controller.toggleFavorite(context, row),
                          isSelected: row.favorite,
                          icon: controller.favoritingIds.contains(row.id)
                              ? const ButtonProgressIndicator()
                              : const Icon(LucideIcons.star, size: 17),
                          selectedIcon: const Icon(
                            LucideIcons.star600,
                            size: 17,
                          ),
                        ),
                      ServerMenu(controller: controller, row: row),
                    ],
                  ),
                ),
              ),
            ),
            if (showDivider) Divider(height: 1, color: p.border),
          ],
        );
      },
    );
  }
}

class ServerMenu extends StatelessWidget {
  final ServersController controller;
  final CoreConfigData row;
  const ServerMenu({super.key, required this.controller, required this.row});

  static Future<void> open(
    BuildContext context,
    ServersController controller,
    CoreConfigData row,
  ) async {
    final l = AppLocalizations.of(context)!;
    final action = await showServerActionsMenu(
      context,
      name: controller.serverName(row),
      source: controller.sourceName(l, row),
      provider: controller.providerRow(row),
      canMove: ServerCatalog.isManual(row),
    );
    if (context.mounted && action != null) {
      await controller.serverAction(context, row, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return IconButton(
      tooltip: '${l.prototypeMoreActions}: ${controller.serverName(row)}',
      onPressed: controller.serverBusy(row)
          ? null
          : () => open(context, controller, row),
      style: IconButton.styleFrom(
        foregroundColor: ColorManager.palette(context).mutedStrong,
        iconSize: 18,
        padding: EdgeInsets.zero,
        minimumSize: Size.square(
          AppLayout.touchExtent(36, platform: Theme.of(context).platform),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(),
      ),
      icon: const Icon(LucideIcons.ellipsis),
    );
  }
}

class SourceMenu extends StatelessWidget {
  final ServersController controller;
  final SubscriptionData source;
  const SourceMenu({super.key, required this.controller, required this.source});

  static Future<void> open(
    BuildContext context,
    ServersController controller,
    SubscriptionData source,
  ) async {
    final action = await showSourceActionsMenu(
      context,
      name: source.name,
      count: controller.sourceCount(source.id),
      provider: controller.providerSource(source),
    );
    if (context.mounted && action != null) {
      await controller.sourceAction(context, source, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return IconButton(
      tooltip: '${l.prototypeMoreActions}: ${source.name}',
      onPressed: controller.sourceBusy(source.id)
          ? null
          : () => open(context, controller, source),
      style: IconButton.styleFrom(
        foregroundColor: ColorManager.palette(context).mutedStrong,
        iconSize: 18,
        padding: EdgeInsets.zero,
        minimumSize: Size.square(
          AppLayout.touchExtent(36, platform: Theme.of(context).platform),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(),
      ),
      icon: const Icon(LucideIcons.ellipsis),
    );
  }
}
