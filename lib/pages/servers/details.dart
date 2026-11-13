import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/resource_json.dart';
import 'package:onexray/pages/servers/subscription/user_info.dart';
import 'package:onexray/pages/shared/share/params.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/pages/main/navigation.dart';

class ServerResourceParams {
  const ServerResourceParams({
    required this.controller,
    required this.resourceId,
    this.raw = false,
  });
  final ServersController controller;
  final int resourceId;
  final bool raw;
}

class ServerSourceParams {
  const ServerSourceParams({required this.controller, required this.sourceId});
  final ServersController controller;
  final int sourceId;
}

/// A resource is inspected before an explicit action changes the connection.
class ServerResourcePage extends StatelessWidget {
  const ServerResourcePage({super.key, required this.params});
  final ServerResourceParams params;
  ServersController get controller => params.controller;
  int get resourceId => params.resourceId;
  bool get raw => params.raw;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ServersController, ServersPageState>(
    bloc: controller,
    builder: (context, state) {
      final l = AppLocalizations.of(context)!;
      final row = (raw ? state.rawConfigurations : state.servers)
          .where((row) => row.id == resourceId)
          .firstOrNull;
      final name = row == null
          ? l.prototypeServers
          : raw
          ? row.name
          : controller.serverName(row);
      final provider = row != null && !raw && controller.providerRow(row);
      final chosen =
          row != null &&
          (raw
              ? state.configuration.connection.expert &&
                    state.configuration.connection.rawId == row.id
              : controller.chosen(row));
      final busy =
          row != null && (controller.busy || controller.serverBusy(row));
      return Scaffold(
        appBar: PageAppBar(title: Text(name)),
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
                if (row == null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.prototypeNoServersYet),
                  )
                else ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: busy || (!raw && !controller.canChoose(row))
                            ? null
                            : () => raw
                                  ? controller.chooseRaw(context, row)
                                  : controller.chooseRow(context, row),
                        icon: controller.selecting?.id == row.id
                            ? const ButtonProgressIndicator()
                            : Icon(
                                chosen
                                    ? LucideIcons.circleCheck
                                    : LucideIcons.check,
                                size: 17,
                              ),
                        label: Text(
                          chosen ? l.prototypeCurrentSelection : l.prototypeUse,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => raw
                                  ? controller.editRaw(context, row.id)
                                  : controller.serverAction(
                                      context,
                                      row,
                                      ServerAction.edit,
                                    ),
                        icon: Icon(
                          provider ? LucideIcons.fileJson : LucideIcons.pencil,
                          size: 17,
                        ),
                        label: Text(
                          provider
                              ? l.providerViewConfiguration
                              : raw
                              ? l.prototypeEditRawJson
                              : l.prototypeEditServer,
                        ),
                      ),
                      if (!raw && !provider)
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => controller.test(context, [row]),
                          icon: const Icon(LucideIcons.activity, size: 17),
                          label: Text(l.prototypeTestAgain),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SettingSection(
                    title: l.serverResourceInformation,
                    padding: EdgeInsets.zero,
                    children: [
                      if (!raw && !provider)
                        SettingRow(
                          title: l.serverProtocol,
                          value: controller.protocol(row),
                          valueMaxLines: 3,
                        )
                      else
                        SettingRow(
                          title: name,
                          subtitle: raw
                              ? l.prototypeCompleteXrayConfiguration
                              : l.providerConfigurationTitle,
                          leading: const Icon(LucideIcons.fileJson, size: 20),
                          titleTrailing: chosen
                              ? Icon(
                                  LucideIcons.circleCheck,
                                  size: 16,
                                  color: ColorManager.palette(context).primary,
                                )
                              : null,
                        ),
                      SettingRow(
                        title: l.prototypeSource,
                        subtitle: raw
                            ? l.prototypeManualAdditions
                            : controller.sourceName(l, row),
                        showChevron: row.subId != 0,
                        onTap: row.subId == 0
                            ? null
                            : () => context.pushScoped(
                                AppPageDestination.sourceDetails,
                                extra: ServerSourceParams(
                                  controller: controller,
                                  sourceId: row.subId,
                                ),
                              ),
                      ),
                      if (!raw && !provider)
                        SettingRow(
                          title: l.prototypeSpeedTest,
                          subtitle: controller.health(l, row),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SettingSection(
                    title: l.serverConfigurationJson,
                    padding: EdgeInsets.zero,
                    children: [ServerResourceJsonPreview(row: row)],
                  ),
                  const SizedBox(height: 20),
                  SettingSection(
                    title: l.prototypeMoreActions,
                    padding: EdgeInsets.zero,
                    children: [
                      if (!raw)
                        SettingRow(
                          title: provider
                              ? l.providerCopyAsRaw
                              : l.prototypeSaveAsLocalServer,
                          leading: const Icon(LucideIcons.copy, size: 18),
                          enabled: !busy,
                          onTap: () => controller.serverAction(
                            context,
                            row,
                            ServerAction.copy,
                          ),
                        ),
                      if (!raw)
                        SettingRow(
                          title: row.favorite
                              ? l.prototypeRemoveFavorite
                              : l.prototypeAddFavorite,
                          leading: const Icon(LucideIcons.star, size: 18),
                          enabled: !busy,
                          onTap: () => controller.toggleFavorite(context, row),
                        ),
                      if (!raw && ServerCatalog.isManual(row))
                        SettingRow(
                          title: l.manualGroupMove,
                          leading: const Icon(
                            LucideIcons.folderInput,
                            size: 18,
                          ),
                          enabled: !busy,
                          onTap: () => controller.serverAction(
                            context,
                            row,
                            ServerAction.move,
                          ),
                        ),
                      SettingRow(
                        title: l.prototypeShare,
                        leading: const Icon(LucideIcons.share2, size: 18),
                        enabled: !busy,
                        onTap: () => raw
                            ? controller.shareAsset(
                                context,
                                SharePageParams(ShareType.config, row.id),
                              )
                            : controller.serverAction(
                                context,
                                row,
                                ServerAction.share,
                              ),
                      ),
                      SettingRow(
                        title: l.prototypeDelete,
                        leading: const Icon(LucideIcons.trash2, size: 18),
                        enabled: !busy,
                        onTap: () => raw
                            ? controller.removeRaw(context, row)
                            : controller.serverAction(
                                context,
                                row,
                                ServerAction.delete,
                              ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ServerSourcePage extends StatelessWidget {
  const ServerSourcePage({super.key, required this.params});
  final ServerSourceParams params;
  ServersController get controller => params.controller;
  int get sourceId => params.sourceId;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ServersController, ServersPageState>(
    bloc: controller,
    builder: (context, state) {
      final l = AppLocalizations.of(context)!;
      final source = state.sources
          .where((source) => source.id == sourceId)
          .firstOrNull;
      final rows = state.servers.where((row) => row.subId == sourceId).toList();
      final busy = controller.sourceBusy(sourceId);
      final testGroupId = 'subscription:$sourceId';
      final testing = controller.testingGroup(testGroupId);
      final cancelling = controller.cancellingGroup(testGroupId);
      final error = state.sourceErrors[sourceId];
      final package = source == null
          ? null
          : SubscriptionUserInfo.fromSubscription(source);
      return Scaffold(
        appBar: PageAppBar(
          title: Text(source?.name ?? l.prototypeSubscriptions),
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
                if (source == null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.prototypeNoServersYet),
                  )
                else ...[
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: SelectableText(
                          error,
                          style: AppTypography.supporting.copyWith(
                            color: ColorManager.palette(context).destructive,
                          ),
                        ),
                      ),
                    ),
                  SettingSection(
                    title: l.prototypeSubscriptions,
                    padding: EdgeInsets.zero,
                    children: [
                      SettingRow(
                        title: l.prototypeSubscriptionName,
                        value: source.name,
                      ),
                      SettingRow(
                        title: l.prototypeSubscriptionLink,
                        subtitle: source.url,
                        valueMaxLines: 4,
                      ),
                      SettingRow(
                        title: l.subscriptionPanelTitle,
                        value: source.panel == 'remnawave'
                            ? 'Remnawave'
                            : l.subscriptionPanelGeneric,
                      ),
                      SettingRow(
                        title: l.subscriptionModeTitle,
                        value: controller.providerSource(source)
                            ? l.subscriptionModeProviderManaged
                            : l.subscriptionModeAppManaged,
                      ),
                      if (source.userAgent?.isNotEmpty == true)
                        SettingRow(
                          title: l.subscriptionUserAgentTitle,
                          subtitle: source.userAgent,
                        ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => controller.sourceAction(
                                    context,
                                    source,
                                    SourceAction.update,
                                  ),
                            icon: busy
                                ? const ButtonProgressIndicator()
                                : const Icon(LucideIcons.refreshCw, size: 17),
                            label: Text(l.prototypeCheckForUpdates),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => controller.sourceAction(
                                    context,
                                    source,
                                    SourceAction.edit,
                                  ),
                            icon: const Icon(LucideIcons.pencil, size: 17),
                            label: Text(l.prototypeEditSubscription),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (package != null) ...[
                    const SizedBox(height: 20),
                    SettingSection(
                      title: '',
                      padding: EdgeInsets.zero,
                      children: [SubscriptionPackageDetails(info: package)],
                    ),
                  ],
                  const SizedBox(height: 20),
                  SettingSection(
                    title: controller.providerSource(source)
                        ? l.providerConfigurationTitle
                        : l.serverNodesTab,
                    description: controller.providerSource(source)
                        ? l.providerConfigurationCount(rows.length)
                        : l.prototypeServerCount(rows.length),
                    padding: EdgeInsets.zero,
                    children: [
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(l.subscriptionModeNeedsRefresh),
                        ),
                      for (final row in rows)
                        SettingRow(
                          title: controller.serverName(row),
                          subtitle: controller.protocol(row),
                          leading: Icon(
                            controller.providerRow(row)
                                ? LucideIcons.fileJson
                                : LucideIcons.server,
                            size: 19,
                          ),
                          onTap: () => context.pushScoped(
                            AppPageDestination.serverResource,
                            extra: ServerResourceParams(
                              controller: controller,
                              resourceId: row.id,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SettingSection(
                    title: l.prototypeMoreActions,
                    padding: EdgeInsets.zero,
                    children: [
                      if (!controller.providerSource(source))
                        SettingRow(
                          key: ValueKey('source-test-action-$sourceId'),
                          title: testing
                              ? cancelling
                                    ? l.prototypePleaseWait
                                    : l.prototypeCancel
                              : l.prototypeTestServers,
                          enabled: testing
                              ? !cancelling
                              : !busy && rows.isNotEmpty,
                          leading: const Icon(LucideIcons.activity, size: 18),
                          onTap: testing
                              ? () => controller.cancelTest(testGroupId)
                              : () => controller.test(
                                  context,
                                  rows,
                                  groupId: testGroupId,
                                ),
                        ),
                      SettingRow(
                        title: l.prototypeShareSubscription,
                        enabled: !busy,
                        leading: const Icon(LucideIcons.share2, size: 18),
                        onTap: () => controller.sourceAction(
                          context,
                          source,
                          SourceAction.share,
                        ),
                      ),
                      SettingRow(
                        title: l.prototypeDeleteSource,
                        enabled: !busy,
                        leading: const Icon(LucideIcons.trash2, size: 18),
                        onTap: () => controller.sourceAction(
                          context,
                          source,
                          SourceAction.delete,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
