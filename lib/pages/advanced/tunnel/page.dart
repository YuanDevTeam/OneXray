import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/main/page_visibility.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/widgets/app_switch.dart';
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
      controller.loadProxyCapability();
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
        final ipv6 = controller.effectiveIpv6;
        final pending = draft.hasChanges;
        final pane = Scaffold(
          body: SettingsPageScroll(
            desktopMaxWidth: AppLayout.advancedMaxWidth,
            padding: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 20,
                children: [
                  if (!pending && state.error != null)
                    SelectableText(
                      state.error!,
                      style: AppTypography.supporting.copyWith(
                        color: palette.destructive,
                      ),
                    ),
                  if (controller.platform == ConnectionPlatform.ios)
                    _apnsPreset(context, controller, l),
                  SettingSection(
                    key: const ValueKey('tunnel-connection-parameters'),
                    title: l.tunnelConnectionParameters,
                    padding: EdgeInsets.zero,
                    children: [
                      if (controller.supportsProxy)
                        _proxySettings(context, controller, l),
                      if (!controller.proxyMode)
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
                      if (!controller.proxyMode &&
                          (controller.platform == ConnectionPlatform.ios ||
                              controller.platform == ConnectionPlatform.macos))
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
                      if (!controller.proxyMode &&
                          controller.supportsWindowsSystemVpn)
                        _entry(
                          context,
                          controller,
                          destination: TunnelDestination.windows,
                          title: l.prototypeWindowsSystemVpn,
                          icon: LucideIcons.monitor,
                        ),
                      if (!controller.proxyMode &&
                          controller.service.requiresInterface)
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
                        title: controller.activeProxy
                            ? l.desktopLocalProxy
                            : l.prototypeSystemVpn,
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
                      if (!controller.proxyMode)
                        PolicyValueRow(
                          title: l.prototypeIpv4TunAddress,
                          value: '${PlatformPolicy.tunIpv4Address}/15',
                        ),
                      if (!controller.proxyMode)
                        PolicyValueRow(
                          title: l.prototypeIpv6TunAddress,
                          value: ipv6
                              ? '${PlatformPolicy.tunIpv6Address}/64'
                              : l.tunnelIpv6Disabled,
                          valueTextDirection: ipv6 ? TextDirection.ltr : null,
                        ),
                      if (controller.supportsAppleVpnRemoval)
                        _removalContent(context, controller, l),
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
        if (controller.platform != ConnectionPlatform.ios) return pane;
        return PageVisibility(
          onChanged: (visible) =>
              controller.apnsPresetPageVisibilityChanged(context, visible),
          child: pane,
        );
      },
    ),
  );

  Widget _apnsPreset(
    BuildContext context,
    PolicyEditorController controller,
    AppLocalizations l,
  ) {
    final state = controller.state;
    final enabled = controller.apnsPresetEnabled;
    final checking = state.appleCapabilitiesLoading || state.apnsPresetChecking;
    final capabilities = state.appleCapabilities;
    final retry =
        !checking &&
        (capabilities == null ||
            capabilities.serviceExclusions &&
                state.apnsPresetApplicable == null);
    final status =
        enabled != controller.draft!.original.policy.appleApnsProxyPreset
        ? l.tunnelApnsPresetPendingSave
        : enabled && controller.apnsPresetApplied
        ? l.tunnelApnsPresetApplied
        : checking
        ? l.prototypePleaseWait
        : retry
        ? l.prototypeTemporarilyUnavailable
        : capabilities?.serviceExclusions != true
        ? l.tunnelApnsPresetRequiresIos
        : state.apnsPresetApplicable == false
        ? l.tunnelApnsPresetUnavailableForConfiguration
        : enabled
        ? l.lanProxyNextStartNotice
        : l.tunnelApnsPresetDescription;
    return SettingSection(
      key: const ValueKey('tunnel-presets'),
      title: l.tunnelPresets,
      padding: EdgeInsets.zero,
      children: [
        MergeSemantics(
          child: SettingRow(
            key: const ValueKey('tunnel-apns-preset'),
            title: l.tunnelApnsPreset,
            subtitleWidget: Text(
              status,
              style: AppTypography.supporting.copyWith(
                color: ColorManager.secondaryText(context),
              ),
            ),
            leading: const Icon(LucideIcons.bell),
            trailing: AppSwitch(
              value: enabled,
              onChanged:
                  controller.blocked ||
                      controller.runtimeBusy ||
                      (!enabled &&
                          (checking || !controller.canEnableApnsPreset))
                  ? null
                  : (value) => controller.toggleApnsProxyPreset(
                      context,
                      value,
                      saveImmediately: true,
                    ),
            ),
          ),
        ),
        if (controller.apnsPresetDisconnectsOnCellular)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 12),
            child: Text(
              l.tunnelApnsPresetCellularDisconnect,
              style: AppTypography.supporting.copyWith(
                color: ColorManager.secondaryText(context),
              ),
            ),
          ),
        if (retry)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: controller.blocked
                  ? null
                  : capabilities == null
                  ? controller.readAppleCapabilities
                  : controller.refreshApnsPresetApplicability,
              child: Text(l.prototypeRetry),
            ),
          ),
      ],
    );
  }

  Widget _proxySettings(
    BuildContext context,
    PolicyEditorController controller,
    AppLocalizations l,
  ) {
    final proxy = controller.proxyMode;
    final supported = controller.state.systemProxySupported;
    return Column(
      key: const ValueKey('desktop-proxy-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingRow(
          title: l.desktopCaptureMode,
          trailing: SettingSelect<CaptureMode>(
            value: CaptureMode.values.byName(
              controller.value['captureMode'] as String,
            ),
            entries: {
              CaptureMode.tun: l.desktopVpnTunnel,
              CaptureMode.proxy: l.desktopLocalProxy,
            },
            onChanged: controller.blocked
                ? null
                : (mode) {
                    if (mode != null) {
                      controller.update('captureMode', mode.name);
                    }
                  },
          ),
        ),
        if (proxy) ...[
          SettingRow(
            title: l.desktopProxyPort,
            trailing: SizedBox(
              width: 132,
              child: _ProxyPortField(
                key: const ValueKey('desktop-proxy-port'),
                value: controller.value['proxyPort'] as int,
                enabled: !controller.blocked,
                label: l.desktopProxyPort,
                onChanged: (value) => controller.update('proxyPort', value),
              ),
            ),
          ),
          if (supported == true ||
              controller.value['autoSetSystemProxy'] == true)
            PolicyToggle(
              controller: controller,
              field: 'autoSetSystemProxy',
              title: l.desktopAutoSystemProxy,
              // A saved unsupported preference may always be turned off.
              supported:
                  supported == true ||
                  controller.value['autoSetSystemProxy'] == true,
            ),
          if (controller.state.systemProxyLoading)
            SettingRow(
              title: l.prototypePleaseWait,
              trailing: const ButtonProgressIndicator(),
            )
          else if (supported == false)
            PolicyValueRow(
              title: l.desktopAutoSystemProxy,
              value: l.desktopSystemProxyUnavailable,
              valueTextDirection: null,
            ),
          PolicyValueRow(
            title: l.desktopProxyHttp,
            value: 'http://127.0.0.1:${controller.value['proxyPort']}',
          ),
          PolicyValueRow(
            title: l.desktopProxySocks,
            value: 'socks5://127.0.0.1:${controller.value['proxyPort']}',
          ),
          if (controller.value['autoSetSystemProxy'] != true)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l.desktopProxyManualHint,
                style: AppTypography.supporting.copyWith(
                  color: ColorManager.secondaryText(context),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _removalContent(
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
    return Column(
      key: const ValueKey('tunnel-apple-vpn-removal'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
    trailing: controller.state.loadingDestination == destination
        ? const ButtonProgressIndicator()
        : null,
    enabled: !controller.blocked && openTunnel != null,
    onTap: () {
      final open = openTunnel;
      if (open != null) controller.openPlatform(context, destination, open);
    },
  );

  String _status(PolicyEditorController controller, AppLocalizations l) =>
      switch (controller.state.connection.phase) {
        ConnectionPhase.disconnected =>
          controller.activeProxy
              ? l.desktopProxyStopped
              : l.prototypeDisconnected,
        ConnectionPhase.preparing ||
        ConnectionPhase.connecting => l.prototypeConnecting,
        ConnectionPhase.connected =>
          controller.activeProxy ? l.desktopProxyRunning : l.prototypeConnected,
        ConnectionPhase.disconnecting => l.prototypeDisconnecting,
        ConnectionPhase.failed => l.prototypeConnectionFailed,
      };
}

class _ProxyPortField extends StatefulWidget {
  const _ProxyPortField({
    super.key,
    required this.value,
    required this.enabled,
    required this.label,
    required this.onChanged,
  });
  final int value;
  final bool enabled;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  State<_ProxyPortField> createState() => _ProxyPortFieldState();
}

class _ProxyPortFieldState extends State<_ProxyPortField> {
  late final TextEditingController controller = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void didUpdateWidget(covariant _ProxyPortField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        (int.tryParse(controller.text) ?? 0) != widget.value) {
      controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: widget.enabled,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(5),
    ],
    textAlign: TextAlign.end,
    decoration: InputDecoration(labelText: widget.label),
    onChanged: (value) => widget.onChanged(int.tryParse(value) ?? 0),
  );
}
