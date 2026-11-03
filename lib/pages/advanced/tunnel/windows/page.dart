import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/excluded_networks.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/advanced/policy_editor.dart';

class WindowsVpnPage extends StatelessWidget {
  final PolicyEditorDraft draft;
  final OpenPolicyChild openInterface;
  const WindowsVpnPage({
    super.key,
    required this.draft,
    required this.openInterface,
  });
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PolicyEditorController(draft: draft),
    child: Builder(
      builder: (context) => WindowsVpnView(
        controller: context.read<PolicyEditorController>(),
        openInterface: openInterface,
      ),
    ),
  );
}

class WindowsVpnView extends StatelessWidget {
  const WindowsVpnView({
    super.key,
    required this.controller,
    required this.openInterface,
  });

  final PolicyEditorController controller;
  final OpenPolicyChild openInterface;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
    bloc: controller,
    builder: (context, state) {
      final l = AppLocalizations.of(context)!;
      final palette = ColorManager.palette(context);
      final width = MediaQuery.sizeOf(context).width;
      final mobile = width <= AppLayout.mobileBreakpoint;
      final gutter = mobile
          ? AppSpacing.mobilePage
          : AppSpacing.advancedDesktopGutter(width);
      final cidrs = controller.strings('windows', 'excludedCidrs');
      return PolicyDetailScaffold(
        title: l.prototypeWindowsSystemVpn,
        help: [
          l.prototypeWindowsBypassNotice,
          l.prototypeWindowsAutoConnectNotice,
          l.prototypeBypassLocalSubnetsHint,
          l.prototypeBypassNetworksHint,
        ],
        controller: controller,
        canSave: controller.validationHint(l) == null,
        contentPadding: EdgeInsets.zero,
        body: Padding(
          padding: EdgeInsets.fromLTRB(gutter, 20, gutter, mobile ? 18 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingSection(
                title: l.prototypeSystemVpnPolicy,
                padding: EdgeInsets.zero,
                children: [
                  _toggle(context, 'alwaysOn', l.prototypeAlwaysOn),
                  _toggle(
                    context,
                    'allowLocalNetwork',
                    l.prototypeBypassLocalSubnets,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SettingSection(
                title: l.prototypeBypassNetworks,
                padding: EdgeInsets.zero,
                action: Text(
                  '${cidrs.where((value) => value.trim().isNotEmpty).length} / 64',
                  textDirection: TextDirection.ltr,
                  style: AppTypography.windowsNetworkMeta.copyWith(
                    color: palette.mutedForeground,
                  ),
                ),
                children: [
                  ExcludedNetworks(
                    rowKeyPrefix: 'windows-cidr-row',
                    maxEntries: 64,
                    values: cidrs,
                    enabled: !controller.blocked,
                    onChanged: (values) => controller.update(
                      'excludedCidrs',
                      values,
                      section: 'windows',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l.prototypeBypassNetworkInputHint,
                    style: AppTypography.windowsNetworkNote.copyWith(
                      color: palette.mutedForeground,
                    ),
                  ),
                  if (controller.value['ipv6Enabled'] == false) ...[
                    const SizedBox(height: 14),
                    Text(
                      controller.ipv6Conflict
                          ? l.prototypeIpv6BypassConflict
                          : l.prototypeEnableIpv6ForBypass,
                      style: AppTypography.windowsNetworkNote.copyWith(
                        color: palette.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
              if ((controller.value['xrayOutboundInterfaceName'] as String)
                  .isEmpty) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: controller.blocked
                        ? null
                        : () => controller.openChild(context, openInterface),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: AppTypography.control,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(l.prototypeChooseInterfaceBeforeSaving),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _toggle(BuildContext context, String field, String title) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: AppTypography.platformChoiceTitle),
          ),
          const SizedBox(width: 12),
          AppSwitch(
            value: controller.group('windows')[field] as bool,
            onChanged: controller.blocked
                ? null
                : (value) =>
                      controller.update(field, value, section: 'windows'),
          ),
        ],
      ),
    );
  }
}
