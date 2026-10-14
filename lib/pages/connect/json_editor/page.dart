import 'dart:async';

import 'package:material_ui/material_ui.dart';
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
  const JsonConfigurationEditorPage({
    super.key,
    this.configurationId,
    this.kind = ConfigurationKind.raw,
  });
  @override
  State<JsonConfigurationEditorPage> createState() =>
      _JsonConfigurationEditorState();
}

class _JsonConfigurationEditorState extends State<JsonConfigurationEditorPage> {
  late final controller = JsonConfigurationEditorController(
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
            final gap = mobile ? 16.0 : 20.0;
            return Scaffold(
              appBar: PageAppBar(
                title: Text(
                  controller.advanced
                      ? l10n.routingAdvancedJson
                      : widget.configurationId == null
                      ? l10n.prototypeAddRawJson
                      : l10n.prototypeEditRawJson,
                ),
                leading: BackButton(
                  onPressed: () => controller.closePage(context),
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
                    mobile ? 14 : AppSpacing.page,
                    mobile ? 12 : AppSpacing.desktopPageTop,
                    mobile ? 14 : AppSpacing.page,
                    mobile ? 12 : AppSpacing.desktopPageBottom,
                  ),
                  child: ResponsiveContent(
                    desktopMaxWidth: 900,
                    child: RoutingCard(
                      padding: EdgeInsets.symmetric(
                        horizontal: mobile ? 12 : 20,
                        vertical: mobile ? 14 : 20,
                      ),
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
                                l10n.prototypeSharingDataSourceLinks(count),
                              ),
                            ),
                          SizedBox(height: gap),
                          Text(
                            l10n.prototypeConfigurationName,
                            style: AppTypography.rawField.copyWith(
                              color: palette.mutedStrong,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 42,
                            child: TextField(
                              controller: controller.name,
                              maxLength: 32,
                              enabled: state.loaded,
                              style: AppTypography.rawField,
                              decoration: InputDecoration(
                                hintText: l10n.prototypeConfigurationName,
                                hintStyle: AppTypography.rawField.copyWith(
                                  color: palette.mutedForeground,
                                ),
                                counterText: '',
                                contentPadding: const EdgeInsets.symmetric(
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
                            style: AppTypography.rawField.copyWith(
                              color: palette.mutedStrong,
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
                                domainSuggestions: state.domainSuggestions,
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
                                        MediaQuery.sizeOf(context).height / 4,
                                  ),
                                  child: SingleChildScrollView(
                                    child: SelectableText(
                                      state.error!,
                                      style: AppTypography.rawNote.copyWith(
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
                  if (widget.configurationId != null && controller.advanced)
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
                      onPressed: () => controller.closePage(context),
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
