import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/advanced/xray/dialing/controller.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/connect/dialing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ServerDialingPage extends StatelessWidget {
  const ServerDialingPage({super.key, this.createController});

  final ServerDialingController Function()? createController;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final controller = createController?.call() ?? ServerDialingController();
      if (controller.draft == null) controller.load(context);
      return controller;
    },
    child: BlocBuilder<ServerDialingController, PolicyEditorPageState>(
      builder: (context, state) {
        final controller = context.read<ServerDialingController>();
        final l = AppLocalizations.of(context)!;
        final width = MediaQuery.sizeOf(context).width;
        final mobile = width <= AppLayout.mobileBreakpoint;
        final gutter = mobile ? 14.0 : AppSpacing.advancedDesktopGutter(width);
        return PolicyDetailScaffold(
          title: l.serverDialingTitle,
          controller: controller,
          canSave: state.draft != null,
          help: [
            l.serverDialingScopeHelp,
            l.serverDialingFallbackHelp,
            l.serverDialingDnsHelp,
            l.serverDialingHappyEyeballsHelp,
            l.serverDialingIpv6Help,
          ],
          contentPadding: EdgeInsets.zero,
          body: state.draft == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: state.busy
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: TextButton(
                            onPressed: () => controller.load(context),
                            child: Text(l.prototypeRetry),
                          ),
                        ),
                )
              : Padding(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    mobile ? 14 : 48,
                    gutter,
                    24,
                  ),
                  child: Column(
                    children: [
                      SettingRow(
                        title: l.serverDialingDomainStrategy,
                        trailing: SizedBox(
                          width: mobile ? 165 : 210,
                          child: SettingSelect<ServerDomainStrategy>(
                            key: const ValueKey('server-dialing-strategy'),
                            value: controller.dialing.domainStrategy,
                            entries: {
                              ServerDomainStrategy.system:
                                  l.serverDialingSystem,
                              ServerDomainStrategy.useIp: l.serverDialingUseIp,
                              ServerDomainStrategy.ipv4: 'IPv4',
                              ServerDomainStrategy.ipv6: 'IPv6',
                              ServerDomainStrategy.ipv4First:
                                  l.serverDialingIpv4First,
                              ServerDomainStrategy.ipv6First:
                                  l.serverDialingIpv6First,
                            },
                            onChanged: controller.blocked
                                ? null
                                : controller.setDomainStrategy,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      SettingRow(
                        title: 'Happy Eyeballs',
                        titleMaxLines: 3,
                        subtitle: controller.happyEyeballsAvailable
                            ? null
                            : l.serverDialingHappyEyeballsUnavailable,
                        enabled:
                            !controller.blocked &&
                            controller.happyEyeballsAvailable,
                        trailing: ShadSwitch(
                          key: const ValueKey('server-dialing-happy-eyeballs'),
                          value: controller.dialing.happyEyeballs,
                          enabled:
                              !controller.blocked &&
                              controller.happyEyeballsAvailable,
                          onChanged: controller.setHappyEyeballs,
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    ),
  );
}
