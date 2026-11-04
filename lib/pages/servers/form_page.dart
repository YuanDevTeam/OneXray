import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/layout.dart';

/// A single configuration card within a server form. Other form sections keep
/// their own surfaces instead of receiving a second page-wide card.
class ServerFormSection extends StatelessWidget {
  const ServerFormSection({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final gutter = mobile ? 16.0 : 28.0;
    return SettingSection(
      title: title,
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
      children: [child],
    );
  }
}

/// Full content presentation for import and server editing. Choice and
/// confirmation dialogs keep their existing modal surfaces.
class ServerFormPage extends StatelessWidget {
  const ServerFormPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.expandBody = false,
    this.onBack,
    this.onClose,
  });
  final String title;
  final Widget body;
  final List<Widget> actions;

  /// Gives an editor workspace the Scaffold's finite remaining space.
  final bool expandBody;
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
          child: expandBody
              ? body
              : ResponsiveContent(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [body, const SizedBox(height: 24)],
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
