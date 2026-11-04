import 'package:material_ui/material_ui.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/geodata/controller.dart';
import 'package:onexray/pages/advanced/xray/geodata/view.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';

class GeoDataPage extends StatefulWidget {
  const GeoDataPage({super.key, required this.openFile, this.openAdd});
  final void Function(BuildContext, int) openFile;
  final Future<bool?> Function(BuildContext)? openAdd;
  @override
  State<GeoDataPage> createState() => _GeoDataPageState();
}

class _GeoDataPageState extends State<GeoDataPage> {
  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => GeoDataController()..initialize(),
    child: BlocBuilder<GeoDataController, GeoDataPageState>(
      builder: (context, state) {
        final controller = context.read<GeoDataController>();
        final l = AppLocalizations.of(context)!;
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        final palette = ColorManager.palette(context);
        return Scaffold(
          appBar: PageAppBar.forPage(
            context,
            title: Text(l.prototypeRoutingData),
            description: l.prototypeRoutingDataHint,
          ),
          body: SafeArea(
            child: ResponsiveContent(
              desktopMaxWidth: AppLayout.advancedMaxWidth,
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : state.failed
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(appFailureMessage(l, state.failure)),
                          TextButton(
                            onPressed: controller.initialize,
                            child: Text(l.prototypeRetry),
                          ),
                        ],
                      ),
                    )
                  : Scrollbar(
                      controller: scroll,
                      child: ListView(
                        controller: scroll,
                        padding: mobile
                            ? const EdgeInsets.fromLTRB(16, 20, 16, 24)
                            : EdgeInsets.fromLTRB(
                                AppSpacing.advancedDesktopGutter(
                                  MediaQuery.sizeOf(context).width,
                                ),
                                20,
                                AppSpacing.advancedDesktopGutter(
                                  MediaQuery.sizeOf(context).width,
                                ),
                                28,
                              ),
                        children: [
                          SettingSection(
                            title: l.prototypeDefaultRoutingData,
                            padding: EdgeInsets.zero,
                            action: OutlinedButton.icon(
                              style: _headingButtonStyle(context),
                              onPressed: state.fileBusy(-1)
                                  ? null
                                  : () => controller.update(context, null),
                              icon: AppActivityBuilder(
                                builder: (context, activity) =>
                                    activity.downloading
                                    ? const ButtonProgressIndicator()
                                    : const Icon(
                                        LucideIcons.refreshCw,
                                        size: 16,
                                      ),
                              ),
                              label: Text(l.prototypeUpdate),
                            ),
                            children: [
                              GeoDataRows(
                                files: state.defaults,
                                custom: false,
                                busy: state.updatingAll,
                                onOpen: (file) =>
                                    widget.openFile(context, file.row.id),
                                onUpdate: (file) =>
                                    controller.update(context, file.row),
                                onDelete: (file) =>
                                    controller.delete(context, file.row),
                              ),
                              if (state.errors[-1] != null)
                                _error(context, state.errors[-1]!),
                              for (final file in state.defaults)
                                if (file.failure != null)
                                  _error(
                                    context,
                                    '${file.fileName}: ${appFailureMessage(l, file.failure)}',
                                  ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SettingSection(
                            title: l.prototypeCustomRoutingData,
                            padding: EdgeInsets.zero,
                            children: [
                              if (state.custom.isEmpty && state.pending.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    l.prototypeNoCustomRoutingData,
                                    style: AppTypography.supporting.copyWith(
                                      color: palette.mutedForeground,
                                    ),
                                  ),
                                ),
                              if (state.custom.isNotEmpty)
                                GeoDataRows(
                                  files: state.custom,
                                  custom: true,
                                  busy: state.updatingAll,
                                  updating: state.updating,
                                  deleting: state.deleting,
                                  onOpen: (file) =>
                                      widget.openFile(context, file.row.id),
                                  onUpdate: (file) =>
                                      controller.update(context, file.row),
                                  onDelete: (file) =>
                                      controller.delete(context, file.row),
                                ),
                              for (final file in state.custom) ...[
                                if (file.failure != null)
                                  _error(
                                    context,
                                    '${file.fileName}: ${appFailureMessage(l, file.failure)}',
                                  ),
                                if (state.errors[file.row.id] != null)
                                  _error(
                                    context,
                                    '${file.fileName}: ${state.errors[file.row.id]}',
                                  ),
                              ],
                              for (final row in state.pending) ...[
                                PendingGeoDataRow(
                                  row: row,
                                  busy: state.fileBusy(row.id),
                                  deleting: state.deleting.contains(row.id),
                                  onDownload: () =>
                                      controller.update(context, row),
                                  onDelete: () =>
                                      controller.delete(context, row),
                                ),
                                if (state.errors[row.id] != null)
                                  _error(
                                    context,
                                    '${row.name}.dat: ${state.errors[row.id]}',
                                  ),
                              ],
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: _headingButtonStyle(context),
                                  onPressed:
                                      state.formBusy || widget.openAdd == null
                                      ? null
                                      : () => widget.openAdd!(context),
                                  icon: const Icon(LucideIcons.plus, size: 16),
                                  label: Text(l.prototypeAddDataSource),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _updateActions(context, state, controller),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    ),
  );

  Widget _updateActions(
    BuildContext context,
    GeoDataPageState state,
    GeoDataController controller,
  ) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          style: _headingButtonStyle(context),
          onPressed: !state.canUpdateAll
              ? null
              : () => controller.updateAll(context),
          icon: AppActivityBuilder(
            builder: (context, activity) => activity.downloading
                ? const ButtonProgressIndicator(size: 15)
                : const Icon(LucideIcons.refreshCw, size: 15),
          ),
          label: Text(l.prototypeUpdateAll),
        ),
        const SizedBox(height: 5),
        Text(
          l.prototypeHttpsOnly,
          textAlign: TextAlign.start,
          style: AppTypography.geodataValue.copyWith(
            color: palette.mutedForeground,
          ),
        ),
      ],
    );
  }

  ButtonStyle _headingButtonStyle(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return OutlinedButton.styleFrom(
      minimumSize: Size(0, mobile ? 48 : 42),
      padding: EdgeInsets.symmetric(horizontal: mobile ? 9 : 12),
      textStyle: mobile ? AppTypography.geodataAction : null,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _error(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: SelectableText(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.error),
    ),
  );
}
