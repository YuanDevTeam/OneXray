import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/shared/widgets/dns_text_field.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/settings.dart';

class TunnelDnsPage extends StatelessWidget {
  const TunnelDnsPage({super.key, required this.draft, this.createController});

  final PolicyEditorDraft draft;
  final PolicyEditorController Function()? createController;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        createController?.call() ?? PolicyEditorController(draft: draft),
    child: BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
      builder: (context, state) {
        final controller = context.read<PolicyEditorController>();
        final l = AppLocalizations.of(context)!;
        final apple =
            controller.platform == ConnectionPlatform.ios ||
            controller.platform == ConnectionPlatform.macos;
        final dot = apple && controller.group('apple')['dnsOverTls'] == true;
        Widget field(
          TunnelDnsField field,
          String key,
          String label,
          String name,
        ) => DnsTextField(
          key: ValueKey('tunnel-dns-$name'),
          label: label,
          value: controller.value[key] as String,
          enabled: !controller.blocked,
          focusNode: controller.dnsFocusNode(field),
          errorText: controller.dnsErrorText(l, field),
          onChanged: (value) => controller.update(key, value),
        );
        return PolicyDetailScaffold(
          title: l.prototypeTunnelDns,
          description: l.tunnelDetailDescription,
          controller: controller,
          help: [
            l.tunnelDnsServerNameHint,
            if (apple) l.prototypeUseDnsOverTlsHint,
          ],
          contentPadding: EdgeInsets.zero,
          body: _bodyPadding(
            context,
            SettingSection(
              title: l.prototypeTunnelDns,
              padding: EdgeInsets.zero,
              children: [
                field(
                  TunnelDnsField.ipv4,
                  'dnsIpv4Address',
                  l.prototypeIpv4Dns,
                  'ipv4',
                ),
                if (controller.value['ipv6Enabled'] == true ||
                    controller.supportsWindowsSystemVpn) ...[
                  const SizedBox(height: 16),
                  field(
                    TunnelDnsField.ipv6,
                    'dnsIpv6Address',
                    l.prototypeIpv6Dns,
                    'ipv6',
                  ),
                ],
                if (apple) ...[
                  const SizedBox(height: 16),
                  PolicyToggle(
                    key: const ValueKey('tunnel-dns-over-tls'),
                    controller: controller,
                    section: 'apple',
                    field: 'dnsOverTls',
                    title: l.prototypeUseDnsOverTls,
                  ),
                ],
                if (dot) ...[
                  const SizedBox(height: 16),
                  field(
                    TunnelDnsField.serverName,
                    'dnsServerName',
                    l.prototypeDomain,
                    'server-name',
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

class TunnelNetworkPage extends StatelessWidget {
  const TunnelNetworkPage({
    super.key,
    required this.draft,
    this.createController,
  });

  final PolicyEditorDraft draft;
  final PolicyEditorController Function()? createController;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        createController?.call() ?? PolicyEditorController(draft: draft),
    child: BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
      builder: (context, state) {
        final controller = context.read<PolicyEditorController>();
        final l = AppLocalizations.of(context)!;
        return PolicyDetailScaffold(
          title: 'IPv6',
          description: l.tunnelDetailDescription,
          controller: controller,
          canSave: controller.validationHint(l) == null,
          contentPadding: EdgeInsets.zero,
          body: _bodyPadding(
            context,
            SettingSection(
              title: 'IPv6',
              description: controller.ipv6Conflict
                  ? l.prototypeIpv6BypassConflict
                  : null,
              descriptionBelow: true,
              padding: EdgeInsets.zero,
              children: [
                PolicyToggle(
                  key: const ValueKey('tunnel-ipv6-enabled'),
                  controller: controller,
                  field: 'ipv6Enabled',
                  title: l.prototypeUseIpv6,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _bodyPadding(BuildContext context, Widget child) {
  final width = MediaQuery.sizeOf(context).width;
  final gutter = width <= AppLayout.mobileBreakpoint
      ? AppSpacing.mobilePage
      : AppSpacing.advancedDesktopGutter(width);
  return Padding(
    padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 24),
    child: child,
  );
}
