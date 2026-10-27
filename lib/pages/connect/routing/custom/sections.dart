import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/layout.dart';

/// Rule editing and runtime settings adapt independently to the content width.
class CustomRoutingSections extends StatefulWidget {
  final Widget rules;
  final Widget? editor;
  final Widget options;
  final Widget dns;
  final Widget sniffing;

  const CustomRoutingSections({
    super.key,
    required this.rules,
    this.editor,
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
  final _editor = GlobalKey();
  final _options = GlobalKey();
  final _dns = GlobalKey();
  final _sniffing = GlobalKey();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rules = KeyedSubtree(key: _rules, child: widget.rules);
      final editor = widget.editor == null
          ? null
          : KeyedSubtree(key: _editor, child: widget.editor!);
      final options = KeyedSubtree(key: _options, child: widget.options);
      final dns = KeyedSubtree(key: _dns, child: widget.dns);
      final sniffing = KeyedSubtree(key: _sniffing, child: widget.sniffing);
      final Widget workspace;
      if (editor != null && constraints.maxWidth >= 876) {
        workspace = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            Expanded(child: rules),
            Expanded(child: editor),
          ],
        );
      } else {
        workspace = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [rules, ?editor],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          workspace,
          if (constraints.maxWidth >= AppLayout.mobileBreakpoint)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                Expanded(child: dns),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: [options, sniffing],
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [options, dns, sniffing],
            ),
        ],
      );
    },
  );
}
