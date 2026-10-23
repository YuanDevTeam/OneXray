import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/font.dart';

/// Keeps editing resources local while the owning page Cubit owns the value.
class DnsTextField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? hint;
  final String? errorText;
  final FocusNode? focusNode;

  const DnsTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.hint,
    this.errorText,
    this.focusNode,
  });

  @override
  State<DnsTextField> createState() => _DnsTextFieldState();
}

class _DnsTextFieldState extends State<DnsTextField> {
  late final controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant DnsTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.value) controller.text = widget.value;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      TextField(
        controller: controller,
        focusNode: widget.focusNode,
        onChanged: widget.onChanged,
        enabled: widget.enabled,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        style: AppTypography.settingsInput,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: widget.errorText,
          errorMaxLines: 3,
        ),
      ),
      if (widget.hint != null)
        Text(widget.hint!, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
