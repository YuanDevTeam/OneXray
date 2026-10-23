import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/widgets/dns_text_field.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/settings.dart';

/// Embedded below Advanced's tabs; the footer belongs to this full-page body.
class VpnTunnelPane extends StatelessWidget {
  final OpenTunnelPage? openTunnel;
  final PolicyEditorController Function()? createController;

  const VpnTunnelPane({super.key, this.openTunnel, this.createController});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final controller = createController?.call() ?? PolicyEditorController();
      if (controller.draft == null) controller.load(context);
      return controller;
    },
    child: BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
      builder: (context, state) {
        final controller = context.read<PolicyEditorController>();
        final l = AppLocalizations.of(context)!;
        final palette = ColorManager.palette(context);
        final width = MediaQuery.sizeOf(context).width;
        final mobile = width <= AppLayout.mobileBreakpoint;
        final gutter = mobile ? 15.0 : AppSpacing.advancedDesktopGutter(width);
        if (controller.draft == null) {
          return Center(
            child: controller.busy
                ? const CircularProgressIndicator()
                : TextButton(
                    onPressed: () => controller.load(context),
                    child: Text(l.prototypeRetry),
                  ),
          );
        }
        return Scaffold(
          body: SettingsPageScroll(
            desktopMaxWidth: AppLayout.advancedMaxWidth,
            padding: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                mobile ? 22 : 54,
                gutter,
                mobile ? 24 : 28,
              ),
              child: Column(
                spacing: mobile ? 25 : 28,
                children: [
                  _section(
                    icon: LucideIcons.activity,
                    title: l.prototypeConnectionStatus,
                    children: [
                      SettingRow(
                        title: l.prototypeSystemVpn,
                        leading: Icon(
                          LucideIcons.shield,
                          color: palette.mutedStrong,
                        ),
                        decorateLeading: false,
                        minHeight: mobile ? 52 : 56,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: mobile ? 13 : 14,
                          vertical: 10,
                        ),
                        titleStyle:
                            (mobile
                                    ? AppTypography.settingsStatus
                                    : AppTypography.desktopSettingsStatus)
                                .copyWith(color: palette.foreground),
                        valueStyle:
                            (mobile
                                    ? AppTypography.settingsStatus
                                    : AppTypography.desktopSettingsStatus)
                                .copyWith(
                                  color: switch (state.connection.phase) {
                                    ConnectionPhase.connected =>
                                      palette.runningText,
                                    ConnectionPhase.preparing ||
                                    ConnectionPhase.connecting ||
                                    ConnectionPhase.disconnecting =>
                                      palette.restartingText,
                                    ConnectionPhase.failed =>
                                      palette.destructive,
                                    ConnectionPhase.disconnected =>
                                      palette.mutedStrong,
                                  },
                                ),
                        value: _status(controller, l),
                      ),
                    ],
                  ),
                  _section(
                    icon: LucideIcons.network,
                    title: l.prototypeTunAddress,
                    children: [
                      PolicyValueRow(
                        title: l.prototypeIpv4TunAddress,
                        value: '${PlatformPolicy.tunIpv4Address}/15',
                      ),
                      PolicyValueRow(
                        title: l.prototypeIpv6TunAddress,
                        value: '${PlatformPolicy.tunIpv6Address}/64',
                      ),
                    ],
                  ),
                  _section(
                    icon: LucideIcons.globe2,
                    title: l.prototypeTunnelDns,
                    action: PageHelpButton(
                      title: l.prototypeTunnelDns,
                      messages: [l.tunnelDnsServerNameHint],
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          spacing: 18,
                          children: [
                            DnsTextField(
                              label: l.prototypeIpv4Dns,
                              value:
                                  controller.value['dnsIpv4Address'] as String,
                              enabled: !controller.blocked,
                              onChanged: (value) =>
                                  controller.update('dnsIpv4Address', value),
                            ),
                            DnsTextField(
                              label: l.prototypeIpv6Dns,
                              value:
                                  controller.value['dnsIpv6Address'] as String,
                              enabled: !controller.blocked,
                              onChanged: (value) =>
                                  controller.update('dnsIpv6Address', value),
                            ),
                            DnsTextField(
                              label: l.prototypeDomain,
                              value:
                                  controller.value['dnsServerName'] as String,
                              enabled: !controller.blocked,
                              onChanged: (value) =>
                                  controller.update('dnsServerName', value),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _section(
                    icon: LucideIcons.network,
                    title: 'IPv6',
                    description: controller.ipv6Conflict
                        ? l.prototypeIpv6BypassConflict
                        : null,
                    children: [
                      PolicyToggle(
                        controller: controller,
                        field: 'ipv6Enabled',
                        title: l.prototypeUseIpv6,
                      ),
                    ],
                  ),
                  if (controller.service.requiresInterface)
                    _section(
                      icon: LucideIcons.network,
                      title: l.prototypeXrayOutboundInterface,
                      action: PageHelpButton(
                        title: l.prototypeXrayOutboundInterface,
                        messages: [l.prototypeManagedInterfaceNotice],
                      ),
                      children: [
                        SettingRow(
                          title: l.prototypeXrayOutboundInterface,
                          value:
                              (controller.value['xrayOutboundInterfaceName']
                                      as String)
                                  .isEmpty
                              ? l.prototypeChooseInterface
                              : controller.value['xrayOutboundInterfaceName']
                                    as String,
                          showChevron: true,
                          minHeight: mobile ? 52 : 56,
                          titleStyle: mobile
                              ? AppTypography.settingsValueLabel
                              : AppTypography.desktopSettingsValueLabel,
                          valueStyle:
                              (mobile
                                      ? AppTypography.settingsValue
                                      : AppTypography.desktopSettingsValue)
                                  .copyWith(
                                    color: ColorManager.primaryText(context),
                                  ),
                          enabled: !controller.blocked && openTunnel != null,
                          onTap: () => _open(
                            context,
                            controller,
                            TunnelDestination.interface,
                          ),
                        ),
                      ],
                    ),
                  if (controller.platform == ConnectionPlatform.ios ||
                      controller.platform == ConnectionPlatform.macos)
                    _platformEntry(
                      context,
                      controller,
                      l.prototypeAppleSystemVpn,
                      l.prototypeAppleVpnDescription,
                      TunnelDestination.apple,
                    ),
                  if (controller.platform == ConnectionPlatform.android)
                    _platformEntry(
                      context,
                      controller,
                      l.prototypeAndroidSystemVpn,
                      l.prototypeAndroidVpnDescription,
                      TunnelDestination.android,
                    ),
                  if (controller.supportsWindowsSystemVpn)
                    _platformEntry(
                      context,
                      controller,
                      l.prototypeWindowsSystemVpn,
                      l.prototypeWindowsVpnDescription,
                      TunnelDestination.windows,
                    ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: PolicyActions(
            root: true,
            controller: controller,
            cancel: () {
              controller.restoreDefaults();
              ContextAlert.showToast(context, l.settingsDefaultsRestored);
            },
            cancelLabel: l.prototypeRestoreDefaults,
            cancelIcon: LucideIcons.rotateCcw,
            save: () => controller.save(context, pop: false),
          ),
        );
      },
    ),
  );

  Widget _platformEntry(
    BuildContext context,
    PolicyEditorController controller,
    String title,
    String description,
    TunnelDestination destination,
  ) => _section(
    icon: switch (destination) {
      TunnelDestination.apple => LucideIcons.apple,
      TunnelDestination.android => LucideIcons.appWindow,
      _ => LucideIcons.monitor,
    },
    title: title,
    children: [
      SettingRow(
        title: description,
        titleStyle: AppTypography.settingsRow,
        minHeight:
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint
            ? 52
            : 56,
        contentPadding: EdgeInsets.symmetric(
          horizontal:
              MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint
              ? 13
              : 14,
          vertical: 10,
        ),
        showChevron: true,
        enabled: !controller.blocked && openTunnel != null,
        onTap: () => _open(context, controller, destination),
      ),
    ],
  );

  Widget _section({
    required String title,
    required IconData icon,
    String? description,
    Widget? action,
    required List<Widget> children,
  }) => SettingSection(
    title: title,
    icon: icon,
    description: description,
    action: action,
    descriptionBelow: true,
    padding: EdgeInsets.zero,
    dividerIndent: 0,
    children: children,
  );

  void _open(
    BuildContext context,
    PolicyEditorController controller,
    TunnelDestination destination,
  ) {
    final open = openTunnel;
    if (open != null) {
      controller.openPlatform(context, destination, open);
    }
  }

  String _status(PolicyEditorController controller, AppLocalizations l) =>
      switch (controller.state.connection.phase) {
        ConnectionPhase.disconnected => l.prototypeDisconnected,
        ConnectionPhase.preparing ||
        ConnectionPhase.connecting => l.prototypeConnecting,
        ConnectionPhase.connected => l.prototypeConnected,
        ConnectionPhase.disconnecting => l.prototypeDisconnecting,
        ConnectionPhase.failed => l.prototypeConnectionFailed,
      };
}
