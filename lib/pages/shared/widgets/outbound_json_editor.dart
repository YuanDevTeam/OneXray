import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/json_editor.dart';
import 'package:onexray/service/shared/json_editing.dart';
import 'package:re_editor/re_editor.dart';

/// Outbound JSON input, compact by default or expanded in a page workspace.
class OutboundJsonEditor extends StatelessWidget {
  const OutboundJsonEditor({
    super.key,
    required this.controller,
    this.diagnostic,
    this.expand = false,
  });

  final CodeLineEditingController controller;
  final JsonDiagnostic? diagnostic;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final editor = AppJsonEditor(
      controller: controller,
      diagnostic: diagnostic,
      kind: JsonEditorKind.outbound,
      textStyle: AppTypography.importJson,
    );
    if (expand) return editor;
    final height =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint
        ? 340
        : 290;
    return SizedBox(
      height: AppJsonEditor.heightForViewport(context, height.toDouble()),
      child: editor,
    );
  }
}
