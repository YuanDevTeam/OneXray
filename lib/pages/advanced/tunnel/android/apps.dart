import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/android/app_icon/controller.dart';
import 'package:onexray/pages/advanced/tunnel/android/app_icon/view.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

@immutable
class AndroidAppsPageState {
  final Set<String> selected;
  final List<AndroidAppInfo> apps;
  final bool loading;
  final bool failed;
  final Object? failure;
  final String query;

  AndroidAppsPageState({
    Set<String> selected = const {},
    List<AndroidAppInfo> apps = const [],
    this.loading = true,
    this.failed = false,
    this.failure,
    this.query = '',
  }) : selected = Set<String>.unmodifiable(selected),
       apps = List<AndroidAppInfo>.unmodifiable(apps);

  AndroidAppsPageState copyWith({
    Set<String>? selected,
    List<AndroidAppInfo>? apps,
    bool? loading,
    bool? failed,
    Object? failure,
    String? query,
  }) => AndroidAppsPageState(
    selected: selected ?? this.selected,
    apps: apps ?? this.apps,
    loading: loading ?? this.loading,
    failed: failed ?? this.failed,
    failure: failed == false ? null : failure ?? this.failure,
    query: query ?? this.query,
  );
}

class AndroidAppsController extends PageCubit<AndroidAppsPageState> {
  final Future<List<AndroidAppInfo>> Function() loadApps;
  AndroidAppsController(
    List<String> selected, {
    Future<List<AndroidAppInfo>> Function()? loadApps,
  }) : loadApps = loadApps ?? AppHostApi().getInstalledApps,
       super(AndroidAppsPageState(selected: selected.toSet()));

  Set<String> get selected => state.selected;
  List<AndroidAppInfo> get apps => state.apps;
  bool get loading => state.loading;
  bool get failed => state.failed;
  String get query => state.query;

  Future<void> load() async {
    emit(state.copyWith(loading: true, failed: false));
    try {
      final result = await loadApps();
      // Group once on load so toggling a checkbox does not move its row.
      final ordered = [
        ...result.where((app) => selected.contains(app.packageName)),
        ...result.where((app) => !selected.contains(app.packageName)),
      ];
      emit(state.copyWith(apps: ordered));
    } catch (error) {
      emit(state.copyWith(failed: true, failure: error));
    } finally {
      emit(state.copyWith(loading: false));
    }
  }

  List<AndroidAppInfo> get visible => apps
      .where(
        (app) =>
            app.name.toLowerCase().contains(query) ||
            app.packageName.toLowerCase().contains(query),
      )
      .toList();

  // Keep stored, no-longer-installed IDs visible so the user can remove them.
  List<String> get missing => selected
      .where(
        (id) =>
            !apps.any((app) => app.packageName == id) &&
            id.toLowerCase().contains(query),
      )
      .toList();

  void search(String value) {
    emit(state.copyWith(query: value.trim().toLowerCase()));
  }

  void toggle(String id) {
    final selected = state.selected.toSet();
    if (!selected.remove(id)) {
      selected.add(id);
    }
    emit(state.copyWith(selected: selected));
  }

  void finish(BuildContext context) =>
      Navigator.of(context).pop(selected.toList());
  void cancel(BuildContext context) => Navigator.of(context).pop();
}

class AndroidAppsPage extends StatelessWidget {
  final String mode;
  final List<String> selected;
  const AndroidAppsPage({
    super.key,
    required this.mode,
    required this.selected,
  });
  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => AndroidAppsController(selected)..load()),
      BlocProvider(create: (_) => TunAppIconController()),
    ],
    child: BlocBuilder<AndroidAppsController, AndroidAppsPageState>(
      builder: (context, state) {
        final controller = context.read<AndroidAppsController>();
        final l = AppLocalizations.of(context)!;
        final palette = ColorManager.palette(context);
        final rows = controller.visible;
        final missing = controller.missing;
        return Scaffold(
          appBar: PageAppBar(title: Text(l.prototypeSelectApps)),
          body: SafeArea(
            child: ResponsiveContent(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              mode == 'included'
                                  ? l.prototypeChooseAppsUseVpn
                                  : l.prototypeChooseAppsBypassVpn,
                              style: AppTypography.androidTitle,
                            ),
                          ),
                          Text(
                            l.prototypeSeparateAppListsNotice,
                            style: AppTypography.androidBody,
                          ),
                          const SizedBox(height: 14),
                          Semantics(
                            label: l.prototypeSearchInstalledApps,
                            child: ShadInput(
                              constraints: const BoxConstraints(minHeight: 43),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              gap: 9,
                              style: AppTypography.androidBody,
                              placeholderStyle: AppTypography.androidBody
                                  .copyWith(color: palette.mutedForeground),
                              placeholder: Text(l.prototypeSearchInstalledApps),
                              leading: Icon(
                                LucideIcons.search,
                                size: 18,
                                color: palette.mutedForeground,
                              ),
                              onChanged: controller.search,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              l.prototypeAppsSelectedCount(
                                controller.selected.length,
                              ),
                              style: AppTypography.androidCount.copyWith(
                                color: palette.mutedStrong,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                    sliver: controller.loading || controller.failed
                        ? SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(30),
                              child: Center(
                                child: controller.loading
                                    ? const CircularProgressIndicator()
                                    : Column(
                                        children: [
                                          SelectableText(
                                            appFailureMessage(l, state.failure),
                                          ),
                                          TextButton(
                                            onPressed: controller.load,
                                            child: Text(l.prototypeRetry),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          )
                        : DecoratedSliver(
                            decoration: BoxDecoration(
                              color: palette.card,
                              border: Border.all(color: palette.border),
                              borderRadius: BorderRadius.circular(
                                AppRadii.card,
                              ),
                            ),
                            sliver: SliverPadding(
                              padding: const EdgeInsets.all(1),
                              sliver: rows.isEmpty && missing.isEmpty
                                  ? SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 30,
                                        ),
                                        child: Text(
                                          l.prototypeNoMatchingApps,
                                          textAlign: TextAlign.center,
                                          style: AppTypography.androidEmpty
                                              .copyWith(
                                                color: palette.mutedForeground,
                                              ),
                                        ),
                                      ),
                                    )
                                  : SliverList.builder(
                                      itemCount: rows.length + missing.length,
                                      itemBuilder: (context, index) {
                                        final last =
                                            index ==
                                            rows.length + missing.length - 1;
                                        if (index < missing.length) {
                                          final id = missing[index];
                                          return _AndroidAppRow(
                                            key: ValueKey(id),
                                            name: id,
                                            description: l
                                                .prototypeTemporarilyUnavailable,
                                            icon: Icon(
                                              LucideIcons.package,
                                              color: palette.primary,
                                            ),
                                            selected: true,
                                            last: last,
                                            onTap: () => controller.toggle(id),
                                          );
                                        }
                                        final app =
                                            rows[index - missing.length];
                                        return _AndroidAppRow(
                                          key: ValueKey(app.packageName),
                                          name: app.name,
                                          description: app.packageName,
                                          descriptionDirection:
                                              TextDirection.ltr,
                                          icon: AppIconView(
                                            packageName: app.packageName,
                                          ),
                                          selected: controller.selected
                                              .contains(app.packageName),
                                          last: last,
                                          onTap: () => controller.toggle(
                                            app.packageName,
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: PageActionBar(
            children: [
              OutlinedButton(
                onPressed: () => controller.cancel(context),
                child: Text(l.prototypeCancel),
              ),
              FilledButton(
                onPressed: controller.loading || controller.failed
                    ? null
                    : () => controller.finish(context),
                child: Text(l.prototypeDone),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _AndroidAppRow extends StatelessWidget {
  const _AndroidAppRow({
    super.key,
    required this.name,
    required this.description,
    this.descriptionDirection,
    required this.icon,
    required this.selected,
    required this.last,
    required this.onTap,
  });

  final String name;
  final String description;
  final TextDirection? descriptionDirection;
  final Widget icon;
  final bool selected;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              border: last
                  ? null
                  : Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              spacing: 10,
              children: [
                SizedBox.square(dimension: 34, child: icon),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(name, style: AppTypography.androidRowTitle),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: descriptionDirection,
                        style: AppTypography.androidPackage.copyWith(
                          color: palette.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox.square(
                  dimension: 18,
                  child: Checkbox(
                    value: selected,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (_) => onTap(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
