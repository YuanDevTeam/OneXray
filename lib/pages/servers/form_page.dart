import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';

/// Full content presentation for import and server editing. Choice and
/// confirmation dialogs keep their existing modal surfaces.
class ServerFormPage extends StatelessWidget {
  const ServerFormPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.actions = const [],
    this.onBack,
    this.onClose,
  });
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final VoidCallback? onBack, onClose;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          (onBack ?? onClose)?.call(),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        appBar: PageAppBar(
          title: Text(title),
          leading: BackButton(onPressed: onBack ?? onClose),
          actions: [
            if (onBack != null && onClose != null)
              IconButton(
                tooltip: AppLocalizations.of(context)!.prototypeCloseDialog,
                onPressed: onClose,
                icon: const Icon(LucideIcons.x, size: 20),
              ),
          ],
        ),
        body: SafeArea(
          child: ResponsiveContent(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (subtitle?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        16,
                        16,
                        0,
                      ),
                      child: Text(
                        subtitle!,
                        style: AppTypography.supporting.copyWith(
                          color: ColorManager.palette(context).mutedForeground,
                        ),
                      ),
                    ),
                  body,
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: actions.isEmpty
            ? null
            : PageActionBar(children: actions),
      ),
    ),
  );
}
