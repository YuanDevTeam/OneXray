import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SetupInterfaceParams {
  final List<OutboundInterfaceOption> interfaces;
  final String selected;
  const SetupInterfaceParams(this.interfaces, this.selected);
}

String setupRegionLabel(AppLocalizations l10n, String code) =>
    l10n.countryRegionName(code.toUpperCase());

class SetupInterfacePage extends StatelessWidget {
  final SetupInterfaceParams params;
  const SetupInterfacePage({super.key, required this.params});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _SetupSelector(
      title: l10n.prototypeXrayOutboundInterface,
      selected: params.selected,
      choices: [
        for (final item in params.interfaces)
          _Choice(
            item.name,
            item.name,
            [
              if (item.currentInternet) l10n.prototypeCurrentInternetInterface,
              ...item.addresses,
            ].join(' · '),
          ),
      ],
    );
  }
}

class _Choice {
  final String id;
  final String label;
  final String description;
  const _Choice(this.id, this.label, this.description);
}

class _ChoiceState {
  final String selected;
  final List<_Choice> choices;
  const _ChoiceState(this.selected, this.choices);
}

class _ChoiceController extends PageCubit<_ChoiceState> {
  _ChoiceController(List<_Choice> choices, String selected)
    : super(_ChoiceState(selected, choices));

  void select(BuildContext context, String id) {
    context.pop(id);
  }

  void cancel(BuildContext context) => context.pop();
}

class _SetupSelector extends StatelessWidget {
  final String title;
  final String selected;
  final List<_Choice> choices;
  const _SetupSelector({
    required this.title,
    required this.selected,
    required this.choices,
  });

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => _ChoiceController(choices, selected),
    child: BlocBuilder<_ChoiceController, _ChoiceState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        final controller = context.read<_ChoiceController>();
        final palette = ColorManager.palette(context);
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        return Scaffold(
          appBar: PageAppBar(
            leading: IconButton(
              tooltip: l10n.prototypeBack,
              onPressed: () => controller.cancel(context),
              icon: const Icon(LucideIcons.arrowLeftDir),
            ),
            title: Text(title),
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: ResponsiveContent(
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      mobile ? AppSpacing.mobilePage : AppSpacing.page,
                      16,
                      mobile ? AppSpacing.mobilePage : AppSpacing.page,
                      24,
                    ),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        if (state.choices.isEmpty)
                          SliverToBoxAdapter(
                            child: Text(
                              l10n.prototypeTemporarilyUnavailable,
                              style: AppTypography.supporting.copyWith(
                                color: palette.mutedForeground,
                              ),
                            ),
                          )
                        else
                          SliverList.builder(
                            itemCount: state.choices.length,
                            itemBuilder: (context, index) =>
                                _choice(context, index, state, controller),
                          ),
                      ],
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
                child: Text(l10n.prototypeBack),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _choice(
    BuildContext context,
    int index,
    _ChoiceState state,
    _ChoiceController controller,
  ) {
    final palette = ColorManager.palette(context);
    final choice = state.choices[index];
    final isSelected = state.selected == choice.id;
    final radius = BorderRadius.vertical(
      top: index == 0 ? const Radius.circular(AppRadii.card) : Radius.zero,
      bottom: index == state.choices.length - 1
          ? const Radius.circular(AppRadii.card)
          : Radius.zero,
    );
    return Semantics(
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: isSelected ? palette.selectedSurface : palette.card,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => controller.select(context, choice.id),
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border(
                left: BorderSide(color: palette.border),
                right: BorderSide(color: palette.border),
                bottom: BorderSide(color: palette.border),
                top: index == 0
                    ? BorderSide(color: palette.border)
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                ShadRadioGroup<String>(
                  initialValue: state.selected,
                  onChanged: (value) {
                    if (value != null && value != state.selected) {
                      controller.select(context, value);
                    }
                  },
                  items: [
                    ShadRadio<String>(
                      value: choice.id,
                      size: 16,
                      circleSize: 10,
                      radioPadding: EdgeInsets.zero,
                      decoration: ShadDecoration(
                        border: ShadBorder.all(
                          color: isSelected
                              ? palette.primary
                              : palette.borderStrong,
                          width: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        choice.label,
                        style: AppTypography.setupSelectorTitle,
                      ),
                      if (choice.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          choice.description,
                          style: AppTypography.setupSelectorDetail.copyWith(
                            color: palette.mutedForeground,
                          ),
                        ),
                      ],
                    ],
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
