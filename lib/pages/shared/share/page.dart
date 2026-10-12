import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/shared/share/action.dart';
import 'package:onexray/pages/shared/share/controller.dart';
import 'package:onexray/pages/shared/share/params.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/shared/share/outgoing_share.dart';

class SharePage extends StatelessWidget {
  const SharePage({
    super.key,
    required this.params,
    this.database,
    this.outgoingShare,
  });

  final SharePageParams params;
  final AppDatabase? database;
  final OutgoingShare? outgoingShare;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ShareController(params, database: database),
    child: BlocBuilder<ShareController, SharePageState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final controller = context.read<ShareController>();
        return AppDialog(
          title: params.type == ShareType.subscription
              ? l.prototypeShareSubscription
              : state.supportsOriginal
              ? l.prototypeShareServer
              : l.prototypeShare,
          subtitle: state.name.isEmpty ? null : state.name,
          body: _body(context, state),
          actions: [
            ConnectDialogButton(
              label: l.prototypeCancel,
              secondary: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
            ShareAction(
              enabled: !state.loading && state.selectedLink.isNotEmpty,
              prepare: () => ShareText(
                title: controller.state.name,
                text: controller.state.selectedLink,
              ),
              outgoing: outgoingShare,
              warning: state.supportsOriginal
                  ? null
                  : l.prototypeRawJsonShareWarning,
              builder: (_, action) => ConnectDialogButton(
                label: action.label,
                icon: action.icon,
                busy: action.busy,
                onPressed: action.onPressed,
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _body(BuildContext context, SharePageState state) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final controller = context.read<ShareController>();
    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      borderSide: BorderSide(color: palette.border),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: l.prototypeLinkFormat,
          child: Container(
            margin: const EdgeInsets.fromLTRB(22, 16, 22, 0),
            decoration: BoxDecoration(
              color: palette.card,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 41,
              child: Row(
                children: [
                  for (final format in ShareLinkFormat.values)
                    if (state.supportsOriginal ||
                        format == ShareLinkFormat.onexray)
                      Expanded(
                        child: _formatChoice(
                          context,
                          format,
                          selected: state.format == format,
                          onPressed: () => controller.selectFormat(format),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                params.type == ShareType.subscription
                    ? l.prototypeSubscriptionLink
                    : l.prototypeServerShareLink,
                style: AppTypography.subscriptionField.copyWith(
                  color: palette.mutedStrong,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 92,
                child: TextFormField(
                  key: ValueKey(state.format),
                  initialValue: state.selectedLink,
                  readOnly: true,
                  textDirection: TextDirection.ltr,
                  textAlignVertical: TextAlignVertical.top,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  style: AppTypography.shareLink.copyWith(
                    color: palette.foreground,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: palette.muted,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border.copyWith(
                      borderSide: BorderSide(color: palette.primary),
                    ),
                  ),
                ),
              ),
              if (state.selectedLink.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  state.linkError.isEmpty ? l.resultFailed : state.linkError,
                  style: AppTypography.shareHint.copyWith(
                    color: palette.destructive,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (params.type == ShareType.subscription &&
            state.format == ShareLinkFormat.onexray)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
            child: Text(
              l.prototypeSubscriptionShareAgeHint,
              style: AppTypography.shareHint.copyWith(
                color: palette.mutedForeground,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                button: true,
                toggled: state.qrExpanded,
                child: InkWell(
                  onTap: state.selectedLink.isEmpty
                      ? null
                      : controller.toggleQr,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.qrExpanded &&
                          state.qrCode == null &&
                          state.qrError.isEmpty)
                        const ButtonProgressIndicator(size: 18)
                      else
                        const Icon(LucideIcons.qrCode, size: 18),
                      const SizedBox(width: 8),
                      Text(l.sharePageShowQRCode, style: AppTypography.shareQr),
                    ],
                  ),
                ),
              ),
              if (state.qrExpanded) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: state.qrCode != null
                          ? Image.memory(
                              state.qrCode!,
                              width: 200,
                              height: 200,
                              filterQuality: FilterQuality.none,
                              semanticLabel: l.sharePageQRCode,
                            )
                          : Center(
                              child: state.qrError.isEmpty
                                  ? const SizedBox.shrink()
                                  : Text(
                                      state.qrError,
                                      style: AppTypography.shareHint.copyWith(
                                        color: palette.destructive,
                                      ),
                                    ),
                            ),
                    ),
                  ),
                ),
                ConnectDialogButton(
                  label: l.sharePageSaveQRCode,
                  icon: LucideIcons.download,
                  secondary: true,
                  busy: state.savingQr,
                  onPressed: state.qrCode == null || state.savingQr
                      ? null
                      : () => controller.saveQr(context),
                ),
              ],
            ],
          ),
        ),
        ConnectCallout(
          icon: LucideIcons.circleAlert,
          warning: true,
          text: params.type == ShareType.subscription
              ? l.prototypeSubscriptionShareWarning
              : state.supportsOriginal
              ? l.prototypeServerShareWarning
              : l.prototypeRawJsonShareWarning,
        ),
      ],
    );
  }

  Widget _formatChoice(
    BuildContext context,
    ShareLinkFormat format, {
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected ? palette.selectedSurface : palette.card,
            border: selected
                ? Border.all(color: palette.primary)
                : format == ShareLinkFormat.original
                ? BorderDirectional(end: BorderSide(color: palette.border))
                : null,
          ),
          child: Text(
            format == ShareLinkFormat.original
                ? l.prototypeOriginalLink
                : l.sharePageOneXrayLink,
            textAlign: TextAlign.center,
            style: AppTypography.subscriptionField.copyWith(
              color: selected ? palette.primary : palette.mutedStrong,
            ),
          ),
        ),
      ),
    );
  }
}
