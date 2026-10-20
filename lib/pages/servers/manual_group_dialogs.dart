import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/theme/color.dart';

/// Distinguishes a chosen virtual group from dismissing the dialog.
class ManualGroupTarget {
  const ManualGroupTarget(this.id);
  final int? id;
}

enum ManualGroupAction { rename, dissolve, delete }

class ManualGroupNameDialog extends StatefulWidget {
  const ManualGroupNameDialog({super.key, this.initialName});
  final String? initialName;

  @override
  State<ManualGroupNameDialog> createState() => _ManualGroupNameDialogState();
}

class _ManualGroupNameDialogState extends State<ManualGroupNameDialog> {
  late final name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final valid = name.text.trim().isNotEmpty;
    void save() => Navigator.of(context).pop(name.text.trim());
    return AppDialog(
      title: widget.initialName == null
          ? l.manualGroupNew
          : l.manualGroupRename,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: TextField(
          key: const ValueKey('manual-group-name'),
          controller: name,
          autofocus: true,
          decoration: InputDecoration(labelText: l.manualGroupName),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (valid) save();
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.prototypeCancel),
        ),
        FilledButton(
          onPressed: valid ? save : null,
          child: Text(l.prototypeSave),
        ),
      ],
    );
  }
}

class ManualGroupMoveDialog extends StatelessWidget {
  const ManualGroupMoveDialog({
    super.key,
    required this.groups,
    this.currentId,
  });
  final List<ManualServerGroupData> groups;
  final int? currentId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    Widget row(String name, int? id) => ListTile(
      title: Text(name),
      leading: const Icon(LucideIcons.folder),
      trailing: currentId == id
          ? const Icon(LucideIcons.check, size: 18)
          : null,
      onTap: () => Navigator.of(context).pop(ManualGroupTarget(id)),
    );
    return AppDialog(
      title: l.manualGroupMove,
      body: Column(
        children: [
          row(l.manualGroupUngrouped, null),
          for (final group in groups) row(group.name, group.id),
        ],
      ),
    );
  }
}

class ManualGroupActionsDialog extends StatelessWidget {
  const ManualGroupActionsDialog({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      title: name,
      body: Column(
        children: [
          ListTile(
            leading: const Icon(LucideIcons.pencil),
            title: Text(l.manualGroupRename),
            onTap: () => Navigator.of(context).pop(ManualGroupAction.rename),
          ),
          ListTile(
            leading: const Icon(LucideIcons.folderMinus),
            title: Text(l.manualGroupDissolve),
            onTap: () => Navigator.of(context).pop(ManualGroupAction.dissolve),
          ),
          ListTile(
            textColor: ColorManager.palette(context).destructive,
            iconColor: ColorManager.palette(context).destructive,
            leading: const Icon(LucideIcons.trash2),
            title: Text(l.manualGroupDelete),
            onTap: () => Navigator.of(context).pop(ManualGroupAction.delete),
          ),
        ],
      ),
    );
  }
}
