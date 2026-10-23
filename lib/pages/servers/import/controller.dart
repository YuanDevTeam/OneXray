import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/servers/import/page.dart';
import 'package:onexray/pages/servers/subscription/format_confirmation.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/service/servers/import.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/servers/subscription/failure.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/subscription/validator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:re_editor/re_editor.dart';

enum ServerImportAction { scan, paste, subscription, file, json }

enum SubscriptionFormField { name, url, userAgent }

@immutable
class ServerImportPageState {
  static const _unset = Object();

  ServerImportPageState({
    this.inputText = '',
    this.jsonInput = '',
    this.name = '',
    this.url = '',
    this.userAgent = '',
    this.secretKey = '',
    this.publicKey = '',
    this.busy = false,
    this.loadingSubscription = false,
    this.openingAction,
    this.activeAction,
    this.generatingAgeKeyType,
    this.obscureSecret = true,
    this.loadFailed = false,
    this.error,
    this.subscriptionFieldProblem,
    Set<SubscriptionFormField> touchedSubscriptionFields = const {},
    this.jsonDiagnostic,
    List<ServerSubscriptionImport> subscriptionImports = const [],
    this.committedResult,
    this.ageExpanded = false,
    this.hasAgeKeys = false,
    this.scannerPickingImage = false,
    this.hwidEnabled = false,
    this.panel = SubscriptionPanel.generic,
    this.mode,
  }) : subscriptionImports = List.unmodifiable(subscriptionImports),
       touchedSubscriptionFields = Set.unmodifiable(touchedSubscriptionFields);

  final String inputText;
  final String jsonInput;
  final String name;
  final String url;
  final String userAgent;
  final String secretKey;
  final String publicKey;
  final bool busy;
  final bool loadingSubscription;
  final ServerImportAction? openingAction;
  final ServerImportAction? activeAction;
  final AgeKeyType? generatingAgeKeyType;
  final bool obscureSecret;
  final bool loadFailed;
  final String? error;
  final SubscriptionUpdateResult? subscriptionFieldProblem;
  final Set<SubscriptionFormField> touchedSubscriptionFields;
  final JsonDiagnostic? jsonDiagnostic;
  final List<ServerSubscriptionImport> subscriptionImports;
  final ServerImportResult? committedResult;
  final bool ageExpanded;
  final bool hasAgeKeys;
  final bool scannerPickingImage;
  final bool hwidEnabled;
  final SubscriptionPanel panel;
  final SubscriptionMode? mode;

  bool get generatingAgeKey => generatingAgeKeyType != null;
  bool get submitting => busy && !loadingSubscription && openingAction == null;
  bool get canClose => !busy || loadingSubscription || openingAction != null;
  bool get incompleteKeys =>
      secretKey.trim().isEmpty != publicKey.trim().isEmpty;
  int get importedSubscriptionCount =>
      subscriptionImports.where((item) => item.result.success).length;
  int get importedSubscriptionNodes => subscriptionImports
      .where((item) => item.result.success)
      .fold(0, (total, item) => total + item.result.count);

  ServerImportPageState copyWith({
    String? inputText,
    String? jsonInput,
    String? name,
    String? url,
    String? userAgent,
    String? secretKey,
    String? publicKey,
    bool? busy,
    bool? loadingSubscription,
    Object? openingAction = _unset,
    Object? activeAction = _unset,
    Object? generatingAgeKeyType = _unset,
    bool? obscureSecret,
    bool? loadFailed,
    Object? error = _unset,
    Object? subscriptionFieldProblem = _unset,
    Set<SubscriptionFormField>? touchedSubscriptionFields,
    Object? jsonDiagnostic = _unset,
    List<ServerSubscriptionImport>? subscriptionImports,
    Object? committedResult = _unset,
    bool? ageExpanded,
    bool? hasAgeKeys,
    bool? scannerPickingImage,
    bool? hwidEnabled,
    SubscriptionPanel? panel,
    Object? mode = _unset,
  }) => ServerImportPageState(
    inputText: inputText ?? this.inputText,
    jsonInput: jsonInput ?? this.jsonInput,
    name: name ?? this.name,
    url: url ?? this.url,
    userAgent: userAgent ?? this.userAgent,
    secretKey: secretKey ?? this.secretKey,
    publicKey: publicKey ?? this.publicKey,
    busy: busy ?? this.busy,
    loadingSubscription: loadingSubscription ?? this.loadingSubscription,
    openingAction: identical(openingAction, _unset)
        ? this.openingAction
        : openingAction as ServerImportAction?,
    activeAction: identical(activeAction, _unset)
        ? this.activeAction
        : activeAction as ServerImportAction?,
    generatingAgeKeyType: identical(generatingAgeKeyType, _unset)
        ? this.generatingAgeKeyType
        : generatingAgeKeyType as AgeKeyType?,
    obscureSecret: obscureSecret ?? this.obscureSecret,
    loadFailed: loadFailed ?? this.loadFailed,
    error: identical(error, _unset) ? this.error : error as String?,
    subscriptionFieldProblem: identical(subscriptionFieldProblem, _unset)
        ? this.subscriptionFieldProblem
        : subscriptionFieldProblem as SubscriptionUpdateResult?,
    touchedSubscriptionFields:
        touchedSubscriptionFields ?? this.touchedSubscriptionFields,
    jsonDiagnostic: identical(jsonDiagnostic, _unset)
        ? this.jsonDiagnostic
        : jsonDiagnostic as JsonDiagnostic?,
    subscriptionImports: subscriptionImports ?? this.subscriptionImports,
    committedResult: identical(committedResult, _unset)
        ? this.committedResult
        : committedResult as ServerImportResult?,
    ageExpanded: ageExpanded ?? this.ageExpanded,
    hasAgeKeys: hasAgeKeys ?? this.hasAgeKeys,
    scannerPickingImage: scannerPickingImage ?? this.scannerPickingImage,
    hwidEnabled: hwidEnabled ?? this.hwidEnabled,
    panel: panel ?? this.panel,
    mode: identical(mode, _unset) ? this.mode : mode as SubscriptionMode?,
  );
}

class ServerImportController extends PageCubit<ServerImportPageState> {
  final ServerImportService service;
  final int? subscriptionId;
  final Future<SubscriptionData?> Function(int) _loadSubscription;
  final Future<SubscriptionUpdateResult> Function(int, SubscriptionInput)
  _saveSubscriptionInput;
  final SubscriptionInsertOperation _insertSubscription;
  final Future<SubscriptionModeAvailability> Function(int) _modeAvailability;
  ServerImportController({
    ServerImportService? service,
    this.subscriptionId,
    Future<SubscriptionData?> Function(int)? loadSubscription,
    Future<SubscriptionUpdateResult> Function(int, SubscriptionInput)?
    saveSubscriptionInput,
    SubscriptionInsertOperation? insertSubscription,
    Future<SubscriptionModeAvailability> Function(int)? modeAvailability,
  }) : service = service ?? ServerImportService(),
       _loadSubscription =
           loadSubscription ?? AppDatabase().subscriptionDao.searchRow,
       _saveSubscriptionInput =
           saveSubscriptionInput ?? SubscriptionService().saveSubscriptionInput,
       _insertSubscription =
           insertSubscription ?? SubscriptionService().insertSubscription,
       _modeAvailability =
           modeAvailability ?? SubscriptionService().modeAvailability,
       super(ServerImportPageState()) {
    jsonText.addListener(_changed);
    for (final field in [text, name, url, userAgent, secretKey, publicKey]) {
      field.addListener(_changed);
    }
    for (final field in SubscriptionFormField.values) {
      final node = subscriptionFocusNode(field);
      var wasFocused = false;
      node.addListener(() {
        if (node.hasFocus) {
          wasFocused = true;
        } else if (wasFocused) {
          wasFocused = false;
          touchSubscriptionField(field);
        }
      });
    }
  }

  final text = TextEditingController();
  final jsonText = CodeLineEditingController();
  final name = TextEditingController();
  final url = TextEditingController();
  final userAgent = TextEditingController();
  final secretKey = TextEditingController();
  final publicKey = TextEditingController();
  final _nameFocus = FocusNode();
  final _urlFocus = FocusNode();
  final _userAgentFocus = FocusNode();
  bool _closingFlow = false;
  bool _previewOpen = false;
  final _completedSubscriptions = <String, ServerSubscriptionImport>{};
  AgeKeyType? _linkAgeType;
  String? _hwid;
  String? _hwidUrl;
  int _jsonRevision = 0;

  bool get supportsScan => AppPlatform.isMobile;
  bool get editingSubscription => subscriptionId != null;
  FocusNode subscriptionFocusNode(SubscriptionFormField field) =>
      switch (field) {
        SubscriptionFormField.name => _nameFocus,
        SubscriptionFormField.url => _urlFocus,
        SubscriptionFormField.userAgent => _userAgentFocus,
      };

  SubscriptionUpdateResult? get _subscriptionValidation =>
      SubscriptionValidator.validate(
        SubscriptionInput(
          name: state.name,
          url: SubscriptionUrl.normalize(state.url),
          userAgent: state.userAgent,
          ageSecretKey: state.secretKey,
          agePublicKey: state.publicKey,
          panel: state.panel,
          mode: state.mode,
        ),
      );

  static SubscriptionFormField? _subscriptionProblemField(
    SubscriptionUpdateResult? problem,
  ) => switch (problem) {
    SubscriptionUpdateResult.nameRequired => SubscriptionFormField.name,
    SubscriptionUpdateResult.urlRequired ||
    SubscriptionUpdateResult.urlInvalid ||
    SubscriptionUpdateResult.duplicateUrl => SubscriptionFormField.url,
    SubscriptionUpdateResult.userAgentInvalid =>
      SubscriptionFormField.userAgent,
    _ => null,
  };

  void touchSubscriptionField(SubscriptionFormField field) {
    if (!isPageActive || state.touchedSubscriptionFields.contains(field))
      return;
    emit(
      state.copyWith(
        touchedSubscriptionFields: {...state.touchedSubscriptionFields, field},
      ),
    );
  }

  String? subscriptionFieldError(
    AppLocalizations l,
    SubscriptionFormField field,
  ) {
    if (!state.touchedSubscriptionFields.contains(field)) return null;
    final savedProblem = state.subscriptionFieldProblem;
    final problem = _subscriptionProblemField(savedProblem) == field
        ? savedProblem
        : _subscriptionValidation;
    return _subscriptionProblemField(problem) == field
        ? subscriptionError(l, problem!)
        : null;
  }

  bool canSubmit(ServerImportAction action) {
    if (state.busy || state.generatingAgeKey || state.loadFailed) return false;
    if (action == ServerImportAction.subscription) {
      return _subscriptionValidation == null;
    }
    return action == ServerImportAction.file ||
        action == ServerImportAction.scan ||
        (action == ServerImportAction.json ? state.jsonInput : state.inputText)
            .trim()
            .isNotEmpty;
  }

  void _changed() {
    final jsonChanged = state.jsonInput != jsonText.text;
    final problemField = _subscriptionProblemField(
      state.subscriptionFieldProblem,
    );
    final problemFieldChanged = switch (problemField) {
      SubscriptionFormField.name => state.name != name.text,
      SubscriptionFormField.url => state.url != url.text,
      SubscriptionFormField.userAgent => state.userAgent != userAgent.text,
      null => false,
    };
    if (jsonChanged) _jsonRevision++;
    var hwidEnabled = state.hwidEnabled;
    if (_hwidUrl != null && !SubscriptionUrl.sameOrigin(_hwidUrl!, url.text)) {
      // A new origin needs consent again, not a new subscription identity.
      _hwidUrl = null;
      hwidEnabled = false;
    }
    final uri = Uri.tryParse(SubscriptionUrl.normalize(url.text));
    if (_hwid != null && uri != null && NetClient.isHttpsDownloadUri(uri)) {
      _hwidUrl ??= url.text;
    }
    final hasAgeKeys =
        secretKey.text.trim().isNotEmpty || publicKey.text.trim().isNotEmpty;
    emit(
      state.copyWith(
        inputText: text.text,
        jsonInput: jsonText.text,
        error: jsonChanged ? null : state.error,
        subscriptionFieldProblem: problemFieldChanged
            ? null
            : state.subscriptionFieldProblem,
        jsonDiagnostic: jsonChanged ? null : state.jsonDiagnostic,
        name: name.text,
        url: url.text,
        userAgent: userAgent.text,
        secretKey: secretKey.text,
        publicKey: publicKey.text,
        hasAgeKeys: hasAgeKeys,
        ageExpanded: state.ageExpanded || (hasAgeKeys && !state.hasAgeKeys),
        hwidEnabled: hwidEnabled,
      ),
    );
  }

  void closePage(BuildContext context) {
    if (!state.canClose) return;
    // A completed preview must not become an editable, repeatable import again.
    if (_previewOpen && state.committedResult != null) {
      closeFlow(context);
    } else {
      Navigator.of(context).pop();
    }
  }

  void closeFlow(BuildContext context) {
    if (!state.canClose) return;
    _closingFlow = true;
    Navigator.of(
      context,
    ).pop(state.committedResult ?? (_previewOpen ? null : _subscriptionResult));
  }

  ServerImportResult? get _subscriptionResult =>
      state.importedSubscriptionCount == 0
      ? null
      : ServerImportResult(
          count: state.importedSubscriptionNodes,
          subscriptionCount: state.importedSubscriptionCount,
        );

  Future<void> loadSubscription(BuildContext context) async {
    final id = subscriptionId;
    if (id == null || state.busy) return;
    final fields = [name, url, userAgent, secretKey, publicKey];
    final initialValues = fields.map((field) => field.text).toList();
    emit(state.copyWith(busy: true, loadingSubscription: true));
    try {
      final row = await _loadSubscription(id);
      if (!isPageActive) return;
      if (row == null) throw StateError('Subscription no longer exists');
      final loadedValues = [
        row.name,
        row.url,
        row.userAgent ?? '',
        row.ageSecretKey ?? '',
        row.agePublicKey ?? '',
      ];
      for (var index = 0; index < fields.length; index++) {
        if (fields[index].text == initialValues[index]) {
          fields[index].text = loadedValues[index];
        }
      }
      final sameOrigin = SubscriptionUrl.sameOrigin(row.url, url.text);
      _hwid = row.hwid;
      final panel =
          SubscriptionPanel.fromString(row.panel) ??
          (throw const FormatException('Unsupported subscription panel'));
      final mode =
          SubscriptionMode.fromString(row.mode) ??
          (throw const FormatException('Unsupported subscription mode'));
      _hwidUrl = sameOrigin ? row.url : null;
      emit(
        state.copyWith(
          hwidEnabled: sameOrigin && row.hwidEnabled,
          panel: panel,
          mode: mode,
        ),
      );
      await _fillDefaultUserAgent();
    } catch (error) {
      if (context.mounted) {
        emit(
          state.copyWith(
            loadFailed: true,
            error: appFailureMessage(
              AppLocalizations.of(context)!,
              error,
              operation: AppLocalizations.of(context)!
                  .prototypeCannotReadContent,
            ),
          ),
        );
      }
    } finally {
      emit(state.copyWith(busy: false, loadingSubscription: false));
    }
  }

  Future<void> open(BuildContext context, ServerImportAction action) async {
    if (state.busy || state.activeAction != null) return;
    _closingFlow = false;
    emit(
      state.copyWith(error: null, committedResult: null, activeAction: action),
    );
    ServerImportResult? result;
    if (action == ServerImportAction.file ||
        action == ServerImportAction.scan) {
      String? input;
      emit(state.copyWith(busy: true, openingAction: action));
      try {
        try {
          input = action == ServerImportAction.file
              ? await ServerImportService.pickTextFile()
              : await _scan(context);
        } finally {
          emit(state.copyWith(busy: false, openingAction: null));
        }
        if (input != null && isPageActive && context.mounted && !_closingFlow) {
          result = await _importText(context, input);
        }
      } catch (error) {
        if (context.mounted) {
          emit(
            state.copyWith(
              error: appFailureMessage(
                AppLocalizations.of(context)!,
                error,
                operation: AppLocalizations.of(context)!
                    .prototypeCannotReadContent,
              ),
            ),
          );
        }
      }
    } else {
      if (action == ServerImportAction.subscription) {
        emit(state.copyWith(busy: true, openingAction: action));
        try {
          await _fillDefaultUserAgent();
        } finally {
          emit(state.copyWith(busy: false, openingAction: null));
        }
        if (!isPageActive || !context.mounted || _closingFlow) return;
      }
      if (action == ServerImportAction.json && jsonText.text.isEmpty) {
        jsonText.text = '{\n  "outbounds": []\n}';
      }
      result = await showAppDialog<ServerImportResult>(
        context,
        (dialogContext) => ServerImportFormPage(
          controller: this,
          action: action,
          onBack: () => closePage(dialogContext),
          onClose: () => closeFlow(dialogContext),
        ),
      );
    }
    emit(state.copyWith(activeAction: null));
    if (!context.mounted) return;
    if (result != null || _closingFlow) {
      Navigator.of(context)
          .pop(result ?? state.committedResult ?? _subscriptionResult);
    }
  }

  Future<void> openText(BuildContext context, String input) async {
    if (state.busy || state.activeAction != null) return;
    _closingFlow = false;
    emit(state.copyWith(activeAction: ServerImportAction.paste));
    try {
      final result = await _importText(context, input);
      if ((result != null || _closingFlow) && context.mounted) {
        Navigator.of(context)
            .pop(result ?? state.committedResult ?? _subscriptionResult);
      }
    } finally {
      emit(state.copyWith(activeAction: null));
    }
  }

  Future<ServerImportResult?> _importText(
    BuildContext context,
    String input,
  ) async {
    final ServerImportDetection detection;
    try {
      detection = service.detect(input);
    } catch (error) {
      if (context.mounted) {
        emit(
          state.copyWith(
            error: appFailureMessage(
              AppLocalizations.of(context)!,
              error,
              operation: AppLocalizations.of(context)!
                  .prototypeCannotReadContent,
            ),
          ),
        );
      }
      return null;
    }
    emit(state.copyWith(committedResult: null));
    if (detection.subscriptions.length == 1 &&
        detection.localText.trim().isEmpty) {
      final link = detection.subscriptions.single;
      emit(
        state.copyWith(
          busy: true,
          openingAction: state.activeAction ?? ServerImportAction.subscription,
          subscriptionImports: const [],
          hwidEnabled: false,
          panel: link.panel,
          mode: link.mode,
        ),
      );
      try {
        _hwid = null;
        _hwidUrl = null;
        name.text = link.name;
        url.text = link.url;
        userAgent.text = link.userAgent ?? '';
        secretKey.clear();
        publicKey.clear();
        _linkAgeType = link.ageKeyType;
        await _fillDefaultUserAgent();
      } finally {
        emit(state.copyWith(busy: false, openingAction: null));
      }
      if (!isPageActive || !context.mounted || _closingFlow) return null;
      return showAppDialog<ServerImportResult>(
        context,
        (dialogContext) => ServerImportFormPage(
          controller: this,
          action: ServerImportAction.subscription,
          onBack: () => closePage(dialogContext),
          onClose: () => closeFlow(dialogContext),
        ),
      );
    }
    emit(
      state.copyWith(busy: true, error: null, subscriptionImports: const []),
    );
    try {
      // Back only reopens the local draft; successful subscriptions are not
      // downloaded and inserted again when Detect is pressed a second time.
      final pending = detection.subscriptions
          .where((link) => !_completedSubscriptions.containsKey(link.url))
          .toList();
      final results = await service.importSubscriptions(
        pending,
        confirmOrdinary: (name) => _confirmOrdinary(context, name),
      );
      for (var index = 0; index < results.length; index++) {
        if (results[index].result.success) {
          _completedSubscriptions[pending[index].url] = results[index];
        }
      }
      emit(
        state.copyWith(
          subscriptionImports: [
            ..._completedSubscriptions.values,
            ...results.where((item) => !item.result.success),
          ],
        ),
      );
    } finally {
      emit(state.copyWith(busy: false));
    }
    if (!context.mounted) return null;
    ServerImportResult? local;
    if (detection.localText.trim().isNotEmpty) {
      local = await _preview(context, () => service.previewDetected(detection));
    }
    if (local == null && state.importedSubscriptionCount == 0) return null;
    final result = ServerImportResult(
      count: state.importedSubscriptionNodes + (local?.count ?? 0),
      rawCount: local?.rawCount ?? 0,
      customCount: local?.customCount ?? 0,
      geoDataCount: local?.geoDataCount ?? 0,
      subscriptionCount: state.importedSubscriptionCount,
      failedGeoData: local?.failedGeoData ?? const [],
    );
    if (detection.localText.trim().isNotEmpty &&
        local == null &&
        !_closingFlow) {
      emit(state.copyWith(committedResult: result));
      return null;
    }
    if (detection.localText.trim().isEmpty) {
      if (state.subscriptionImports.any((item) => !item.result.success)) {
        // Keep failures visible and the original input available for retry.
        // Closing this input still reports subscriptions already imported.
        emit(state.copyWith(committedResult: result));
        return null;
      }
      if (context.mounted) {
        ContextAlert.showToast(
          context,
          AppLocalizations.of(context)!.prototypeUsableNodes(result.count),
        );
      }
    }
    return result;
  }

  Future<String?> _scan(BuildContext context) async {
    if (!supportsScan) return null;
    final permission = await Permission.camera.request();
    if (!context.mounted) return null;
    if (!permission.isGranted) {
      await ContextAlert.showPermissionDialog(context);
      return null;
    }
    var completed = false;
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (scannerContext) => ServerImportScannerPage(
          controller: this,
          onDetect: (capture) {
            final value = capture.barcodes.firstOrNull?.rawValue;
            if (completed || state.scannerPickingImage || value == null) {
              return;
            }
            completed = true;
            Navigator.of(scannerContext).pop(value);
          },
          onPickImage: () async {
            if (completed || state.scannerPickingImage) return;
            emit(state.copyWith(scannerPickingImage: true));
            try {
              final value = await pickQrImage(scannerContext);
              if (completed || value == null || !scannerContext.mounted) return;
              completed = true;
              Navigator.of(scannerContext).pop(value);
            } finally {
              emit(state.copyWith(scannerPickingImage: false));
            }
          },
        ),
      ),
    );
  }

  Future<String?> pickQrImage(BuildContext context) async {
    try {
      return await ServerImportService.pickQrImage();
    } catch (error) {
      if (context.mounted) {
        ContextAlert.showToast(
          context,
          appFailureMessage(
            AppLocalizations.of(context)!,
            error,
            operation: AppLocalizations.of(context)!.prototypeCannotReadContent,
          ),
        );
      }
      return null;
    }
  }

  Future<void> readClipboard(BuildContext context) async {
    try {
      final input = await ServerImportService.readClipboard();
      if (!isPageActive) return;
      if (input == null) throw const FormatException('Empty clipboard');
      text.text = input;
      emit(state.copyWith(error: null));
    } catch (error) {
      if (context.mounted) {
        emit(
          state.copyWith(
            error: appFailureMessage(
              AppLocalizations.of(context)!,
              error,
              operation: AppLocalizations.of(context)!
                  .prototypeCannotReadContent,
            ),
          ),
        );
      }
    }
  }

  Future<void> detect(BuildContext context, ServerImportAction action) async {
    if (state.busy) return;
    final revision = _jsonRevision;
    final result = action == ServerImportAction.json
        ? await _preview(
            context,
            () => service.preview(state.jsonInput, manual: true),
            manual: true,
          )
        : await _importText(context, state.inputText);
    if (action == ServerImportAction.json && revision != _jsonRevision) return;
    if ((result != null || _closingFlow) && context.mounted) {
      Navigator.of(context)
          .pop(result ?? state.committedResult ?? _subscriptionResult);
    }
  }

  Future<ServerImportResult?> _preview(
    BuildContext context,
    Future<ServerImportPreview> Function() prepare, {
    bool manual = false,
  }) async {
    final revision = manual ? _jsonRevision : null;
    emit(
      state.copyWith(
        busy: true,
        error: null,
        jsonDiagnostic: null,
        committedResult: null,
      ),
    );
    ServerImportPreview? preview;
    try {
      preview = await prepare();
      if (!context.mounted) {
        await preview.dispose();
        return null;
      }
      if (!preview.hasItems) {
        final error = AppLocalizations.of(context)!.prototypeNoSupportedLinks;
        await preview.dispose();
        emit(state.copyWith(error: error));
        return null;
      }
      if (preview.rawCount == 0 &&
          preview.customRoutes.isEmpty &&
          preview.geoData.isEmpty) {
        try {
          return await _commit(context, preview, jsonRevision: revision);
        } finally {
          await preview.dispose();
        }
      }
    } catch (error) {
      if (context.mounted && (revision == null || revision == _jsonRevision)) {
        final l10n = AppLocalizations.of(context)!;
        emit(
          state.copyWith(
            jsonDiagnostic: manual ? JsonDiagnostic.fromError(error) : null,
            error: appFailureMessage(
              l10n,
              error,
              operation: l10n.buttonAddFailed,
            ),
          ),
        );
      }
    } finally {
      emit(state.copyWith(busy: false));
    }
    if (preview == null) return null;
    if (!context.mounted) {
      await preview.dispose();
      return null;
    }
    final ready = preview;
    _previewOpen = true;
    try {
      return await showAppDialog<ServerImportResult>(
        context,
        (dialogContext) => ServerImportPreviewPage(
          controller: this,
          preview: ready,
          onBack: () => closePage(dialogContext),
          onClose: () => closeFlow(dialogContext),
        ),
      );
    } finally {
      _previewOpen = false;
      await ready.dispose();
    }
  }

  Future<void> confirm(
    BuildContext context,
    ServerImportPreview preview,
  ) async {
    if (state.busy) return;
    if (state.committedResult != null) {
      Navigator.of(context).pop(state.committedResult);
      return;
    }
    emit(state.copyWith(busy: true, error: null));
    try {
      final result = await _commit(context, preview);
      if (result != null && result.writeFailureCount == 0 && context.mounted) {
        Navigator.of(context).pop(result);
      }
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  Future<ServerImportResult?> _commit(
    BuildContext context,
    ServerImportPreview preview, {
    int? jsonRevision,
  }) async {
    try {
      final result = await service.commit(preview);
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        if (result.writeFailureCount > 0) {
          emit(state.copyWith(committedResult: result));
          return result;
        }
        ContextAlert.showToast(
          context,
          result.count > 0
              ? l10n.prototypeUsableNodes(result.count)
              : result.rawCount > 0
              ? l10n.prototypeNameSaved(
                  preview.raw.map((raw) => raw.name).join(', '),
                )
              : result.customCount > 0
              ? l10n.prototypeNameSaved(
                  preview.customRoutes.map((route) => route.name).join(', '),
                )
              : l10n.prototypeGeodataAdded,
        );
      }
      return result;
    } catch (error) {
      if (context.mounted &&
          (jsonRevision == null || jsonRevision == _jsonRevision)) {
        emit(
          state.copyWith(
            jsonDiagnostic: jsonRevision == null
                ? null
                : JsonDiagnostic.fromError(error),
            error: appFailureMessage(
              AppLocalizations.of(context)!,
              error,
              operation: subscriptionId == null
                  ? AppLocalizations.of(context)!.buttonAddFailed
                  : AppLocalizations.of(context)!.buttonSaveFailed,
            ),
          ),
        );
      }
    }
    return null;
  }

  Future<void> subscribe(BuildContext context) async {
    if (state.busy || state.generatingAgeKey || state.loadFailed) return;
    emit(state.copyWith(busy: true, error: null));
    try {
      if (_linkAgeType != null &&
          secretKey.text.trim().isEmpty &&
          publicKey.text.trim().isEmpty) {
        final pair = await AppHostApi().generateAgeKeyPair(
          keyType: _linkAgeType!,
        );
        if (!isPageActive) return;
        secretKey.text = pair.secretKey ?? '';
        publicKey.text = pair.publicKey ?? '';
        if (secretKey.text.isEmpty || publicKey.text.isEmpty) {
          throw StateError('Missing Age keys');
        }
      }
      final input = SubscriptionInput(
        name: state.name.trim(),
        url: SubscriptionUrl.normalize(state.url),
        userAgent: state.userAgent,
        ageSecretKey: state.secretKey,
        agePublicKey: state.publicKey,
        hwidEnabled: state.hwidEnabled,
        hwid: _hwid,
        panel: state.panel,
        mode: state.mode,
      );
      final problem = SubscriptionValidator.validate(input);
      if (!isPageActive || !context.mounted) return;
      if (problem != null) {
        if (!_showSubscriptionFieldProblem(problem, input)) {
          emit(
            state.copyWith(
              error: subscriptionError(AppLocalizations.of(context)!, problem),
            ),
          );
        }
        return;
      }
      if (subscriptionId != null) {
        final status = await _saveSubscriptionInput(subscriptionId!, input);
        if (!context.mounted) return;
        if (status == SubscriptionUpdateResult.success) {
          final l = AppLocalizations.of(context)!;
          final messages = <String>[l.prototypeSubscriptionSaved];
          try {
            final availability = await _modeAvailability(subscriptionId!);
            if (!availability.hasActiveCache) {
              messages.add(l.subscriptionModeNeedsRefresh);
            }
            if (!availability.selectedCompatible) {
              messages.add(l.subscriptionModeNeedsReselection);
            }
          } catch (error) {
            messages.add(
              appFailureMessage(
                l,
                error,
                operation: l.prototypeCannotReadContent,
              ),
            );
          }
          if (!context.mounted || !isPageActive) return;
          ContextAlert.showToast(context, messages.join('\n'));
          Navigator.of(context).pop(subscriptionId);
        } else {
          if (!_showSubscriptionFieldProblem(status, input)) {
            emit(
              state.copyWith(
                error: subscriptionError(AppLocalizations.of(context)!, status),
              ),
            );
          }
        }
        return;
      }
      final result = await _insertSubscription(
        input,
        confirmOrdinary: (name) => _confirmOrdinary(context, name),
      );
      if (!context.mounted) return;
      if (failureCancelled(result.error)) return;
      final l10n = AppLocalizations.of(context)!;
      if (!result.success) {
        if (!_showSubscriptionFieldProblem(result.status, input)) {
          emit(
            state.copyWith(
              error: subscriptionFailureMessage(
                l10n,
                result.status,
                error: result.error,
              ),
            ),
          );
        }
        return;
      }
      ContextAlert.showToast(context, l10n.prototypeUsableNodes(result.count));
      Navigator.of(context).pop(
        ServerImportResult(count: result.count, subscriptionId: result.subId),
      );
    } catch (error) {
      if (context.mounted) {
        emit(
          state.copyWith(
            error: appFailureMessage(
              AppLocalizations.of(context)!,
              error,
              operation: subscriptionId == null
                  ? AppLocalizations.of(context)!.buttonAddFailed
                  : AppLocalizations.of(context)!.buttonSaveFailed,
            ),
          ),
        );
      }
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  bool _showSubscriptionFieldProblem(
    SubscriptionUpdateResult problem,
    SubscriptionInput submitted,
  ) {
    final field = _subscriptionProblemField(problem);
    if (field == null) return false;
    // Inputs remain editable during requests. A result for the old field value
    // must not mark a newer draft as invalid.
    final unchanged = switch (field) {
      SubscriptionFormField.name => state.name.trim() == submitted.name,
      SubscriptionFormField.url =>
        SubscriptionUrl.normalize(state.url) == submitted.url,
      SubscriptionFormField.userAgent => state.userAgent == submitted.userAgent,
    };
    if (!unchanged) return true;
    emit(
      state.copyWith(
        error: null,
        subscriptionFieldProblem: problem,
        touchedSubscriptionFields: {...state.touchedSubscriptionFields, field},
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isPageActive) return;
      final focus = subscriptionFocusNode(field);
      focus.requestFocus();
      final fieldContext = focus.context;
      if (fieldContext != null && fieldContext.mounted) {
        Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 200),
          alignment: 0.2,
        );
      }
    });
    return true;
  }

  static String subscriptionError(
    AppLocalizations l10n,
    SubscriptionUpdateResult status, {
    Object? error,
  }) => subscriptionFailureMessage(l10n, status, error: error);

  Future<bool> _confirmOrdinary(BuildContext context, String name) async {
    if (!isPageActive) return false;
    final confirmed = await confirmOrdinarySubscription(context, name);
    return isPageActive && confirmed;
  }

  Future<void> setPanel(SubscriptionPanel panel) async {
    if (state.busy || state.loadFailed || state.generatingAgeKey) return;
    emit(state.copyWith(panel: panel));
    await _fillDefaultUserAgent();
  }

  Future<void> _fillDefaultUserAgent() async {
    if (userAgent.text.trim().isNotEmpty) return;
    final client = NetClient();
    await client.asyncInit();
    if (isPageActive && userAgent.text.trim().isEmpty) {
      userAgent.text = client.downloadUserAgent;
    }
  }

  void setMode(SubscriptionMode? mode) {
    if (state.busy || state.loadFailed || state.generatingAgeKey) return;
    if (editingSubscription && mode == null) return;
    emit(state.copyWith(mode: mode));
  }

  void toggleSecret() {
    emit(state.copyWith(obscureSecret: !state.obscureSecret));
  }

  void toggleAgeExpanded() {
    emit(state.copyWith(ageExpanded: !state.ageExpanded));
  }

  void setHwidEnabled(bool enabled) {
    if (state.busy || state.loadFailed) return;
    if (enabled) {
      _hwid ??= SubscriptionService.createHwid();
      final uri = Uri.tryParse(SubscriptionUrl.normalize(url.text));
      if (uri != null && NetClient.isHttpsDownloadUri(uri)) {
        _hwidUrl = url.text;
      }
    }
    emit(state.copyWith(hwidEnabled: enabled));
  }

  void clearKeys() {
    if (state.busy || state.generatingAgeKey) return;
    secretKey.clear();
    publicKey.clear();
  }

  Future<void> generateKeys(BuildContext context, AgeKeyType type) async {
    if (state.busy || state.generatingAgeKey || !isPageActive) return;
    final l10n = AppLocalizations.of(context)!;
    emit(state.copyWith(generatingAgeKeyType: type, error: null));
    try {
      if (secretKey.text.isNotEmpty || publicKey.text.isNotEmpty) {
        if (!await ContextAlert.showConfirmDialog(
              context,
              title: l10n.prototypeReplaceAgeKeys,
              content: l10n.subscriptionReplaceAgeKeyMessage,
              confirmLabel: l10n.subscriptionGenerateAgeKey,
            ) ||
            !isPageActive ||
            !context.mounted) {
          return;
        }
      }
      final pair = await AppHostApi().generateAgeKeyPair(keyType: type);
      if (isPageActive) {
        secretKey.text = pair.secretKey ?? '';
        publicKey.text = pair.publicKey ?? '';
      }
    } catch (error) {
      emit(
        state.copyWith(
          error: appFailureMessage(
            l10n,
            error,
            operation: l10n.subscriptionGenerateAgeKeyFailed,
          ),
        ),
      );
    } finally {
      emit(state.copyWith(generatingAgeKeyType: null));
    }
  }

  @override
  void disposePageResources() {
    for (final field in SubscriptionFormField.values) {
      subscriptionFocusNode(field).dispose();
    }
    jsonText.removeListener(_changed);
    jsonText.dispose();
    for (final controller in [
      text,
      name,
      url,
      userAgent,
      secretKey,
      publicKey,
    ]) {
      controller.removeListener(_changed);
      controller.dispose();
    }
  }
}
