import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/smart/controller.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/connect/routing/options_form.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SmartRoutingEditorPage extends StatefulWidget {
  final OpenDirectRegions openRegions;
  final OpenFinalExit openFinalExit;
  const SmartRoutingEditorPage({
    super.key,
    required this.openRegions,
    required this.openFinalExit,
  });
  @override
  State<SmartRoutingEditorPage> createState() => _SmartRoutingEditorPageState();
}

class _SmartRoutingEditorPageState extends State<SmartRoutingEditorPage> {
  final controller = SmartRoutingEditorController();
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      controller.load(context);
    }
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<SmartRoutingEditorController, SmartRoutingEditorState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        return Scaffold(
          appBar: PageAppBar(
            title: Text(l.prototypeSmartRouting),
            leading: BackButton(onPressed: () => controller.cancel(context)),
          ),
          body: SafeArea(
            child: state.original == null
                ? Center(
                    child: state.busy
                        ? const CircularProgressIndicator()
                        : TextButton(
                            onPressed: () => controller.load(context),
                            child: Text(l.prototypeRetry),
                          ),
                  )
                : SettingsPageScroll(
                    desktopMaxWidth: AppLayout.routingMaxWidth,
                    padding: EdgeInsetsDirectional.fromSTEB(
                      mobile ? AppSpacing.mobilePage : AppSpacing.page,
                      mobile ? 12 : AppSpacing.desktopPageTop,
                      mobile ? AppSpacing.mobilePage : AppSpacing.page,
                      mobile ? 18 : AppSpacing.desktopPageBottom,
                    ),
                    child: SmartRoutingEditorContent(
                      controller: controller,
                      state: state,
                      openRegions: widget.openRegions,
                      openFinalExit: widget.openFinalExit,
                    ),
                  ),
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.error case final error?)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              PageActionBar(
                children: [
                  if (!mobile)
                    OutlinedButton(
                      onPressed: () => controller.cancel(context),
                      child: Text(l.prototypeCancel),
                    ),
                  FilledButton(
                    onPressed: state.busy || state.original == null
                        ? null
                        : () => controller.save(context),
                    child: ButtonProgress(
                      busy: state.busy && state.original != null,
                      child: Text(l.prototypeSave),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// The editable groups share one scroll surface on phones, tablets and desktop.
class SmartRoutingEditorContent extends StatelessWidget {
  final SmartRoutingEditorController controller;
  final SmartRoutingEditorState state;
  final OpenDirectRegions openRegions;
  final OpenFinalExit openFinalExit;

  const SmartRoutingEditorContent({
    super.key,
    required this.controller,
    required this.state,
    required this.openRegions,
    required this.openFinalExit,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final direct = _directSettings(context);
      final proxy = _proxySettings(context);
      final dns = _dnsSettings(context);
      final sniffing = _sniffingSettings(context);
      final preview = _preview(context, state);
      // Account for the sidebar and page gutters before choosing two columns.
      if (constraints.maxWidth < AppLayout.mobileBreakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [direct, proxy, dns, sniffing, preview],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Expanded(
            child: Column(
              key: const ValueKey('smart-routing-primary'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [direct, dns],
            ),
          ),
          Expanded(
            child: Column(
              key: const ValueKey('smart-routing-secondary'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [proxy, sniffing, preview],
            ),
          ),
        ],
      );
    },
  );

  Widget _directSettings(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final smart = state.draft;
    return RoutingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoutingCardHeader(
            title: l.smartRoutingDirectAndBlock,
            help: [
              l.prototypeDirectPrivateAddressesHint,
              l.prototypeDirectAppleServicesHint,
              l.directWindowsServicesHint,
              l.prototypeBlockAdDomainsHint,
            ],
          ),
          RoutingSettingRow(
            icon: LucideIcons.earth,
            title: l.prototypeDirectRegions,
            value: controller.regionsSummary(l),
            enabled: !state.busy,
            onTap: () => controller.chooseRegions(context, openRegions),
          ),
          _switch(
            l.prototypeDirectPrivateAddresses,
            LucideIcons.network,
            'directPrivate',
            smart.directPrivate,
            state,
          ),
          _switch(
            l.prototypeDirectAppleServices,
            LucideIcons.apple,
            'directApple',
            smart.directApple,
            state,
          ),
          _switch(
            l.directWindowsServices,
            LucideIcons.appWindow,
            'directWindows',
            smart.directWindows,
            state,
          ),
          _switch(
            l.prototypeBlockAdDomains,
            LucideIcons.shieldCheck,
            'blockAds',
            smart.blockAds,
            state,
            divider: false,
          ),
        ],
      ),
    );
  }

  Widget _proxySettings(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final smart = state.draft;
    return RoutingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoutingCardHeader(title: l.smartRoutingProxyConnection),
          RoutingEntryCountRow(
            value: smart.entryCount,
            onChanged: state.busy
                ? null
                : (count) => controller.update('entryCount', count),
          ),
          RoutingSelectionSettingsForm(
            value: smart.selection,
            enabled: !state.busy,
            entryCount: controller.effectiveEntryCount,
            onChanged: (value) =>
                controller.update('selection', value.toJson()),
          ),
          RoutingFragmentRow(
            value: smart.fragment,
            enabled: state.original != null && !state.busy,
            onChanged: (value) => controller.update('fragment', value),
          ),
          RoutingSettingRow(
            icon: LucideIcons.server,
            title: l.prototypeVpnFinalExit,
            help: l.prototypeVpnFinalExitHint,
            value: smart.finalExitId == null
                ? l.prototypeNotSet
                : state.finalExitName ?? l.prototypeTemporarilyUnavailable,
            enabled: !state.busy,
            divider: false,
            onTap: () => controller.chooseFinalExit(context, openFinalExit),
          ),
        ],
      ),
    );
  }

  Widget _dnsSettings(BuildContext context) => RoutingDnsSettingsForm(
    value: state.draft.dns,
    enabled: !state.busy,
    directEnabled: state.draft.directDns,
    leading: _switch(
      AppLocalizations.of(context)!.prototypeDirectDns,
      LucideIcons.earth,
      'directDns',
      state.draft.directDns,
      state,
      help: AppLocalizations.of(context)!.prototypeDirectDnsHint,
    ),
    onChanged: (value) => controller.update('dns', value.toJson()),
  );

  Widget _sniffingSettings(BuildContext context) => RoutingSniffingSettingsForm(
    value: state.draft.sniffing,
    enabled: !state.busy,
    fakeDns: state.draft.fakeDns,
    leading: RoutingFakeDnsRow(
      value: state.draft.fakeDns,
      enabled:
          !state.busy && (state.draft.fakeDns || state.draft.sniffing.enabled),
      onChanged: (value) => controller.update('fakeDns', value),
    ),
    onChanged: (value) => controller.update('sniffing', value.toJson()),
  );

  Widget _switch(
    String title,
    IconData icon,
    String key,
    bool value,
    SmartRoutingEditorState state, {
    Widget? below,
    String? help,
    bool divider = true,
  }) => RoutingSettingRow(
    icon: icon,
    title: title,
    help: help,
    divider: divider,
    enabled: state.original != null && !state.busy,
    below: below,
    trailing: Semantics(
      label: title,
      child: ShadSwitch(
        value: value,
        enabled: state.original != null && !state.busy,
        onChanged: (value) => controller.update(key, value),
      ),
    ),
  );

  Widget _preview(BuildContext context, SmartRoutingEditorState state) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return RoutingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoutingCardHeader(title: l.prototypeRoutingPreview),
          _result(
            context,
            l.prototypeDirect,
            controller.directPreview(l),
            palette.runningText,
            palette.runningSurface,
          ),
          _result(
            context,
            'VPN',
            controller.vpnPath(l),
            palette.primary,
            palette.selectedSurface,
            textColor: palette.primaryText,
            hint: controller.effectiveEntryCount > 1
                ? l.prototypeDistributedEntries(controller.effectiveEntryCount)
                : null,
          ),
          _result(
            context,
            l.prototypeBlock,
            controller.blockPreview(l),
            palette.destructive,
            palette.destructiveSurface,
          ),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.prototypeSmartRuleSummary(
                    controller.rulesFor('direct').length,
                  ),
                  style: AppTypography.routingPreviewMeta.copyWith(
                    color: palette.mutedForeground,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.prototypeRuleOrderMaintained,
                  style: AppTypography.routingPreviewMeta.copyWith(
                    color: palette.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: mobile ? 8 : 12),
        ],
      ),
    );
  }

  Widget _result(
    BuildContext context,
    String title,
    String description,
    Color foreground,
    Color background, {
    Color? textColor,
    String? hint,
  }) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return Container(
      constraints: BoxConstraints(minHeight: mobile ? 64 : 74),
      margin: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: foreground,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.routingPreviewTitle.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            description,
            style: AppTypography.routingPreviewBody.copyWith(
              color: textColor ?? foreground,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 5),
            Text(
              hint,
              style: AppTypography.routingPreviewHint.copyWith(
                color: textColor ?? foreground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
