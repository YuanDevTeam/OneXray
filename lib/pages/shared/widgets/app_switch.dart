import 'package:flutter/widgets.dart';
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
    return Semantics(
      enabled: effectiveEnabled,
      child: ShadSwitch(
        value: value,
        enabled: effectiveEnabled,
        onChanged: effectiveEnabled ? onChanged : null,
        width: width,
        height: height,
      ),
    );
  }
}
