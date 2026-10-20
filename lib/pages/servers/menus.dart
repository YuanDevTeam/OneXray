import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';

Future<ServerAction?> showServerActionsMenu(
  BuildContext context, {
  required String name,
  required String source,
  bool provider = false,
  bool canMove = false,
}) => showAppDialog<ServerAction>(
  context,
  (_) => ServerActionsMenu(
    name: name,
    source: source,
    provider: provider,
    canMove: canMove,
  ),
);

Future<SourceAction?> showSourceActionsMenu(
  BuildContext context, {
  required String name,
  required int count,
  bool provider = false,
}) => showAppDialog<SourceAction>(
  context,
  (_) => SourceActionsMenu(name: name, count: count, provider: provider),
);

/// Selects an action only; the caller keeps the controller's existing workflow.
class ServerActionsMenu extends StatelessWidget {
  const ServerActionsMenu({
    super.key,
    required this.name,
    required this.source,
    this.provider = false,
    this.canMove = false,
  });

  final String name;
  final String source;
  final bool provider;
  final bool canMove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      title: name,
      subtitle: source,
      body: Column(
        children: [
          _menuRow(
            context,
            ServerAction.edit,
            provider ? LucideIcons.fileJson : LucideIcons.pencil,
            provider ? l.providerViewConfiguration : l.prototypeEditServer,
          ),
          if (!provider)
            _menuRow(
              context,
              ServerAction.test,
              LucideIcons.refreshCw,
              l.prototypeTestAgain,
            ),
          _menuRow(
            context,
            ServerAction.copy,
            LucideIcons.copy,
            provider ? l.providerCopyAsRaw : l.prototypeSaveAsLocalServer,
            hint: provider ? l.providerCopyAsRawHint : l.prototypeLocalCopyHint,
          ),
          if (canMove)
            _menuRow(
              context,
              ServerAction.move,
              LucideIcons.folderInput,
              l.manualGroupMove,
            ),
          _menuRow(
            context,
            ServerAction.share,
            LucideIcons.share2,
            provider ? l.prototypeShare : l.prototypeShareServer,
          ),
          _menuRow(
            context,
            ServerAction.delete,
            LucideIcons.trash2,
            l.prototypeDelete,
            destructive: true,
          ),
        ],
      ),
    );
  }
}

class SourceActionsMenu extends StatelessWidget {
  const SourceActionsMenu({
    super.key,
    required this.name,
    required this.count,
    this.provider = false,
  });

  final String name;
  final int count;
  final bool provider;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      title: name,
      subtitle: provider
          ? l.providerConfigurationCount(count)
          : l.prototypeServerCount(count),
      body: Column(
        children: [
          _menuRow(
            context,
            SourceAction.update,
            LucideIcons.refreshCw,
            l.prototypeCheckForUpdates,
          ),
          if (!provider)
            _menuRow(
              context,
              SourceAction.test,
              LucideIcons.refreshCw,
              l.prototypeTestServers,
            ),
          _menuRow(
            context,
            SourceAction.edit,
            LucideIcons.pencil,
            l.prototypeEditSubscription,
          ),
          _menuRow(
            context,
            SourceAction.share,
            LucideIcons.share2,
            l.prototypeShareSubscription,
          ),
          _menuRow(
            context,
            SourceAction.delete,
            LucideIcons.trash2,
            l.prototypeDelete,
            destructive: true,
          ),
        ],
      ),
    );
  }
}

Widget _menuRow<T>(
  BuildContext context,
  T action,
  IconData icon,
  String title, {
  String? hint,
  bool destructive = false,
}) {
  final palette = ColorManager.palette(context);
  final textColor = destructive ? palette.destructive : palette.foreground;
  return Semantics(
    button: true,
    child: InkWell(
      onTap: () => Navigator.of(context).pop(action),
      hoverColor: palette.surfaceHover,
      child: Container(
        constraints: BoxConstraints(minHeight: hint == null ? 52 : 68),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          border: destructive
              ? null
              : Border(bottom: BorderSide(color: palette.border)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: destructive ? palette.destructive : palette.primary,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(
                    title,
                    style: AppTypography.serverMenuTitle.copyWith(
                      color: textColor,
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint,
                      style: AppTypography.serverMenuHint.copyWith(
                        color: palette.mutedForeground,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 13),
            Icon(LucideIcons.arrowRightDir, size: 18, color: textColor),
          ],
        ),
      ),
    ),
  );
}
