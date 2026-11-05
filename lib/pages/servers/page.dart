import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/view.dart';
import 'package:onexray/pages/servers/sort.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';

class ServersPage extends StatefulWidget {
  const ServersPage({super.key, this.controller});

  /// An injected controller remains owned by the caller.
  final ServersController? controller;
  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  late final controller = widget.controller ?? ServersController();
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
    if (widget.controller == null) unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<ServersController, ServersPageState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        final page = Scaffold(
          appBar: PageAppBar(
            title: Text(l.prototypeServers),
            actions: [
              if (!mobile)
                IconButton(
                  tooltip: l.manualGroupNew,
                  onPressed: () => controller.createManualGroup(context),
                  icon: const Icon(LucideIcons.folderPlus, size: 20),
                ),
              IconButton(
                key: const ValueKey('servers-add'),
                tooltip: l.prototypeAddServer,
                onPressed: () => controller.addServers(context),
                icon: const Icon(LucideIcons.plus, size: 20),
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
          final group = controller
              .groups(l, filter: false)
              .where((row) => row.manual && row.id == params.groupId)
              .firstOrNull;
          return Scaffold(
            appBar: PageAppBar(
              title: Text(
                group?.name ?? l.prototypeServers,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                if (controller.query.trim().isNotEmpty)
                  IconButton(
                    tooltip: l.prototypeClear,
                    onPressed: controller.search.clear,
                    icon: const Icon(LucideIcons.x, size: 18),
                  ),
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
