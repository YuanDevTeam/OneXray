import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/apple/widgets.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AppleWifiPage extends StatelessWidget {
  final PolicyEditorDraft draft;
  const AppleWifiPage({super.key, required this.draft});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PolicyEditorController(draft: draft),
    child: BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final controller = context.read<PolicyEditorController>();
        return PolicyDetailScaffold(
          title: l.prototypeWifiRules,
          controller: controller,
          canSave: !controller.wifiConflict,
          contentPadding: EdgeInsets.zero,
          body: AppleWifiView(controller: controller),
        );
      },
    ),
  );
}

class AppleWifiView extends StatelessWidget {
  final PolicyEditorController controller;
  const AppleWifiView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
        bloc: controller,
        builder: (context, state) {
          final l = AppLocalizations.of(context)!;
          final width = MediaQuery.sizeOf(context).width;
          final mobile = width <= AppLayout.mobileBreakpoint;
          final gutter = mobile
              ? AppSpacing.mobilePage
              : AppSpacing.advancedDesktopGutter(width);
          final palette = ColorManager.palette(context);
          const gap = 20.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(gutter, 20, gutter, mobile ? 18 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final connect in [true, false])
                  Padding(
                    padding: EdgeInsets.only(bottom: gap, top: connect ? 0 : 2),
                    child: AppleWifiEditorSection(
                      key: ValueKey(connect),
                      title: connect
                          ? l.prototypeWifiConnectNetworks
                          : l.prototypeWifiDisconnectNetworks,
                      description: connect
                          ? l.prototypeWifiConnectNetworksHint
                          : l.prototypeWifiDisconnectNetworksHint,
                      values: controller.strings(
                        'apple',
                        connect ? 'connectWifiSsids' : 'disconnectWifiSsids',
                      ),
                      otherValues: controller.strings(
                        'apple',
                        connect ? 'disconnectWifiSsids' : 'connectWifiSsids',
                      ),
                      onChanged: (values) => controller.update(
                        connect ? 'connectWifiSsids' : 'disconnectWifiSsids',
                        values,
                        section: 'apple',
                      ),
                      enabled: !controller.blocked,
                    ),
                  ),
                if (controller.wifiConflict)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      l.prototypeWifiActionConflict,
                      style:
                          (mobile
                                  ? AppTypography.appleWifiDescription
                                  : AppTypography.appleWifiDescriptionDesktop)
                              .copyWith(color: palette.destructive),
                    ),
                  )
                else
                  AppleWifiPreview(controller: controller),
                SizedBox(height: gap),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.info,
                      size: 17,
                      color: palette.mutedForeground,
                    ),
                    SizedBox(width: mobile ? 7 : 8),
                    Expanded(
                      child: Text(
                        l.prototypeWifiExactMatchNotice,
                        style:
                            (mobile
                                    ? AppTypography.appleWifiMatchNote
                                    : AppTypography.appleWifiMatchNoteDesktop)
                                .copyWith(color: palette.mutedForeground),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}
