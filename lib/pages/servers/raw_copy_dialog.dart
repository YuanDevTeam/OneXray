import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';

/// Names the independent personal copy; it never edits subscription JSON.
class ProviderRawCopyNameDialog extends StatefulWidget {
  const ProviderRawCopyNameDialog({super.key, required this.initialName});

  final String initialName;

  @override
  State<ProviderRawCopyNameDialog> createState() =>
      _ProviderRawCopyNameDialogState();
}

class _ProviderRawCopyNameDialogState extends State<ProviderRawCopyNameDialog> {
  late final name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final valid = name.text.trim().isNotEmpty && name.text.trim().length <= 32;
    return AppDialog(
      title: l.providerCopyAsRaw,
      subtitle: l.providerCopyAsRawHint,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: TextField(
          key: const ValueKey('provider-raw-copy-name'),
          controller: name,
          maxLength: 32,
          autofocus: true,
          decoration: InputDecoration(labelText: l.prototypeConfigurationName),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (valid) Navigator.of(context).pop(name.text.trim());
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.prototypeCancel),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(name.text.trim())
              : null,
          child: Text(l.providerCopyAsRaw),
        ),
      ],
    );
  }
}
