import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/service/settings/backup/service.dart';

class ExistingBackupDialog extends StatelessWidget {
  const ExistingBackupDialog({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      title: l.backupExistingTitle,
      subtitle: p.basename(location),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(l.backupExistingPrompt),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, BackupExistingAction.restore),
              child: Text(l.backupRestore),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.pop(context, BackupExistingAction.overwrite),
              child: Text(l.backupOverwrite),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.prototypeCancel),
        ),
      ],
    );
  }
}
