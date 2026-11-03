import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/page.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/xray/page.dart';
import 'package:onexray/pages/main/navigation.dart';

/// Route wiring stays in the shell; platform pages only edit their own drafts.
class AdvancedRootPage extends TunnelRootPage {
  const AdvancedRootPage({super.key});
}

class TunnelRootPage extends StatelessWidget {
  const TunnelRootPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageAppBar(
      title: Text(AppLocalizations.of(context)!.prototypeVpnTunnel),
    ),
    body: VpnTunnelPane(
      openTunnel: (context, destination, draft) =>
          context.pushScoped<bool>(switch (destination) {
            TunnelDestination.apple => AppPageDestination.appleVpn,
            TunnelDestination.android => AppPageDestination.androidVpn,
            TunnelDestination.windows => AppPageDestination.windowsVpn,
            TunnelDestination.interface => AppPageDestination.outboundInterface,
          }, extra: draft),
    ),
  );
}

class XrayRootPage extends StatelessWidget {
  const XrayRootPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageAppBar(
      title: Text(
        AppLocalizations.of(context)!.prototypeXrayRuntimeDiagnostics,
      ),
    ),
    body: XrayRuntimePage(
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
