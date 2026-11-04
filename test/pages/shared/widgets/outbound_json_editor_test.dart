import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/json_editor_workspace.dart';
import 'package:onexray/pages/shared/widgets/outbound_json_editor.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'landscape keyboard reveals the rendered caret without page assistance',
    (tester) async {
      final source = const JsonEncoder.withIndent('  ').convert({
        'values': [for (var i = 0; i < 40; i++) 'Item $i'],
      });
      final controller = CodeLineEditingController.fromText(source);
      addTearDown(controller.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1160, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.material(Brightness.light),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) =>
              ShadTheme(data: AppTheme.shad(Brightness.light), child: child!),
          home: Scaffold(
            appBar: AppBar(title: const Text('JSON')),
            body: JsonEditorWorkspace(
              header: const Text('Configuration JSON'),
              editor: OutboundJsonEditor(controller: controller, expand: true),
              footer: const Text('Stored locally'),
            ),
            bottomNavigationBar: PageActionBar(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Save')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final focus = tester
          .widget<CodeEditor>(find.byType(CodeEditor))
          .focusNode!;
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      focus.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      tester.view.physicalSize = const Size(844, 390);
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      // Wait through both geometry frames and the production reveal animation.
      // Deliberately do not ensureVisible or move any outer scroll position.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      final outer = find.byKey(const ValueKey('json-editor-workspace-scroll'));
      expect(outer, findsOneWidget);
      final viewport = tester.getRect(outer);
      final outerScroll = tester.state<ScrollableState>(
        find.descendant(of: outer, matching: find.byType(Scrollable)).first,
      );
      void expectCaretVisible() {
        final numbers = tester.widget<DefaultCodeLineNumber>(
          find.byType(DefaultCodeLineNumber),
        );
        final paragraph = numbers.notifier.value!.paragraphs.singleWhere(
          (paragraph) => paragraph.index == controller.selection.extentIndex,
        );
        final caret = paragraph.getOffset(
          controller.selection.extent.textPosition,
        )!;
        final render = tester.renderObject<RenderBox>(
          find.byType(DefaultCodeLineNumber),
        );
        final top = render
            .localToGlobal(Offset(0, paragraph.offset.dy + caret.dy))
            .dy;
        expect(top, greaterThanOrEqualTo(viewport.top - .01));
        expect(
          top + paragraph.preferredLineHeight,
          lessThanOrEqualTo(viewport.bottom + .01),
        );
        expect(focus.hasFocus, isTrue);
      }

      expect(controller.selection.extentIndex, 0);
      expectCaretVisible();
      final firstLineScroll = outerScroll.position.pixels;
      controller.moveCursorToPageEnd();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(controller.selection.extentIndex, controller.codeLines.length - 1);
      expectCaretVisible();
      expect(outerScroll.position.pixels, greaterThan(firstLineScroll));
      expect(controller.text, source);
      expect(
        find.widgetWithText(FilledButton, 'Save').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('expanded workspace fills the body and bounds keyboard chrome', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText(
      '{"tag":"Local draft","protocol":"socks"}',
    );
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var footerActions = 0;
    Future<void> show({required bool keyboard}) async {
      tester.view.physicalSize = keyboard
          ? const Size(844, 390)
          : const Size(1160, 720);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.material(Brightness.light),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard ? 200 : 0)),
            child: ShadTheme(
              data: AppTheme.shad(Brightness.light),
              child: child!,
            ),
          ),
          home: Scaffold(
            appBar: AppBar(title: const Text('JSON')),
            body: SafeArea(
              top: false,
              bottom: false,
              child: JsonEditorWorkspace(
                header: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const TextField(
                      decoration: InputDecoration(labelText: 'Name'),
                    ),
                    if (keyboard)
                      for (var i = 0; i < 12; i++) Text('Header guidance $i'),
                  ],
                ),
                editor: OutboundJsonEditor(
                  controller: controller,
                  expand: true,
                ),
                footer: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (keyboard)
                      for (var i = 0; i < 12; i++) Text('Footer feedback $i'),
                    TextButton(
                      key: const ValueKey('workspace-footer-action'),
                      onPressed: () => footerActions++,
                      child: const Text('Footer action'),
                    ),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: PageActionBar(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Save')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final editor = find.byType(OutboundJsonEditor);
    await show(keyboard: false);
    expect(tester.getSize(editor).width, 1160 - 56);
    expect(tester.getSize(editor).height, greaterThan(290));
    expect(
      find.ancestor(of: editor, matching: find.byType(Scrollable)),
      findsNothing,
    );
    final original = tester.widget<CodeEditor>(find.byType(CodeEditor));
    final focus = original.focusNode!;
    focus.requestFocus();
    await tester.pump();
    await show(keyboard: true);
    final rect = tester.getRect(editor);
    expect(rect.width, 844 - 56);
    expect(
      rect.height,
      greaterThanOrEqualTo(AppLayout.jsonEditorMinHeight - .01),
    );
    final expanded = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(expanded.controller, same(controller));
    expect(expanded.focusNode, same(focus));
    expect(expanded.scrollController, same(original.scrollController));
    expect(focus.hasFocus, isTrue);
    final header = find.byKey(const ValueKey('json-editor-workspace-header'));
    final footer = find.byKey(const ValueKey('json-editor-workspace-footer'));
    ScrollableState scroll(Finder panel) => tester.state<ScrollableState>(
      find.descendant(of: panel, matching: find.byType(Scrollable)).first,
    );
    final headerScroll = scroll(header);
    final footerScroll = scroll(footer);
    final outer = find.byKey(const ValueKey('json-editor-workspace-scroll'));
    final outerScroll = scroll(outer);
    expect(outerScroll.position.maxScrollExtent, greaterThan(0));
    final viewport = tester.getRect(outer);
    expect(viewport.bottom, lessThanOrEqualTo(390 - 200));
    final save = find.widgetWithText(FilledButton, 'Save');
    final saveRect = tester.getRect(save);
    await tester.ensureVisible(editor);
    await tester.pumpAndSettle();
    expect(tester.getRect(editor).overlaps(viewport), isTrue);
    outerScroll.position.jumpTo(outerScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final scrolledEditor = tester.getRect(editor);
    expect(headerScroll.position.maxScrollExtent, greaterThan(0));
    expect(footerScroll.position.maxScrollExtent, greaterThan(0));
    expect(headerScroll.position, isNot(same(footerScroll.position)));
    headerScroll.position.jumpTo(headerScroll.position.maxScrollExtent);
    footerScroll.position.jumpTo(footerScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getRect(editor), scrolledEditor);
    expect(tester.getRect(save), saveRect);
    expect(save.hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workspace-footer-action')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('workspace-footer-action')));
    expect(footerActions, 1);
    expect(controller.text, '{"tag":"Local draft","protocol":"socks"}');
    focus.requestFocus();
    await tester.pump();
    await show(keyboard: false);
    expect(outer, findsNothing);
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).focusNode,
      same(focus),
    );
    expect(focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long outbound JSON stays bounded, scrollable and LTR in fa', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText(
      const JsonEncoder.withIndent('  ').convert({
        'outbounds': List.generate(
          60,
          (index) => {
            'tag': 'Node $index',
            'protocol': 'vless',
            'settings': {'address': 'example.test'},
          },
        ),
        'last': 'END_OF_OUTBOUND_JSON',
      }),
    );
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final (width, height) in [(427.0, 340.0), (1000.0, 290.0)]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.material(Brightness.light, mobile: width < 720),
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => ShadTheme(
            data: AppTheme.shad(Brightness.light, mobile: width < 720),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: OutboundJsonEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editor = find.byType(OutboundJsonEditor);
      final codeEditor = find.descendant(
        of: editor,
        matching: find.byType(CodeEditor),
      );
      expect(tester.getSize(editor).height, height);
      expect(Directionality.of(tester.element(editor)), TextDirection.rtl);
      expect(Directionality.of(tester.element(codeEditor)), TextDirection.ltr);
      final widget = tester.widget<CodeEditor>(codeEditor);
      expect(widget.controller, same(controller));
      expect(widget.autofocus, isFalse);
      expect(widget.wordWrap, isFalse);
      expect(widget.style?.codeTheme, isNotNull);
      expect(tester.takeException(), isNull);

      final scrollable = find.descendant(
        of: codeEditor,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              (widget.axisDirection == AxisDirection.down ||
                  widget.axisDirection == AxisDirection.up),
        ),
      );
      expect(scrollable, findsOneWidget);
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));
      expect(controller.text, contains('END_OF_OUTBOUND_JSON'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
