import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/traffic_format.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/page_empty_state.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/connect/runtime_observatory.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/failure.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ConnectView extends StatelessWidget {
  const ConnectView({
    super.key,
    required this.view,
    this.trafficBuilder,
    required this.hasServers,
    required this.expert,
    required this.raws,
    required this.activeRawId,
    this.pendingChange,
    this.deletingRawIds = const {},
    required this.location,
    this.targetKind,
    this.runningPath,
    this.fallbackMessage,
    this.locationDetail,
    this.locationHealth,
    required this.method,
    this.methodDetail,
    this.methodEnabled = true,
    required this.onConnection,
    required this.onAddServers,
    required this.onExpert,
    required this.onServer,
    required this.onMethod,
    required this.onWhy,
    required this.onRawAdd,
    required this.onRawSelect,
    required this.onRawActions,
  });
  final ConnectionView view;
  final Widget Function(bool desktop)? trafficBuilder;
  final bool hasServers;
  final bool expert;
  final List<CoreConfigData> raws;
  final int? activeRawId;
  final String? pendingChange;
  final Set<int> deletingRawIds;
  final String location;
  final String? targetKind;
  final String? runningPath;
  final String? fallbackMessage;
  final String? locationDetail, locationHealth, methodDetail;
  final String method;
  final bool methodEnabled;
  final VoidCallback onConnection,
      onAddServers,
      onServer,
      onMethod,
      onWhy,
      onRawAdd;
  final ValueChanged<bool> onExpert;
  final ValueChanged<CoreConfigData> onRawSelect, onRawActions;

  bool get _connectionPending => pendingChange == 'connection';
  bool get _busy => view.busy || _connectionPending;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final raw = raws.where((row) => row.id == activeRawId).firstOrNull;
    Widget choice(
      IconData icon,
      String label,
      String value,
      String? detail,
      VoidCallback? action,
    ) => Semantics(
      button: action != null,
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(icon, size: 19, color: palette.mutedStrong),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.supporting.copyWith(
                        color: palette.mutedStrong,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(value, style: AppTypography.rowTitle),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: AppTypography.supporting.copyWith(
                          color: palette.mutedStrong,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Icon(
                    LucideIcons.chevronRightDir,
                    size: 18,
                    color: palette.mutedForeground,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!hasServers && raws.isEmpty && !view.canDisconnect && !_busy) {
      return ResponsiveContent(
        child: PageEmptyState(
          title: l.prototypeStartUsingOneXray,
          description: l.prototypeFirstConnectionHint,
          primaryLabel: l.prototypeAddServers,
          onPrimary: onAddServers,
          secondaryLabel: l.prototypeUseCompleteRawJson,
          onSecondary: onRawAdd,
        ),
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('connection-single-column'),
      padding: EdgeInsets.fromLTRB(mobile ? 16 : 28, 12, mobile ? 16 : 28, 28),
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _status(context),
            if (fallbackMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: ShadAlert(
                    icon: const Icon(LucideIcons.info, size: 18),
                    description: Text(fallbackMessage!),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.connectionPlan, style: AppTypography.panelTitle),
                    const SizedBox(height: 6),
                    choice(
                      expert || !methodEnabled
                          ? LucideIcons.fileJson
                          : LucideIcons.server,
                      targetKind ??
                          (expert || !methodEnabled
                              ? l.serverCompleteConfigurationsTab
                              : l.prototypeServers),
                      expert ? (raw?.name ?? l.prototypeNotSelected) : location,
                      locationDetail,
                      _busy || pendingChange != null ? null : onServer,
                    ),
                    choice(
                      LucideIcons.route,
                      l.navigationRouting,
                      method,
                      methodDetail,
                      methodEnabled && !expert && !_busy ? onMethod : null,
                    ),
                  ],
                ),
              ),
            ),
            if (view.canDisconnect &&
                (runningPath != null ||
                    view.runtime?.profile != null ||
                    view.runtime?.configuration.connection.expert == true)) ...[
              const SizedBox(height: 18),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l.connectionRuntimeTitle,
                        style: AppTypography.panelTitle,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        view.runtime?.profile?.name ??
                            view.runtime?.rawName ??
                            runningPath ??
                            l.prototypeCompleteXrayConfiguration,
                        style: AppTypography.rowTitle,
                      ),
                      if (locationHealth != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            locationHealth!,
                            style: AppTypography.supporting,
                          ),
                        ),
                      TextButton.icon(
                        onPressed: onWhy,
                        icon: const Icon(LucideIcons.circleHelp, size: 16),
                        label: Text(l.prototypeWhyThisConnection),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.prototypeThisConnection,
                      style: AppTypography.panelTitle,
                    ),
                    const SizedBox(height: 14),
                    trafficBuilder?.call(false) ?? TrafficReadout(view: view),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _status(BuildContext context, {bool desktop = false}) {
    final l = AppLocalizations.of(context)!;
    final connected = view.phase == ConnectionPhase.connected;
    final canDisconnect = view.canDisconnect;
    final failed = view.failed && !connected;
    final presentationPhase = failed ? ConnectionPhase.failed : view.phase;
    final title = switch (presentationPhase) {
      ConnectionPhase.disconnected => l.prototypeDisconnected,
      ConnectionPhase.preparing => l.connectionPreparing,
      ConnectionPhase.connecting => l.prototypeConnecting,
      ConnectionPhase.connected => l.prototypeConnected,
      ConnectionPhase.disconnecting => l.prototypeDisconnecting,
      ConnectionPhase.failed => l.prototypeConnectionFailed,
    };
    final startedAt = view.runtime?.startedAt.millisecondsSinceEpoch;
    final elapsed = startedAt == null
        ? 0
        : DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(startedAt))
              .inMinutes;
    final detail = switch (presentationPhase) {
      ConnectionPhase.disconnected => l.prototypeReadyToProtectConnection,
      ConnectionPhase.preparing ||
      ConnectionPhase.connecting => l.prototypePreparingSecureConnection,
      ConnectionPhase.connected =>
        elapsed < 1
            ? l.prototypeJustConnected
            : elapsed < 60
            ? l.prototypeProtectedMinutes(elapsed)
            : l.prototypeProtectedHoursMinutes(elapsed ~/ 60, elapsed % 60),
      ConnectionPhase.disconnecting => l.prototypeFinishingConnection,
      ConnectionPhase.failed => connectionFailureMessage(
        l,
        issue: view.issue,
        error: view.error,
        permission: view.permission,
      ),
    };
    final palette = ColorManager.palette(context);
    final color = failed
        ? palette.destructive
        : connected
        ? palette.running
        : _busy
        ? palette.primary
        : palette.mutedStrong;
    final waitingForPhase = _connectionPending && !view.busy;
    final button = FilledButton(
      onPressed:
          view.phase == ConnectionPhase.disconnecting ||
              (pendingChange != null && !view.busy)
          ? null
          : onConnection,
      style: desktop
          ? AppTheme.connectionButton(
              context,
              destructive: canDisconnect,
            ).copyWith(
              minimumSize: const WidgetStatePropertyAll(
                Size(
                  AppLayout.connectDesktopButtonWidth,
                  AppLayout.connectDesktopButtonMinHeight,
                ),
              ),
              textStyle: WidgetStatePropertyAll(
                AppTypography.connectDesktopAction,
              ),
            )
          : AppTheme.connectionButton(context, destructive: canDisconnect),
      child: ButtonProgress(
        busy: desktop && _busy,
        child: Text(
          waitingForPhase
              ? l.prototypePleaseWait
              : canDisconnect
              ? l.prototypeDisconnect
              : view.phase == ConnectionPhase.disconnecting
              ? l.prototypePleaseWait
              : view.busy
              ? l.prototypeCancel
              : failed
              ? l.prototypeTryAgain
              : l.prototypeConnect,
        ),
      ),
    );
    final content = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: desktop
            ? AppLayout.connectDesktopStatusMinHeight
            : AppLayout.connectStatusMinHeight,
      ),
      child: Padding(
        padding: desktop
            ? const EdgeInsets.fromLTRB(20, 66, 20, 39)
            : const EdgeInsets.fromLTRB(15, 25, 15, 17),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_busy)
                  SizedBox.square(
                    dimension: desktop ? 29 : 24,
                    child: MediaQuery.disableAnimationsOf(context)
                        ? Icon(
                            LucideIcons.loaderCircle,
                            color: color,
                            size: desktop ? 29 : 24,
                          )
                        : CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                  )
                else if (connected)
                  Container(
                    width: desktop ? 29 : 24,
                    height: desktop ? 29 : 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.check,
                      size: desktop ? 19 : 14,
                      color: palette.primaryForeground,
                    ),
                  )
                else
                  Icon(
                    failed ? LucideIcons.circleAlert : LucideIcons.shield,
                    color: color,
                    size: desktop ? 29 : 24,
                  ),
                SizedBox(width: desktop ? 12 : 10),
                Flexible(
                  child: Text(
                    title,
                    style:
                        (desktop
                                ? AppTypography.connectDesktopStatusTitle
                                : AppTypography.connectStatusTitle)
                            .copyWith(color: color),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            SizedBox(height: desktop ? 16 : 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style:
                  (desktop
                          ? AppTypography.connectDesktopStatusDetail
                          : AppTypography.connectStatusDetail)
                      .copyWith(color: palette.mutedStrong),
            ),
            if (view.issue == 'selectionReset')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    l.prototypeNameActive(l.prototypeAutomaticSelection),
                    textAlign: TextAlign.center,
                    style: AppTypography.metadata,
                  ),
                ),
              ),
            if (view.failed && !failed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l.prototypeCheckNetwork,
                  style: AppTypography.supporting.copyWith(
                    color: palette.destructive,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            SizedBox(height: desktop ? 30 : 18),
            if (desktop)
              Align(
                child: SizedBox(
                  width: AppLayout.connectDesktopButtonWidth,
                  child: button,
                ),
              )
            else
              button,
          ],
        ),
      ),
    );
    return Card(margin: EdgeInsets.zero, child: content);
  }
}

class TrafficReadout extends StatelessWidget {
  const TrafficReadout({super.key, required this.view, this.desktop = false});
  final ConnectionView view;
  final bool desktop;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final live =
        view.phase == ConnectionPhase.connected && view.metricsAvailable;
    final started = view.phase == ConnectionPhase.connected
        ? view.runtime?.startedAt
        : null;
    final duration = started == null
        ? null
        : DateTime.now().difference(started);
    final elapsed = duration == null
        ? '—'
        : '${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
    Widget metric(String title, String value, String? detail) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.supporting.copyWith(
              color: palette.mutedStrong,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: AppTypography.metric,
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                detail,
                textDirection: TextDirection.ltr,
                style: AppTypography.supporting.copyWith(
                  color: palette.mutedStrong,
                ),
              ),
            ),
        ],
      ),
    );
    final items = [
      metric(
        l.prototypeDownload,
        live ? '${formatTraffic(view.downloadSpeed, connection: true)}/s' : '—',
        !live || view.traffic == null
            ? '—'
            : formatTraffic(view.traffic!.downlink, connection: true),
      ),
      metric(
        l.prototypeUpload,
        live ? '${formatTraffic(view.uploadSpeed, connection: true)}/s' : '—',
        !live || view.traffic == null
            ? '—'
            : formatTraffic(view.traffic!.uplink, connection: true),
      ),
      metric(l.prototypeUptime, elapsed, null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final large = MediaQuery.textScalerOf(context).scale(14) > 18;
            if (constraints.maxWidth < 300 || large) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: items,
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in items.indexed) ...[
                    if (item.$1 > 0) const SizedBox(width: 8),
                    Expanded(child: item.$2),
                  ],
                ],
              ),
            );
          },
        ),
        RuntimeObservatoryReadout(view: view, desktop: desktop),
      ],
    );
  }
}
