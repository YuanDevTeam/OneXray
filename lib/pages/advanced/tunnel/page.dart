import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/settings.dart';

/// The root summarizes settings; each destination owns its editing draft.
class VpnTunnelPane extends StatelessWidget {
  final OpenTunnelPage? openTunnel;
  final PolicyEditorController Function()? createController;
  const VpnTunnelPane({super.key, this.openTunnel, this.createController});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final controller = createController?.call() ?? PolicyEditorController();
      if (controller.draft == null) controller.load(context);
      controller.loadAppleVpnRemoval(context);
      return controller;
    },
    child: BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
      builder: (context, state) {
        final controller = context.read<PolicyEditorController>();
        final l = AppLocalizations.of(context)!;
        final palette = ColorManager.palette(context);
        final width = MediaQuery.sizeOf(context).width;
        final mobile = width <= AppLayout.mobileBreakpoint;
        final gutter = mobile
            ? AppSpacing.mobilePage
            : AppSpacing.advancedDesktopGutter(width);
        final draft = controller.draft;
        if (draft == null) {
          return Center(
            child: controller.busy
                ? const CircularProgressIndicator()
                : TextButton(
                    onPressed: () => controller.load(context),
                    child: Text(l.prototypeRetry),
                  ),
          );
        }
        final ipv6 = controller.value['ipv6Enabled'] == true;
        final pending = !const DeepCollectionEquality().equals(
          draft.original.policy.toJson(),
          draft.policy,
        );
        return Scaffold(
          body: SettingsPageScroll(
            desktopMaxWidth: AppLayout.advancedMaxWidth,
            padding: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 20,
                children: [
                  SettingSection(
                    key: const ValueKey('tunnel-system-capture'),
                    icon: LucideIcons.shield,
                    title: l.tunnelSystemCapture,
                    padding: EdgeInsets.zero,
                    children: [
                      PolicyValueRow(
                        title: l.tunnelCurrentPlatform,
                        value: switch (controller.platform) {
                          ConnectionPlatform.ios => 'iOS',
                          ConnectionPlatform.macos => 'macOS',
                          ConnectionPlatform.android => 'Android',
                          ConnectionPlatform.windows => 'Windows',
                          ConnectionPlatform.linux => 'Linux',
                        },
                      ),
                      PolicyValueRow(
                        title: l.prototypeSystemVpn,
                        leading: Icon(
                          LucideIcons.shield,
                          color: palette.mutedStrong,
                        ),
                        minHeight: mobile ? 56 : 48,
                        titleStyle: AppTypography.rowTitle.copyWith(
                          color: palette.foreground,
                        ),
                        valueStyle: AppTypography.badge.copyWith(
                          color: switch (state.connection.phase) {
                            ConnectionPhase.connected => palette.runningText,
                            ConnectionPhase.preparing ||
                            ConnectionPhase.connecting ||
                            ConnectionPhase.disconnecting =>
                              palette.restartingText,
                            ConnectionPhase.failed => palette.destructive,
                            ConnectionPhase.disconnected => palette.mutedStrong,
                          },
                        ),
                        value: _status(controller, l),
                        valueTextDirection: null,
                      ),
                      PolicyValueRow(
                        title: l.prototypeIpv4TunAddress,
                        value: '${PlatformPolicy.tunIpv4Address}/15',
                      ),
                      PolicyValueRow(
                        title: l.prototypeIpv6TunAddress,
                        value: ipv6
                            ? '${PlatformPolicy.tunIpv6Address}/64'
                            : l.tunnelIpv6Disabled,
                        valueTextDirection: ipv6 ? TextDirection.ltr : null,
                      ),
                    ],
                  ),
                  SettingSection(
                    key: const ValueKey('tunnel-connection-parameters'),
                    title: l.tunnelConnectionParameters,
                    padding: EdgeInsets.zero,
                    children: [
                      _entry(
                        context,
                        controller,
                        destination: TunnelDestination.dns,
                        title: l.prototypeTunnelDns,
                        subtitle: [
                          controller.value['dnsIpv4Address'],
                          if (ipv6) controller.value['dnsIpv6Address'],
                        ].join(' · '),
                        icon: LucideIcons.network,
                      ),
                      _entry(
                        context,
                        controller,
                        destination: TunnelDestination.network,
                        title: 'IPv6',
                        subtitle: ipv6
                            ? l.tunnelIpv6Enabled
                            : l.tunnelIpv6Disabled,
                        icon: LucideIcons.globe2,
                      ),
                      if (controller.platform == ConnectionPlatform.ios ||
                          controller.platform == ConnectionPlatform.macos)
                        _entry(
                          context,
                          controller,
                          destination: TunnelDestination.apple,
                          title: l.prototypeAppleSystemVpn,
                          icon: LucideIcons.apple,
                        ),
                      if (controller.platform == ConnectionPlatform.android)
                        _entry(
                          context,
                          controller,
                          destination: TunnelDestination.android,
                          title: l.prototypeAndroidSystemVpn,
                          icon: LucideIcons.appWindow,
                        ),
                      if (controller.supportsWindowsSystemVpn)
                        _entry(
                          context,
                          controller,
                          destination: TunnelDestination.windows,
                          title: l.prototypeWindowsSystemVpn,
                          icon: LucideIcons.monitor,
                        ),
                      if (controller.service.requiresInterface)
                        _entry(
                          context,
                          controller,
                          destination: TunnelDestination.interface,
                          title: l.prototypeXrayOutboundInterface,
                          subtitle:
                              (controller.value['xrayOutboundInterfaceName']
                                      as String)
                                  .isEmpty
                              ? l.prototypeChooseInterface
                              : controller.value['xrayOutboundInterfaceName']
                                    as String,
                          icon: LucideIcons.network,
                        ),
                    ],
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const ValueKey('tunnel-restore-defaults'),
                      onPressed: controller.blocked
                          ? null
                          : () {
                              controller.restoreDefaults();
                              ContextAlert.showToast(
                                context,
                                l.settingsDefaultsRestored,
                              );
                            },
                      child: Text(l.prototypeRestoreDefaults),
                    ),
                  ),
                  if (controller.supportsAppleVpnRemoval)
                    _removalSection(context, controller, l),
                ],
              ),
            ),
          ),
          bottomNavigationBar: pending
              ? PolicyActions(
                  root: true,
                  controller: controller,
                  cancel: () => controller.load(context),
                  cancelLabel: l.prototypeCancel,
                  save: () => controller.save(context, pop: false),
                )
              : null,
        );
      },
    ),
  );

  Widget _removalSection(
    BuildContext context,
    PolicyEditorController controller,
    AppLocalizations l,
  ) {
    final state = controller.state;
    final palette = ColorManager.palette(context);
    final systemExtension = state.appleSystemExtension;
    final enabled =
        !controller.blocked &&
        !controller.runtimeBusy &&
        !state.appleVpnRemovalRestartRequired;
    return SettingSection(
      key: const ValueKey('tunnel-apple-vpn-removal'),
      title: l.tunnelSystemManagement,
      children: [
        if (systemExtension == null)
          SettingRow(
            key: const ValueKey('tunnel-apple-vpn-removal-edition'),
            title: state.appleVpnRemovalLoading
                ? l.tunnelVpnRemovalChecking
                : l.prototypeRetry,
            leading: const Icon(LucideIcons.refreshCw),
            enabled: !state.appleVpnRemovalLoading && !controller.blocked,
            onTap: state.appleVpnRemovalLoading || controller.blocked
                ? null
                : () => controller.loadAppleVpnRemoval(context),
            trailing: state.appleVpnRemovalLoading
                ? const ButtonProgressIndicator()
                : null,
          )
        else
          SettingRow(
            key: const ValueKey('tunnel-remove-apple-vpn'),
            title: systemExtension
                ? l.tunnelUninstallSystemExtension
                : l.tunnelDeleteVpnConfiguration,
            titleMaxLines: 4,
            leading: Icon(
              systemExtension ? LucideIcons.packageMinus : LucideIcons.trash2,
              color: palette.destructive,
            ),
            titleStyle: AppTypography.rowTitle.copyWith(
              color: palette.destructive,
            ),
            enabled: enabled,
            onTap: enabled ? () => controller.removeAppleVpn(context) : null,
            trailing: state.appleVpnRemovalBusy
                ? const ButtonProgressIndicator()
                : null,
          ),
        if (state.appleVpnRemovalRestartRequired)
          _removalNotice(
            text: l.tunnelSystemExtensionRestartRequired,
            color: palette.restartingText,
            icon: LucideIcons.rotateCw,
            key: const ValueKey('tunnel-apple-vpn-restart-required'),
          ),
        if (state.appleVpnRemovalError != null)
          _removalNotice(
            text: state.appleVpnRemovalError!,
            color: palette.destructive,
            icon: LucideIcons.circleAlert,
            key: const ValueKey('tunnel-apple-vpn-removal-error'),
          ),
      ],
    );
  }

  Widget _removalNotice({
    required Key key,
    required String text,
    required Color color,
    required IconData icon,
  }) => Semantics(
    key: key,
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              text,
              style: AppTypography.supporting.copyWith(color: color),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _entry(
    BuildContext context,
    PolicyEditorController controller, {
    required TunnelDestination destination,
    required String title,
    String? subtitle,
    required IconData icon,
  }) => SettingRow(
    key: ValueKey('tunnel-open-${destination.name}'),
    title: title,
    subtitle: subtitle,
    leading: Icon(icon),
    showChevron: true,
    enabled: !controller.blocked && openTunnel != null,
    onTap: () {
      final open = openTunnel;
      if (open != null) controller.openPlatform(context, destination, open);
    },
  );

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
