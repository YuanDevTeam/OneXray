import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

bool _mobile(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;

class AppleSettingToggle extends StatelessWidget {
  const AppleSettingToggle({
    super.key,
    required this.title,
    this.description,
    required this.value,
    required this.onChanged,
    this.nested = false,
  });
  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    final mobile = _mobile(context);
    final palette = ColorManager.palette(context);
    return MergeSemantics(
      child: Container(
        constraints: BoxConstraints(minHeight: mobile ? 64 : 61),
        padding: EdgeInsetsDirectional.fromSTEB(
          nested ? (mobile ? 20 : 32) : (mobile ? 12 : 16),
          mobile ? 9 : 10,
          mobile ? 12 : 16,
          mobile ? 9 : 10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: mobile
                        ? AppTypography.appleSettingTitle
                        : AppTypography.appleSettingTitleDesktop,
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      description!,
                      style:
                          (mobile
                                  ? AppTypography.appleSettingHint
                                  : AppTypography.appleSettingHintDesktop)
                              .copyWith(color: palette.mutedForeground),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: mobile ? 12 : 16),
            ShadSwitch(
              value: value,
              enabled: onChanged != null,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class AppleWifiPreview extends StatelessWidget {
  const AppleWifiPreview({
    super.key,
    required this.controller,
    this.showNetwork = false,
    this.editable = false,
    this.onEdit,
  });
  final PolicyEditorController controller;
  final bool showNetwork;
  final bool editable;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final mobile = _mobile(context);
    final palette = ColorManager.palette(context);
    final l = AppLocalizations.of(context)!;
    final connect = controller
        .strings('apple', 'connectWifiSsids')
        .where((name) => name.trim().isNotEmpty)
        .toList();
    final disconnect = controller
        .strings('apple', 'disconnectWifiSsids')
        .where((name) => name.trim().isNotEmpty)
        .toList();
    final sections = <Widget>[
      if (connect.isEmpty && disconnect.isEmpty)
        Container(
          constraints: BoxConstraints(minHeight: mobile ? 58 : 62),
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 12 : 16,
            vertical: mobile ? 11 : 12,
          ),
          alignment: AlignmentDirectional.centerStart,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.prototypeNoWifiRules,
                style: mobile
                    ? AppTypography.appleRuleTitle
                    : AppTypography.appleRuleTitleDesktop,
              ),
              const SizedBox(height: 3),
              Text(
                l.prototypeOtherNetworkRulesApply,
                style:
                    (mobile
                            ? AppTypography.appleRuleHint
                            : AppTypography.appleRuleHintDesktop)
                        .copyWith(color: palette.mutedForeground),
              ),
            ],
          ),
        ),
      if (connect.isNotEmpty)
        _WifiRuleLine(names: connect, disconnect: false, editable: editable),
      if (disconnect.isNotEmpty)
        _WifiRuleLine(names: disconnect, disconnect: true, editable: editable),
      if (showNetwork) _NetworkChoice(controller: controller),
      _WifiFallback(editable: editable, onEdit: onEdit),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < sections.length; index++) ...[
            if (index > 0) Divider(height: 0, color: palette.border),
            sections[index],
          ],
        ],
      ),
    );
  }
}

class _WifiRuleLine extends StatelessWidget {
  const _WifiRuleLine({
    required this.names,
    required this.disconnect,
    required this.editable,
  });
  final List<String> names;
  final bool disconnect;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final mobile = _mobile(context);
    final palette = ColorManager.palette(context);
    final l = AppLocalizations.of(context)!;
    final style = mobile
        ? AppTypography.appleRuleTitle
        : AppTypography.appleRuleTitleDesktop;
    return Container(
      constraints: BoxConstraints(minHeight: mobile ? 0 : 62),
      padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 16, vertical: 12),
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: mobile ? 8 : 14,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l.prototypeConnectTo, style: style),
          Wrap(
            spacing: mobile ? 6 : 7,
            runSpacing: mobile ? 6 : 7,
            children: [
              for (final name in names)
                _WifiToken(
                  name: name,
                  disconnect: disconnect,
                  editable: editable,
                ),
            ],
          ),
          Text(
            disconnect
                ? l.prototypeThenDisconnectVpn
                : l.prototypeThenConnectVpn,
            style: style.copyWith(
              color: disconnect ? palette.destructive : palette.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _WifiToken extends StatelessWidget {
  const _WifiToken({
    required this.name,
    required this.disconnect,
    required this.editable,
  });
  final String name;
  final bool disconnect;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final mobile = _mobile(context);
    final palette = ColorManager.palette(context);
    return Container(
      constraints: BoxConstraints(minHeight: mobile ? 28 : 30),
      padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 9, vertical: 4),
      decoration: BoxDecoration(
        color: disconnect ? palette.destructiveSurface : palette.muted,
        border: Border.all(
          color: disconnect
              ? Color.lerp(palette.border, palette.destructive, .28)!
              : palette.border,
        ),
        borderRadius: BorderRadius.circular(AppRadii.compact),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            editable ? LucideIcons.pencil : LucideIcons.wifi,
            size: editable ? 13 : 14,
            color: palette.mutedStrong,
          ),
          SizedBox(width: mobile ? 6 : 7),
          Flexible(
            child: Text(
              name,
              style:
                  (mobile
                          ? AppTypography.appleWifiToken
                          : AppTypography.appleWifiTokenDesktop)
                      .copyWith(
                        color: disconnect
                            ? palette.destructive
                            : palette.foreground,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkChoice extends StatelessWidget {
  const _NetworkChoice({required this.controller});
  final PolicyEditorController controller;

  @override
  Widget build(BuildContext context) {
    final mobile = _mobile(context);
    final palette = ColorManager.palette(context);
    final l = AppLocalizations.of(context)!;
    final ios = controller.platform == ConnectionPlatform.ios;
    final field = ios ? 'cellularAction' : 'ethernetAction';
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ios ? l.prototypeCellularNetwork : l.prototypeEthernet,
          style: mobile
              ? AppTypography.appleRuleTitle
              : AppTypography.appleRuleTitleDesktop,
        ),
        const SizedBox(height: 3),
        Text(
          ios ? l.prototypeWhenUsingCellular : l.prototypeWhenUsingEthernet,
          style:
              (mobile
                      ? AppTypography.appleRuleHint
                      : AppTypography.appleRuleHintDesktop)
                  .copyWith(color: palette.mutedForeground),
        ),
      ],
    );
    final options = Container(
      key: const ValueKey('apple-network-action-choice'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.muted,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: mobile ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (final choice in ['connect', 'disconnect'])
              if (mobile)
                Expanded(
                  child: _NetworkChoiceButton(
                    controller: controller,
                    field: field,
                    choice: choice,
                    mobile: true,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 88),
                  child: _NetworkChoiceButton(
                    controller: controller,
                    field: field,
                    choice: choice,
                    mobile: false,
                  ),
                ),
          ],
        ),
      ),
    );
    return Container(
      constraints: BoxConstraints(minHeight: mobile ? 0 : 70),
      padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 16, vertical: 12),
      child: mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [label, const SizedBox(height: 9), options],
            )
          : Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: 16),
                options,
              ],
            ),
    );
  }
}

class _NetworkChoiceButton extends StatelessWidget {
  const _NetworkChoiceButton({
    required this.controller,
    required this.field,
    required this.choice,
    required this.mobile,
  });

  final PolicyEditorController controller;
  final String field;
  final String choice;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final selected = controller.group('apple')[field] == choice;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: TextButton(
        key: ValueKey('$field-$choice'),
        onPressed: controller.blocked
            ? null
            : () => controller.update(field, choice, section: 'apple'),
        style: TextButton.styleFrom(
          minimumSize: Size(0, mobile ? 34 : 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: selected ? palette.primary : palette.mutedStrong,
          backgroundColor: selected ? palette.card : Colors.transparent,
          side: selected ? BorderSide(color: palette.primary) : BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.chip),
          ),
          textStyle: mobile
              ? AppTypography.appleNetworkAction
              : AppTypography.appleNetworkActionDesktop,
        ),
        child: Text(
          choice == 'connect'
              ? l.prototypeConnectAutomatically
              : l.prototypeDisconnectVpn,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _WifiFallback extends StatelessWidget {
  const _WifiFallback({required this.editable, this.onEdit});
  final bool editable;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final mobile = _mobile(context);
    final palette = ColorManager.palette(context);
    final l = AppLocalizations.of(context)!;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: mobile ? 8 : 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l.prototypeOtherWifiNetworks,
              style: mobile
                  ? AppTypography.appleRuleTitle
                  : AppTypography.appleRuleTitleDesktop,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: palette.muted,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(AppRadii.chip),
              ),
              child: Text(
                l.prototypeKeepCurrentConnection,
                style: mobile
                    ? AppTypography.appleFallbackPill
                    : AppTypography.appleFallbackPillDesktop,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l.prototypeKeepCurrentConnectionHint,
          style:
              (mobile
                      ? AppTypography.appleSettingHint
                      : AppTypography.appleSettingHintDesktop)
                  .copyWith(color: palette.mutedForeground),
        ),
      ],
    );
    final edit = TextButton(
      onPressed: onEdit,
      style: TextButton.styleFrom(
        foregroundColor: palette.primary,
        minimumSize: Size(0, mobile ? 45 : 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsetsDirectional.only(
          start: mobile ? 12 : 10,
          end: mobile ? 10 : 4,
        ),
        shape: const RoundedRectangleBorder(),
        textStyle: mobile
            ? AppTypography.appleWifiEdit
            : AppTypography.appleWifiEditDesktop,
      ),
      child: Row(
        mainAxisSize: mobile ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (mobile)
            Expanded(child: Text(l.prototypeEditWifiRules))
          else
            Text(l.prototypeEditWifiRules),
          const SizedBox(width: 5),
          const Icon(LucideIcons.chevronRightDir, size: 18),
        ],
      ),
    );
    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, editable ? 11 : 12),
            child: copy,
          ),
          if (editable) ...[Divider(height: 0, color: palette.border), edit],
        ],
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(child: copy),
          if (editable) ...[const SizedBox(width: 18), edit],
        ],
      ),
    );
  }
}

class AppleWifiEditorSection extends StatefulWidget {
  const AppleWifiEditorSection({
    super.key,
    required this.title,
    required this.description,
    required this.values,
    required this.otherValues,
    required this.onChanged,
    required this.enabled,
  });
  final String title;
  final String description;
  final List<String> values;
  final List<String> otherValues;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  @override
  State<AppleWifiEditorSection> createState() => _AppleWifiEditorSectionState();
}

class _AppleWifiEditorSectionState extends State<AppleWifiEditorSection> {
  late final List<TextEditingController> fields = widget.values
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
  void didUpdateWidget(AppleWifiEditorSection oldWidget) {
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
    final mobile = _mobile(context);
    final palette = ColorManager.palette(context);
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: mobile
              ? AppTypography.appleWifiHeading
              : AppTypography.appleWifiHeadingDesktop,
        ),
        SizedBox(height: mobile ? 4 : 5),
        Text(
          widget.description,
          style:
              (mobile
                      ? AppTypography.appleWifiDescription
                      : AppTypography.appleWifiDescriptionDesktop)
                  .copyWith(color: palette.mutedForeground),
        ),
        SizedBox(height: mobile ? 13 : 17),
        Container(
          padding: EdgeInsets.all(mobile ? 12 : 20),
          decoration: BoxDecoration(
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < widget.values.length; index++) ...[
                _WifiInputRow(
                  key: ObjectKey(fields[index]),
                  controller: fields[index],
                  label: '${widget.title} ${index + 1}',
                  removeLabel: '${l.prototypeRemoveWifi} ${index + 1}',
                  enabled: widget.enabled,
                  conflict:
                      widget.values[index].trim().isNotEmpty &&
                      widget.otherValues.contains(widget.values[index]),
                  onChanged: (_) => _publish(),
                  onRemove: () => _remove(index),
                ),
                SizedBox(height: mobile ? 9 : 12),
              ],
              OutlinedButton(
                onPressed: widget.enabled ? _add : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.primary,
                  side: BorderSide(color: palette.primary),
                  minimumSize: Size(0, mobile ? 47 : 54),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                  textStyle: mobile
                      ? AppTypography.appleWifiAdd
                      : AppTypography.appleWifiAddDesktop,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.plus, size: 18),
                    const SizedBox(width: 9),
                    Flexible(child: Text(l.prototypeAddWifi)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WifiInputRow extends StatelessWidget {
  const _WifiInputRow({
    super.key,
    required this.controller,
    required this.label,
    required this.removeLabel,
    required this.enabled,
    required this.conflict,
    required this.onChanged,
    required this.onRemove,
  });
  final TextEditingController controller;
  final String label;
  final String removeLabel;
  final bool enabled;
  final bool conflict;
  final ValueChanged<String> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final mobile = _mobile(context);
    final palette = ColorManager.palette(context);
    return Focus(
      child: Builder(
        builder: (context) => Container(
          constraints: BoxConstraints(minHeight: mobile ? 48 : 58),
          padding: EdgeInsetsDirectional.only(
            start: mobile ? 10 : 16,
            end: mobile ? 6 : 10,
          ),
          decoration: BoxDecoration(
            color: palette.card,
            border: Border.all(
              color: conflict
                  ? palette.destructive
                  : Focus.of(context).hasFocus
                  ? palette.primary
                  : palette.border,
            ),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.wifi,
                size: mobile ? 17 : 19,
                color: palette.mutedStrong,
              ),
              SizedBox(width: mobile ? 9 : 12),
              Expanded(
                child: Semantics(
                  label: label,
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: mobile
                        ? AppTypography.appleWifiInput
                        : AppTypography.appleWifiInputDesktop,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                    ),
                    onChanged: onChanged,
                  ),
                ),
              ),
              SizedBox(width: mobile ? 9 : 12),
              IconButton(
                onPressed: enabled ? onRemove : null,
                tooltip: removeLabel,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: mobile ? 34 : 36,
                  height: mobile ? 34 : 36,
                ),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  LucideIcons.circleX,
                  size: 18,
                  color: palette.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
