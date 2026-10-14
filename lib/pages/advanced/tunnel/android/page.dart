import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/advanced/tunnel/android/app_icon.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AndroidVpnPage extends StatefulWidget {
  final PolicyEditorDraft draft;
  final OpenAndroidApps openApps;
  final void Function(BuildContext)? openAutomation;
  const AndroidVpnPage({
    super.key,
    required this.draft,
    required this.openApps,
    this.openAutomation,
  });
  @override
  State<AndroidVpnPage> createState() => _AndroidVpnPageState();
}

class _AndroidVpnPageState extends State<AndroidVpnPage> {
  late final controller = PolicyEditorController(draft: widget.draft)
    ..loadAndroidAppNames();
  @override
  void dispose() {
    unawaited(controller.close());
    AppIconService().clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final palette = ColorManager.palette(context);
        final mode = controller.group('android')['appScope'] as String;
        final included = mode == 'included';
        final names = controller.strings(
          'android',
          included ? 'includedAppPackageNames' : 'excludedAppPackageNames',
        );
        return PolicyDetailScaffold(
          title: l.prototypeAndroidSystemVpn,
          controller: controller,
          contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l.prototypeVpnAppScope,
                  style: AppTypography.androidTitle,
                ),
              ),
              Text(
                l.prototypeChooseAndroidApps,
                style: AppTypography.androidBody,
              ),
              const SizedBox(height: 12),
              ShadRadioGroup<String>(
                axis: Axis.horizontal,
                initialValue: mode,
                enabled: !controller.blocked,
                onChanged: (value) {
                  if (value != null) {
                    controller.update('appScope', value, section: 'android');
                  }
                },
                items: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: palette.border)),
                    ),
                    child: Column(
                      children: [
                        for (final choice in ['all', 'included', 'excluded'])
                          _AndroidModeRow(
                            value: choice,
                            title: switch (choice) {
                              'all' => l.prototypeAllApps,
                              'included' => l.prototypeOnlySelectedApps,
                              _ => l.prototypeAllExceptSelectedApps,
                            },
                            selected: mode == choice,
                            enabled: !controller.blocked,
                            onTap: () => controller.update(
                              'appScope',
                              choice,
                              section: 'android',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (mode != 'all') ...[
                const SizedBox(height: 12),
                Material(
                  color: palette.card,
                  child: InkWell(
                    onTap: controller.blocked
                        ? null
                        : () => controller.selectApps(context, widget.openApps),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 64),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(color: palette.border),
                        ),
                      ),
                      child: Row(
                        spacing: 11,
                        children: [
                          Icon(
                            LucideIcons.appWindow,
                            size: 19,
                            color: palette.primary,
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  included
                                      ? l.prototypeAppsUsingVpn
                                      : l.prototypeAppsBypassingVpn,
                                  style: AppTypography.androidRowTitle,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  names.isEmpty
                                      ? l.prototypeNoAppsSelected
                                      : names
                                            .map(controller.androidAppName)
                                            .join(', '),
                                  style: AppTypography.androidRowHint.copyWith(
                                    color: palette.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            constraints: const BoxConstraints(minWidth: 26),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: palette.selectedSurface,
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                            ),
                            child: Text(
                              '${names.length}',
                              textAlign: TextAlign.center,
                              style: AppTypography.androidBadge.copyWith(
                                color: palette.primary,
                              ),
                            ),
                          ),
                          const Icon(LucideIcons.chevronRightDir, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (widget.openAutomation != null) ...[
                const SizedBox(height: 24),
                SettingRow(
                  title: l.automationTitle,
                  leading: const Icon(LucideIcons.zap),
                  showChevron: true,
                  onTap: () => widget.openAutomation!(context),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _AndroidModeRow extends StatelessWidget {
  const _AndroidModeRow({
    required this.value,
    required this.title,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String value;
  final String title;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      child: MergeSemantics(
        child: Material(
          color: palette.card,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 68),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: palette.border)),
              ),
              child: Row(
                spacing: 12,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(5, 3, 3, 0),
                    child: ShadRadio<String>(
                      value: value,
                      enabled: enabled,
                      size: 11,
                      circleSize: 7,
                      radioPadding: EdgeInsets.zero,
                      decoration: ShadDecoration(
                        border: ShadBorder.all(
                          color: selected
                              ? palette.primary
                              : palette.mutedForeground,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(title, style: AppTypography.androidModeTitle),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
