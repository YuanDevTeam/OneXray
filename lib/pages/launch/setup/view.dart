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
            children: [
              if (welcome) ...[
                Text(
                  l.prototypeWelcomeSubtitle,
                  style: AppTypography.rowValue.copyWith(
                    color: ColorManager.palette(context).mutedForeground,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l.prototypeNoDataCollection,
                  style: AppTypography.rowValue,
                ),
                const SizedBox(height: 16),
                Text(l.prototypeBringOwnServers, style: AppTypography.rowValue),
                const SizedBox(height: 24),
                SettingRow(
                  title: l.prototypePrivacyPolicy,
                  leading: const Icon(LucideIcons.shieldCheck),
                  onTap: _action(SetupAction.privacy),
                ),
              ] else
                ..._configuration(context),
              ..._feedback(context),
            ],
          ),
        ),
        bottomNavigationBar: state.step == SetupStep.complete
            ? null
            : PageActionBar(children: _actions(l)),
      ),
    );
  }

  List<Widget> _configuration(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return [
      if (requiresInterface) ...[
        _SetupRow(
          icon: LucideIcons.network,
          title: l.prototypeXrayOutboundInterface,
          description: state.interfaceName.isEmpty
              ? l.prototypeNotSelected
              : state.interfaceName,
          busy: state.activeAction == SetupAction.chooseInterface,
          onTap: _action(SetupAction.chooseInterface),
        ),
        const SizedBox(height: 10),
        Text(
          l.prototypeInterfaceSelectionNotice,
          style: AppTypography.setupSkipNote.copyWith(
            color: palette.mutedForeground,
          ),
        ),
        const SizedBox(height: 24),
      ],
      _SetupRow(
        icon: LucideIcons.globe2,
        title: switch (state.regions) {
          null => l.prototypeChooseCountryRegion,
          [] => l.prototypeNoDirectRegions,
          [final code, ...] => setupRegionLabel(l, code),
        },
        description: l.prototypeRegionPurpose,
        busy: state.activeAction == SetupAction.chooseRegion,
        onTap: _action(SetupAction.chooseRegion),
      ),
      if (state.regions == null) ...[
        const SizedBox(height: 10),
        Text(
          l.prototypeRegionSkipNotice,
          style: AppTypography.setupSkipNote.copyWith(
            color: palette.mutedForeground,
          ),
        ),
      ],
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
    required this.description,
    this.onTap,
    this.busy = false,
  });
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => SettingRow(
    title: title,
    subtitle: description,
    leading: Icon(icon),
    onTap: onTap,
    trailing: busy ? const ButtonProgressIndicator() : null,
    showChevron: !busy,
  );
}
