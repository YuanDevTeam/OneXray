import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Theme;
import 'package:onexray/pages/theme/layout.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Keeps the native accessibility state aligned with switch interaction.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    this.enabled = true,
    this.onChanged,
    this.width,
    this.height,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final effectiveEnabled = enabled && onChanged != null;
    // ShadSwitch supplies toggled/tap semantics but omits enabled. iOS requires
    // an explicit enabled state when mapping a Flutter switch to UISwitch.
    final control = Semantics(
      enabled: effectiveEnabled,
      child: ShadSwitch(
        value: value,
        enabled: effectiveEnabled,
        onChanged: effectiveEnabled ? onChanged : null,
        width: width,
        height: height,
      ),
    );
    final touchExtent = AppLayout.touchExtent(
      0,
      platform: Theme.of(context).platform,
    );
    if (touchExtent == 0) return control;
    // The track keeps its configured dimensions. Its own recognizer wins taps
    // inside the track; this recognizer handles only the expanded touch area.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: effectiveEnabled ? () => onChanged!(!value) : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: touchExtent,
          minHeight: touchExtent,
        ),
        child: Center(widthFactor: 1, heightFactor: 1, child: control),
      ),
    );
  }
}
