import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/launch/setup/controller.dart';
import 'package:onexray/pages/launch/setup/selectors.dart';
import 'package:onexray/pages/launch/setup/widgets.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/launch/setup.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The production presentation, without creating services or changing setup
/// preferences. It is also the isolated entry point for visual verification.
class SetupView extends StatelessWidget {
  const SetupView({
    super.key,
    required this.state,
    required this.requiresInterface,
    this.failureText,
    required this.onAction,
  });

  final SetupPageState state;
  final bool requiresInterface;
  final String? failureText;
  final ValueChanged<SetupAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final welcome = state.step == SetupStep.welcome;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: PageAppBar(
          title: Text(
            welcome ? l.prototypeWelcome : l.prototypeGetReadyToConnect,
          ),
          leading: welcome
              ? null
              : IconButton(
                  tooltip: l.prototypeBack,
                  onPressed: _action(SetupAction.back),
                  icon: const Icon(LucideIcons.arrowLeftDir),
                ),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: SetupBody(
            header: SetupProgress(
              current: welcome ? 0 : 1,
              labels: [l.prototypeWelcomePrivacy, l.prototypeSettings],
            ),
            bottom: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (welcome)
                  Card(
                    margin: EdgeInsets.zero,
                    child: SettingRow(
                      title: l.prototypePrivacyPolicy,
                      leading: const Icon(LucideIcons.fileText),
                      showChevron: true,
                      minHeight: 72,
                      contentPadding: const EdgeInsets.all(20),
                      onTap: _action(SetupAction.privacy),
                    ),
                  )
                else if (state.localReady)
                  SetupPoint(
                    icon: LucideIcons.circleCheck,
                    text: l.prototypeLocalConfigurationReady,
                  ),
                ..._feedback(context),
              ],
            ),
            children: [
              if (welcome) ...[
                SetupIntro(
                  icon: LucideIcons.shieldCheck,
                  title: l.prototypeWelcomeSubtitle,
                ),
                const SizedBox(height: 24),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SetupPoint(
                          icon: LucideIcons.lockKeyhole,
                          text: l.prototypeNoDataCollection,
                        ),
                        const SizedBox(height: 24),
                        SetupPoint(
                          icon: LucideIcons.server,
                          text: l.prototypeBringOwnServers,
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                ..._configuration(context),
            ],
          ),
        ),
        bottomNavigationBar: state.step == SetupStep.complete
            ? null
            : PageActionBar(
                maxWidth: AppLayout.setupContentMaxWidth,
                children: _actions(l),
              ),
      ),
    );
  }

  List<Widget> _configuration(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return [
      SetupIntro(
        icon: LucideIcons.route,
        title: l.prototypeSmartRouting,
        description: l.prototypeSmartRoutingDescription,
      ),
      const SizedBox(height: 24),
      if (requiresInterface) ...[
        _SetupRow(
          icon: LucideIcons.network,
          title: l.prototypeXrayOutboundInterface,
          value: state.interfaceName.isEmpty
              ? l.prototypeNotSelected
              : state.interfaceName,
          description: l.prototypeInterfaceSelectionNotice,
          busy: state.activeAction == SetupAction.chooseInterface,
          onTap: _action(SetupAction.chooseInterface),
        ),
        const SizedBox(height: 16),
      ],
      _SetupRow(
        icon: LucideIcons.globe2,
        title: l.prototypeYourRegion,
        value: switch (state.regions) {
          null => l.prototypeChooseCountryRegion,
          [] => l.prototypeNoDirectRegions,
          [final code, ...] => setupRegionLabel(l, code),
        },
        description: l.prototypeRegionPurpose,
        note: state.regions == null ? l.prototypeRegionSkipNotice : null,
        busy: state.activeAction == SetupAction.chooseRegion,
        onTap: _action(SetupAction.chooseRegion),
      ),
    ];
  }

  List<Widget> _feedback(BuildContext context) => [
    if (state.busy && state.activeAction == null) ...[
      const SizedBox(height: 20),
      const LinearProgressIndicator(),
    ],
    if (failureText != null) ...[
      SetupError(text: failureText!),
      if (state.failure?.component != 'region')
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _action(SetupAction.retry),
            child: ButtonProgress(
              busy: state.activeAction == SetupAction.retry,
              child: Text(AppLocalizations.of(context)!.prototypeRetry),
            ),
          ),
        ),
    ],
  ];

  VoidCallback? _action(SetupAction action) =>
      state.busy &&
          action != SetupAction.privacy &&
          (state.activeAction == null || state.activeAction == action)
      ? null
      : () => onAction(action);

  List<Widget> _actions(AppLocalizations l) => switch (state.step) {
    SetupStep.welcome => [
      SetupActionButton(
        label: l.prototypeAgreeAndContinue,
        busy: state.activeAction == SetupAction.acceptPrivacy,
        onPressed: _action(SetupAction.acceptPrivacy),
      ),
    ],
    SetupStep.configuration => [
      SetupActionButton(
        label: l.prototypeBack,
        outline: true,
        onPressed: _action(SetupAction.back),
      ),
      SetupActionButton(
        label: l.prototypeGoToHome,
        busy: state.activeAction == SetupAction.finish,
        onPressed: state.ready(requiresInterface: requiresInterface)
            ? _action(SetupAction.finish)
            : null,
      ),
    ],
    SetupStep.complete => const [],
  };
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.description,
    this.note,
    this.onTap,
    this.busy = false,
  });
  final IconData icon;
  final String title;
  final String value;
  final String description;
  final String? note;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 22, color: palette.primaryText),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTypography.supporting.copyWith(
                              color: palette.mutedForeground,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(value, style: AppTypography.panelTitle),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (busy)
                      const ButtonProgressIndicator()
                    else
                      Icon(
                        LucideIcons.chevronRightDir,
                        size: 20,
                        color: palette.mutedForeground,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  description,
                  style: AppTypography.rowValue.copyWith(
                    color: palette.mutedStrong,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    note!,
                    style: AppTypography.supporting.copyWith(
                      color: palette.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
