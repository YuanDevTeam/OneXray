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
            subtitle: state.name,
            onClose: () => controller.closePage(context),
            body: ServerFormSection(
              title: l.configurationContentTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.prototypeXrayOutboundJson,
                    style: AppTypography.fieldLabel.copyWith(
                      color: p.foreground,
                    ),
                  ),
                  const SizedBox(height: 7),
                  OutboundJsonEditor(
                    controller: controller.text,
                    diagnostic:
                        state.diagnostic ??
                        (state.error == null
                            ? null
                            : JsonDiagnostic(state.error!)),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    state.fromSubscription
                        ? l.prototypeSubscriptionOutboundHint
                        : l.prototypeOutboundJsonHint,
                    style: AppTypography.importJsonHint.copyWith(
                      color: p.mutedForeground,
                    ),
                  ),
                  if (!state.loaded && state.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height / 4,
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              state.error!,
                              style: AppTypography.subscriptionInfo.copyWith(
                                color: p.destructive,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
