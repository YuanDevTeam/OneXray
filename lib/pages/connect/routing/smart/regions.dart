import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/l10n/localizations/app_localizations_en.dart';
import 'package:onexray/pages/launch/setup/selectors.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/service/connect/routing/custom/geodata_suggestions.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DirectRegionsState {
  final List<String> codes;
  final Set<String> selected;
  final String query;
  final bool busy;
  final bool failed;

  DirectRegionsState({
    Iterable<String> codes = const [],
    Iterable<String> selected = const [],
    this.query = '',
    this.busy = true,
    this.failed = false,
  }) : codes = List.unmodifiable(codes),
       selected = Set.unmodifiable(selected.take(1));

  DirectRegionsState copyWith({
    Iterable<String>? codes,
    Iterable<String>? selected,
    String? query,
    bool? busy,
    bool? failed,
  }) => DirectRegionsState(
    codes: codes ?? this.codes,
    selected: selected ?? this.selected,
    query: query ?? this.query,
    busy: busy ?? this.busy,
    failed: failed ?? this.failed,
  );
}

class DirectRegionsController extends PageCubit<DirectRegionsState> {
  final Future<RegionCatalog> Function()? loadRegions;

  DirectRegionsController(List<String> selectedCodes, {this.loadRegions})
    : super(DirectRegionsState(selected: selectedCodes));

  List<String> get codes => state.codes;
  Set<String> get selected => state.selected;
  String get query => state.query;
  bool get busy => state.busy;
  bool get failed => state.failed;

  Future<void> load() async {
    emit(state.copyWith(busy: true, failed: false));
    try {
      final regions =
          await (loadRegions?.call() ??
              RoutingGeodataIndex.load().then(
                (index) => index.regionCatalog(),
              ));
      if (!isPageActive) return;
      final codes = regions.regionCodes;
      emit(
        state.copyWith(
          codes: codes,
          selected: state.selected.where(codes.contains),
        ),
      );
    } catch (_) {
      emit(state.copyWith(failed: true));
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  List<String> visibleCodes(AppLocalizations l) {
    final value = state.query.trim().toLowerCase();
    return state.codes
        .where(
          (code) => '$code ${setupRegionLabel(l, code)} ${englishName(code)}'
              .toLowerCase()
              .contains(value),
        )
        .toList();
  }

  String englishName(String code) =>
      setupRegionLabel(AppLocalizationsEn(), code);

  String detail(String code) {
    final name = englishName(code);
    return name == code ? code : '$name · $code';
  }

  void search(String value) {
    emit(state.copyWith(query: value));
  }

  void select(String code) {
    if (!state.codes.contains(code)) return;
    emit(state.copyWith(selected: [code]));
  }

  void clear() => emit(state.copyWith(selected: const []));

  void cancel(BuildContext context) => Navigator.of(context).pop();
  void save(BuildContext context) {
    if (!state.busy && !state.failed) {
      Navigator.of(context).pop(state.selected.toList());
    }
  }
}

class DirectRegionsPage extends StatefulWidget {
  final List<String> selectedCodes;
  final Future<RegionCatalog> Function()? loadRegions;
  const DirectRegionsPage({
    super.key,
    required this.selectedCodes,
    this.loadRegions,
  });
  @override
  State<DirectRegionsPage> createState() => _DirectRegionsPageState();
}

class _DirectRegionsPageState extends State<DirectRegionsPage> {
  late final controller = DirectRegionsController(
    widget.selectedCodes,
    loadRegions: widget.loadRegions,
  );
  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<DirectRegionsController, DirectRegionsState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final visible = controller.visibleCodes(l);
        final palette = ColorManager.palette(context);
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        return Scaffold(
          appBar: PageAppBar.forPage(
            context,
            title: Text(l.prototypeDirectRegions),
          ),
          body: SafeArea(
            child: ResponsiveContent(
              desktopMaxWidth:
                  AppLayout.routingEditorMaxWidth + AppSpacing.page * 2,
              child: Semantics(
                label: l.prototypeSupportedRegions,
                child: CustomScrollView(
                  semanticChildCount: visible.length,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        mobile ? AppSpacing.mobilePage : AppSpacing.page,
                        mobile ? 12 : AppSpacing.desktopPageTop,
                        mobile ? AppSpacing.mobilePage : AppSpacing.page,
                        mobile ? 18 : AppSpacing.desktopPageBottom,
                      ),
                      sliver: DecoratedSliver(
                        decoration: BoxDecoration(
                          color: palette.card,
                          border: Border.all(color: palette.border),
                          borderRadius: BorderRadius.circular(AppRadii.card),
                        ),
                        sliver: SliverPadding(
                          padding: const EdgeInsets.all(1),
                          sliver: SliverMainAxisGroup(
                            slivers: [
                              SliverToBoxAdapter(
                                child: _search(context, mobile, state),
                              ),
                              if (state.busy)
                                const SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.all(28),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                )
                              else if (state.failed)
                                SliverToBoxAdapter(
                                  child: Center(
                                    child: TextButton(
                                      onPressed: controller.load,
                                      child: Text(l.prototypeRetry),
                                    ),
                                  ),
                                )
                              else if (visible.isEmpty)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 28,
                                    ),
                                    child: Text(
                                      l.prototypeNoRegionsFound,
                                      style: AppTypography.supporting.copyWith(
                                        color: palette.mutedForeground,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                SliverList.builder(
                                  itemCount: visible.length,
                                  itemBuilder: (context, index) =>
                                      _region(context, visible[index], state),
                                ),
                              SliverToBoxAdapter(child: _note(context, mobile)),
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
          bottomNavigationBar: PageActionBar(
            maxWidth: AppLayout.routingEditorMaxWidth,
            children: [
              OutlinedButton(
                onPressed: () => controller.cancel(context),
                child: Text(l.prototypeCancel),
              ),
              FilledButton(
                onPressed: state.busy || state.failed
                    ? null
                    : () => controller.save(context),
                child: Text(l.prototypeDone),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _search(BuildContext context, bool mobile, DirectRegionsState state) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Column(
      children: [
        Container(
          constraints: BoxConstraints(minHeight: mobile ? 54 : 58),
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 12 : 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.search,
                size: 18,
                color: palette.mutedForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RoutingSearchField(
                  label: l.prototypeSearchDirectRegions,
                  hint: l.prototypeRegionSearch,
                  onChanged: controller.search,
                ),
              ),
            ],
          ),
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 12 : 14,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.prototypeSelectedCount(state.selected.length),
                  style: AppTypography.routingSelectionCount.copyWith(
                    color: palette.mutedStrong,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: state.selected.isEmpty ? null : controller.clear,
                style: TextButton.styleFrom(
                  minimumSize: Size(
                    0,
                    AppLayout.touchExtent(
                      32,
                      platform: Theme.of(context).platform,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: AppTypography.routingSelectionCount,
                ),
                child: Text(l.prototypeClearAll),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _region(BuildContext context, String code, DirectRegionsState state) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final selected = state.selected.contains(code);
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? palette.selectedSurface : palette.card,
        child: InkWell(
          onTap: () => controller.select(code),
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: EdgeInsets.symmetric(
              horizontal: mobile ? 12 : 14,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.surfaceHover,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    code,
                    textDirection: TextDirection.ltr,
                    style: AppTypography.routingRegionCode.copyWith(
                      color: palette.mutedStrong,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        setupRegionLabel(l, code),
                        style: AppTypography.routingSelectionTitle,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        controller.detail(code),
                        textDirection: TextDirection.ltr,
                        style: AppTypography.routingSelectionDescription
                            .copyWith(color: palette.mutedForeground),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 11),
                Icon(
                  selected ? LucideIcons.check : LucideIcons.circle,
                  size: selected ? 19 : 18,
                  color: palette.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _note(BuildContext context, bool mobile) {
    final palette = ColorManager.palette(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.muted,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadii.card - 1),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 17, color: palette.mutedForeground),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.prototypeInstalledRegionsOnly,
              style: AppTypography.routingSelectionNote.copyWith(
                color: palette.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
