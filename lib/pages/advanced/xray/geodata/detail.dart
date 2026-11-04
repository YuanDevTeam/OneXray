import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/core/model/geo_dat.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/geodata/controller.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class GeoDataFilePage extends StatefulWidget {
  const GeoDataFilePage({super.key, required this.fileId});
  final int fileId;
  @override
  State<GeoDataFilePage> createState() => _GeoDataFilePageState();
}

class _GeoDataFilePageState extends State<GeoDataFilePage> {
  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => GeoDataFileController(widget.fileId)..initialize(),
    child: BlocBuilder<GeoDataFileController, GeoDataFilePageState>(
      builder: (context, state) {
        final controller = context.read<GeoDataFileController>();
        final l = AppLocalizations.of(context)!;
        final palette = ColorManager.palette(context);
        final file = state.file;
        final codes = state.codes;
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        final gutter = mobile
            ? AppSpacing.mobilePage
            : AppSpacing.advancedDesktopGutter(
                MediaQuery.sizeOf(context).width,
              );
        return Scaffold(
          appBar: PageAppBar.forPage(
            context,
            title: Text(file?.fileName ?? l.prototypeRoutingData),
            description: l.pageXrayConfigurationDescription,
            actions: const [AppActivityIndicator(pinging: false)],
          ),
          body: SafeArea(
            child: ResponsiveContent(
              desktopMaxWidth: AppLayout.advancedMaxWidth,
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : file == null || state.failed
                  ? Center(
                      child: Text(
                        appFailureMessage(
                          l,
                          state.failure,
                          operation: l.prototypeRoutingFileUnavailable,
                        ),
                      ),
                    )
                  : Scrollbar(
                      controller: scroll,
                      child: CustomScrollView(
                        controller: scroll,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                gutter,
                                20,
                                gutter,
                                20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SettingSection(
                                    title: l.serverResourceInformation,
                                    action: Text(
                                      l.prototypeReadOnly,
                                      style: AppTypography.badge.copyWith(
                                        color: palette.mutedForeground,
                                      ),
                                    ),
                                    icon: LucideIcons.globe2,
                                    padding: EdgeInsets.zero,
                                    dividerIndent: 0,
                                    children: [
                                      SettingRow(
                                        title: l.prototypeSourceUrl,
                                        subtitleWidget: SelectableText(
                                          file.row.url,
                                          textDirection: TextDirection.ltr,
                                          style: AppTypography.supporting
                                              .copyWith(
                                                color: palette.mutedForeground,
                                              ),
                                        ),
                                        trailing: _copyButton(
                                          context,
                                          tooltip: l.prototypeCopySourceUrl,
                                          onPressed: () => controller.copy(
                                            context,
                                            file.row.url,
                                            l.prototypeSourceUrlCopied,
                                          ),
                                        ),
                                      ),
                                      SettingRow(
                                        title: l.prototypeDataType,
                                        trailing: Text(
                                          file.row.type == 'ip'
                                              ? 'GeoIP'
                                              : 'GeoSite',
                                          style: AppTypography.rowTitle,
                                        ),
                                      ),
                                      SettingRow(
                                        title: l.prototypeCategories,
                                        trailing: Text(
                                          '${file.index.categoryCount}',
                                          style: AppTypography.rowTitle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              gutter,
                              0,
                              gutter,
                              mobile ? 18 : 28,
                            ),
                            sliver: DecoratedSliver(
                              decoration: BoxDecoration(
                                color: palette.card,
                                border: Border.all(color: palette.border),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.card,
                                ),
                              ),
                              sliver: SliverPadding(
                                padding: const EdgeInsets.all(18),
                                sliver: SliverMainAxisGroup(
                                  slivers: [
                                    SliverToBoxAdapter(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Semantics(
                                            header: true,
                                            child: Text(
                                              l.geodataCategoriesAndReferences,
                                              style: AppTypography.sectionTitle
                                                  .copyWith(
                                                    color: palette.foreground,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Semantics(
                                            label: l.prototypeSearchCategories,
                                            child: ShadInput(
                                              onChanged:
                                                  controller.searchChanged,
                                              gap: 10,
                                              style: AppTypography.geodataBody,
                                              placeholderStyle: AppTypography
                                                  .geodataBody
                                                  .copyWith(
                                                    color:
                                                        palette.mutedForeground,
                                                  ),
                                              placeholder: Text(
                                                l.prototypeSearchCategories,
                                              ),
                                              leading: Icon(
                                                LucideIcons.search,
                                                size: 18,
                                                color: palette.mutedForeground,
                                              ),
                                              decoration: ShadDecoration(
                                                border: ShadBorder.all(
                                                  color: palette.border,
                                                  radius: BorderRadius.circular(
                                                    AppRadii.control,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                        ],
                                      ),
                                    ),
                                    codes.isEmpty
                                        ? SliverToBoxAdapter(
                                            child: Container(
                                              constraints: BoxConstraints(
                                                minHeight: mobile ? 0 : 72,
                                              ),
                                              alignment: mobile
                                                  ? AlignmentDirectional
                                                        .centerStart
                                                  : Alignment.center,
                                              padding: const EdgeInsets.all(18),
                                              child: Text(
                                                l.prototypeNoMatchingCategories,
                                                textAlign: mobile
                                                    ? TextAlign.start
                                                    : TextAlign.center,
                                                style:
                                                    (mobile
                                                            ? AppTypography
                                                                  .geodataEmpty
                                                            : AppTypography
                                                                  .geodataTableBody)
                                                        .copyWith(
                                                          color: palette
                                                              .mutedForeground,
                                                        ),
                                              ),
                                            ),
                                          )
                                        : GeoDataCategorySliver(
                                            file: file,
                                            codes: codes,
                                            onCopy: (reference) =>
                                                controller.copy(
                                                  context,
                                                  reference,
                                                  l.prototypeRuleReferenceCopied,
                                                ),
                                          ),
                                  ],
                                ),
                              ),
                            ),
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

class GeoDataCategorySliver extends StatelessWidget {
  const GeoDataCategorySliver({
    super.key,
    required this.file,
    required this.codes,
    required this.onCopy,
  });

  final PublishedGeoData file;
  final List<XrayGeoListCodes> codes;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) => SliverPrototypeExtentList.builder(
    prototypeItem: _row(context, 0),
    itemCount: codes.length,
    itemBuilder: _row,
  );

  Widget _row(BuildContext context, int index) {
    final l = AppLocalizations.of(context)!;
    final code = codes[index];
    final reference = file.reference(code.code!);
    final palette = ColorManager.palette(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.all(12),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  code.code!,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.geodataCategory,
                ),
                const SizedBox(height: 4),
                Text(
                  reference,
                  textDirection: TextDirection.ltr,
                  style: AppTypography.geodataReference.copyWith(
                    color: palette.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            l.prototypeRuleCount(code.ruleCount!),
            style: AppTypography.geodataValue.copyWith(
              color: palette.mutedForeground,
            ),
            maxLines: 1,
          ),
          _copyButton(
            context,
            tooltip: '${l.prototypeCopyRuleReference}: $reference',
            onPressed: () => onCopy(reference),
          ),
        ],
      ),
    );
  }
}

Widget _copyButton(
  BuildContext context, {
  required String tooltip,
  required VoidCallback onPressed,
}) => IconButton(
  tooltip: tooltip,
  onPressed: onPressed,
  style: IconButton.styleFrom(
    minimumSize: const Size.square(36),
    maximumSize: const Size.square(36),
    padding: EdgeInsets.zero,
    foregroundColor: ColorManager.palette(context).mutedStrong,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ),
  icon: const Icon(LucideIcons.copy, size: 17),
);
