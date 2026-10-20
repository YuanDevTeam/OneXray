import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/servers/sort.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';

class ServersPage extends StatefulWidget {
  const ServersPage({super.key});
  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  final controller = ServersController();
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.initialize();
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<ServersController, ServersPageState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final mobileRoot =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        final empty = state.ready && !state.failed && state.servers.isEmpty;
        final page = Scaffold(
          appBar: PageAppBar(
            title: Text(l.prototypeServers),
            actions: [
              IconButton(
                tooltip: l.manualGroupNew,
                onPressed: () => controller.createManualGroup(context),
                icon: const Icon(LucideIcons.folderPlus),
              ),
              if (!mobileRoot && !empty) ...[
                OutlinedButton.icon(
                  onPressed: () => controller.openSources(context),
                  icon: AppActivityBuilder(
                    builder: (context, activity) => activity.downloading
                        ? const ButtonProgressIndicator()
                        : const Icon(LucideIcons.refreshCw),
                  ),
                  label: Text(l.prototypeUpdatesAndSources),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => controller.addServers(context),
                  icon: const Icon(LucideIcons.plus),
                  label: Text(l.prototypeAddServer),
                ),
              ] else if (mobileRoot)
                IconButton(
                  color: ColorManager.palette(context).primary,
                  tooltip: l.prototypeAddServers,
                  onPressed: () => controller.addServers(context),
                  icon: const Icon(LucideIcons.plus),
                ),
            ],
          ),
          body: SafeArea(
            child: ServerLoadState(
              ready: controller.ready,
              failed: controller.failed,
              failure: state.failure,
              onRetry: controller.initialize,
              child: ResponsiveContent(
                desktopMaxWidth: AppLayout.standardMaxWidth,
                child: ServerBrowser(controller: controller, scroll: scroll),
              ),
            ),
          ),
        );
        return page;
      },
    ),
  );
}

class ServerGroupPage extends StatelessWidget {
  final ServerGroupParams params;
  const ServerGroupPage({super.key, required this.params});

  @override
  Widget build(BuildContext context) {
    final controller = params.controller;
    return BlocProvider.value(
      value: controller,
      child: BlocBuilder<ServersController, ServersPageState>(
        builder: (context, _) {
          final l = AppLocalizations.of(context)!;
          var group = controller
              .groups(l)
              .where((row) => row.id == params.groupId)
              .firstOrNull;
          if (group == null) {
            final source = controller.sources
                .where(
                  (source) =>
                      params.groupId == 'subscription:${source.id}' &&
                      controller.sourceCount(source.id) == 0,
                )
                .firstOrNull;
            if (source != null) {
              group = ServerGroup(
                id: params.groupId,
                name: source.name,
                source: source,
                selection: ServerSelection.source(source.id),
                rows: const [],
                visibleRows: const [],
              );
            }
          }
          return Scaffold(
            appBar: PageAppBar(
              title: Text(group?.name ?? l.prototypeServers),
              actions: [
                ServerSortButton(controller: controller),
                const AppActivityIndicator(pinging: false),
              ],
            ),
            body: SafeArea(
              child: ResponsiveContent(
                child: group == null
                    ? Center(child: Text(l.prototypeNoServersYet))
                    : ServerGroupView(
                        controller: controller,
                        group: group,
                        groupPage: true,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ServerLoadState extends StatelessWidget {
  final bool ready, failed;
  final Object? failure;
  final VoidCallback onRetry;
  final Widget child;
  const ServerLoadState({
    super.key,
    required this.ready,
    required this.failed,
    this.failure,
    required this.onRetry,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (failed) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(appFailureMessage(l, failure)),
              FilledButton(onPressed: onRetry, child: Text(l.prototypeRetry)),
            ],
          ),
        ),
      );
    }
    if (!ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return child;
  }
}
