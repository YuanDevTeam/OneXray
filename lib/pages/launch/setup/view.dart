import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/launch/setup/controller.dart';
import 'package:onexray/pages/launch/setup/selectors.dart';
import 'package:onexray/pages/launch/setup/widgets.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
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
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final welcome = state.step == SetupStep.welcome;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 48).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: SettingSection(
                      title: welcome
                          ? l.prototypeWelcome
                          : l.prototypeGetReadyToConnect,
                      description: welcome ? l.prototypeWelcomeSubtitle : null,
                      padding: EdgeInsets.zero,
                      children: [
                        if (welcome) ...[
                          Text(
                            l.prototypeNoDataCollection,
                            style: AppTypography.rowValue,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l.prototypeBringOwnServers,
                            style: AppTypography.rowValue,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: _action(SetupAction.privacy),
                            child: Text(l.prototypePrivacyPolicy),
                          ),
                        ] else
                          ..._configuration(context, mobile),
                        ..._feedback(context),
                        if (state.step != SetupStep.complete) ...[
                          const SizedBox(height: 24),
                          if (welcome)
                            ..._actions(l)
                          else
                            OverflowBar(
                              spacing: 10,
                              overflowSpacing: 10,
                              children: _actions(l),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _configuration(BuildContext context, bool mobile) {
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
