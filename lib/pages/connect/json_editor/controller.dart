import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/widgets/configuration_transfer.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/service/connect/raw/editor.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/editor.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/geodata_suggestions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:re_editor/re_editor.dart';

const _unchanged = Object();

class JsonConfigurationEditorState {
  final bool loaded;
  final bool busy;
  final bool deleting;
  final String? error;
  final JsonDiagnostic? diagnostic;
  final List<String> domainSuggestions;
  final List<String> ipSuggestions;
  final int? sharingDataCount;
  final String name;
  final String text;
  final String savedName;
  final String savedText;
  final bool confirmingClose;
  final bool closeAllowed;
  final ConfigurationTransferState transfer;

  const JsonConfigurationEditorState({
    this.loaded = false,
    this.busy = true,
    this.deleting = false,
    this.error,
    this.diagnostic,
    this.domainSuggestions = const [],
    this.ipSuggestions = const [],
    this.sharingDataCount,
    this.name = '',
    this.text = '',
    this.savedName = '',
    this.savedText = '',
    this.confirmingClose = false,
    this.closeAllowed = false,
    this.transfer = const ConfigurationTransferState(),
  });

  bool get dirty => name != savedName || text != savedText;
  bool get closeBlocked => (loaded && busy) || transfer.busy;
  bool get canPop =>
      closeAllowed || (!closeBlocked && !confirmingClose && !dirty);

  JsonConfigurationEditorState copyWith({
    bool? loaded,
    bool? busy,
    bool? deleting,
    Object? error = _unchanged,
    Object? diagnostic = _unchanged,
    List<String>? domainSuggestions,
    List<String>? ipSuggestions,
    Object? sharingDataCount = _unchanged,
    String? name,
    String? text,
    String? savedName,
    String? savedText,
    bool? confirmingClose,
    bool? closeAllowed,
    ConfigurationTransferState? transfer,
  }) => JsonConfigurationEditorState(
    loaded: loaded ?? this.loaded,
    busy: busy ?? this.busy,
    deleting: deleting ?? this.deleting,
    error: identical(error, _unchanged) ? this.error : error as String?,
    diagnostic: identical(diagnostic, _unchanged)
        ? this.diagnostic
        : diagnostic as JsonDiagnostic?,
    domainSuggestions: domainSuggestions ?? this.domainSuggestions,
    ipSuggestions: ipSuggestions ?? this.ipSuggestions,
    sharingDataCount: identical(sharingDataCount, _unchanged)
        ? this.sharingDataCount
        : sharingDataCount as int?,
    name: name ?? this.name,
    text: text ?? this.text,
    savedName: savedName ?? this.savedName,
    savedText: savedText ?? this.savedText,
    confirmingClose: confirmingClose ?? this.confirmingClose,
    closeAllowed: closeAllowed ?? this.closeAllowed,
    transfer: transfer ?? this.transfer,
  );
}

class JsonConfigurationEditorController
    extends PageCubit<JsonConfigurationEditorState> {
  final RawEditorService? _rawService;
  final CustomRoutingEditorService? _customService;
  final ConfigurationTransferService? _transferService;
  late final service =
      _rawService ??
      RawEditorService(
        database: _customService?.db,
        coordinator: _customService?.coordinator,
      );
  late final customService =
      _customService ??
      CustomRoutingEditorService(
        database: _rawService?.db,
        coordinator: _rawService?.coordinator,
      );
  final ConfigurationKind kind;
  final int? configurationId;

  JsonConfigurationEditorController({
    required this.configurationId,
    RawEditorService? service,
    CustomRoutingEditorService? customService,
    ConfigurationTransferService? transferService,
    this.kind = ConfigurationKind.raw,
  }) : _rawService = service,
       _customService = customService,
       _transferService = transferService,
       super(const JsonConfigurationEditorState()) {
    text.addListener(_textChanged);
    name.addListener(_nameChanged);
    _transferSubscription = transfers.stream.listen(_transferChanged);
  }

  final name = TextEditingController();
  final text = CodeLineEditingController();
  RawEditorDraft? _draft;
  CustomRoutingEditorDraft? _routingDraft;
  bool get advanced => kind == ConfigurationKind.customAdvanced;
  bool get canDelete =>
      advanced &&
      _routingDraft?.original != null &&
      !working &&
      !state.confirmingClose &&
      !state.closeAllowed;
  bool _saving = false;
  int _textRevision = 0;
  int _draftRevision = 0;
  late final StreamSubscription<ConfigurationTransferState>
  _transferSubscription;
  late final transfers = ConfigurationTransferController(
    kind: kind,
    service: _transferService,
    readText: () => text.text,
    readName: () => name.text,
    onImport: (draft) {
      text.text = draft.text;
      if (name.text.trim().isEmpty && draft.name.isNotEmpty) {
        name.text = draft.name;
      }
      emit(state.copyWith(error: null, diagnostic: null));
    },
  );

  bool get busy => state.busy;
  String? get error => state.error;
  int? get sharingDataCount => state.sharingDataCount;
  bool get working => state.busy || state.transfer.busy;
  bool get loaded => state.loaded;
  bool get canSave =>
      !working &&
      !state.confirmingClose &&
      !state.closeAllowed &&
      loaded &&
      state.text.trim().isNotEmpty &&
      state.name.trim().isNotEmpty;

  void _textChanged() {
    if (!isPageActive || state.text == text.text) return;
    _draftRevision++;
    emit(state.copyWith(text: text.text, error: null, diagnostic: null));
    unawaited(_updateSharingDataCount());
  }

  void _nameChanged() {
    if (isPageActive && state.name != name.text) {
      _draftRevision++;
      emit(state.copyWith(name: name.text, error: null, diagnostic: null));
    }
  }

  void _transferChanged(ConfigurationTransferState transfer) {
    if (!isPageActive) return;
    emit(state.copyWith(transfer: transfer));
    unawaited(_updateSharingDataCount());
  }

  Future<void> _updateSharingDataCount() async {
    final revision = ++_textRevision;
    emit(state.copyWith(sharingDataCount: null));
    try {
      final count = await transfers.service.sharingDataCount(
        state.text,
        assets: transfers.assets,
      );
      if (isPageActive && revision == _textRevision) {
        emit(state.copyWith(sharingDataCount: count));
      }
    } catch (error) {
      // Invalid or unresolved drafts cannot promise data links in a share.
    }
  }

  Future<void> closePage(BuildContext context) async {
    if (!isPageActive ||
        !context.mounted ||
        state.closeBlocked ||
        state.confirmingClose ||
        state.closeAllowed ||
        ModalRoute.of(context)?.isCurrent != true)
      return;
    if (state.dirty) {
      final l = AppLocalizations.of(context)!;
      emit(state.copyWith(confirmingClose: true));
      var discard = false;
      try {
        discard = await AppConfirmationDialog(
          title: l.jsonEditorDiscardTitle,
          content: l.jsonEditorDiscardMessage,
          cancelLabel: l.jsonEditorKeepEditing,
          confirmLabel: l.jsonEditorDiscardChanges,
          destructive: true,
        ).show(context);
      } finally {
        emit(state.copyWith(confirmingClose: false));
      }
      if (!discard || !isPageActive || !context.mounted || state.closeBlocked)
        return;
    }
    _finishClose(context);
  }

  void _finishClose(BuildContext context, {int? result}) {
    if (!isPageActive ||
        !context.mounted ||
        state.closeAllowed ||
        ModalRoute.of(context)?.isCurrent != true)
      return;
    emit(state.copyWith(closeAllowed: true));
    Navigator.of(context).pop(result);
  }

  Future<void> load(BuildContext context) async {
    final initialName = name.text;
    final initialText = text.text;
    try {
      if (advanced) {
        final draft = configurationId == null
            ? CustomRoutingEditorDraft(
                state: AdvancedRoutingDocument.parse(
                  AdvancedRoutingProfile.defaultText,
                ).state,
              )
            : await customService.load(configurationId);
        if (!draft.state.advanced) {
          throw const FormatException('Use the normal routing editor');
        }
        if (!isPageActive) return;
        _routingDraft = draft;
        final loadedText = draft.state.encode();
        emit(
          state.copyWith(savedName: draft.state.name, savedText: loadedText),
        );
        if (name.text == initialName) name.text = draft.state.name;
        if (text.text == initialText) text.text = loadedText;
      } else {
        final draft = await service.load(configurationId);
        if (!isPageActive) return;
        _draft = draft;
        emit(state.copyWith(savedName: draft.name, savedText: draft.text));
        if (name.text == initialName) name.text = draft.name;
        if (text.text == initialText) text.text = draft.text;
      }
    } catch (error) {
      if (context.mounted) {
        emit(
          state.copyWith(
            error: appFailureMessage(AppLocalizations.of(context)!, error),
          ),
        );
      }
    } finally {
      if (isPageActive) {
        emit(
          state.copyWith(
            loaded: _draft != null || _routingDraft != null,
            busy: false,
            name: name.text,
            text: text.text,
          ),
        );
      }
    }
    unawaited(_loadGeodataSuggestions());
  }

  Future<void> _loadGeodataSuggestions() async {
    try {
      if (VpnConstants.datDir.isEmpty) return;
      final index = await RoutingGeodataIndex.load(
        database: advanced ? customService.db : service.db,
        directory: VpnConstants.datDir,
      );
      if (!isPageActive) return;
      emit(
        state.copyWith(
          domainSuggestions: index.suggestions('', domain: true),
          ipSuggestions: index.suggestions('', domain: false),
        ),
      );
    } catch (_) {
      // Missing local indexes disable hints only; saving still uses libXray.
    }
  }

  Future<void> save(BuildContext context) async {
    if (!canSave) return;
    final revision = _draftRevision;
    final submittedText = state.text;
    final submittedName = state.name;
    _saving = true;
    emit(state.copyWith(busy: true, error: null, diagnostic: null));
    final l10n = AppLocalizations.of(context)!;
    try {
      Future<bool> confirmReconnect() => context.mounted
          ? showApplyAndReconnectDialog(context, label: submittedName.trim())
          : Future.value(false);
      int? id;
      if (advanced) {
        final doc = AdvancedRoutingDocument.parse(
          submittedText,
          name: submittedName,
        );
        if (doc.assets.isNotEmpty) {
          throw const FormatException(
            'Use Import to install geodata.assets before saving',
          );
        }
        id = await customService.save(
          CustomRoutingEditorDraft(
            original: _routingDraft!.original,
            state: doc.state,
          ),
          imported: transfers.imported,
          confirmReconnect: confirmReconnect,
        );
      } else {
        id = await service.save(
          RawEditorDraft(
            original: _draft!.original,
            name: submittedName,
            text: submittedText,
          ),
          imported: transfers.imported,
          confirmReconnect: confirmReconnect,
        );
      }
      if (id != null) await transfers.completeImport();
      if (id != null && isPageActive) {
        emit(
          state.copyWith(savedName: submittedName, savedText: submittedText),
        );
      }
      if (id != null &&
          isPageActive &&
          context.mounted &&
          revision == _draftRevision &&
          ModalRoute.of(context)?.isCurrent == true) {
        ContextAlert.showToast(
          context,
          l10n.prototypeNameSaved(submittedName.trim()),
        );
        _finishClose(context, result: id);
      } else if (id != null && isPageActive) {
        // Keep newer edits visible, but advance the saved baseline so a later
        // save updates this row instead of duplicating it or reporting conflict.
        if (advanced) {
          _routingDraft = await customService.load(id);
        } else {
          _draft = await service.load(id);
        }
        if (isPageActive && context.mounted && revision != _draftRevision) {
          ContextAlert.showToast(context, l10n.jsonEditorEarlierDraftSaved);
        }
      }
    } on RawEditorException catch (failure) {
      if (!isPageActive || revision != _draftRevision) return;
      emit(
        state.copyWith(
          diagnostic: JsonDiagnostic.fromError(failure),
          error: switch (failure.reason) {
            'limit' => l10n.prototypeRawJsonLimit,
            'name' => l10n.validationNameRequired,
            'invalid' => l10n.validationJsonInvalid,
            _ => appFailureMessage(
              l10n,
              failure,
              operation: l10n.buttonSaveFailed,
            ),
          },
        ),
      );
    } on CustomRoutingEditorException catch (failure) {
      if (!isPageActive || revision != _draftRevision) return;
      emit(
        state.copyWith(
          diagnostic: JsonDiagnostic.fromError(failure),
          error: switch (failure.reason) {
            'limit' => l10n.prototypeCustomRouteLimit,
            'name' => l10n.prototypeRouteNameRequired,
            'duplicate' => l10n.prototypeRouteNameUnique,
            _ => appFailureMessage(
              l10n,
              failure,
              operation: l10n.buttonSaveFailed,
            ),
          },
        ),
      );
    } catch (error) {
      if (!isPageActive || revision != _draftRevision) return;
      emit(
        state.copyWith(
          diagnostic: JsonDiagnostic.fromError(error),
          error: appFailureMessage(
            l10n,
            error,
            operation: l10n.buttonSaveFailed,
          ),
        ),
      );
    } finally {
      _saving = false;
      if (!isPageActive) await transfers.close();
      emit(state.copyWith(busy: false));
    }
  }

  Future<void> delete(BuildContext context) async {
    if (!canDelete) return;
    final row = _routingDraft!.original!;
    final l10n = AppLocalizations.of(context)!;
    emit(state.copyWith(busy: true, deleting: true, error: null));
    try {
      final deleted = await customService.delete(
        row,
        confirm: (selected, reconnect) => context.mounted
            ? showDestructiveConfirmationDialog(
                context,
                title: l10n.prototypeDeleteName(row.name),
                subtitle: reconnect
                    ? l10n.prototypeDeletingRouteReconnectNotice
                    : selected
                    ? l10n.prototypeDeletedRouteSmartNotice
                    : l10n.prototypeRemoveRouteNotice,
                warning: l10n.prototypeCannotUndo,
                confirmLabel: reconnect
                    ? l10n.prototypeSwitchAndReconnect
                    : selected
                    ? l10n.prototypeDeleteAndUseSmartRouting
                    : l10n.prototypeDeleteRoute,
              )
            : Future.value(false),
      );
      if (deleted && isPageActive && context.mounted) {
        _finishClose(context);
      }
    } catch (error) {
      emit(state.copyWith(error: appFailureMessage(l10n, error)));
    } finally {
      emit(state.copyWith(busy: false, deleting: false));
    }
  }

  Future<void> openDocumentation(BuildContext context) async {
    final language = Localizations.localeOf(context).languageCode;
    final prefix = const {'zh', 'ru'}.contains(language) ? '$language/' : '';
    try {
      if (!await launchUrl(
        Uri.parse(
          'https://onexray.com/${prefix}docs/configuration/advanced-routing/',
        ),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('No application could open this link');
      }
    } catch (error) {
      if (context.mounted) {
        ContextAlert.showToast(
          context,
          appFailureMessage(AppLocalizations.of(context)!, error),
        );
      }
    }
  }

  @override
  Future<void> disposePageResources() async {
    text.removeListener(_textChanged);
    name.removeListener(_nameChanged);
    await _transferSubscription.cancel();
    if (!_saving) await transfers.close();
    name.dispose();
    text.dispose();
  }
}
