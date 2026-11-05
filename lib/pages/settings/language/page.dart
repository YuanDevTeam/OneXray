import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/language/controller.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/settings/widgets.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LanguageController(),
      child: BlocBuilder<LanguageController, LanguagePageState>(
        builder: (context, state) {
          final controller = context.read<LanguageController>();
          final l10n = AppLocalizations.of(context)!;
          return Scaffold(
            appBar: PageAppBar(
              title: Text(l10n.prototypeLanguage),
              leading: BackButton(onPressed: () => controller.cancel(context)),
            ),
            body: SafeArea(
              child: AbsorbPointer(
                absorbing: state.saving,
                child: LanguageChoiceView(
                  selected: state.languageCode,
                  onSelected: controller.updateLanguageCode,
                ),
              ),
            ),
            bottomNavigationBar: PageActionBar(
              maxWidth: AppLayout.standardMaxWidth,
              children: [
                ShadButton.outline(
                  onPressed: () => controller.cancel(context),
                  child: Text(l10n.prototypeCancel),
                ),
                ShadButton(
                  enabled: !state.saving,
                  onPressed: state.saving
                      ? null
                      : () => controller.save(context),
                  child: ButtonProgress(
                    busy: state.saving,
                    child: Text(l10n.prototypeSave),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class LanguageChoiceView extends StatelessWidget {
  final LanguageCode selected;
  final ValueChanged<LanguageCode?> onSelected;

  const LanguageChoiceView({
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
          title: l10n.settingsAppLanguage,
          padding: EdgeInsets.zero,
          children: [
            Text(l10n.prototypeLanguage, style: AppTypography.rowValue),
            const SizedBox(height: 12),
            ShadSelect<LanguageCode>(
              key: ValueKey(selected),
              initialValue: selected,
              selectedOptionBuilder: (_, language) => Text(
                languageNativeLabel(l10n, language),
                textDirection: language == LanguageCode.fa
                    ? TextDirection.rtl
                    : language == LanguageCode.system
                    ? null
                    : TextDirection.ltr,
              ),
              options: [
                for (final language in LanguageCode.values)
                  ShadOption(
                    value: language,
                    child: Text(
                      languageNativeLabel(l10n, language),
                      textDirection: language == LanguageCode.fa
                          ? TextDirection.rtl
                          : language == LanguageCode.system
                          ? null
                          : TextDirection.ltr,
                    ),
                  ),
              ],
              onChanged: onSelected,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

String languageNativeLabel(AppLocalizations l10n, LanguageCode language) =>
    switch (language) {
      LanguageCode.system => l10n.prototypeFollowSystem,
      LanguageCode.zh => '简体中文',
      LanguageCode.zhHant => '繁體中文',
      LanguageCode.en => 'English',
      LanguageCode.ru => 'Русский',
      LanguageCode.fa => 'فارسی',
    };
