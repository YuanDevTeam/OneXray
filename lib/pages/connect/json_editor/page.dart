import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/service/shared/json_editing.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/json_editor/controller.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/configuration_transfer.dart';
import 'package:onexray/pages/shared/widgets/json_editor.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/json_editor_workspace.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';

class JsonConfigurationEditorPage extends StatefulWidget {
  final int? configurationId;
  final ConfigurationKind kind;
  final JsonConfigurationEditorController Function()? createController;
  const JsonConfigurationEditorPage({
    super.key,
    this.configurationId,
    this.kind = ConfigurationKind.raw,
    this.createController,
  });
  @override
  State<JsonConfigurationEditorPage> createState() =>
      _JsonConfigurationEditorState();
}

class _JsonConfigurationEditorState extends State<JsonConfigurationEditorPage> {
  late final controller =
      widget.createController?.call() ??
      JsonConfigurationEditorController(
        configurationId: widget.configurationId,
        kind: widget.kind,
      );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      controller.load(context);
    }
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child:
        BlocBuilder<
          JsonConfigurationEditorController,
          JsonConfigurationEditorState
        >(
          builder: (context, state) {
            final l10n = AppLocalizations.of(context)!;
            final mobile =
                MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
            final canClose =
                !state.closeBlocked &&
                !state.confirmingClose &&
                !state.closeAllowed;
            final delete = widget.configurationId != null && controller.advanced
                ? ShadButton.destructive(
                    enabled: controller.canDelete,
                    onPressed: controller.canDelete
                        ? () => controller.delete(context)
                        : null,
                    child: ButtonProgress(
                      busy: state.deleting,
                      child: Text(l10n.prototypeDelete),
                    ),
                  )
                : null;
            final cancel = ShadButton.outline(
              enabled: canClose,
              onPressed: canClose ? () => controller.closePage(context) : null,
              child: Text(l10n.prototypeCancel),
            );
            final save = ShadButton(
              enabled: controller.canSave,
              onPressed: controller.canSave
                  ? () => controller.save(context)
                  : null,
              child: ButtonProgress(
                busy: state.loaded && state.busy && !state.deleting,
                child: Text(l10n.prototypeSave),
              ),
            );
            return CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    controller.closePage(context),
              },
              child: Focus(
                autofocus: true,
                child: PopScope(
                  canPop: state.canPop,
                  onPopInvokedWithResult: (didPop, result) {
                    if (!didPop) controller.closePage(context);
                  },
                  child: Scaffold(
                    appBar: PageAppBar.forPage(
                      context,
                      title: Text(
                        controller.advanced
                            ? widget.configurationId == null
                                  ? l10n.routingAdvancedCreateTitle
                                  : l10n.routingAdvancedEditTitle
                            : widget.configurationId == null
                            ? l10n.prototypeAddRawJson
                            : l10n.prototypeEditRawJson,
                      ),
                      description: controller.advanced
                          ? l10n.routingAdvancedDescription
                          : null,
                      leading: BackButton(
                        onPressed:
                            state.closeBlocked ||
                                state.confirmingClose ||
                                state.closeAllowed
                            ? null
                            : () => controller.closePage(context),
                      ),
                      actions: [
                        if (!controller.advanced)
                          PageHelpButton(
                            title: l10n.xrayRawPageTitle,
                            messages: [
                              l10n.prototypeRawManagedSettingsNotice,
                              l10n.prototypeRawAdditionalSettingsNotice,
                            ],
                          ),
                      ],
                    ),
                    body: SafeArea(
                      bottom: false,
                      child: JsonEditorWorkspace(
                        header: _workspaceHeader(context, state),
                        editor: AbsorbPointer(
                          absorbing: !state.loaded,
                          child: AppJsonEditor(
                            controller: controller.text,
                            kind: controller.advanced
                                ? JsonEditorKind.advancedRouting
                                : JsonEditorKind.raw,
                            diagnostic:
                                state.diagnostic ??
                                (state.error == null
                                    ? null
                                    : JsonDiagnostic(state.error!)),
                            domainSuggestions: state.domainSuggestions,
                            ipSuggestions: state.ipSuggestions,
                          ),
                        ),
                        footer: _workspaceFooter(context, state),
                      ),
                    ),
                    bottomNavigationBar: PageActionBar(
                      children: [
                        if (mobile && delete != null)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              delete,
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: cancel),
                                  const SizedBox(width: AppSpacing.actionGap),
                                  Expanded(child: save),
                                ],
                              ),
                            ],
                          )
                        else ...[
                          ?delete,
                          cancel,
                          save,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
  );

  Widget _workspaceHeader(
    BuildContext context,
    JsonConfigurationEditorState state,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final nameLabel = controller.advanced
        ? l10n.configurationNameLabel
        : l10n.prototypeConfigurationName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(
          nameLabel,
          style: AppTypography.fieldLabel.copyWith(color: palette.foreground),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppLayout.touchExtent(44)),
          child: Semantics(
            label: nameLabel,
            child: TextField(
              controller: controller.name,
              maxLength: 32,
              enabled: state.loaded,
              style: AppTypography.rowValue,
              decoration: InputDecoration(
                hintText: controller.advanced
                    ? l10n.configurationNameHint
                    : l10n.prototypeConfigurationName,
                hintStyle: AppTypography.rowValue.copyWith(
                  color: palette.mutedForeground,
                ),
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                controller.advanced
                    ? l10n.routingAdvancedCardTitle
                    : l10n.prototypeCompleteXrayConfiguration,
                style: AppTypography.fieldLabel.copyWith(
                  color: palette.foreground,
                ),
              ),
            ),
            if (controller.advanced) ...[
              PageHelpButton(
                title: l10n.routingAdvancedCardTitle,
                messages: [l10n.routingAdvancedNotice],
              ),
              IconButton(
                tooltip: l10n.prototypeDocumentation,
                onPressed: () => controller.openDocumentation(context),
                icon: const Icon(LucideIcons.bookOpen),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _workspaceFooter(
    BuildContext context,
    JsonConfigurationEditorState state,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        ConfigurationTransferTools(
          controller: controller.transfers,
          disabled: state.busy || !state.loaded,
        ),
        if (state.sharingDataCount case final count? when count > 0)
          _RawNote(l10n.prototypeSharingDataSourceLinks(count)),
        if (!state.loaded && state.busy) const LinearProgressIndicator(),
        if (!state.loaded && state.error != null)
          Semantics(
            liveRegion: true,
            child: SelectableText(
              state.error!,
              style: AppTypography.rawNote.copyWith(color: palette.destructive),
            ),
          ),
      ],
    );
  }
}

class _RawNote extends StatelessWidget {
  final String text;
  const _RawNote(this.text);

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.info, size: 16, color: palette.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTypography.rawNote.copyWith(
              color: palette.mutedForeground,
            ),
          ),
        ),
      ],
    );
  }
}
