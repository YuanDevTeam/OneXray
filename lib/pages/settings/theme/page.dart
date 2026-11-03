import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/theme/controller.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/pages/settings/widgets.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ThemeController(),
      child: BlocBuilder<ThemeController, ThemePageState>(
        builder: (context, state) {
          final controller = context.read<ThemeController>();
          final l10n = AppLocalizations.of(context)!;
          return Scaffold(
            appBar: PageAppBar.forPage(
              context,
              title: Text(l10n.themePageTitle),
              description: l10n.settingsDevicePreferenceDescription,
            ),
            body: SafeArea(
              child: ThemeChoiceView(
                selected: state.themeCode,
                onSelected: controller.updateThemeCode,
              ),
            ),
            bottomNavigationBar: PageActionBar(
              children: [
                ShadButton.outline(
                  onPressed: () => Navigator.maybePop(context),
                  child: Text(l10n.prototypeCancel),
                ),
                ShadButton(
                  onPressed: () => controller.save(context),
                  child: Text(l10n.buttonSave),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ThemeChoiceView extends StatelessWidget {
  final ThemeCode selected;
  final ValueChanged<ThemeCode?> onSelected;

  const ThemeChoiceView({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsPageScroll(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: settingsContentPadding(context),
        child: SettingSection(
          title: l10n.themePageTitle,
          padding: EdgeInsets.zero,
          children: [
            SettingsThemeOptions(selected: selected, onSelected: onSelected),
          ],
        ),
      ),
    );
  }
}
