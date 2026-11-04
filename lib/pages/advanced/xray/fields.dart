import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';

/// Detail forms keep their labels above full-width controls on every device.
class XrayLabeledField extends StatelessWidget {
  const XrayLabeledField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      Text(
        label,
        style: AppTypography.fieldLabel.copyWith(
          color: ColorManager.primaryText(context),
        ),
      ),
      Semantics(
        label: label,
        child: SizedBox(width: double.infinity, child: child),
      ),
    ],
  );
}

class XrayToggleField extends StatelessWidget {
  const XrayToggleField({
    super.key,
    this.switchKey,
    required this.title,
    this.description,
    required this.value,
    required this.onChanged,
  });

  final Key? switchKey;
  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
    title: title,
    subtitleWidget: description == null
        ? null
        : Text(
            description!,
            style: AppTypography.supporting.copyWith(
              color: ColorManager.secondaryText(context),
            ),
          ),
    titleMaxLines: 4,
    enabled: onChanged != null,
    contentPadding: const EdgeInsets.symmetric(vertical: 10),
    onTap: onChanged == null ? null : () => onChanged!(!value),
    leading: Semantics(
      label: title,
      child: AppSwitch(
        key: switchKey,
        value: value,
        enabled: onChanged != null,
        onChanged: onChanged,
      ),
    ),
  );
}
