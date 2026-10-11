import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/routing/widgets.dart';
import 'package:onexray/pages/shared/widgets/dns_text_field.dart';
import 'package:onexray/pages/shared/widgets/menu_picker.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/connect/routing/custom/geodata_suggestions.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadSwitch;

/// Ordinary routing forms edit business values, never generated Core JSON.
class RoutingDnsSettingsForm extends StatelessWidget {
  final RoutingDnsSettings value;
  final ValueChanged<RoutingDnsSettings> onChanged;
  final bool enabled;
  final bool directEnabled;
  final bool fakeDns;

  const RoutingDnsSettingsForm({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.directEnabled = true,
    this.fakeDns = false,
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
    final concurrencyAllowed =
        enabled &&
        value.sameExitOnly &&
        !fakeDns &&
        (value.effectiveProxyResolvers.length > 1 ||
            (directEnabled && value.effectiveDirectResolvers.length > 1));
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
          _RoutingDetails(
            title: l.routingDnsAdvanced,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OptionSwitch(
                  icon: LucideIcons.database,
                  title: l.routingDnsCache,
                  value: !value.disableCache,
                  enabled: enabled,
                  onChanged: (selected) =>
                      onChanged(value.copyWith(disableCache: !selected)),
                ),
                _OptionSwitch(
                  icon: LucideIcons.history,
                  title: l.routingDnsServeStale,
                  description: l.routingDnsServeStaleHint,
                  value: value.serveStale,
                  enabled: enabled && !value.disableCache,
                  onChanged: (selected) =>
                      onChanged(value.copyWith(serveStale: selected)),
                ),
                if (value.serveStale)
                  _FieldPadding(
                    child: _OptionTextField(
                      label: l.routingDnsStaleTtl,
                      value: '${value.serveExpiredTTL}',
                      enabled: enabled && !value.disableCache,
                      keyboardType: TextInputType.number,
                      onChanged: (text) => onChanged(
                        value.copyWith(
                          serveExpiredTTL: int.tryParse(text) ?? -1,
                        ),
                      ),
                    ),
                  ),
                _OptionSwitch(
                  icon: LucideIcons.gitFork,
                  title: l.routingDnsParallel,
                  description: l.routingDnsParallelHint,
                  value: value.enableParallelQuery,
                  enabled: concurrencyAllowed,
                  onChanged: (selected) =>
                      onChanged(value.copyWith(enableParallelQuery: selected)),
                  divider: false,
                ),
                if (!concurrencyAllowed)
                  _HelpPadding(text: l.routingDnsParallelUnavailable),
              ],
            ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
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
        ),
        _RoutingDetails(
          title: l.routingDnsResolverOptions,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              _OptionTextField(
                label: l.routingDnsTimeout,
                value: '${value.timeoutMs}',
                keyboardType: TextInputType.number,
                enabled: enabled,
                onChanged: (text) => onChanged(
                  value.copyWith(timeoutMs: int.tryParse(text) ?? -1),
                ),
              ),
              _OptionTextField(
                label: l.routingDnsExpectedIps,
                geodataDomain: false,
                value: value.expectedIPs.join('\n'),
                multiline: true,
                enabled: enabled,
                onChanged: (text) =>
                    onChanged(value.copyWith(expectedIPs: _lines(text))),
              ),
              _OptionTextField(
                label: l.routingDnsUnexpectedIps,
                geodataDomain: false,
                value: value.unexpectedIPs.join('\n'),
                multiline: true,
                enabled: enabled,
                onChanged: (text) =>
                    onChanged(value.copyWith(unexpectedIPs: _lines(text))),
              ),
              _HelpPadding(text: l.routingDnsIpFilterHint),
              _NullableChoice(
                label: l.routingDnsCache,
                value: value.disableCache,
                trueLabel: l.routingOptionOff,
                falseLabel: l.routingOptionOn,
                enabled: enabled,
                onChanged: (selected) => onChanged(
                  selected == null
                      ? value.copyWith(clearDisableCache: true)
                      : value.copyWith(disableCache: selected),
                ),
              ),
              _NullableChoice(
                label: l.routingDnsServeStale,
                value: value.serveStale,
                trueLabel: l.routingOptionOn,
                falseLabel: l.routingOptionOff,
                enabled: enabled,
                onChanged: (selected) => onChanged(
                  selected == null
                      ? value.copyWith(clearServeStale: true)
                      : value.copyWith(serveStale: selected),
                ),
              ),
              _OptionTextField(
                label: l.routingDnsStaleTtl,
                hint: l.routingOptionInherit,
                value: value.serveExpiredTTL?.toString() ?? '',
                keyboardType: TextInputType.number,
                enabled: enabled,
                onChanged: (text) => onChanged(
                  text.trim().isEmpty
                      ? value.copyWith(clearServeExpiredTTL: true)
                      : value.copyWith(
                          serveExpiredTTL: int.tryParse(text) ?? -1,
                        ),
                ),
              ),
            ],
          ),
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
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                _OptionTextField(
                  label: l.routingSniffingDomainsExcluded,
                  geodataDomain: true,
                  value: value.domainsExcluded.join('\n'),
                  multiline: true,
                  enabled: enabled && value.enabled,
                  onChanged: (text) =>
                      onChanged(value.copyWith(domainsExcluded: _lines(text))),
                ),
                _OptionTextField(
                  label: l.routingSniffingIpsExcluded,
                  geodataDomain: false,
                  value: value.ipsExcluded.join('\n'),
                  multiline: true,
                  enabled: enabled && value.enabled,
                  onChanged: (text) =>
                      onChanged(value.copyWith(ipsExcluded: _lines(text))),
                ),
                _HelpPadding(text: l.routingSniffingExclusionsHint),
              ],
            ),
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

List<String> _lines(String value) => value
    .split(RegExp(r'[\n,]'))
    .map((text) => text.trim())
    .where((text) => text.isNotEmpty)
    .toList();

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

class _NullableChoice extends StatelessWidget {
  final String label;
  final bool? value;
  final String trueLabel;
  final String falseLabel;
  final bool enabled;
  final ValueChanged<bool?> onChanged;
  const _NullableChoice({
    required this.label,
    required this.value,
    required this.trueLabel,
    required this.falseLabel,
    required this.enabled,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => _OptionPicker(
    label: label,
    value: value?.toString() ?? 'inherit',
    labels: {
      'inherit': AppLocalizations.of(context)!.routingOptionInherit,
      'true': trueLabel,
      'false': falseLabel,
    },
    enabled: enabled,
    onChanged: (selected) =>
        onChanged(selected == 'inherit' ? null : selected == 'true'),
  );
}

class _FieldPadding extends StatelessWidget {
  final Widget child;
  const _FieldPadding({required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
    child: child,
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

class _OptionTextField extends StatefulWidget {
  final String label;
  final String value;
  final String? hint;
  final bool enabled;
  final bool multiline;
  final bool? geodataDomain;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;
  const _OptionTextField({
    required this.label,
    required this.value,
    this.hint,
    required this.enabled,
    required this.onChanged,
    this.multiline = false,
    this.keyboardType,
    this.geodataDomain,
  });
  @override
  State<_OptionTextField> createState() => _OptionTextFieldState();
}

class _OptionTextFieldState extends State<_OptionTextField> {
  late final controller = TextEditingController(text: widget.value);
  final focus = FocusNode();
  TextEditingValue _autocompleteValue = TextEditingValue.empty;
  String? _pendingEcho;

  @override
  void initState() {
    super.initState();
    focus.addListener(_syncAfterFocus);
  }

  void _syncAfterFocus() {
    if (!focus.hasFocus && controller.text != widget.value) {
      controller.text = widget.value;
    }
  }

  void _changed(String text) {
    _pendingEcho = widget.keyboardType == TextInputType.number
        ? (text.trim().isEmpty && widget.hint != null
              ? ''
              : '${int.tryParse(text) ?? -1}')
        : widget.multiline
        ? _lines(text).join('\n')
        : text;
    widget.onChanged(text);
  }

  @override
  void didUpdateWidget(covariant _OptionTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final echo = _pendingEcho == widget.value;
    _pendingEcho = null;
    // Keep unfinished local text while focused, but never conceal imported
    // values or values shifted into this resolver row after deleting another.
    if (controller.text != widget.value &&
        (!focus.hasFocus || (oldWidget.value != widget.value && !echo))) {
      controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    focus.removeListener(_syncAfterFocus);
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  ({int start, int end, String query, bool preferred}) _currentRule(
    TextEditingValue value,
  ) {
    final text = value.text;
    final cursor = value.selection.isValid
        ? value.selection.extentOffset
        : text.length;
    final before = text.substring(0, cursor);
    final boundary = RegExp(r'[\n,]');
    final preceding = boundary.allMatches(before).lastOrNull;
    final following = boundary.firstMatch(text.substring(cursor));
    final start = preceding == null ? 0 : preceding.end;
    final end = following == null ? text.length : cursor + following.start;
    final query = text.substring(start, cursor).trim();
    return (
      start: start,
      end: end,
      query: query.startsWith('*') ? query.substring(1) : query,
      preferred: query.startsWith('*'),
    );
  }

  Future<Iterable<String>> _suggestions(TextEditingValue value) async {
    _autocompleteValue = value;
    final rule = _currentRule(value);
    if (rule.query.isEmpty) return const [];
    try {
      final index = await RoutingGeodataIndex.load();
      if (!mounted) return const [];
      return index.suggestions(rule.query, domain: widget.geodataDomain!);
    } catch (_) {
      return const [];
    }
  }

  String _replacement(String option) {
    final value = _autocompleteValue;
    final rule = _currentRule(value);
    return value.text.replaceRange(
      rule.start,
      rule.end,
      '${rule.preferred ? '*' : ''}$option',
    );
  }

  Widget _field({VoidCallback? submit}) => TextField(
    controller: controller,
    focusNode: focus,
    enabled: widget.enabled,
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.left,
    autocorrect: false,
    enableSuggestions: false,
    minLines: widget.multiline ? 2 : 1,
    maxLines: widget.multiline ? 5 : 1,
    keyboardType:
        widget.keyboardType ??
        (widget.multiline ? TextInputType.multiline : TextInputType.text),
    style: AppTypography.settingsInput,
    decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
    onChanged: _changed,
    onSubmitted: submit == null ? null : (_) => submit(),
  );

  @override
  Widget build(BuildContext context) => widget.geodataDomain == null
      ? _field()
      : LayoutBuilder(
          builder: (context, constraints) => RawAutocomplete<String>(
            textEditingController: controller,
            focusNode: focus,
            optionsBuilder: _suggestions,
            displayStringForOption: _replacement,
            onSelected: (_) => _changed(controller.text),
            fieldViewBuilder: (context, text, focus, submit) =>
                _field(submit: submit),
            optionsViewBuilder: (context, select, options) => Align(
              alignment: AlignmentDirectional.topStart,
              child: Material(
                elevation: 4,
                color: ColorManager.palette(context).card,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final option in options)
                          ListTile(
                            title: Text(
                              option,
                              textDirection: TextDirection.ltr,
                              style: AppTypography.routingInput,
                            ),
                            onTap: () => select(option),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
}
