import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/excluded_networks.dart';
import 'package:onexray/pages/advanced/tunnel/apple/widgets.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/settings.dart';

class AppleVpnPage extends StatelessWidget {
  final PolicyEditorDraft draft;
  final OpenPolicyChild openWifi;
  const AppleVpnPage({super.key, required this.draft, required this.openWifi});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        PolicyEditorController(draft: draft)
          ..readAppleCapabilities(reportError: true),
    child: BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final controller = context.read<PolicyEditorController>();
        return PolicyDetailScaffold(
          title: l.prototypeAppleSystemVpn,
          help: [
            l.prototypeAllowLocalNetworkHint,
            l.prototypeBypassCellularServicesHint,
            l.prototypeBypassApplePushHint,
            l.prototypeAllowDeviceCommunicationHint,
            l.prototypeAlwaysOnHint,
            l.prototypeConnectOnDemandHint,
            l.appleExcludedNetworksHint,
          ],
          controller: controller,
          canSave: state.appleCapabilities != null,
          contentPadding: EdgeInsets.zero,
          body: AppleVpnView(
            controller: controller,
            capabilities: state.appleCapabilities,
            capabilityLoading: state.appleCapabilitiesLoading,
            onRetry: () => controller.readAppleCapabilities(reportError: true),
            onEditWifi: () => controller.openChild(context, openWifi),
          ),
        );
      },
    ),
  );
}

/// Presentation can be exercised without invoking Apple system APIs.
class AppleVpnView extends StatelessWidget {
  final PolicyEditorController controller;
  final AppleVpnCapabilities? capabilities;
  final bool capabilityLoading;
  final VoidCallback? onRetry;
  final VoidCallback? onEditWifi;

  const AppleVpnView({
    super.key,
    required this.controller,
    required this.capabilities,
    this.capabilityLoading = false,
    this.onRetry,
    this.onEditWifi,
  });

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
    bloc: controller,
    builder: (context, state) {
      final l = AppLocalizations.of(context)!;
      final apple = controller.group('apple');
      final managed = controller.apnsPresetManagesSettings;
      final captureAll = managed || apple['captureAllTraffic'] == true;
      final checking =
          controller.apnsPresetEnabled &&
          (capabilityLoading || state.apnsPresetChecking);
      final palette = ColorManager.palette(context);
      final width = MediaQuery.sizeOf(context).width;
      final mobile = width <= AppLayout.mobileBreakpoint;
      final gutter = mobile
          ? AppSpacing.mobilePage
          : AppSpacing.advancedDesktopGutter(width);
      Widget toggle(
        String field,
        String title,
        String? description, {
        bool nested = false,
        bool supported = true,
        bool showDescription = false,
        bool? effectiveValue,
      }) => AppleSettingToggle(
        key: ValueKey(field),
        title: title,
        description: effectiveValue != null
            ? l.tunnelApnsPresetManaged
            : showDescription || !supported
            ? description
            : null,
        nested: nested,
        value: effectiveValue ?? apple[field] as bool,
        onChanged: controller.blocked || !supported || effectiveValue != null
            ? null
            : (value) => controller.update(field, value, section: 'apple'),
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter, 20, gutter, mobile ? 18 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (capabilities == null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: capabilityLoading
                    ? const CircularProgressIndicator()
                    : Column(
                        children: [
                          Text(l.prototypeTemporarilyUnavailable),
                          TextButton(
                            onPressed: onRetry,
                            child: Text(l.prototypeRetry),
                          ),
                        ],
                      ),
              ),
            SettingSection(
              title: l.prototypeSystemVpnPolicy,
              padding: EdgeInsets.zero,
              dividerIndent: 0,
              children: [
                toggle(
                  'captureAllTraffic',
                  l.prototypeCaptureAllTraffic,
                  l.prototypeCaptureAllTrafficHint,
                  supported: !checking,
                  effectiveValue: managed ? true : null,
                  showDescription: true,
                ),
                if (captureAll) ...[
                  toggle(
                    'allowLocalNetwork',
                    l.prototypeAllowLocalNetwork,
                    l.prototypeAllowLocalNetworkHint,
                    nested: true,
                  ),
                  toggle(
                    'bypassCellularServices',
                    l.prototypeBypassCellularServices,
                    capabilities?.serviceExclusions == true
                        ? l.prototypeBypassCellularServicesHint
                        : l.tunSettingsPageExcludeCellularServicesTip,
                    nested: true,
                    supported: capabilities?.serviceExclusions ?? false,
                  ),
                  toggle(
                    'bypassApplePushNotifications',
                    l.prototypeBypassApplePush,
                    capabilities?.serviceExclusions == true
                        ? l.prototypeBypassApplePushHint
                        : l.tunSettingsPageExcludeAPNsTip,
                    nested: true,
                    supported:
                        capabilities?.serviceExclusions == true && !checking,
                    effectiveValue: managed ? false : null,
                  ),
                  toggle(
                    'allowDeviceCommunication',
                    l.prototypeAllowDeviceCommunication,
                    capabilities?.deviceCommunication == true
                        ? l.prototypeAllowDeviceCommunicationHint
                        : l.tunSettingsPageExcludeDeviceCommunicationTip,
                    nested: true,
                    supported: capabilities?.deviceCommunication ?? false,
                  ),
                ],
                if (controller.platform == ConnectionPlatform.ios)
                  toggle(
                    'hideVpnIcon',
                    l.appleHideVpnIcon,
                    captureAll
                        ? !managed || apple['hideVpnIcon'] == true
                              ? l.appleHideVpnIconInactive
                              : null
                        : l.appleHideVpnIconHint,
                    supported: !captureAll,
                    showDescription: true,
                  ),
                if (managed) TurnOffApnsPresetButton(controller: controller),
              ],
            ),
            if (!managed ||
                controller.strings('apple', 'excludedCidrs').isNotEmpty) ...[
              const SizedBox(height: 20),
              SettingSection(
                title: l.prototypeBypassNetworks,
                description: captureAll
                    ? l.appleExcludedNetworksInactive
                    : null,
                padding: EdgeInsets.zero,
                children: [
                  if (!captureAll) ...[
                    ExcludedNetworks(
                      rowKeyPrefix: 'apple-cidr-row',
                      values: controller.strings('apple', 'excludedCidrs'),
                      enabled: !controller.blocked,
                      onChanged: (values) => controller.update(
                        'excludedCidrs',
                        values,
                        section: 'apple',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.appleExcludedNetworksInputHint,
                      style: AppTypography.windowsNetworkNote.copyWith(
                        color: palette.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 20),
            SettingSection(
              title: l.prototypeAutomaticConnectionDisconnection,
              padding: EdgeInsets.zero,
              dividerIndent: 0,
              children: [
                toggle(
                  'alwaysOn',
                  l.prototypeAlwaysOn,
                  l.prototypeAlwaysOnHint,
                ),
                if (apple['alwaysOn'] == false) ...[
                  toggle(
                    'onDemandEnabled',
                    l.prototypeConnectOnDemand,
                    l.prototypeConnectOnDemandHint,
                  ),
                  if (apple['onDemandEnabled'] == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AppleWifiPreview(
                        controller: controller,
                        showNetwork: true,
                        onEdit: controller.blocked ? null : onEditWifi,
                        editable: true,
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      );
    },
  );
}
