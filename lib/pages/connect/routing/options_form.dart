import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/shared/widgets/dns_text_field.dart';
import 'package:onexray/pages/shared/widgets/menu_picker.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSwitch;

/// Ordinary routing forms edit business values, never generated Core JSON.
class RoutingDnsSettingsForm extends StatelessWidget {
  final RoutingDnsSettings value;
  final ValueChanged<RoutingDnsSettings> onChanged;
  final bool enabled;
  final bool directEnabled;

  const RoutingDnsSettingsForm({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.directEnabled = true,
  });

  void _updateResolver(bool direct, int index, RoutingDnsResolver resolver) {
    final resolvers = List<RoutingDnsResolver>.of(
      direct ? value.effectiveDirectResolvers : value.effectiveProxyResolvers,
    );
    resolvers[index] = resolver;
    onChanged(
      direct
          ? value.copyWith(directResolvers: resolvers)
          : value.copyWith(proxyResolvers: resolvers),
    );
  }

  void _removeResolver(bool direct, int index) {
    final resolvers = List<RoutingDnsResolver>.of(
      direct ? value.effectiveDirectResolvers : value.effectiveProxyResolvers,
    )..removeAt(index);
    onChanged(
      direct
          ? value.copyWith(directResolvers: resolvers)
          : value.copyWith(proxyResolvers: resolvers),
    );
  }

  void _addResolver(bool direct) {
    final resolvers = [
      ...(direct
          ? value.effectiveDirectResolvers
          : value.effectiveProxyResolvers),
      const RoutingDnsResolver(address: ''),
    ];
    onChanged(
      direct
          ? value.copyWith(directResolvers: resolvers)
          : value.copyWith(proxyResolvers: resolvers),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return RoutingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoutingCardHeader(
            title: l.routingDnsSettings,
            description: l.routingDnsSettingsHint,
          ),
          _resolvers(context, direct: false),
          if (directEnabled) _resolvers(context, direct: true),
          _OptionSwitch(
            icon: LucideIcons.route,
            title: l.routingDnsSameExitOnly,
            description: l.routingDnsSameExitOnlyHint,
            value: value.sameExitOnly,
            enabled: enabled,
            onChanged: (selected) =>
                onChanged(value.copyWith(sameExitOnly: selected)),
          ),
          _OptionSwitch(
            icon: LucideIcons.database,
            title: l.routingDnsCache,
            value: !value.disableCache,
            enabled: enabled,
            onChanged: (selected) =>
                onChanged(value.copyWith(disableCache: !selected)),
            divider: false,
          ),
        ],
      ),
    );
  }

  Widget _resolvers(BuildContext context, {required bool direct}) {
    final l = AppLocalizations.of(context)!;
    final resolvers = direct
        ? value.effectiveDirectResolvers
        : value.effectiveProxyResolvers;
    final active = enabled && (!direct || directEnabled);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            direct ? l.routingDnsDirect : l.routingDnsProxy,
            style: AppTypography.routingRowTitle,
          ),
          for (final (index, resolver) in resolvers.indexed)
            _ResolverForm(
              key: ValueKey('dns-${direct ? 'direct' : 'proxy'}-$index'),
              value: resolver,
              primary: index == 0,
              enabled: active,
              onChanged: (updated) => _updateResolver(direct, index, updated),
              onRemove: index == 0
                  ? null
                  : () => _removeResolver(direct, index),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: active ? () => _addResolver(direct) : null,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(l.routingDnsAddFallback),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolverForm extends StatelessWidget {
  final RoutingDnsResolver value;
  final ValueChanged<RoutingDnsResolver> onChanged;
  final VoidCallback? onRemove;
  final bool primary;
  final bool enabled;

  const _ResolverForm({
    super.key,
    required this.value,
    required this.onChanged,
    required this.primary,
    required this.enabled,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DnsTextField(
            label: primary ? l.routingDnsPrimary : l.routingDnsFallback,
            value: value.address,
            enabled: enabled,
            onChanged: (text) => onChanged(value.copyWith(address: text)),
          ),
        ),
        if (onRemove != null)
          IconButton(
            tooltip: l.prototypeDelete,
            onPressed: enabled ? onRemove : null,
            icon: const Icon(LucideIcons.trash2, size: 18),
          ),
      ],
    );
  }
}

class RoutingSniffingSettingsForm extends StatelessWidget {
  final RoutingSniffingSettings value;
  final ValueChanged<RoutingSniffingSettings> onChanged;
  final bool enabled;
  final bool fakeDns;

  const RoutingSniffingSettingsForm({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.fakeDns = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return RoutingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoutingCardHeader(
            title: l.routingSniffingSettings,
            description: l.routingSniffingHint,
          ),
          _OptionSwitch(
            icon: LucideIcons.scanSearch,
            title: l.routingSniffingEnabled,
            value: value.enabled,
            enabled: enabled && !fakeDns,
            onChanged: (selected) =>
                onChanged(value.copyWith(enabled: selected)),
          ),
          if (fakeDns) _HelpPadding(text: l.routingSniffingFakeDnsHint),
          _OptionSwitch(
            icon: LucideIcons.route,
            title: l.routingSniffingRouteOnly,
            description: l.routingSniffingRouteOnlyHint,
            value: value.routeOnly,
            enabled: enabled && value.enabled,
            onChanged: (selected) =>
                onChanged(value.copyWith(routeOnly: selected)),
            divider: false,
          ),
          _RoutingDetails(
            title: l.routingSniffingMore,
            child: _OptionSwitch(
              icon: LucideIcons.fileSearch,
              title: l.routingSniffingMetadataOnly,
              description: l.routingSniffingMetadataOnlyHint,
              value: value.metadataOnly,
              enabled: enabled && value.enabled,
              onChanged: (selected) =>
                  onChanged(value.copyWith(metadataOnly: selected)),
              divider: false,
            ),
          ),
        ],
      ),
    );
  }
}

class RoutingSelectionSettingsForm extends StatelessWidget {
  final RoutingSelectionSettings value;
  final ValueChanged<RoutingSelectionSettings> onChanged;
  final bool enabled;
  final int entryCount;

  const RoutingSelectionSettingsForm({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.entryCount = 1,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final choices = {
      'roundRobin': l.routingSelectionRoundRobin,
      'leastPing': l.routingSelectionLeastPing,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoutingSettingRow(
          icon: LucideIcons.gitBranch,
          title: l.routingSelectionStrategy,
          below: _OptionPicker(
            value: value.type,
            labels: choices,
            enabled: enabled,
            onChanged: (selected) => onChanged(value.copyWith(type: selected)),
          ),
        ),
        if (value.type == 'leastPing') ...[
          _HelpPadding(text: l.routingSelectionHint),
          if (entryCount < 2) _HelpPadding(text: l.routingSelectionSingleHint),
          _RoutingDetails(
            title: l.routingSelectionProbeSettings,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                DnsTextField(
                  label: l.routingSelectionProbeUrl,
                  value: value.probeURL,
                  enabled: enabled,
                  onChanged: (text) =>
                      onChanged(value.copyWith(probeURL: text)),
                ),
                _OptionPicker(
                  label: l.routingSelectionProbeInterval,
                  value: value.probeInterval,
                  enabled: enabled,
                  labels: {
                    '30s': l.routingSelectionInterval30,
                    '60s': l.routingSelectionInterval60,
                    '300s': l.routingSelectionInterval300,
                    if (!const [
                      '30s',
                      '60s',
                      '300s',
                    ].contains(value.probeInterval))
                      value.probeInterval: value.probeInterval,
                  },
                  onChanged: (selected) =>
                      onChanged(value.copyWith(probeInterval: selected)),
                ),
                _OptionSwitch(
                  icon: LucideIcons.gitFork,
                  title: l.routingSelectionProbeConcurrency,
                  value: value.enableConcurrency,
                  enabled: enabled,
                  onChanged: (selected) =>
                      onChanged(value.copyWith(enableConcurrency: selected)),
                  divider: false,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OptionSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final bool value;
  final bool enabled;
  final bool divider;
  final ValueChanged<bool> onChanged;
  const _OptionSwitch({
    required this.icon,
    required this.title,
    this.description,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.divider = true,
  });
  @override
  Widget build(BuildContext context) => RoutingSettingRow(
    icon: icon,
    title: title,
    description: description,
    enabled: enabled,
    divider: divider,
    trailing: Semantics(
      label: title,
      child: ShadSwitch(value: value, enabled: enabled, onChanged: onChanged),
    ),
  );
}

class _RoutingDetails extends StatefulWidget {
  final String title;
  final Widget child;
  const _RoutingDetails({required this.title, required this.child});
  @override
  State<_RoutingDetails> createState() => _RoutingDetailsState();
}

class _RoutingDetailsState extends State<_RoutingDetails> {
  bool open = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        button: true,
        expanded: open,
        child: TextButton(
          onPressed: () => setState(() => open = !open),
          child: Row(
            children: [
              Expanded(child: Text(widget.title, textAlign: TextAlign.start)),
              Icon(
                open ? LucideIcons.chevronDown : LucideIcons.chevronRightDir,
                size: 18,
              ),
            ],
          ),
        ),
      ),
      Offstage(
        offstage: !open,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
          child: widget.child,
        ),
      ),
    ],
  );
}

class _OptionPicker extends StatelessWidget {
  final String? label;
  final String value;
  final Map<String, String> labels;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const _OptionPicker({
    this.label,
    required this.value,
    required this.labels,
    required this.enabled,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 6,
    children: [
      if (label != null) Text(label!, style: AppTypography.routingRowTitle),
      AppMenuButton<String>(
        entries: [
          for (final option in labels.entries)
            AppMenuEntry.item(value: option.key, title: option.value),
        ],
        onSelected: onChanged,
        triggerBuilder: (open) => OutlinedButton(
          onPressed: enabled ? open : null,
          child: Row(
            children: [
              Expanded(
                child: Text(labels[value] ?? value, textAlign: TextAlign.start),
              ),
              const Icon(LucideIcons.chevronDown, size: 16),
            ],
          ),
        ),
      ),
    ],
  );
}

class _HelpPadding extends StatelessWidget {
  final String text;
  const _HelpPadding({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
    child: Text(
      text,
      style: AppTypography.routingRowDescription.copyWith(
        color: ColorManager.palette(context).mutedForeground,
      ),
    ),
  );
}
