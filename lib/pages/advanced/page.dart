import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/controller.dart';
import 'package:onexray/pages/advanced/tab_visibility.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/page.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';

class AdvancedPage extends StatelessWidget {
  final WidgetBuilder? xrayBuilder;
  final OpenTunnelPage? openTunnel;
  const AdvancedPage({super.key, this.xrayBuilder, this.openTunnel});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AdvancedController(),
      child: AdvancedPageView(
        tunnel: VpnTunnelPane(openTunnel: openTunnel),
        xray: Builder(builder: xrayBuilder ?? _runtimeSummary),
      ),
    );
  }

  Widget _runtimeSummary(BuildContext context) =>
      BlocBuilder<AdvancedController, AdvancedPageState>(
        builder: (context, state) {
          final l = AppLocalizations.of(context)!;
          final controller = context.read<AdvancedController>();
          return AdvancedTabVisibility(
            tabIndex: 1,
            onChanged: controller.setVisible,
            child: SettingsPageScroll(
              child: SettingSection(
                title: l.prototypeRuntimeStatus,
                children: [
                  SettingRow(
                    title: l.prototypeXrayCore,
                    value: controller.statusLabel(l),
                    leading: const Icon(LucideIcons.activity),
                  ),
                  PolicyValueRow(
                    title: l.prototypeVersion,
                    value: state.xrayVersion,
                  ),
                  PolicyValueRow(title: l.prototypeUptime, value: state.uptime),
                ],
              ),
            ),
          );
        },
      );
}

/// The fixed header and tabs share the same measured text space as their body.
class AdvancedPageView extends StatelessWidget {
  final Widget tunnel;
  final Widget xray;

  const AdvancedPageView({super.key, required this.tunnel, required this.xray});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final l = AppLocalizations.of(context)!;
      final mobile =
          MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
      final padding = mobile ? AppSpacing.mobilePage : AppSpacing.page;
      final theme = Theme.of(context);
      final selectedStyle = theme.textTheme.titleSmall!.merge(
        theme.tabBarTheme.labelStyle,
      );
      final unselectedStyle = theme.textTheme.titleSmall!.merge(
        theme.tabBarTheme.unselectedLabelStyle,
      );
      final labels = [l.prototypeVpnTunnel, l.prototypeXrayRuntimeDiagnostics];
      final labelWidth = mobile
          ? math.max(1.0, (constraints.maxWidth - padding * 2) / 2 - 24)
          : double.infinity;
      final painters = <TextPainter>[];
      for (final label in labels) {
        for (final style in [selectedStyle, unselectedStyle]) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textAlign: TextAlign.center,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.localeOf(context),
          )..layout();
          painters.add(painter);
        }
      }
      // Keep tab labels on one line; scroll when either needs more than a cell.
      final scrollable =
          !mobile || painters.any((painter) => painter.width > labelWidth);
      var tabHeight = 46.0;
      for (final painter in painters) {
        tabHeight = math.max(tabHeight, painter.height + 20);
        painter.dispose();
      }
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: PageAppBar(
            title: Text(l.prototypeAdvanced),
            bottom: TabBar(
              isScrollable: scrollable,
              tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
              padding: EdgeInsets.symmetric(horizontal: padding),
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              labelStyle: selectedStyle,
              unselectedLabelStyle: unselectedStyle,
              tabs: [
                for (final label in labels)
                  Tab(
                    height: tabHeight,
                    child: Builder(
                      builder: (context) => Text(
                        label,
                        textAlign: TextAlign.center,
                        softWrap: false,
                        // TabBar merges its own defaults into the label style.
                        // Keep the measured metrics and inherit only its color.
                        style: selectedStyle.copyWith(
                          inherit: false,
                          color: DefaultTextStyle.of(context).style.color,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          body: SafeArea(
            top: false,
            child: TabBarView(children: [tunnel, xray]),
          ),
        ),
      );
    },
  );
}
