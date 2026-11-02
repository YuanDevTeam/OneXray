import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:onexray/core/tools/json_document.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/core/tools/file.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/share/action.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/service/servers/import.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/shared/share/outgoing_share.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

enum ConfigurationTransferAction { file, clipboard, export }

class ConfigurationTransferState {
  final bool busy;
  final ConfigurationTransferAction? action;
  final String? notice;
  final bool failed;
  final List<GeoDataInput> assets;

  const ConfigurationTransferState({
    this.busy = false,
    this.action,
    this.notice,
    this.failed = false,
    this.assets = const [],
  });

  ConfigurationTransferState copyWith({
    bool? busy,
    ConfigurationTransferAction? action,
    bool clearAction = false,
    String? notice,
    bool? failed,
    bool clearNotice = false,
    List<GeoDataInput>? assets,
  }) => ConfigurationTransferState(
    busy: busy ?? this.busy,
    action: clearAction ? null : action ?? this.action,
    notice: clearNotice ? null : notice ?? this.notice,
    failed: clearNotice ? false : failed ?? this.failed,
    assets: assets ?? this.assets,
  );
}

class ConfigurationTransferController
    extends PageCubit<ConfigurationTransferState> {
  final ConfigurationKind kind;
  final String Function() readText;
  final String Function() readName;
  final bool Function()? hasContent;
  final void Function(ConfigurationImportDraft) onImport;
  final ConfigurationTransferService service;
  ConfigurationImportDraft? _draft;

  ConfigurationTransferController({
    required this.kind,
    required this.readText,
    required this.readName,
    required this.onImport,
    this.hasContent,
    ConfigurationTransferService? service,
  }) : service = service ?? ConfigurationTransferService(),
       super(const ConfigurationTransferState());

  bool get busy => state.busy;
  ConfigurationTransferAction? get action => state.action;
  String? get notice => state.notice;
  ConfigurationImportDraft? get imported => _draft;
  List<GeoDataInput> get assets => state.assets;

  Future<void> import(BuildContext context, {required bool clipboard}) async {
    if (busy) return;
    final l10n = AppLocalizations.of(context)!;
    emit(
      state.copyWith(
        busy: true,
        action: clipboard
            ? ConfigurationTransferAction.clipboard
            : ConfigurationTransferAction.file,
        clearNotice: true,
      ),
    );
    ConfigurationImportDraft? next;
    String? input;
    var parsed = false;
    try {
      input = clipboard
          ? await ServerImportService.readClipboard()
          : await ServerImportService.pickTextFile(jsonOnly: true);
      if (input == null || !context.mounted || !isPageActive) return;
      // Parse before asking to replace anything, and download only after consent.
      final content = ConfigurationTransferService.read(input, kind);
      parsed = true;
      if ((hasContent?.call() ?? readText().trim().isNotEmpty) &&
          !await ContextAlert.showConfirmDialog(
            context,
            title: kind == ConfigurationKind.raw
                ? l10n.prototypeReplaceEditorJson
                : l10n.prototypeReplaceCustomRoute,
            confirmLabel: clipboard
                ? l10n.prototypeReadClipboard
                : l10n.prototypeImportFile,
          )) {
        return;
      }
      if (!context.mounted || !isPageActive) return;
      final previousText = readText();
      final previousName = readName();
      next = await service.prepare(content);
      if (!context.mounted || !isPageActive) return;
      if (previousText != readText() || previousName != readName()) {
        throw const AppFailure(
          FailureCategory.conflict,
          'configurationChanged',
        );
      }
      onImport(next);
      final previous = _draft;
      _draft = next;
      next = null;
      await previous?.dispose();
      emit(
        state.copyWith(
          notice: kind == ConfigurationKind.raw
              ? l10n.prototypeJsonImportedIntoEditor
              : l10n.prototypeCustomImportedIntoEditor,
          assets: _draft?.content.assets ?? const [],
        ),
      );
    } catch (error) {
      // A decoded App Link and a failed dependency download are not positions
      // in the imported text. Only locate syntax in the original JSON source.
      final syntax =
          !parsed && input != null && input.trimLeft().startsWith('{')
          ? JsonDocument(input).syntaxError
          : null;
      final position = syntax?.offset == null
          ? null
          : JsonDocument(input!).positionAt(syntax!.offset!);
      final detail = appFailureMessage(
        l10n,
        error,
        operation: l10n.buttonAddFailed,
      );
      emit(
        state.copyWith(
          failed: true,
          notice: position == null
              ? detail
              : '${l10n.jsonEditorErrorLocation(position.line + 1, position.column + 1)}\n$detail',
        ),
      );
    } finally {
      await next?.dispose();
      if (!isPageActive) await _disposeDraft();
      emit(
        state.copyWith(
          busy: false,
          clearAction: true,
          assets: _draft?.content.assets ?? const [],
        ),
      );
    }
  }

  Future<ShareText> prepareShareText() async {
    final name = readName();
    final text = readText();
    final dependencies = List<GeoDataInput>.of(assets);
    final links = await service.shareLinks(
      kind: kind,
      name: name,
      text: text,
      assets: dependencies,
    );
    return ShareText(title: name, text: links);
  }

  Future<void> exportJson(BuildContext context) async {
    if (busy) return;
    final l10n = AppLocalizations.of(context)!;
    emit(
      state.copyWith(
        busy: true,
        action: ConfigurationTransferAction.export,
        clearNotice: true,
      ),
    );
    try {
      if (!await ContextAlert.showConfirmDialog(
            context,
            title: l10n.prototypeExportJson,
            content: kind == ConfigurationKind.raw
                ? l10n.prototypeRawJsonShareWarning
                : l10n.prototypeCustomShareWarning,
            confirmLabel: l10n.prototypeExportJson,
          ) ||
          !context.mounted ||
          !isPageActive) {
        return;
      }
      final name = readName();
      final text = readText();
      final json = await service.exportJson(
        kind: kind,
        name: name,
        text: text,
        assets: assets,
      );
      if (!isPageActive || !context.mounted) return;
      final basename = name.trim().replaceAll(
        RegExp(r'[\\/:*?"<>|\x00-\x1f]'),
        '_',
      );
      if (await FileTool.saveData(
        Uint8List.fromList(utf8.encode(json)),
        '${basename.isEmpty ? 'xray' : basename}.json',
      )) {
        emit(
          state.copyWith(
            notice: kind == ConfigurationKind.raw
                ? l10n.prototypeOriginalJsonExported
                : l10n.prototypeCustomJsonExported,
          ),
        );
      }
    } catch (error) {
      emit(
        state.copyWith(
          failed: true,
          notice: appFailureMessage(
            l10n,
            error,
            operation: l10n.actionResult(
              l10n.prototypeExportJson,
              l10n.resultFailed,
            ),
          ),
        ),
      );
    } finally {
      if (!isPageActive) await _disposeDraft();
      emit(state.copyWith(busy: false, clearAction: true));
    }
  }

  /// A successful save installed the dependencies. Later edits must use those
  /// files rather than reusing the completed import transaction.
  Future<void> completeImport() async {
    await _disposeDraft();
    emit(state.copyWith(assets: const [], clearNotice: true));
  }

  Future<void> _disposeDraft() async {
    final draft = _draft;
    _draft = null;
    await draft?.dispose();
  }

  @override
  Future<void> disposePageResources() async {
    if (!state.busy) await _disposeDraft();
  }
}

class ConfigurationTransferTools extends StatelessWidget {
  final ConfigurationTransferController controller;
  final bool disabled;
  final List<Widget> children;
  final OutgoingShare? outgoingShare;
  const ConfigurationTransferTools({
    super.key,
    required this.controller,
    this.disabled = false,
    this.children = const [],
    this.outgoingShare,
  });

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ConfigurationTransferController, ConfigurationTransferState>(
        bloc: controller,
        builder: (context, state) {
          final l10n = AppLocalizations.of(context)!;
          final busy = disabled || state.busy;
          final empty = controller.readText().trim().isEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButtonTheme(
                data: OutlinedButtonThemeData(
                  style: Theme.of(context).outlinedButtonTheme.style?.copyWith(
                    minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 10),
                    ),
                    textStyle: WidgetStatePropertyAll(
                      AppTypography.configurationTool,
                    ),
                  ),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => controller.import(context, clipboard: false),
                      icon: AppActivityBuilder(
                        builder: (context, activity) =>
                            activity.downloading ||
                                state.action == ConfigurationTransferAction.file
                            ? const ButtonProgressIndicator()
                            : const Icon(LucideIcons.upload, size: 16),
                      ),
                      label: Text(l10n.prototypeImportFile),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => controller.import(context, clipboard: true),
                      icon: AppActivityBuilder(
                        builder: (context, activity) =>
                            activity.downloading ||
                                state.action ==
                                    ConfigurationTransferAction.clipboard
                            ? const ButtonProgressIndicator()
                            : const Icon(LucideIcons.clipboard, size: 16),
                      ),
                      label: Text(l10n.prototypeReadClipboard),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy || empty
                          ? null
                          : () => controller.exportJson(context),
                      icon: state.action == ConfigurationTransferAction.export
                          ? const ButtonProgressIndicator()
                          : const Icon(LucideIcons.download, size: 16),
                      label: Text(l10n.prototypeExportJson),
                    ),
                    ShareAction(
                      enabled: !busy && !empty,
                      prepare: controller.prepareShareText,
                      warning: controller.kind == ConfigurationKind.raw
                          ? l10n.prototypeRawJsonShareWarning
                          : l10n.prototypeCustomShareWarning,
                      copiedMessage: l10n.prototypeConfigurationLinksCopied,
                      outgoing: outgoingShare,
                      builder: (_, action) => OutlinedButton.icon(
                        onPressed: action.onPressed,
                        icon: action.busy
                            ? const ButtonProgressIndicator()
                            : Icon(action.icon, size: 16),
                        label: Text(action.label),
                      ),
                    ),
                    ...children,
                  ],
                ),
              ),
              if (state.notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          state.notice!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (state.failed)
                          TextButton.icon(
                            onPressed: () async {
                              try {
                                await Clipboard.setData(
                                  ClipboardData(text: state.notice!),
                                );
                                if (context.mounted) {
                                  ContextAlert.showToast(
                                    context,
                                    l10n.actionResult(
                                      l10n.jsonEditorCopyError,
                                      l10n.resultSuccess,
                                    ),
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ContextAlert.showToast(
                                    context,
                                    l10n.prototypeCopyFailed,
                                  );
                                }
                              }
                            },
                            icon: const Icon(LucideIcons.copy, size: 16),
                            label: Text(l10n.jsonEditorCopyError),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );
}
