import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/core/tools/traffic_format.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';

/// Pending declarations have no published size, timestamp or category page.
class PendingGeoDataRow extends StatelessWidget {
  const PendingGeoDataRow({
    super.key,
    required this.row,
    required this.busy,
    required this.deleting,
    required this.onDownload,
    required this.onDelete,
  });
  final GeoDataData row;
  final bool busy;
  final bool deleting;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingRow(
          title: '${row.name}.dat',
          titleTextDirection: TextDirection.ltr,
          subtitleWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                Uri.tryParse(row.url)?.host ?? '',
                textDirection: TextDirection.ltr,
                style: AppTypography.supporting.copyWith(
                  color: palette.mutedForeground,
                ),
              ),
              Text(
                l.geodataPendingDownload,
                style: AppTypography.supporting.copyWith(
                  color: palette.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onDownload,
                icon: AppActivityBuilder(
                  builder: (context, activity) => activity.downloading
                      ? const ButtonProgressIndicator()
                      : const Icon(LucideIcons.download, size: 16),
                ),
                label: Text(l.prototypeDownload),
              ),
              TextButton.icon(
                onPressed: busy ? null : onDelete,
                icon: deleting
                    ? const ButtonProgressIndicator()
                    : const Icon(LucideIcons.trash2, size: 16),
                label: Text(l.prototypeDelete),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Default and custom datasets share file rows, never a second detail screen
/// embedded in the list. Only custom rows expose their dataset actions.
class GeoDataRows extends StatelessWidget {
  final List<GeoDataFile> files;
  final bool custom;
  final bool busy;
  final Set<int> updating;
  final Set<int> deleting;
  final void Function(GeoDataFile) onOpen;
  final void Function(GeoDataFile) onUpdate;
  final void Function(GeoDataFile) onDelete;
  const GeoDataRows({
    super.key,
    required this.files,
    required this.custom,
    required this.busy,
    this.updating = const {},
    this.deleting = const {},
    required this.onOpen,
    required this.onUpdate,
    required this.onDelete,
  });

  bool _busy(GeoDataFile file) =>
      busy || updating.contains(file.row.id) || deleting.contains(file.row.id);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final file in files) _resourceRow(context, file)],
  );

  Widget _resourceRow(BuildContext context, GeoDataFile file) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Semantics(
      container: true,
      label: file.builtIn
          ? l.prototypeDefaultRoutingData
          : l.prototypeCustomRuleDataset(file.row.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingRow(
            title: file.fileName,
            titleTextDirection: TextDirection.ltr,
            onTap: () => onOpen(file),
            showChevron: true,
            subtitleWidget: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Semantics(
                  label: l.prototypeSource,
                  child: Text(
                    file.sourceHost,
                    textDirection: TextDirection.ltr,
                    style: AppTypography.supporting.copyWith(
                      color: palette.mutedForeground,
                    ),
                  ),
                ),
                Semantics(
                  label: l.prototypeSize,
                  child: Text(
                    file.bytes == null ? '—' : formatTraffic(file.bytes!),
                    textDirection: TextDirection.ltr,
                    style: AppTypography.supporting.copyWith(
                      color: palette.mutedForeground,
                    ),
                  ),
                ),
                Semantics(
                  label: l.prototypeLastSuccessfulUpdate,
                  child: Text(
                    DateFormat.yMd(Localizations.localeOf(context).toString())
                        .add_Hm()
                        .format(file.row.timestamp.toLocal()),
                    style: AppTypography.supporting.copyWith(
                      color: palette.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (custom)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _actions(context, file),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, GeoDataFile file) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: Size(
              0,
              MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint
                  ? 48
                  : 42,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            textStyle: AppTypography.geodataDesktopAction,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _busy(file) ? null : () => onUpdate(file),
          child: AppActivityBuilder(
            builder: (context, activity) => ButtonProgress(
              busy:
                  activity.downloading &&
                  (busy || updating.contains(file.row.id)),
              child: Text(
                l.prototypeUpdate,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: l.prototypeDeleteCustomDataset,
          style: IconButton.styleFrom(
            foregroundColor: palette.destructive,
            minimumSize: Size.square(
              AppLayout.touchExtent(40, platform: Theme.of(context).platform),
            ),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _busy(file) ? null : () => onDelete(file),
          icon: deleting.contains(file.row.id)
              ? const ButtonProgressIndicator()
              : const Icon(LucideIcons.trash2, size: 16),
        ),
      ],
    );
  }
}
