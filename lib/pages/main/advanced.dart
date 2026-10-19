import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/advanced/page.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/xray/page.dart';
import 'package:onexray/pages/main/navigation.dart';

/// Route wiring stays in the shell; platform pages only edit their own drafts.
class AdvancedRootPage extends StatelessWidget {
  const AdvancedRootPage({super.key});

  @override
  Widget build(BuildContext context) => AdvancedPage(
    openTunnel: (context, destination, draft) =>
        context.pushScoped<bool>(switch (destination) {
          TunnelDestination.apple => AppPageDestination.appleVpn,
          TunnelDestination.android => AppPageDestination.androidVpn,
          TunnelDestination.windows => AppPageDestination.windowsVpn,
          TunnelDestination.interface => AppPageDestination.outboundInterface,
        }, extra: draft),
    xrayBuilder: (context) => XrayRuntimePage(
      onGeodata: (context) =>
          context.pushScoped(AppPageDestination.routingData),
      onUpdates: (context) => context.pushScoped(AppPageDestination.autoUpdate),
      onSpeedTest: (context) => context.pushScoped(AppPageDestination.ping),
      onLocalApi: (context) => context.pushScoped(AppPageDestination.localApi),
      onLanProxy: (context) async {
        await context.pushScoped(AppPageDestination.lanProxy);
      },
      onServerDialing: (context) =>
          context.pushScoped(AppPageDestination.serverDialing),
      onLog: (context, params) =>
          context.pushScoped(AppPageDestination.logFile, extra: params),
      onConfig: (context, params) => context.pushScoped(
        AppPageDestination.configFileViewer,
        extra: params,
      ),
    ),
  );
}
