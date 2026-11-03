import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/geodata/controller.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadInput;

class GeoDataAddPage extends StatelessWidget {
  const GeoDataAddPage({super.key, this.createController});

  final GeoDataController Function()? createController;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final controller =
          createController?.call() ?? (GeoDataController()..initialize());
      if (!controller.state.adding) controller.toggleAdd();
      return controller;
    },
    child: BlocConsumer<GeoDataController, GeoDataPageState>(
      listenWhen: (previous, current) =>
          previous.formBusy &&
          !current.formBusy &&
          !current.adding &&
          current.formError == null,
      listener: (context, _) {
        if (ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop(true);
        }
      },
      builder: (context, state) {
        final controller = context.read<GeoDataController>();
        final l = AppLocalizations.of(context)!;
        final palette = ColorManager.palette(context);
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        void cancel() {
          if (!state.formBusy) Navigator.of(context).pop();
        }

        Widget field(String label, Widget input) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Text(
              label,
              style: AppTypography.fieldLabel.copyWith(
                color: palette.foreground,
              ),
            ),
            Semantics(label: label, child: input),
          ],
        );
        return PopScope(
          canPop: !state.formBusy,
          child: Scaffold(
            appBar: PageAppBar.forPage(
              context,
              title: Text(l.prototypeAddDataSource),
              leading: BackButton(onPressed: cancel),
            ),
            body: SafeArea(
              child: SettingsPageScroll(
                desktopMaxWidth: AppLayout.advancedMaxWidth,
                padding: EdgeInsets.fromLTRB(
                  mobile ? 16 : 28,
                  20,
                  mobile ? 16 : 28,
                  24,
                ),
                child: SettingSection(
                  title: l.prototypeCustomRoutingData,
                  padding: EdgeInsets.zero,
                  children: [
                    field(
                      l.prototypeDataType,
                      SettingSelect<GeoDataType>(
                        value: state.type,
                        entries: const {
                          GeoDataType.ip: 'GeoIP',
                          GeoDataType.domain: 'GeoSite',
                        },
                        textStyle: AppTypography.rowValue,
                        onChanged: state.formBusy
                            ? null
                            : controller.changeType,
                      ),
                    ),
                    const SizedBox(height: 16),
                    field(
                      l.prototypeSavedFileName,
                      ShadInput(
                        key: const ValueKey('geodata-source-name'),
                        controller: controller.name,
                        enabled: !state.formBusy,
                        autofocus: true,
                        autocorrect: false,
                        textDirection: TextDirection.ltr,
                        style: AppTypography.rowValue,
                        placeholderStyle: AppTypography.rowValue.copyWith(
                          color: palette.mutedForeground,
                        ),
                        placeholder: Text(
                          state.type == GeoDataType.ip
                              ? 'geoip.dat'
                              : 'geosite.dat',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    field(
                      l.prototypeHttpsDownloadAddress,
                      ShadInput(
                        key: const ValueKey('geodata-source-url'),
                        controller: controller.url,
                        enabled: !state.formBusy,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textDirection: TextDirection.ltr,
                        style: AppTypography.rowValue,
                        placeholderStyle: AppTypography.rowValue.copyWith(
                          color: palette.mutedForeground,
                        ),
                        placeholder: const Text(
                          'https://example.com/geoip.dat',
                        ),
                      ),
                    ),
                    if (state.formError != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: SelectableText(
                          state.formError!,
                          style: AppTypography.supporting.copyWith(
                            color: palette.destructive,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            bottomNavigationBar: PageActionBar(
              children: [
                OutlinedButton(
                  onPressed: state.formBusy ? null : cancel,
                  child: Text(l.prototypeCancel),
                ),
                FilledButton(
                  key: const ValueKey('geodata-source-add'),
                  onPressed: state.formBusy
                      ? null
                      : () => controller.add(context),
                  child: AppActivityBuilder(
                    builder: (context, activity) => ButtonProgress(
                      busy: activity.downloading || state.formBusy,
                      child: Text(l.prototypeAdd),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
