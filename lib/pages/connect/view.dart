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
    required this.onServer,
    required this.onMethod,
    required this.onWhy,
    required this.onRawAdd,
  });
  final ConnectionView view;
  final Widget Function(bool desktop)? trafficBuilder;
  final bool hasServers;
  final bool expert;
  final List<CoreConfigData> raws;
  final int? activeRawId;
  final String? pendingChange;
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
      VoidCallback? action, {
      bool selected = false,
      bool includeLabel = true,
    }) => Semantics(
      selected: selected,
      button: action != null,
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? palette.selectedSurface : null,
            borderRadius: BorderRadius.circular(AppRadii.control),
            border: selected ? Border.all(color: palette.border) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? palette.primaryText : palette.mutedStrong,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: AppTypography.rowTitle.copyWith(
                        color: selected
                            ? palette.primaryText
                            : palette.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (includeLabel && label != value) label,
                        if (detail != null && detail.isNotEmpty) detail,
                      ].join(' · '),
                      style: AppTypography.supporting.copyWith(
                        color: palette.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null)
                Icon(
                  LucideIcons.chevronRightDir,
                  size: 18,
                  color: palette.mutedForeground,
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
      padding: EdgeInsets.fromLTRB(mobile ? 16 : 28, 16, mobile ? 16 : 28, 28),
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
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.connectionPlan, style: AppTypography.panelTitle),
                    const SizedBox(height: 4),
                    Text(
                      view.phase == ConnectionPhase.connected
                          ? l.connectionPlanConnectedCaption
                          : l.connectionPlanCaption,
                      style: AppTypography.supporting.copyWith(
                        color: palette.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                      selected: true,
                    ),
                    const SizedBox(height: 8),
                    choice(
                      LucideIcons.route,
                      l.navigationRouting,
                      method,
                      methodDetail,
                      methodEnabled && !expert && !_busy ? onMethod : null,
                      includeLabel: false,
                    ),
                  ],
                ),
              ),
            ),
            if (view.canDisconnect && view.runtime != null) ...[
              const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.connectionSessionTitle,
                      style: AppTypography.panelTitle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.connectionSessionCaption,
                      style: AppTypography.supporting.copyWith(
                        color: palette.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 16),
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

  Widget _status(BuildContext context) {
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
        ? palette.runningText
        : _busy
        ? palette.primaryText
        : palette.secondaryForeground;
    final waitingForPhase = _connectionPending && !view.busy;
    final button = FilledButton(
      onPressed:
          view.phase == ConnectionPhase.disconnecting ||
              (pendingChange != null && !view.busy)
          ? null
          : onConnection,
      style: AppTheme.connectionButton(context, destructive: canDisconnect),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_busy ? LucideIcons.x : LucideIcons.power, size: 18),
          const SizedBox(width: 8),
          Flexible(
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
        ],
      ),
    );
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_busy)
              SizedBox.square(
                dimension: 17,
                child: MediaQuery.disableAnimationsOf(context)
                    ? Icon(LucideIcons.loaderCircle, color: color, size: 17)
                    : CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(LucideIcons.shield, size: 17, color: palette.primary),
            Text(l.prototypeSystemVpn, style: AppTypography.badge),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: failed
                    ? palette.destructiveSurface
                    : connected
                    ? palette.runningSurface
                    : _busy
                    ? palette.selectedSurface
                    : palette.secondary,
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Text(
                title,
                style: AppTypography.badge.copyWith(color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(title, style: AppTypography.connectStatusTitle),
        if (connected || _busy || failed) ...[
          const SizedBox(height: 5),
          Text(
            detail,
            style: AppTypography.connectStatusDetail.copyWith(
              color: failed ? palette.destructive : palette.mutedForeground,
            ),
          ),
        ],
        if (view.issue == 'selectionReset')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                l.prototypeNameActive(l.prototypeAutomaticSelection),
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
            ),
          ),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      color: palette.card,
      clipBehavior: Clip.antiAlias,
      child: ColoredBox(
        color: palette.primary.withValues(alpha: .055),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 520 ||
                  MediaQuery.textScalerOf(context).scale(14) > 18) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [label, const SizedBox(height: 14), button],
                );
              }
              return Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 20),
                  SizedBox(width: 150, child: button),
                ],
              );
            },
          ),
        ),
      ),
    );
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
    Widget metric(
      String title,
      String value,
      String? detail, {
      required int index,
    }) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.primary.withValues(alpha: .045 + index * .025),
          palette.card,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.supporting.copyWith(
              color: palette.mutedForeground,
            ),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              textDirection: TextDirection.ltr,
              style: AppTypography.metric,
            ),
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                detail,
                textDirection: TextDirection.ltr,
                style: AppTypography.supporting.copyWith(
                  color: palette.mutedForeground,
                ),
              ),
            ),
        ],
      ),
    );
    final items = [
      metric(
        l.prototypeUpload,
        !live || view.traffic == null
            ? '—'
            : formatTraffic(view.traffic!.uplink, connection: true),
        live ? '${formatTraffic(view.uploadSpeed, connection: true)}/s' : '—',
        index: 0,
      ),
      metric(
        l.prototypeDownload,
        !live || view.traffic == null
            ? '—'
            : formatTraffic(view.traffic!.downlink, connection: true),
        live ? '${formatTraffic(view.downloadSpeed, connection: true)}/s' : '—',
        index: 1,
      ),
      metric(l.connectionSessionDuration, elapsed, null, index: 2),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final gap = constraints.maxWidth < 520 ? 8.0 : 12.0;
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
                    if (item.$1 > 0) SizedBox(width: gap),
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
