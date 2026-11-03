import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/core/tools/json_document.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/widgets/json_editor_state.dart';
import 'package:onexray/pages/shared/widgets/json_editor_toolbar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/shared/json_editing.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

class AppJsonEditor extends StatefulWidget {
  const AppJsonEditor({
    super.key,
    required this.controller,
    this.textStyle,
    this.diagnostic,
    this.kind,
    this.domainSuggestions = const [],
    this.ipSuggestions = const [],
  });

  final CodeLineEditingController controller;
  final TextStyle? textStyle;
  final JsonDiagnostic? diagnostic;
  final JsonEditorKind? kind;
  final List<String> domainSuggestions;
  final List<String> ipSuggestions;

  /// Call above a Scaffold that consumes viewInsets, or inside a dialog frame.
  /// A focused editor must fit alongside the keyboard and fixed page actions.
  static double heightForViewport(BuildContext context, double normalHeight) {
    final media = MediaQuery.of(context);
    if (media.viewInsets.bottom == 0) return normalHeight;
    final visibleHeight = math.max(
      0.0,
      media.size.height - media.viewInsets.bottom - media.padding.vertical,
    );
    return math.min(normalHeight, visibleHeight / 2);
  }

  @override
  State<AppJsonEditor> createState() => _AppJsonEditorState();
}

class _AppJsonEditorState extends State<AppJsonEditor>
    with WidgetsBindingObserver {
  final _toolbar = AppJsonEditorToolbar();
  final _focus = FocusNode();
  final _scroll = CodeScrollController();
  final _suggestionScroll = ScrollController();
  late JsonEditorCubit _cubit;

  @override
  void initState() {
    super.initState();
    _createCubit();
    _focus.addListener(_focusChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _createCubit() {
    _cubit = JsonEditorCubit(
      controller: widget.controller,
      diagnostic: widget.diagnostic,
      kind: widget.kind,
      domainSuggestions: widget.domainSuggestions,
      ipSuggestions: widget.ipSuggestions,
    );
    _cubit.setFocused(_focus.hasFocus);
  }

  @override
  void didUpdateWidget(AppJsonEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      unawaited(_cubit.close());
      _createCubit();
      return;
    }
    if (oldWidget.diagnostic != widget.diagnostic) {
      _cubit.updateDiagnostic(widget.diagnostic);
    }
    if (oldWidget.kind != widget.kind ||
        oldWidget.domainSuggestions != widget.domainSuggestions ||
        oldWidget.ipSuggestions != widget.ipSuggestions) {
      _cubit.configure(
        kind: widget.kind,
        domainSuggestions: widget.domainSuggestions,
        ipSuggestions: widget.ipSuggestions,
      );
    }
  }

  void _focusChanged() {
    _cubit.setFocused(_focus.hasFocus);
    if (_focus.hasFocus) _revealEditor();
  }

  @override
  void didChangeMetrics() {
    if (_focus.hasFocus) _revealEditor();
  }

  void _revealEditor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus) return;
      final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
      final render = context.findRenderObject();
      if (scrollable == null || render == null) return;
      scrollable.position.ensureVisible(
        render,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 120),
      );
    });
  }

  @override
  void deactivate() {
    _toolbar.hide(context);
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cubit.close());
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _scroll.dispose();
    _scroll.verticalScroller.dispose();
    _scroll.horizontalScroller.dispose();
    _suggestionScroll.dispose();
    _toolbar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<JsonEditorCubit, JsonEditorState>(
      bloc: _cubit,
      builder: (context, state) => LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildEditor(context, state)),
            if (state.completions.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(112, constraints.maxHeight * .3),
                ),
                child: _buildCompletions(context, state),
              ),
            if (state.diagnostic != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(150, constraints.maxHeight * .42),
                ),
                child: _buildDiagnostic(context, state),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context, JsonEditorState state) {
    final palette = ColorManager.palette(context);
    final style = widget.textStyle ?? AppTypography.jsonEditor;
    final codeTheme = Map<String, TextStyle>.from(
      Theme.of(context).brightness == Brightness.dark
          ? atomOneDarkTheme
          : atomOneLightTheme,
    );
    final rootStyle = codeTheme['root'];
    if (rootStyle != null) {
      codeTheme['root'] = rootStyle.copyWith(
        backgroundColor: Colors.transparent,
      );
    }
    final lineNumberStyle = style.copyWith(
      color: palette.mutedForeground,
      fontFamily: AppFontFamily.mono,
    );

    // re_editor still uses the SDK's Material/Cupertino widgets.
    // ignore: deprecated_member_use
    return MaterialUiCompatibilityBridge(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: CodeEditor(
          controller: widget.controller,
          focusNode: _focus,
          scrollController: _scroll,
          toolbarController: _toolbar,
          shortcutOverrideActions: state.completions.isEmpty
              ? null
              : {
                  CodeShortcutCursorMoveIntent:
                      CallbackAction<CodeShortcutCursorMoveIntent>(
                        onInvoke: (intent) {
                          if (intent.direction == AxisDirection.up) {
                            _cubit.selectCompletion(-1);
                          } else if (intent.direction == AxisDirection.down) {
                            _cubit.selectCompletion(1);
                          } else {
                            widget.controller.moveCursor(intent.direction);
                          }
                          return null;
                        },
                      ),
                  CodeShortcutNewLineIntent:
                      CallbackAction<CodeShortcutNewLineIntent>(
                        onInvoke: (_) {
                          _applyCompletion();
                          return null;
                        },
                      ),
                  CodeShortcutIndentIntent:
                      CallbackAction<CodeShortcutIndentIntent>(
                        onInvoke: (_) {
                          _applyCompletion();
                          return null;
                        },
                      ),
                  CodeShortcutEscIntent: CallbackAction<CodeShortcutEscIntent>(
                    onInvoke: (_) {
                      _cubit.dismissCompletions();
                      return null;
                    },
                  ),
                },
          autofocus: false,
          autocompleteSymbols: true,
          wordWrap: false,
          padding: EdgeInsets.symmetric(
            horizontal: 13,
            vertical:
                MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint
                ? 14
                : 12,
          ),
          border: Border.all(color: palette.input),
          borderRadius: BorderRadius.circular(AppRadii.control),
          clipBehavior: Clip.antiAlias,
          style: CodeEditorStyle(
            fontFamily: AppFontFamily.mono,
            fontSize: style.fontSize,
            fontHeight: style.height,
            textColor: palette.foreground,
            backgroundColor: palette.card,
            selectionColor: palette.selection,
            cursorColor: palette.primary,
            cursorLineColor: palette.primary.withValues(alpha: .05),
            codeTheme: CodeHighlightTheme(
              languages: {'json': CodeHighlightThemeMode(mode: langJson)},
              theme: codeTheme,
            ),
          ),
          indicatorBuilder: (context, editingController, _, notifier) =>
              Container(
                color: Color.lerp(palette.card, palette.surfaceHover, .76),
                // Paragraph offsets already include the editor's top padding.
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                  textStyle: lineNumberStyle,
                  focusedTextStyle: lineNumberStyle.copyWith(
                    color: palette.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          leadingDivider: Container(width: 1, color: palette.border),
        ),
      ),
    );
  }

  Widget _buildDiagnostic(BuildContext context, JsonEditorState state) {
    final l10n = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final diagnostic = state.diagnostic!;
    final range = state.range;
    final position = range == null
        ? null
        : _cubit.document.positionAt(range.start);
    return DecoratedBox(
      key: const ValueKey('json-editor-diagnostic'),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: Theme.of(context).colorScheme.error),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: position == null
                      ? const SizedBox.shrink()
                      : Text(
                          l10n.jsonEditorErrorLocation(
                            position.line + 1,
                            position.column + 1,
                          ),
                        ),
                ),
                IconButton(
                  onPressed: () => _copyDiagnostic(diagnostic),
                  icon: const Icon(LucideIcons.copy, size: 16),
                  tooltip: l10n.jsonEditorCopyError,
                ),
                if (range != null)
                  IconButton(
                    onPressed: () => _locateDiagnostic(range),
                    icon: const Icon(LucideIcons.locate, size: 16),
                    tooltip: l10n.jsonEditorLocateError,
                  ),
              ],
            ),
            Semantics(
              liveRegion: true,
              child: Text(diagnostic.message, textDirection: TextDirection.ltr),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyDiagnostic(JsonDiagnostic diagnostic) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await Clipboard.setData(ClipboardData(text: diagnostic.message));
      if (!mounted) return;
      ContextAlert.showToast(
        context,
        l10n.actionResult(l10n.jsonEditorCopyError, l10n.resultSuccess),
      );
    } catch (_) {
      if (mounted) ContextAlert.showToast(context, l10n.prototypeCopyFailed);
    }
  }

  void _locateDiagnostic(JsonSourceRange range) {
    final selection = _cubit.selectionFor(range);
    widget.controller.selection = selection;
    _focus.requestFocus();
    _scroll.makeVisible(selection.base);
  }

  Widget _buildCompletions(BuildContext context, JsonEditorState state) {
    final l10n = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return CodeEditorTapRegion(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.jsonEditorSuggestions,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              SingleChildScrollView(
                key: const ValueKey('json-editor-completions'),
                controller: _suggestionScroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (
                      var index = 0;
                      index < state.completions.length;
                      index++
                    )
                      Builder(
                        builder: (context) {
                          final completion = state.completions[index];
                          final selected = index == state.selectedCompletion;
                          if (selected) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (context.mounted) {
                                Scrollable.of(context).position.ensureVisible(
                                  context.findRenderObject()!,
                                  alignment: .5,
                                  duration: const Duration(milliseconds: 100),
                                );
                              }
                            });
                          }
                          return Semantics(
                            selected: selected,
                            child: TextButton(
                              onPressed: () => _applyCompletion(index),
                              style: TextButton.styleFrom(
                                backgroundColor: selected
                                    ? palette.selection
                                    : null,
                              ),
                              child: Text(
                                completion.label,
                                textDirection: TextDirection.ltr,
                                semanticsLabel: l10n.jsonEditorSuggestion(
                                  completion.label,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyCompletion([int? index]) {
    _cubit.applyCompletion(index);
    _focus.requestFocus();
  }
}
