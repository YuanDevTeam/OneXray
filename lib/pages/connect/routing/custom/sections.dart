import 'package:material_ui/material_ui.dart';

/// Every section shares one content surface at all window widths.
class CustomRoutingSections extends StatefulWidget {
  final Widget rules;
  final Widget options;
  final Widget dns;
  final Widget sniffing;

  const CustomRoutingSections({
    super.key,
    required this.rules,
    required this.options,
    required this.dns,
    required this.sniffing,
  });

  @override
  State<CustomRoutingSections> createState() => _CustomRoutingSectionsState();
}

class _CustomRoutingSectionsState extends State<CustomRoutingSections> {
  // Reparent whole sections together with their input and disclosure state.
  final _rules = GlobalKey();
  final _options = GlobalKey();
  final _dns = GlobalKey();
  final _sniffing = GlobalKey();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 20,
    children: [
      KeyedSubtree(key: _rules, child: widget.rules),
      KeyedSubtree(key: _options, child: widget.options),
      KeyedSubtree(key: _dns, child: widget.dns),
      KeyedSubtree(key: _sniffing, child: widget.sniffing),
    ],
  );
}
