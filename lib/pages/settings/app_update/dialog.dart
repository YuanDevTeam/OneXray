import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/app_update/controller.dart';
import 'package:onexray/pages/settings/app_update/params.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AppUpdateDialog extends StatelessWidget {
  final AppUpdateDialogParams params;

  const AppUpdateDialog({super.key, required this.params});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppUpdateDialogController(params.updateInfo),
      child: BlocBuilder<AppUpdateDialogController, AppUpdateDialogAction?>(
        builder: (context, action) {
          final controller = context.read<AppUpdateDialogController>();
          return AppUpdateDialogView(
            updateInfo: params.updateInfo,
            action: action,
            onLater: () => controller.later(context),
            onSkip: () => controller.skip(context),
            onUpdate: () => controller.update(context),
            onOpenLink: (href) => controller.openLink(context, href),
          );
        },
      ),
    );
  }
}

class AppUpdateDialogView extends StatelessWidget {
  final AppUpdateInfo updateInfo;
  final AppUpdateDialogAction? action;
  final VoidCallback onLater;
  final VoidCallback onSkip;
  final VoidCallback onUpdate;
  final ValueChanged<String?> onOpenLink;

  const AppUpdateDialogView({
    super.key,
    required this.updateInfo,
    this.action,
    required this.onLater,
    required this.onSkip,
    required this.onUpdate,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notes = updateInfo.releaseNotes.trim();
    final screenSize = MediaQuery.sizeOf(context);
    final notesHeight = (screenSize.height * 0.42).clamp(160.0, 420.0);
    return Dialog(
      // Match the prototype dialog's effective UA max-width (viewport - 38).
      insetPadding: const EdgeInsets.symmetric(horizontal: 19, vertical: 16),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ShadCard(
          width: double.infinity,
          padding: EdgeInsets.zero,
          radius: const BorderRadius.all(Radius.circular(AppRadii.card)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.appUpdateDialogTitle,
                      style: AppTypography.updateTitle,
                    ),
                    const SizedBox(height: 14),
                    _VersionGrid(updateInfo: updateInfo),
                  ],
                ),
              ),
              if (notes.isNotEmpty) ...[
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: notesHeight),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.prototypeReleaseNotes,
                            style: AppTypography.sectionTitle,
                          ),
                          const SizedBox(height: 10),
                          // flutter_markdown_plus still uses SDK Material.
                          // ignore: deprecated_member_use
                          MaterialUiCompatibilityBridge(
                            child: MarkdownBody(
                              data: notes,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet(
                                p: AppTypography.supporting,
                                listBullet: AppTypography.supporting,
                                listIndent: 20,
                                listBulletPadding:
                                    const EdgeInsetsDirectional.only(end: 4)
                                        .resolve(Directionality.of(context)),
                                blockSpacing: 6,
                              ),
                              onTapLink: (_, href, _) => onOpenLink(href),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              _UpdateActions(
                laterLabel: l10n.appUpdateLater,
                skipLabel: l10n.appUpdateSkipVersion,
                updateLabel: l10n.appUpdateOpen,
                action: action,
                onLater: onLater,
                onSkip: onSkip,
                onUpdate: onUpdate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionGrid extends StatelessWidget {
  final AppUpdateInfo updateInfo;

  const _VersionGrid({required this.updateInfo});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _row(context, l10n.appUpdateCurrentVersion, updateInfo.currentVersion),
        const SizedBox(height: 10),
        _row(context, l10n.appUpdateLatestVersion, updateInfo.latestVersion),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String version) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.rowTitle)),
        Text(version, style: AppTypography.rowValue),
      ],
    );
  }
}

class _UpdateActions extends StatelessWidget {
  final String laterLabel;
  final String skipLabel;
  final String updateLabel;
  final AppUpdateDialogAction? action;
  final VoidCallback onLater;
  final VoidCallback onSkip;
  final VoidCallback onUpdate;

  const _UpdateActions({
    required this.laterLabel,
    required this.skipLabel,
    required this.updateLabel,
    required this.action,
    required this.onLater,
    required this.onSkip,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = [
            ShadButton.outline(
              height: 48,
              onPressed: onLater,
              child: Text(laterLabel),
            ),
            ShadButton.outline(
              height: 48,
              enabled: action != AppUpdateDialogAction.skip,
              onPressed: action == AppUpdateDialogAction.skip ? null : onSkip,
              child: ButtonProgress(
                busy: action == AppUpdateDialogAction.skip,
                child: Text(skipLabel),
              ),
            ),
            ShadButton(
              height: 48,
              onPressed: onUpdate,
              child: Text(updateLabel),
            ),
          ];
          if (constraints.maxWidth < 460) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < actions.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  actions[index],
                ],
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                actions[index],
              ],
            ],
          );
        },
      ),
    );
  }
}
