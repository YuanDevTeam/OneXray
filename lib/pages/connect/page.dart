import 'dart:async';

import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/service/connect/coordinator.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/controller.dart';
import 'package:onexray/pages/connect/view.dart';
import 'package:onexray/pages/main/page_visibility.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});
  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final controller = ConnectController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.initialize();
    });
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: PageVisibility(
      onChanged: controller.setPageVisible,
      child: Scaffold(
        appBar: PageAppBar(
          title: Text(AppLocalizations.of(context)!.prototypeConnect),
          actions: const [AppActivityIndicator()],
        ),
        body: SafeArea(
          child: BlocBuilder<ConnectController, ConnectPageState>(
            buildWhen: (previous, next) => !previous.sameContentAs(next),
            builder: (context, state) {
              final l = AppLocalizations.of(context)!;
              if (state.failed) {
                return Center(
                  child: FilledButton(
                    onPressed: () => controller.initialize(),
                    child: Text(l.prototypeRetry),
                  ),
                );
              }
              if (!state.ready) {
                return Center(
                  child: Semantics(
                    label: l.prototypePleaseWait,
                    child: const CircularProgressIndicator(),
                  ),
                );
              }
              return ConnectView(
                view: state.connectionView,
                trafficBuilder: (desktop) =>
                    BlocSelector<
                      ConnectController,
                      ConnectPageState,
                      ConnectionView
                    >(
                      selector: (state) => state.connectionView,
                      builder: (context, view) =>
                          TrafficReadout(view: view, desktop: desktop),
                    ),
                hasServers: state.servers.isNotEmpty,
                expert: state.expertView,
                raws: state.raws,
                pendingChange: state.pendingChange,
                deletingRawIds: state.deletingRawIds,
                activeRawId: state.configuration.connection.expert
                    ? state.configuration.connection.rawId
                    : null,
                location: controller.selectionTitle(l),
                runningPath: controller.runningRoute?.path,
                locationDetail: controller.selectionDetail(l),
                locationHealth: controller.selectionHealth(l),
                method: controller.homeMethodTitle(l),
                methodDetail: controller.methodDescription(l),
                methodEnabled: !controller.providerConfiguration,
                onConnection: () => controller.connectionAction(context),
                onAddServers: () => controller.addServers(context),
                onExpert: (value) => controller.toggleExpert(context, value),
                onServer: () => controller.chooseServer(context),
                onMethod: () => controller.chooseTrafficMethod(context),
                onWhy: () => controller.showWhy(context),
                onRawAdd: () => controller.editRaw(context),
                onRawSelect: (row) => controller.selectRaw(context, row.id),
                onRawActions: (row) => controller.showRawActions(context, row),
              );
            },
          ),
        ),
      ),
    ),
  );
}
