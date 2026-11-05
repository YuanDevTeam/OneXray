import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Owns only editing cursors; CIDR validation remains in PolicyEditorService.
class ExcludedNetworks extends StatefulWidget {
  const ExcludedNetworks({
    super.key,
    required this.values,
    required this.enabled,
    required this.onChanged,
    this.rowKeyPrefix = 'excluded-cidr-row',
    this.maxEntries,
  });

  final String rowKeyPrefix;
  final int? maxEntries;
  final List<String> values;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;

  @override
  State<ExcludedNetworks> createState() => _ExcludedNetworksState();
}

class _ExcludedNetworksState extends State<ExcludedNetworks> {
  late final fields = widget.values
      .map((value) => TextEditingController(text: value))
      .toList();

  void _publish() =>
      widget.onChanged(fields.map((field) => field.text).toList());

  void _add() {
    fields.add(TextEditingController());
    _publish();
  }

  void _remove(int index) {
    _retire(fields.removeAt(index));
    _publish();
  }

  void _retire(TextEditingController field) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => field.dispose());

  @override
  void didUpdateWidget(ExcludedNetworks oldWidget) {
    super.didUpdateWidget(oldWidget);
    while (fields.length > widget.values.length) {
      _retire(fields.removeLast());
    }
    while (fields.length < widget.values.length) {
      fields.add(TextEditingController());
    }
    for (var index = 0; index < widget.values.length; index++) {
      final value = widget.values[index];
      if (fields[index].text != value) {
        fields[index].value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < widget.values.length; index++) ...[
          Focus(
            key: ObjectKey(fields[index]),
            child: Builder(
              builder: (context) => Container(
                key: ValueKey('${widget.rowKeyPrefix}:$index'),
                constraints: const BoxConstraints(minHeight: 50),
                padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 8, 4),
                decoration: BoxDecoration(
                  color: palette.card,
                  border: Border.all(
                    color: Focus.of(context).hasFocus
                        ? palette.primary
                        : palette.border,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.network,
                      size: 18,
                      color: palette.mutedForeground,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        label: l.prototypeBypassNetworkNumber(index + 1),
                        child: TextField(
                          controller: fields[index],
                          enabled: widget.enabled,
                          autocorrect: false,
                          enableSuggestions: false,
                          textDirection: TextDirection.ltr,
                          style: AppTypography.windowsNetworkInput,
                          decoration: const InputDecoration(
                            hintText: '192.168.1.0/24',
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          onChanged: (_) => _publish(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: l.prototypeRemoveBypassNetworkNumber(index + 1),
                      onPressed: widget.enabled ? () => _remove(index) : null,
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(36),
                        maximumSize: const Size.square(36),
                        padding: EdgeInsets.zero,
                        foregroundColor: palette.mutedStrong,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(LucideIcons.trash2, size: 17),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.values.isEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            decoration: ShapeDecoration(
              shape: AppDashedBorder(
                borderRadius: BorderRadius.circular(AppRadii.control),
                side: BorderSide(color: palette.border),
              ),
            ),
            child: Text(
              l.prototypeNoBypassNetworks,
              textAlign: TextAlign.center,
              style: AppTypography.windowsNetworkMeta.copyWith(
                color: palette.mutedForeground,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton(
          onPressed:
              widget.enabled &&
                  (widget.maxEntries == null ||
                      widget.values.length < widget.maxEntries!)
              ? _add
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.plus, size: 16),
              const SizedBox(width: 8),
              Text(l.prototypeAddNetwork),
            ],
          ),
        ),
      ],
    );
  }
}
