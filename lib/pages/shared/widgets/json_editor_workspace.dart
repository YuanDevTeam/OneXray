import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/layout.dart';

/// A bounded page body. The enclosing Scaffold/SafeArea owns system insets.
class JsonEditorWorkspace extends StatefulWidget {
  const JsonEditorWorkspace({
    super.key,
    required this.editor,
    this.header,
    this.footer,
  });

  final Widget editor;
  final Widget? header;
  final Widget? footer;

  @override
  State<JsonEditorWorkspace> createState() => _JsonEditorWorkspaceState();
}

class _JsonEditorWorkspaceState extends State<JsonEditorWorkspace> {
  // Adding the short-screen viewport must not replace the editor's focus,
  // selection or internal scroll controllers.
  final _canvasKey = GlobalKey();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      assert(
        constraints.hasBoundedWidth && constraints.hasBoundedHeight,
        'JsonEditorWorkspace requires bounded page-body constraints.',
      );
      final mobile =
          MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
      // Shrink chrome spacing when a keyboard or a short window leaves little
      // body space. Natural-height chrome never takes the editor's whole slot.
      final spacingScale = math.min(1.0, constraints.maxHeight / 240);
      final top = 16 * spacingScale;
      final bottom = 12 * spacingScale;
      final headerGap = widget.header == null ? 0.0 : 16 * spacingScale;
      final footerGap = widget.footer == null ? 0.0 : 7 * spacingScale;
      final panelCount =
          (widget.header == null ? 0 : 1) + (widget.footer == null ? 0 : 1);
      final spacingHeight = top + bottom + headerGap + footerGap;
      final canvasHeight = math.max(
        constraints.maxHeight,
        spacingHeight + AppLayout.jsonEditorMinHeight + 48 * panelCount,
      );
      final contentHeight = canvasHeight - spacingHeight;
      // Reserve the minimum editor height and a usable viewport for each panel.
      // Short content keeps its natural height; long content scrolls locally.
      final chromeLimit = panelCount == 0
          ? 0.0
          : math.min(
              contentHeight / 4,
              (contentHeight - AppLayout.jsonEditorMinHeight) / panelCount,
            );
      final canvas = Padding(
        key: _canvasKey,
        padding: EdgeInsets.fromLTRB(
          mobile ? AppSpacing.mobilePage : AppSpacing.page,
          top,
          mobile ? AppSpacing.mobilePage : AppSpacing.page,
          bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.header != null) ...[
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: chromeLimit),
                child: SingleChildScrollView(
                  key: const ValueKey('json-editor-workspace-header'),
                  primary: false,
                  child: widget.header,
                ),
              ),
              SizedBox(height: headerGap),
            ],
            Expanded(
              key: const ValueKey('json-editor-workspace-editor'),
              child: widget.editor,
            ),
            if (widget.footer != null) ...[
              SizedBox(height: footerGap),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: chromeLimit),
                child: SingleChildScrollView(
                  key: const ValueKey('json-editor-workspace-footer'),
                  primary: false,
                  child: widget.footer,
                ),
              ),
            ],
          ],
        ),
      );
      if (canvasHeight > constraints.maxHeight) {
        return SingleChildScrollView(
          key: const ValueKey('json-editor-workspace-scroll'),
          primary: false,
          child: SizedBox(height: canvasHeight, child: canvas),
        );
      }
      return canvas;
    },
  );
}
