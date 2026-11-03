import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class OutboundInterfaceController extends PolicyEditorController {
  final Future<List<OutboundInterfaceOption>> Function()? loadInterfaces;

  OutboundInterfaceController({
    required PolicyEditorDraft draft,
    super.service,
    this.loadInterfaces,
  }) : super(draft: draft);

  List<OutboundInterfaceOption> get interfaces => state.interfaces;
  bool get loading => state.interfacesLoading;
  bool get failed => state.interfacesFailed;

  Future<void> readInterfaces() async {
    emit(
      state.copyWith(
        interfacesLoading: true,
        interfacesFailed: false,
        error: null,
      ),
    );
    try {
      final values =
          await (loadInterfaces?.call() ?? queryXrayOutboundInterfaces());
      emit(state.copyWith(interfaces: values));
    } catch (error) {
      emit(
        state.copyWith(interfacesFailed: true, error: failureDetails(error)),
      );
    } finally {
      emit(state.copyWith(interfacesLoading: false));
    }
  }
}

class OutboundInterfacePage extends StatelessWidget {
  final PolicyEditorDraft draft;
  const OutboundInterfacePage({super.key, required this.draft});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => OutboundInterfaceController(draft: draft)..readInterfaces(),
    child: Builder(
      builder: (context) => OutboundInterfaceView(
        controller: context.read<OutboundInterfaceController>(),
      ),
    ),
  );
}

class OutboundInterfaceView extends StatelessWidget {
  const OutboundInterfaceView({
    super.key,
    required this.controller,
    this.onRetry,
  });

  final OutboundInterfaceController controller;
  final VoidCallback? onRetry;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<OutboundInterfaceController, PolicyEditorPageState>(
    bloc: controller,
    builder: (context, state) {
      final l = AppLocalizations.of(context)!;
      final palette = ColorManager.palette(context);
      final width = MediaQuery.sizeOf(context).width;
      final mobile = width <= AppLayout.mobileBreakpoint;
      final gutter = mobile ? 14.0 : AppSpacing.advancedDesktopGutter(width);
      final selected = controller.value['xrayOutboundInterfaceName'] as String;
      return PolicyDetailScaffold(
        title: l.prototypeXrayOutboundInterface,
        controller: controller,
        canSave:
            !controller.loading && !controller.failed && selected.isNotEmpty,
        contentPadding: EdgeInsets.zero,
        body: Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            mobile ? 16 : 24,
            gutter,
            mobile ? 18 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.prototypeChooseInterface,
                style: AppTypography.platformDetailTitle,
              ),
              Text(
                l.prototypeInterfaceSelectionNotice,
                style: AppTypography.platformDetailBody,
              ),
              SizedBox(height: mobile ? 12 : 14),
              if (controller.loading)
                const Center(child: CircularProgressIndicator())
              else if (controller.failed || controller.interfaces.isEmpty)
                Column(
                  children: [
                    Text(l.prototypeTemporarilyUnavailable),
                    TextButton(
                      onPressed: onRetry ?? controller.readInterfaces,
                      child: Text(l.prototypeRetry),
                    ),
                  ],
                )
              else
                ShadRadioGroup<String>(
                  initialValue: selected,
                  enabled: !controller.blocked,
                  axis: Axis.horizontal,
                  onChanged: (value) {
                    if (value != null && value != selected) {
                      controller.update('xrayOutboundInterfaceName', value);
                    }
                  },
                  items: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: palette.border)),
                      ),
                      child: Column(
                        children: [
                          for (final value in controller.interfaces)
                            _InterfaceRow(
                              value: value,
                              selected: selected == value.name,
                              enabled: !controller.blocked,
                              onTap: () => controller.update(
                                'xrayOutboundInterfaceName',
                                value.name,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              Container(
                constraints: BoxConstraints(minHeight: mobile ? 50 : 49),
                padding: EdgeInsets.symmetric(
                  horizontal: mobile ? 10 : 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.info, size: 16, color: palette.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.prototypeManagedInterfaceNotice,
                        style:
                            (mobile
                                    ? AppTypography.runtimeCodeNote
                                    : AppTypography.runtimeCodeDesktopNote)
                                .copyWith(color: palette.mutedForeground),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _InterfaceRow extends StatelessWidget {
  const _InterfaceRow({
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final OutboundInterfaceOption value;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: selected ? palette.selectedSurface : palette.card,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 68),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.border)),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(5, 4, 3, 0),
                    child: SizedBox.square(
                      dimension: 17,
                      child: ShadRadio<String>(
                        value: value.name,
                        enabled: enabled,
                        size: 15,
                        circleSize: 9,
                        radioPadding: EdgeInsets.zero,
                        decoration: ShadDecoration(
                          border: ShadBorder.all(
                            color: selected
                                ? palette.primary
                                : palette.mutedForeground,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          value.name,
                          style: AppTypography.platformChoiceTitle,
                        ),
                        if (value.currentInternet) ...[
                          const SizedBox(height: 4),
                          Text(
                            l.prototypeCurrentInternetInterface,
                            style: AppTypography.platformChoiceHint.copyWith(
                              color: palette.primary,
                            ),
                          ),
                        ],
                        if (value.addresses.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            value.addresses.join('\n'),
                            textDirection: TextDirection.ltr,
                            style: AppTypography.platformChoiceHint.copyWith(
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
      ),
    );
  }
}
