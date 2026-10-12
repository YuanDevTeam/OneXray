import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/menus.dart';
import 'package:onexray/pages/servers/subscription/user_info.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/pages/shared/widgets/page_empty_state.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';

class ServerBrowser extends StatelessWidget {
  final ServersController controller;
  final ScrollController scroll;
  const ServerBrowser({
    super.key,
    required this.controller,
    required this.scroll,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final groups = controller.groups(l);
    final favorites = controller.favorites(l);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    if (controller.servers.isEmpty) {
      if (controller.sources.isNotEmpty) {
        return PageEmptyState(
          title: l.subscriptionModeNoCacheTitle,
          description: l.subscriptionModeNeedsRefresh,
          primaryLabel: l.prototypeUpdatesAndSources,
          onPrimary: () => controller.openSources(context),
          secondaryLabel: l.prototypeAddServer,
          onSecondary: () => controller.addServers(context),
          scrollController: scroll,
        );
      }
      return PageEmptyState(
        title: l.prototypeNoServersYet,
        description: l.prototypeAddProviderSubscriptionHint,
        primaryLabel: l.prototypeAddServer,
        onPrimary: () => controller.addServers(context),
        secondaryLabel: l.prototypeHowGetServers,
        onSecondary: () => controller.openServerHelp(context),
        scrollController: scroll,
      );
    }
    if (mobile) {
      return _mobileBrowser(context, groups, favorites);
    }
    final active = _activeGroup(groups);
    final compact =
        MediaQuery.sizeOf(context).width <= AppLayout.compactDesktopBreakpoint;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.desktopPageTop,
        AppSpacing.page,
        AppSpacing.desktopPageBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _search(context),
          const SizedBox(height: 15),
          Expanded(
            child: Flex(
              direction: compact ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: _subscriptionList(context, groups, favorites),
                  ),
                ),
                if (active != null) ...[
                  SizedBox(width: compact ? 0 : 16, height: compact ? 16 : 0),
                  Expanded(
                    child: ServerGroupView(
                      controller: controller,
                      group: active,
                      embedded: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  ServerGroup? _activeGroup(List<ServerGroup> groups) {
    final active = groups
        .where((group) => group.id == controller.activeGroupId)
        .firstOrNull;
    if (active != null) return active;
    final currentId = controller.currentGroupId;
    return groups.where((group) => group.id == currentId).firstOrNull ??
        groups.firstOrNull;
  }

  Widget _mobileBrowser(
    BuildContext context,
    List<ServerGroup> groups,
    List<CoreConfigData> favorites,
  ) {
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 22),
      children: [
        _search(context),
        const SizedBox(height: 12),
        _subscriptionList(context, groups, favorites),
      ],
    );
  }

  Widget _search(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      borderSide: BorderSide(color: palette.border),
    );
    return SizedBox(
      height: 43,
      child: TextField(
        controller: controller.search,
        onChanged: controller.searchChanged,
        textAlignVertical: TextAlignVertical.center,
        style: AppTypography.serverBody.copyWith(color: palette.foreground),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsetsDirectional.only(end: 13),
          hintText: l.prototypeSearchSubscriptionsServers,
          hintStyle: AppTypography.serverBody.copyWith(
            color: palette.mutedForeground,
          ),
          prefixIconConstraints: const BoxConstraints.tightFor(
            width: 41,
            height: 43,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsetsDirectional.only(start: 13, end: 10),
            child: Icon(
              LucideIcons.search,
              size: 18,
              color: palette.mutedForeground,
            ),
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: palette.primary),
          ),
        ),
      ),
    );
  }

  Widget _subscriptionList(
    BuildContext context,
    List<ServerGroup> groups,
    List<CoreConfigData> favorites,
  ) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final current = controller.currentSelectionSummary(l);
    final activeGroup = _activeGroup(groups);
    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _automaticRow(context),
          if (current != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Color.lerp(palette.card, palette.selectedSurface, .45),
                border: Border(top: BorderSide(color: palette.border)),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.circleCheck,
                    size: 20,
                    color: palette.running,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.prototypeCurrentSelection,
                          style: AppTypography.serverSelectionLabel.copyWith(
                            color: palette.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          current.title,
                          style: AppTypography.serverSelectionTitle.copyWith(
                            color: palette.foreground,
                          ),
                        ),
                        if (current.detail.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            current.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.serverSelectionDetail.copyWith(
                              color: palette.mutedForeground,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (favorites.isNotEmpty) ...[
            _listHeading(context, l.prototypeFavorites),
            for (final row in favorites)
              ServerNodeRow(controller: controller, row: row),
          ],
          _listHeading(context, l.prototypeBySubscription),
          for (final group in groups)
            _groupRow(context, group, active: group.id == activeGroup?.id),
          if (groups.isEmpty && controller.search.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
              child: Text(
                l.prototypeNoMatchingSubscriptions,
                textAlign: TextAlign.center,
                style: AppTypography.settingsInput.copyWith(
                  color: palette.mutedForeground,
                ),
              ),
            ),
          if (mobile)
            InkWell(
              onTap: () => controller.openSources(context),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      AppActivityBuilder(
                        builder: (context, activity) => activity.downloading
                            ? const ButtonProgressIndicator()
                            : Icon(
                                LucideIcons.refreshCw,
                                size: 17,
                                color: palette.primary,
                              ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          l.prototypeUpdatesAndSources,
                          style: AppTypography.serverBody.copyWith(
                            color: palette.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _listHeading(BuildContext context, String title) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 17, 16, 8),
    child: Text(
      title.toUpperCase(),
      style: AppTypography.serverSectionTitle.copyWith(
        color: ColorManager.palette(context).mutedForeground,
      ),
    ),
  );

  Widget _automaticRow(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final selected = controller.selected(const ServerSelection.automatic());
    final result = controller.automaticResult(l);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? Color.lerp(palette.card, palette.selectedSurface, .72)
            : palette.card,
        child: InkWell(
          onTap: controller.busy
              ? null
              : () => controller.choose(
                  context,
                  const ServerSelection.automatic(),
                ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 82),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: palette.selectedSurface,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: AppActivityBuilder(
                    builder: (context, activity) =>
                        activity.pinging ||
                            activity.downloading ||
                            controller.selectingGroup(
                              const ServerSelection.automatic(),
                            )
                        ? const Center(child: ButtonProgressIndicator())
                        : Icon(
                            LucideIcons.zap,
                            size: 20,
                            color: palette.primary,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.prototypeAutomaticRecommended,
                        style: AppTypography.serverTitle.copyWith(
                          color: palette.foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.prototypeChooseBySpeedAvailability,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.serverDetail.copyWith(
                          color: palette.mutedForeground,
                        ),
                      ),
                      if (mobile && result != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          result,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.serverSelectionHealth.copyWith(
                            color: palette.running,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!mobile && result != null) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      result,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.serverSelectionHealth.copyWith(
                        color: palette.running,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                Icon(
                  selected
                      ? LucideIcons.circleCheck
                      : LucideIcons.chevronRightDir,
                  size: selected ? 21 : 18,
                  color: selected ? palette.running : palette.foreground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupRow(
    BuildContext context,
    ServerGroup group, {
    required bool active,
  }) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final package = group.source == null
        ? null
        : SubscriptionUserInfo.fromSubscription(group.source!);
    return Material(
      color: active ? palette.muted : palette.card,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => controller.browse(
                  context,
                  group,
                  mobile:
                      MediaQuery.sizeOf(context).width <=
                      AppLayout.mobileBreakpoint,
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 66),
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 6, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.surfaceHover,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          LucideIcons.layers,
                          size: 17,
                          color: palette.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.name,
                              style: AppTypography.serverTitle.copyWith(
                                color: palette.foreground,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              controller.summary(l, group),
                              style: AppTypography.serverGroupDetail.copyWith(
                                color: palette.mutedForeground,
                              ),
                            ),
                            if (package != null) ...[
                              const SizedBox(height: 4),
                              SubscriptionPackageSummary(info: package),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        LucideIcons.chevronRightDir,
                        size: 18,
                        color: palette.foreground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ServerUseButton(
                controller: controller,
                group: group,
                inline: true,
              ),
            ),
            if (group.source != null)
              SizedBox(
                width: 42,
                child: SourceMenu(
                  controller: controller,
                  source: group.source!,
                ),
              ),
          ],
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
          ? const EdgeInsets.fromLTRB(15, 13, 15, 22)
          : const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.desktopPageTop,
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
                constraints: BoxConstraints(minHeight: mobile ? 0 : 88),
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: palette.border)),
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
                child: Text(
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
            return ServerNodeRow(
              key: ValueKey(row.id),
              controller: controller,
              row: row,
              detail: controller.sourceName(l, row),
              showDivider: rowIndex != group.visibleRows.length - 1,
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
          if (!mobile) ...[
            Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.serverGroupTitle,
            ),
            const SizedBox(height: 4),
          ],
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
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.surfaceHover,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(LucideIcons.layers3, size: 20, color: palette.primary),
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
                mobile
                    ? AppLayout.mobileButtonMinHeight
                    : AppLayout.buttonMinHeight,
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
        if (!controller.providerGroup(group))
          ServerUseButton(controller: controller, group: group),
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
    final count = controller.entryCount(group.selection);
    final enabled = controller.canUse(group);
    final selected = controller.selected(group.selection);
    final VoidCallback? choose = controller.busy || !enabled
        ? null
        : () => controller.choose(context, group.selection);
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
                mobile
                    ? AppLayout.mobileButtonMinHeight
                    : inline
                    ? 32
                    : 36,
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
                if (controller.selectingGroup(group.selection))
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
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) =>
      BlocSelector<AppEventBus, AppEventBusState, PingBatchResult?>(
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SelectableText(
                  appFailureMessage(
                    AppLocalizations.of(context)!,
                    failure.error,
                    operation: AppLocalizations.of(context)!.prototypeSpeedTest,
                  ),
                  style: AppTypography.settingsDetailNote.copyWith(
                    color: ColorManager.palette(context).destructive,
                  ),
                ),
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
    final palette = ColorManager.palette(context);
    final conflict = controller.exitConflict(row);
    final rowDetail = detail ?? controller.sourceName(l, row);
    return Container(
      foregroundDecoration: running
          ? BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: palette.primary, width: 3),
              ),
            )
          : null,
      child: Material(
        color: running || chosen
            ? Color.lerp(palette.card, palette.selectedSurface, .72)
            : palette.card,
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 62),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 42,
                      child: Opacity(
                        opacity: enabled ? 1 : .65,
                        child: IconButton(
                          tooltip: row.favorite
                              ? l.prototypeRemoveFavorite
                              : l.prototypeAddFavorite,
                          onPressed: controller.serverBusy(row)
                              ? null
                              : () => controller.toggleFavorite(context, row),
                          isSelected: row.favorite,
                          style: IconButton.styleFrom(
                            foregroundColor: palette.restarting,
                            iconSize: 17,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(42, 42),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: const RoundedRectangleBorder(),
                          ),
                          icon: controller.favoritingIds.contains(row.id)
                              ? const ButtonProgressIndicator()
                              : const Icon(LucideIcons.star),
                          selectedIcon:
                              controller.favoritingIds.contains(row.id)
                              ? const ButtonProgressIndicator()
                              : const Icon(LucideIcons.star600),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Opacity(
                        opacity: enabled ? 1 : .65,
                        child: Semantics(
                          selected: chosen,
                          child: InkWell(
                            onTap: controller.busy || conflict
                                ? null
                                : enabled
                                ? () => controller.chooseRow(context, row)
                                : () =>
                                      ServerMenu.open(context, controller, row),
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                0,
                                9,
                                4,
                                9,
                              ),
                              child: Row(
                                children: [
                                  if (controller.selectingGroup(
                                    ServerSelection.server(row.id),
                                  ))
                                    const ButtonProgressIndicator()
                                  else
                                    Icon(
                                      LucideIcons.server,
                                      size: 19,
                                      color: palette.foreground,
                                    ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          controller.serverName(row),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.serverNodeTitle
                                              .copyWith(
                                                color: palette.foreground,
                                              ),
                                        ),
                                        for (final label in [
                                          row.type,
                                          if (protocol.isNotEmpty) protocol,
                                        ]) ...[
                                          const SizedBox(height: 3),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: palette.surfaceHover,
                                              border: Border.all(
                                                color: palette.border,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              label,
                                              textDirection: TextDirection.ltr,
                                              style: AppTypography
                                                  .serverProtocol
                                                  .copyWith(
                                                    color: palette.mutedStrong,
                                                  ),
                                            ),
                                          ),
                                        ],
                                        if (!controller.providerRow(row)) ...[
                                          const SizedBox(height: 3),
                                          Text.rich(
                                            TextSpan(
                                              text: '$rowDetail · ',
                                              children: [
                                                TextSpan(
                                                  text: controller.health(
                                                    l,
                                                    row,
                                                  ),
                                                  style: TextStyle(
                                                    color:
                                                        ColorManager.nodeLatency(
                                                          context,
                                                          row.delay,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            style: AppTypography.metadata
                                                .copyWith(
                                                  color:
                                                      palette.mutedForeground,
                                                ),
                                          ),
                                        ],
                                        if (conflict) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            l.prototypeFinalExitEntryConflict,
                                            style: AppTypography.metadata
                                                .copyWith(
                                                  color:
                                                      palette.mutedForeground,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 11),
                                  if (running)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.circleCheck,
                                          size: 15,
                                          color: palette.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          l.prototypeConnected,
                                          style: AppTypography
                                              .serverConnectedBadge
                                              .copyWith(color: palette.primary),
                                        ),
                                      ],
                                    )
                                  else if (chosen)
                                    Icon(
                                      LucideIcons.circleCheck,
                                      size: 20,
                                      color: palette.running,
                                    )
                                  else
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
                    ),
                    SizedBox(
                      width: 42,
                      child: ServerMenu(controller: controller, row: row),
                    ),
                  ],
                ),
              ),
            ),
            if (showDivider)
              Divider(height: 1, thickness: 1, color: palette.border),
          ],
        ),
      ),
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
        minimumSize: const Size(42, 42),
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
        minimumSize: const Size(36, 42),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(),
      ),
      icon: const Icon(LucideIcons.ellipsis),
    );
  }
}
