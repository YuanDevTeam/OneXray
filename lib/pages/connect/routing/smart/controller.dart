import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/model/xray_json.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/launch/setup/selectors.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/pages/connect/routing/smart/exit_picker_controller.dart';

import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/smart/editor.dart';

typedef OpenDirectRegions = Future<List<String>?> Function(
  BuildContext context,
  List<String> selectedCodes,
);
typedef OpenFinalExit = Future<ServerExitChoice?> Function(
  BuildContext context,
  ServerExitPickerParams params,
);

const _unchangedSmartRoutingValue = Object();

class SmartRoutingEditorState {
  final SmartRoutingEditorDraft? original;
  final SmartRoutingSettings draft;
  final String? finalExitName;
  final String? error;
  final bool busy;

  SmartRoutingEditorState({
    this.original,
    SmartRoutingSettings? draft,
    this.finalExitName,
    this.error,
    this.busy = true,
  }) : draft = draft ?? SmartRoutingSettings();

  SmartRoutingEditorState copyWith({
    SmartRoutingEditorDraft? original,
    SmartRoutingSettings? draft,
    Object? finalExitName = _unchangedSmartRoutingValue,
    Object? error = _unchangedSmartRoutingValue,
    bool? busy,
  }) => SmartRoutingEditorState(
    original: original ?? this.original,
    draft: draft ?? this.draft,
    finalExitName: identical(finalExitName, _unchangedSmartRoutingValue)
        ? this.finalExitName
        : finalExitName as String?,
    error: identical(error, _unchangedSmartRoutingValue)
        ? this.error
        : error as String?,
    busy: busy ?? this.busy,
  );
}

class SmartRoutingEditorController extends PageCubit<SmartRoutingEditorState> {
  final SmartRoutingEditorService service;

  SmartRoutingEditorController({SmartRoutingEditorService? service})
    : service = service ?? SmartRoutingEditorService(),
      super(SmartRoutingEditorState());

  Future<void> load(BuildContext context) async {
    emit(state.copyWith(busy: true, error: null));
    try {
      final value = await service.load();
      if (!isPageActive) return;
      emit(
        SmartRoutingEditorState(
          original: value,
          draft: value.configuration.connection.smart,
          finalExitName: value.finalExitName,
          busy: false,
        ),
      );
    } catch (error) {
      if (context.mounted) {
        emit(
          state.copyWith(
            error: AppLocalizations.of(context)!
                .prototypeTemporarilyUnavailable,
          ),
        );
      }
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  void update(String key, Object? value) {
    if (state.original == null || state.busy) return;
    emit(
      state.copyWith(
        draft: SmartRoutingSettings.fromJson({
          ...state.draft.toJson(),
          key: value,
        }),
        error: null,
      ),
    );
  }

  List<XrayRoutingRule> rulesFor(String action) => state.original == null
      ? []
      : ConnectionCompiler.smartRules(
          state.draft,
          state.original!.regions,
        ).where((rule) => rule.outboundTag == action).toList();

  String directPreview(AppLocalizations l) {
    if (state.original == null) return l.prototypeNone;
    final regions = state.original!.regions.regionCodes;
    final labels = <String>{
      if (state.draft.directPrivate) l.prototypeLocalNetworkPrivateAddresses,
      if (state.draft.directApple) l.prototypeAppleServices,
      if (state.draft.directWindows) l.windowsServices,
      for (final code in state.draft.directRegions)
        if (regions.contains(code.toUpperCase()))
          setupRegionLabel(l, code.toUpperCase()),
    };
    return labels.isEmpty ? l.prototypeNone : labels.join(' / ');
  }

  String blockPreview(AppLocalizations l) =>
      rulesFor('block').isEmpty ? l.prototypeNone : l.prototypeCommonAdDomains;

  String regionsSummary(AppLocalizations l) {
    final names = state.draft.directRegions
        .map((code) => setupRegionLabel(l, code))
        .toList();
    if (names.isEmpty) return l.prototypeNoDirectRegions;
    if (names.length <= 2) return names.join(' · ');
    return l.prototypeMoreRegions(names.first, names.length - 1);
  }

  int get effectiveEntryCount =>
      state.original?.configuration.connection.selection.kind ==
          SelectionKind.server
      ? 1
      : state.draft.entryCount;

  String vpnPath(AppLocalizations l) {
    final selection = state.original!.configuration.connection.selection;
    final entry = switch (selection.kind) {
      SelectionKind.automatic => l.prototypeAutomaticEntries(
        effectiveEntryCount,
      ),
      SelectionKind.source =>
        '${state.original!.selectionName ?? l.prototypeTemporarilyUnavailable} · ${l.prototypeUseEntryServers(effectiveEntryCount)}',
      SelectionKind.server =>
        state.original!.selectionName ?? l.prototypeTemporarilyUnavailable,
    };
    return state.draft.finalExitId == null
        ? entry
        : '$entry → ${state.finalExitName ?? l.prototypeTemporarilyUnavailable}';
  }

  Future<void> chooseRegions(
    BuildContext context,
    OpenDirectRegions open,
  ) async {
    if (state.busy) return;
    final selected = await open(context, List.of(state.draft.directRegions));
    if (!isPageActive || selected == null) return;
    try {
      final regions = await service.regions();
      if (!isPageActive) return;
      final previous = state.original!;
      final original = SmartRoutingEditorDraft(
        configuration: previous.configuration,
        regions: regions,
        selectionName: previous.selectionName,
        finalExitName: previous.finalExitName,
      );
      emit(
        state.copyWith(
          original: original,
          draft: SmartRoutingSettings.fromJson({
            ...state.draft.toJson(),
            'directRegions': selected,
          }),
          error: null,
        ),
      );
    } catch (error) {
      if (context.mounted) {
        emit(
          state.copyWith(
            error: AppLocalizations.of(context)!
                .prototypeTemporarilyUnavailable,
          ),
        );
      }
    }
  }

  Future<void> chooseFinalExit(BuildContext context, OpenFinalExit open) async {
    if (state.busy || state.original == null) return;
    final selection = state.original!.configuration.connection.selection;
    final choice = await open(
      context,
      ServerExitPickerParams(
        selectedId: state.draft.finalExitId,
        excludedIds: {
          if (selection.kind == SelectionKind.server) selection.id!,
        },
      ),
    );
    if (!isPageActive || choice == null) return;
    try {
      final name = await service.serverName(choice.id);
      if (!isPageActive) return;
      if (choice.id != null && name == null) {
        throw const FormatException('Final exit is missing');
      }
      emit(
        state.copyWith(
          finalExitName: name,
          draft: SmartRoutingSettings.fromJson({
            ...state.draft.toJson(),
            'finalExitId': choice.id,
          }),
          error: null,
        ),
      );
    } catch (error) {
      if (context.mounted) {
        emit(
          state.copyWith(
            error: AppLocalizations.of(context)!
                .prototypeTemporarilyUnavailable,
          ),
        );
      }
    }
  }

  Future<void> save(BuildContext context) async {
    if (state.busy || state.original == null) return;
    final l = AppLocalizations.of(context)!;
    emit(state.copyWith(busy: true, error: null));
    try {
      final saved = await service.save(
        original: state.original!.configuration,
        smart: state.draft,
        confirmReconnect: () => context.mounted
            ? showApplyAndReconnectDialog(
                context,
                label: l.prototypeSmartRouting,
              )
            : Future.value(false),
      );
      if (saved &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        ContextAlert.showToast(context, l.prototypeSettingsSaved);
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      emit(
        state.copyWith(
          error: appFailureMessage(l, error, operation: l.buttonSaveFailed),
        ),
      );
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  void cancel(BuildContext context) {
    Navigator.of(context).pop();
  }
}
