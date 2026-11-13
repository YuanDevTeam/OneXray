import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/controller.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:onexray/pages/settings/widgets.dart';

class AboutOneXrayPage extends StatelessWidget {
  const AboutOneXrayPage({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SettingsController(),
    child: BlocBuilder<SettingsController, SettingsPageState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        final controller = context.read<SettingsController>();
        return Scaffold(
          appBar: PageAppBar(title: Text(l10n.prototypeAboutOneXray)),
          body: SafeArea(
            child: SettingsPageScroll(
              desktopMaxWidth: AppLayout.routingMaxWidth,
              padding: EdgeInsets.zero,
              child: Padding(
                padding: settingsContentPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingSection(
                      title: 'OneXray',
                      padding: EdgeInsets.zero,
                      dividerIndent: 0,
                      children: [
                        SettingsVersionRow(
                          label: l10n.prototypeAppVersion,
                          value: state.appVersion,
                          compact: true,
                        ),
                        SettingsVersionRow(
                          label: 'Xray-core',
                          value: state.xrayVersion,
                          compact: true,
                        ),
                        BlocBuilder<AppEventBus, AppEventBusState>(
                          builder: (context, preferences) => SettingRow(
                            title: l10n.prototypeCheckAppUpdates,
                            leading: const Icon(LucideIcons.refreshCw),
                            subtitle: preferences.appUpdateInfo == null
                                ? null
                                : l10n.prototypeVersionAvailable(
                                    preferences.appUpdateInfo!.latestVersion,
                                  ),
                            titleTrailing: preferences.appUpdateInfo == null
                                ? null
                                : const SettingsUpdateDot(),
                            showChevron: true,
                            trailing:
                                preferences.downloading || state.checkingUpdate
                                ? const ButtonProgressIndicator(size: 20)
                                : null,
                            onTap: state.checkingUpdate
                                ? null
                                : () => controller.checkUpdate(context),
                          ),
                        ),
                        _LinkRow(
                          label: l10n.prototypeReleaseNotes,
                          link: SettingsLink.releaseNotes,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SettingSection(
                      title: l10n.prototypeHelpCommunity,
                      headerInset: 0,
                      padding: EdgeInsets.zero,
                      dividerIndent: 0,
                      children: [
                        _LinkRow(
                          label: l10n.prototypeDocumentation,

                          link: SettingsLink.documentation,
                        ),
                        if (AppPlatform.isMobile || AppPlatform.isMacOS)
                          _LinkRow(
                            label: l10n.prototypeRateOneXray,

                            link: SettingsLink.review,
                          ),
                        _LinkRow(
                          label: l10n.prototypeCommunity,

                          link: SettingsLink.community,
                        ),
                        _LinkRow(
                          label: l10n.prototypeSendFeedback,

                          link: SettingsLink.feedback,
                        ),
                        _LinkRow(
                          label: l10n.prototypeSourceCode,

                          link: SettingsLink.source,
                        ),
                        _LinkRow(
                          label: l10n.prototypeAcknowledgements,
                          link: SettingsLink.credits,
                        ),
                        _LinkRow(
                          label: l10n.prototypePrivacyPolicy,

                          link: SettingsLink.privacy,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _LinkRow extends StatelessWidget {
  final String label;
  final SettingsLink link;
  const _LinkRow({required this.label, required this.link});
  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: label,
      leading: Icon(switch (link) {
        SettingsLink.documentation => LucideIcons.bookOpen,
        SettingsLink.releaseNotes => LucideIcons.history,
        SettingsLink.review => LucideIcons.star,
        SettingsLink.community => LucideIcons.messagesSquare,
        SettingsLink.feedback => LucideIcons.messageSquare,
        SettingsLink.source => LucideIcons.code,
        SettingsLink.credits => LucideIcons.heart,
        SettingsLink.privacy => LucideIcons.shieldCheck,
      }),
      trailing: const Icon(LucideIcons.chevronRightDir, size: 17),
      onTap: () => context.read<SettingsController>().openLink(context, link),
    );
  }
}
