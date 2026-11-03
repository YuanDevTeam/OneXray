import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/gen/assets.gen.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/app_icon/controller.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/settings/widgets.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AppIconPage extends StatelessWidget {
  const AppIconPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppIconController(),
      child: BlocBuilder<AppIconController, AppIconPageState>(
        builder: (context, state) {
          final controller = context.read<AppIconController>();
          final l10n = AppLocalizations.of(context)!;
          final useDockIconLabel = AppPlatform.isMacOS;
          return Scaffold(
            appBar: PageAppBar.forPage(
              context,
              description: l10n.settingsDevicePreferenceDescription,
              title: Text(l10n.prototypeAppIcon),
              leading: BackButton(onPressed: () => controller.cancel(context)),
            ),
            body: SafeArea(
              child: AbsorbPointer(
                absorbing: state.loading || state.saving,
                child: AppIconChoiceView(
                  selected: state.appIcon,
                  useDockIconAssets: useDockIconLabel,
                  description: useDockIconLabel
                      ? l10n.prototypeDockIconHint
                      : l10n.prototypeHomeScreenIconHint,
                  onSelected: controller.updateIcon,
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
                  enabled: !state.loading && !state.saving,
                  onPressed: state.loading || state.saving
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

class AppIconChoiceView extends StatelessWidget {
  final AppIcon selected;
  final bool useDockIconAssets;
  final String description;
  final ValueChanged<AppIcon> onSelected;

  const AppIconChoiceView({
    super.key,
    required this.selected,
    required this.useDockIconAssets,
    required this.description,
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
          title: useDockIconAssets
              ? l10n.settingsDockIcon
              : l10n.settingsHomeScreenIcon,
          padding: EdgeInsets.zero,
          children: [
            Text(l10n.prototypeAppIcon, style: AppTypography.rowValue),
            const SizedBox(height: 12),
            ShadSelect<AppIcon>(
              key: ValueKey(selected),
              initialValue: selected,
              selectedOptionBuilder: (_, icon) =>
                  Text(appIconLabel(l10n, icon)),
              options: [
                for (final icon in AppIcon.values)
                  ShadOption(
                    value: icon,
                    child: Text(appIconLabel(l10n, icon)),
                  ),
              ],
              onChanged: (icon) {
                if (icon != null && icon != selected) onSelected(icon);
              },
            ),
            const SizedBox(height: 28),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _iconImage(_imageFor(selected), 96),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AssetGenImage _imageFor(AppIcon icon) {
    return useDockIconAssets ? icon.dockAssetImage : icon.assetImage;
  }

  static Widget _iconImage(AssetGenImage image, double size) {
    return image.image(width: size, height: size, fit: BoxFit.contain);
  }
}

String appIconLabel(AppLocalizations l10n, AppIcon icon) => switch (icon) {
  AppIcon.primary => l10n.prototypeIconBlue,
  AppIcon.black => l10n.prototypeIconBlack,
  AppIcon.green => l10n.prototypeIconGreen,
  AppIcon.orange => l10n.prototypeIconOrange,
  AppIcon.purple => l10n.prototypeIconPurple,
  AppIcon.red => l10n.prototypeIconRed,
};
