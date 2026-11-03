import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/service/shared/json_editing.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/json_editor/controller.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/configuration_transfer.dart';
import 'package:onexray/pages/shared/widgets/json_editor.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
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
            final palette = ColorManager.palette(context);
            const gap = 16.0;
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
                            ? l10n.routingAdvancedJson
                            : widget.configurationId == null
                            ? l10n.prototypeAddRawJson
                            : l10n.prototypeEditRawJson,
                      ),
                      leading: BackButton(
                        onPressed:
                            state.closeBlocked ||
                                state.confirmingClose ||
                                state.closeAllowed
                            ? null
                            : () => controller.closePage(context),
                      ),
                      actions: [
                        PageHelpButton(
                          title: controller.advanced
                              ? l10n.routingAdvancedJson
                              : l10n.xrayRawPageTitle,
                          messages: controller.advanced
                              ? [l10n.routingAdvancedNotice]
                              : [
                                  l10n.prototypeRawManagedSettingsNotice,
                                  l10n.prototypeRawAdditionalSettingsNotice,
                                ],
                        ),
                      ],
                    ),
                    body: SafeArea(
                      bottom: false,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          mobile ? 16 : AppSpacing.page,
                          16,
                          mobile ? 16 : AppSpacing.page,
                          mobile ? 12 : AppSpacing.desktopPageBottom,
                        ),
                        child: ResponsiveContent(
                          desktopMaxWidth: AppLayout.routingMaxWidth,
                          child: RoutingCard(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ConfigurationTransferTools(
                                  controller: controller.transfers,
                                  disabled: state.busy || !state.loaded,
                                ),
                                if (state.sharingDataCount case final count?
                                    when count > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: _RawNote(
                                      l10n.prototypeSharingDataSourceLinks(
                                        count,
                                      ),
                                    ),
                                  ),
                                SizedBox(height: gap),
                                Text(
                                  l10n.prototypeConfigurationName,
                                  style: AppTypography.fieldLabel.copyWith(
                                    color: palette.foreground,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: AppLayout.touchExtent(44),
                                  ),
                                  child: TextField(
                                    controller: controller.name,
                                    maxLength: 32,
                                    enabled: state.loaded,
                                    style: AppTypography.rowValue,
                                    decoration: InputDecoration(
                                      hintText: l10n.prototypeConfigurationName,
                                      hintStyle: AppTypography.rowValue
                                          .copyWith(
                                            color: palette.mutedForeground,
                                          ),
                                      counterText: '',
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: gap),
                                Text(
                                  controller.advanced
                                      ? l10n.routingAdvancedTemplate
                                      : l10n.prototypeCompleteXrayConfiguration,
                                  style: AppTypography.fieldLabel.copyWith(
                                    color: palette.foreground,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: AppJsonEditor.heightForViewport(
                                    context,
                                    mobile ? 392 : 412,
                                  ),
                                  child: AbsorbPointer(
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
                                      domainSuggestions:
                                          state.domainSuggestions,
                                      ipSuggestions: state.ipSuggestions,
                                    ),
                                  ),
                                ),
                                if (controller.advanced)
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton.icon(
                                      onPressed: () =>
                                          controller.openDocumentation(context),
                                      icon: const Icon(LucideIcons.bookOpen),
                                      label: Text(l10n.prototypeDocumentation),
                                    ),
                                  ),
                                if (!state.loaded && state.busy)
                                  const LinearProgressIndicator(),
                                if (!state.loaded && state.error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxHeight:
                                              MediaQuery.sizeOf(context)
                                                  .height /
                                              4,
                                        ),
                                        child: SingleChildScrollView(
                                          child: SelectableText(
                                            state.error!,
                                            style: AppTypography.rawNote
                                                .copyWith(
                                                  color: palette.destructive,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottomNavigationBar: PageActionBar(
                      children: [
                        if (widget.configurationId != null &&
                            controller.advanced)
                          ShadButton.destructive(
                            enabled: controller.canDelete,
                            onPressed: controller.canDelete
                                ? () => controller.delete(context)
                                : null,
                            child: ButtonProgress(
                              busy: state.deleting,
                              child: Text(l10n.prototypeDelete),
                            ),
                          ),
                        if (!mobile)
                          ShadButton.outline(
                            onPressed:
                                state.closeBlocked ||
                                    state.confirmingClose ||
                                    state.closeAllowed
                                ? null
                                : () => controller.closePage(context),
                            child: Text(l10n.prototypeCancel),
                          ),
                        ShadButton(
                          enabled: controller.canSave,
                          onPressed: controller.canSave
                              ? () => controller.save(context)
                              : null,
                          child: ButtonProgress(
                            busy: state.loaded && state.busy && !state.deleting,
                            child: Text(l10n.prototypeSave),
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
