import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/theme/font.dart';

/// Optional explanations stay out of the form until the user asks for them.
/// Errors, unavailable states and action warnings belong beside their controls.
class PageHelpButton extends StatelessWidget {
  const PageHelpButton({
    super.key,
    required this.title,
    required this.messages,
  });

  final String title;
  final List<String> messages;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '${AppLocalizations.of(context)!.pageHelp} · $title',
    icon: const Icon(LucideIcons.circleHelp, size: 20),
    onPressed: () => showAppDialog<void>(
      context,
      (context) => AppDialog(
        title: title,
        onClose: () => Navigator.pop(context),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              for (final message in messages)
                SelectableText(message, style: AppTypography.confirmationBody),
            ],
          ),
        ),
      ),
    ),
  );
}
