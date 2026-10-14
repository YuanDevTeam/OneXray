import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/pigeon/host_api.dart';
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
import 'package:onexray/service/shared/failure.dart';

class AppleVpnController extends PolicyEditorController {
  AppleVpnController({required PolicyEditorDraft draft}) : super(draft: draft);

  AppleVpnCapabilities? get capabilities => state.appleCapabilities;
  bool get capabilityLoading => state.appleCapabilitiesLoading;

  Future<void> readCapabilities() async {
    emit(state.copyWith(appleCapabilitiesLoading: true, error: null));
    try {
      final value = await AppHostApi().appleVpnCapabilities();
      emit(state.copyWith(appleCapabilities: value));
    } catch (error) {
      // Do not infer a product version from Darwin's kernel version.
      emit(
        state.copyWith(appleCapabilities: null, error: failureDetails(error)),
      );
    } finally {
      emit(state.copyWith(appleCapabilitiesLoading: false));
    }
  }
}

class AppleVpnPage extends StatelessWidget {
  final PolicyEditorDraft draft;
  final OpenPolicyChild openWifi;
  const AppleVpnPage({super.key, required this.draft, required this.openWifi});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => AppleVpnController(draft: draft)..readCapabilities(),
    child: BlocBuilder<AppleVpnController, PolicyEditorPageState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final controller = context.read<AppleVpnController>();
        return PolicyDetailScaffold(
          title: l.prototypeAppleSystemVpn,
          help: [
            l.prototypeAllowLocalNetworkHint,
            l.prototypeBypassCellularServicesHint,
            l.prototypeBypassApplePushHint,
            l.prototypeAllowDeviceCommunicationHint,
            l.prototypeUseDnsOverTlsHint,
            l.prototypeAlwaysOnHint,
            l.prototypeConnectOnDemandHint,
          ],
          controller: controller,
          canSave: state.appleCapabilities != null,
          contentPadding: EdgeInsets.zero,
          body: AppleVpnView(
            controller: controller,
            capabilities: state.appleCapabilities,
            capabilityLoading: state.appleCapabilitiesLoading,
            onRetry: controller.readCapabilities,
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
  Widget build(BuildContext context) =>
      BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
        bloc: controller,
        builder: (context, state) {
          final l = AppLocalizations.of(context)!;
          final apple = controller.group('apple');
          final palette = ColorManager.palette(context);
          final width = MediaQuery.sizeOf(context).width;
          final mobile = width <= AppLayout.mobileBreakpoint;
          final gutter = mobile
              ? 14.0
              : AppSpacing.advancedDesktopGutter(width);
          Widget toggle(
            String field,
            String title,
            String description, {
            bool nested = false,
            bool supported = true,
            bool showDescription = false,
          }) => AppleSettingToggle(
            key: ValueKey(field),
            title: title,
            description: showDescription || !supported ? description : null,
            nested: nested,
            value: apple[field] as bool,
            onChanged: controller.blocked || !supported
                ? null
                : (value) => controller.update(field, value, section: 'apple'),
          );
          return Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              mobile ? 14 : 48,
              gutter,
              mobile ? 18 : 24,
            ),
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
                  title: '',
                  padding: EdgeInsets.zero,
                  dividerIndent: 0,
                  children: [
                    toggle(
                      'captureAllTraffic',
                      l.prototypeCaptureAllTraffic,
                      l.prototypeCaptureAllTrafficHint,
                      showDescription: true,
                    ),
                    if (apple['captureAllTraffic'] == true) ...[
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
                        supported: capabilities?.serviceExclusions ?? false,
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
                        apple['captureAllTraffic'] == true
                            ? l.appleHideVpnIconInactive
                            : l.appleHideVpnIconHint,
                        supported: apple['captureAllTraffic'] == false,
                        showDescription: true,
                      ),
                    toggle(
                      'dnsOverTls',
                      l.prototypeUseDnsOverTls,
                      l.prototypeUseDnsOverTlsHint,
                    ),
                  ],
                ),
                SizedBox(height: mobile ? 16 : 20),
                Text(
                  l.prototypeBypassNetworks,
                  style: mobile
                      ? AppTypography.appleAutoTitle
                      : AppTypography.appleAutoTitleDesktop,
                ),
                const SizedBox(height: 8),
                Text(
                  apple['captureAllTraffic'] == true
                      ? l.appleExcludedNetworksInactive
                      : l.appleExcludedNetworksHint,
                  style: AppTypography.platformDetailBody.copyWith(
                    color: palette.mutedForeground,
                  ),
                ),
                if (apple['captureAllTraffic'] == false) ...[
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 14),
                  Text(
                    l.appleExcludedNetworksInputHint,
                    style: AppTypography.windowsNetworkNote.copyWith(
                      color: palette.mutedForeground,
                    ),
                  ),
                ],
                SizedBox(height: mobile ? 16 : 20),
                Text(
                  l.prototypeAutomaticConnectionDisconnection,
                  style: mobile
                      ? AppTypography.appleAutoTitle
                      : AppTypography.appleAutoTitleDesktop,
                ),
                SizedBox(height: mobile ? 8 : 10),
                SettingSection(
                  title: '',
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
                          padding: mobile
                              ? const EdgeInsets.all(10)
                              : const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
