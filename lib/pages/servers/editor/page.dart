import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/servers/form_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/servers/editor/controller.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/shared/widgets/outbound_json_editor.dart';
import 'package:onexray/pages/shared/widgets/json_editor_workspace.dart';

class ServerEditorPage extends StatelessWidget {
  final int serverId;
  final ServerEditorController Function()? createController;

  const ServerEditorPage({
    super.key,
    required this.serverId,
    this.createController,
  });

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        (createController?.call() ?? ServerEditorController(serverId))
          ..load(context),
    child: BlocBuilder<ServerEditorController, ServerEditorPageState>(
      builder: (context, state) {
        final controller = context.read<ServerEditorController>();
        final l = AppLocalizations.of(context)!;
        final p = ColorManager.palette(context);
        return PopScope(
          canPop: state.canPop,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) controller.closePage(context);
          },
          child: ServerFormPage(
            title: l.prototypeEditServer,
            onClose: () => controller.closePage(context),
            expandBody: true,
            body: JsonEditorWorkspace(
              header: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.name case final name?
                      when name.trim().isNotEmpty) ...[
                    Text(
                      name,
                      style: AppTypography.rowTitle.copyWith(
                        color: p.foreground,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    l.prototypeXrayOutboundJson,
                    style: AppTypography.fieldLabel.copyWith(
                      color: p.foreground,
                    ),
                  ),
                ],
              ),
              editor: OutboundJsonEditor(
                controller: controller.text,
                expand: true,
                diagnostic:
                    state.diagnostic ??
                    (state.error == null ? null : JsonDiagnostic(state.error!)),
              ),
              footer:
                  state.fromSubscription ||
                      (!state.loaded && state.error != null)
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.fromSubscription)
                          Text(
                            l.prototypeSubscriptionOutboundHint,
                            style: AppTypography.importJsonHint.copyWith(
                              color: p.mutedForeground,
                            ),
                          ),
                        if (!state.loaded && state.error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: SelectableText(
                                state.error!,
                                style: AppTypography.subscriptionInfo.copyWith(
                                  color: p.destructive,
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : null,
            ),
            actions: [
              ConnectDialogButton(
                label: l.prototypeCancel,
                secondary: true,
                onPressed:
                    state.busy || state.confirmingClose || state.closeAllowed
                    ? null
                    : () => controller.closePage(context),
              ),
              ConnectDialogButton(
                label: l.prototypeSave,
                busy: state.busy,
                onPressed:
                    state.busy ||
                        state.confirmingClose ||
                        state.closeAllowed ||
                        !state.loaded ||
                        state.jsonText.trim().isEmpty
                    ? null
                    : () => controller.save(context),
              ),
            ],
          ),
        );
      },
    ),
  );
}
