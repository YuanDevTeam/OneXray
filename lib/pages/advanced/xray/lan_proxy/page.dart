import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/advanced/xray/lan_proxy/controller.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';

class LanProxyPage extends StatelessWidget {
  const LanProxyPage({super.key, this.createController});

  final LanProxyController Function()? createController;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) {
      final controller = createController?.call() ?? LanProxyController();
      if (controller.draft == null) controller.load(context);
      return controller;
    },
    child: BlocBuilder<LanProxyController, PolicyEditorPageState>(
      builder: (context, state) {
        final controller = context.read<LanProxyController>();
        final l = AppLocalizations.of(context)!;
        final palette = ColorManager.palette(context);
        final width = MediaQuery.sizeOf(context).width;
        final mobile = width <= AppLayout.mobileBreakpoint;
        final gutter = mobile ? 14.0 : AppSpacing.advancedDesktopGutter(width);
        return PolicyDetailScaffold(
          title: l.lanProxyTitle,
          help: [
            l.lanProxyProtocolHint,
            l.lanProxyRawJsonNotice,
            l.lanProxyClientHint,
          ],
          controller: controller,
          canSave: state.draft != null,
          contentPadding: EdgeInsets.zero,
          body: state.draft == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: state.busy
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: TextButton(
                            onPressed: () => controller.load(context),
                            child: Text(l.prototypeRetry),
                          ),
                        ),
                )
              : Padding(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    mobile ? 14 : 48,
                    gutter,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: mobile ? 25 : 28,
                    children: [
                      Text(
                        l.lanProxyNextStartNotice,
                        style: AppTypography.settingsDetailNote.copyWith(
                          color: palette.mutedForeground,
                        ),
                      ),
                      SettingSection(
                        title: l.lanProxyTitle,
                        icon: LucideIcons.network,
                        padding: EdgeInsets.zero,
                        dividerIndent: 0,
                        children: [
                          SettingRow(
                            title: l.lanProxyListenAddress,
                            value: '0.0.0.0',
                            valueTextDirection: TextDirection.ltr,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 9,
                              children: [
                                Text(
                                  l.lanProxyPort,
                                  style: AppTypography.settingsInput,
                                ),
                                TextField(
                                  key: const ValueKey('lan-proxy-port'),
                                  controller: controller.portController,
                                  focusNode: controller.portFocusNode,
                                  enabled: !controller.blocked,
                                  textDirection: TextDirection.ltr,
                                  textAlign: TextAlign.left,
                                  keyboardType: TextInputType.number,
                                  autocorrect: false,
                                  style: AppTypography.settingsInput,
                                  decoration: InputDecoration(
                                    hintText: '11024',
                                    errorText: controller.portError,
                                    errorMaxLines: 3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        l.lanProxySecurityHint,
                        style: AppTypography.settingsDetailNote.copyWith(
                          color: palette.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    ),
  );
}
