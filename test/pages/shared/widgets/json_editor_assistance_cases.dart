import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/json_editor.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/outbound_json_editor.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/json_editing.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// re_editor caches platform flags, so each platform gets its own test isolate.
void jsonEditorAssistanceTests(TargetPlatform platform) {
  final mobile = platform == TargetPlatform.android;
  final variant = TargetPlatformVariant.only(platform);
  late CodeLineEditingController controller;
  late String clipboard;

  setUp(() {
    clipboard = '';
    controller = CodeLineEditingController.fromText('{\n  "protocol": "vl"\n}');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });

  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  void editorTest(
    String description,
    WidgetTesterCallback body, {
    required TargetPlatformVariant variant,
  }) {
    testWidgets(description, (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await body(tester);
      } finally {
        semantics.dispose();
        // re_editor delays mobile cursor visibility by 100 ms without retaining
        // that timer. Let it complete before disposing the editing resources.
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }, variant: variant);
  }

  Future<void> pumpEditor(
    WidgetTester tester, {
    JsonDiagnostic? diagnostic,
    JsonEditorKind? kind,
    Locale locale = const Locale('en'),
    double keyboardHeight = 0,
    double textScale = 1,
    Widget Function(BuildContext, Widget)? homeBuilder,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 760);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.material(Brightness.light, mobile: mobile),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: ShadTheme(
            data: AppTheme.shad(Brightness.light, mobile: mobile),
            child: ShadToaster(child: child!),
          ),
        ),
        home: Builder(
          builder: (context) {
            final editor = AppJsonEditor(
              controller: controller,
              diagnostic: diagnostic,
              kind: kind,
            );
            return homeBuilder?.call(context, editor) ??
                Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: editor,
                  ),
                );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(AppJsonEditor)))!;

  Future<void> focusProtocol(WidgetTester tester) async {
    controller.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 17,
    );
    tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
  }

  editorTest('error keeps its source message and supports copy and location', (
    tester,
  ) async {
    const message = 'Core rejected the protocol: unsupported value';
    await pumpEditor(
      tester,
      diagnostic: const JsonDiagnostic(message, path: ['protocol']),
    );
    expect(find.text(message), findsOneWidget);
    expect(
      find.text(l10n(tester).jsonEditorErrorLocation(2, 15)),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip(l10n(tester).jsonEditorLocateError));
    await tester.pumpAndSettle();
    expect(controller.selectedText, '"vl"');
    expect(find.text(message), findsOneWidget);

    await tester.tap(find.byTooltip(l10n(tester).jsonEditorCopyError));
    await tester.pumpAndSettle();
    expect(clipboard, message);
    expect(tester.takeException(), isNull);
  }, variant: variant);

  editorTest('text edits invalidate old errors but selection changes do not', (
    tester,
  ) async {
    const message = 'An earlier save failed';
    await pumpEditor(tester, diagnostic: const JsonDiagnostic(message));
    expect(find.byTooltip(l10n(tester).jsonEditorLocateError), findsNothing);
    controller.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 2,
    );
    await tester.pump();
    expect(find.text(message), findsOneWidget);
    controller.replaceSelection(' ');
    await tester.pump();
    expect(find.text(message), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('json-editor-diagnostic')), findsNothing);
  }, variant: variant);

  editorTest('local syntax errors appear after a pause and can be selected', (
    tester,
  ) async {
    await pumpEditor(tester);
    controller.text = '{\n  "tag": @\n}';
    await tester.pump();
    expect(find.byKey(const ValueKey('json-editor-diagnostic')), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.text(l10n(tester).jsonEditorErrorLocation(2, 10)),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip(l10n(tester).jsonEditorLocateError));
    await tester.pumpAndSettle();
    expect(controller.selectedText, '@');
  }, variant: variant);

  editorTest('completion remains visible above keyboard in RTL and can undo', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      kind: JsonEditorKind.outbound,
      locale: const Locale('fa'),
      keyboardHeight: mobile ? 300 : 0,
    );
    await focusProtocol(tester);
    final suggestions = find.byKey(const ValueKey('json-editor-completions'));
    expect(suggestions, findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(AppJsonEditor))),
      TextDirection.rtl,
    );
    expect(
      Directionality.of(tester.element(find.byType(CodeEditor))),
      TextDirection.ltr,
    );
    expect(
      tester.getBottomLeft(suggestions).dy,
      lessThanOrEqualTo(760 - (mobile ? 300 : 0)),
    );
    expect(
      find.bySemanticsLabel(l10n(tester).jsonEditorSuggestion('vless')),
      findsOneWidget,
    );

    final original = controller.text;
    await tester.tap(find.text('vless'));
    await tester.pumpAndSettle();
    expect(controller.text, original.replaceFirst('vl', 'vless'));
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).focusNode!.hasFocus,
      isTrue,
    );
    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, original);
    expect(tester.takeException(), isNull);
  }, variant: variant);

  editorTest('nested TLS completion inserts a key and supports undo', (
    tester,
  ) async {
    const original =
        '{"streamSettings":{"finalmask":{"udp":[{"type":"xdns","settings":{"resolvers":[{"tlsConfig":{"echS":{}}}]}}]}}}';
    controller.text = original;
    await pumpEditor(tester, kind: JsonEditorKind.outbound);
    controller.selection = CodeLineSelection.collapsed(
      index: 0,
      offset: original.indexOf('echS') + 4,
    );
    tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    expect(find.text('echSockopt'), findsOneWidget);
    await tester.tap(find.text('echSockopt'));
    await tester.pumpAndSettle();
    expect(controller.text, original.replaceFirst('echS', 'echSockopt'));
    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.text, original);
    expect(tester.takeException(), isNull);
  }, variant: variant);

  editorTest('long diagnostics scroll within the editor bounds', (
    tester,
  ) async {
    final message = List.filled(60, 'Core diagnostic detail').join('\n');
    await pumpEditor(
      tester,
      diagnostic: JsonDiagnostic(message),
      keyboardHeight: mobile ? 300 : 0,
    );
    final panel = find.byKey(const ValueKey('json-editor-diagnostic'));
    expect(tester.getSize(panel).height, lessThanOrEqualTo(150));
    final scrollable = find.descendant(
      of: panel,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n(tester).jsonEditorCopyError));
    await tester.pumpAndSettle();
    expect(clipboard, message);
    expect(tester.takeException(), isNull);
  }, variant: variant);

  editorTest('no completions during IME composition or within a token', (
    tester,
  ) async {
    await pumpEditor(tester, kind: JsonEditorKind.outbound);
    await focusProtocol(tester);
    expect(
      find.byKey(const ValueKey('json-editor-completions')),
      findsOneWidget,
    );
    controller.composing = const TextRange(start: 15, end: 17);
    await tester.pump();
    expect(find.byKey(const ValueKey('json-editor-completions')), findsNothing);
    controller.clearComposing();
    controller.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 16,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('json-editor-completions')), findsNothing);
  }, variant: variant);

  editorTest('no completion context leaves editing unchanged', (tester) async {
    await pumpEditor(tester);
    await focusProtocol(tester);
    expect(find.byKey(const ValueKey('json-editor-completions')), findsNothing);
  }, variant: variant);

  editorTest('line-number gutter uses the same vertical origin as the source', (
    tester,
  ) async {
    await pumpEditor(tester);
    final gutter = find.byType(DefaultCodeLineNumber);
    final sourceTop = tester.getTopLeft(find.byType(CodeEditor)).dy;
    expect(tester.getTopLeft(gutter).dy, closeTo(sourceTop, 1));
    final lineNumbers = tester.widget<DefaultCodeLineNumber>(gutter);
    final paragraph = lineNumbers.notifier.value!.paragraphs.singleWhere(
      (line) => line.index == 1,
    );
    await tester.tapAt(
      Offset(
        tester.getCenter(gutter).dx,
        sourceTop + paragraph.offset.dy + paragraph.height / 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.selection.baseIndex, 1);
    expect(controller.selectedText, contains('"protocol"'));
  }, variant: variant);

  for (final locale in AppLocalizations.supportedLocales) {
    editorTest(
      'error actions and suggestions remain usable at 2x text in $locale',
      (tester) async {
        controller.text = '{\n  "protocol": ""\n}';
        const message =
            'Core diagnostic remains available for copying. Additional details may scroll.';
        await pumpEditor(
          tester,
          kind: JsonEditorKind.outbound,
          locale: locale,
          textScale: 2,
          keyboardHeight: mobile ? 300 : 0,
          diagnostic: const JsonDiagnostic(message, path: ['protocol']),
          homeBuilder: (context, editor) => Scaffold(
            body: Center(
              child: SizedBox(
                height: AppJsonEditor.heightForViewport(context, 340),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: editor,
                ),
              ),
            ),
          ),
        );
        controller.selection = const CodeLineSelection.collapsed(
          index: 1,
          offset: 15,
        );
        tester
            .widget<CodeEditor>(find.byType(CodeEditor))
            .focusNode!
            .requestFocus();
        await tester.pumpAndSettle();
        final suggestions = find.byKey(
          const ValueKey('json-editor-completions'),
        );
        expect(suggestions, findsOneWidget);
        final horizontal = tester
            .widget<SingleChildScrollView>(suggestions)
            .controller!
            .position;
        expect(horizontal.maxScrollExtent, greaterThan(0));
        final copy = find.byTooltip(l10n(tester).jsonEditorCopyError);
        final locate = find.byTooltip(l10n(tester).jsonEditorLocateError);
        expect(copy.hitTestable(), findsOneWidget);
        expect(locate.hitTestable(), findsOneWidget);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(clipboard, message);
        expect(
          Directionality.of(tester.element(find.byType(CodeEditor))),
          TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
      },
      variant: variant,
    );
  }

  if (mobile) {
    editorTest(
      'Raw-style scrolling form keeps the editor and candidates above page actions',
      (tester) async {
        await pumpEditor(
          tester,
          kind: JsonEditorKind.outbound,
          homeBuilder: (context, editor) => Scaffold(
            appBar: AppBar(title: const Text('Raw JSON')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(
                    height: 240,
                    child: Center(child: Text('Import and configuration name')),
                  ),
                  SizedBox(
                    height: AppJsonEditor.heightForViewport(context, 392),
                    child: editor,
                  ),
                  const SizedBox(
                    height: 100,
                    child: Text('Configuration notes'),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: PageActionBar(
              children: [
                ShadButton(
                  key: const ValueKey('save-action'),
                  onPressed: () {},
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );
        await focusProtocol(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        final suggestions = find.byKey(
          const ValueKey('json-editor-completions'),
        );
        expect(tester.getSize(find.byType(AppJsonEditor)).height, 230);
        expect(
          tester.getTopLeft(find.byType(CodeEditor)).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppBar)).dy),
        );
        expect(
          tester.getBottomLeft(suggestions).dy,
          lessThanOrEqualTo(
            tester.getTopLeft(find.byKey(const ValueKey('save-action'))).dy,
          ),
        );
        await tester.tap(find.text('vless'));
        await tester.pumpAndSettle();
        expect(controller.text, contains('"vless"'));
        expect(tester.takeException(), isNull);
      },
      variant: variant,
    );

    editorTest(
      'actual outbound dialog keeps candidates visible when the keyboard opens',
      (tester) async {
        await pumpEditor(
          tester,
          homeBuilder: (_, _) => AppDialogFrame(
            child: AppDialog(
              title: 'Edit server',
              subtitle: 'Example node',
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Xray outbound JSON'),
                    const SizedBox(height: 7),
                    OutboundJsonEditor(controller: controller),
                    const Text('Edit the complete outbound.'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('save-action'),
                  onPressed: () {},
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );
        await focusProtocol(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        final suggestions = find.byKey(
          const ValueKey('json-editor-completions'),
        );
        expect(tester.getSize(find.byType(OutboundJsonEditor)).height, 230);
        expect(
          tester.getTopLeft(find.byType(CodeEditor)).dy,
          greaterThanOrEqualTo(0),
        );
        expect(
          tester.getBottomLeft(suggestions).dy,
          lessThanOrEqualTo(
            tester.getTopLeft(find.byKey(const ValueKey('save-action'))).dy,
          ),
        );
        await tester.tap(find.text('vless'));
        await tester.pumpAndSettle();
        expect(controller.text, contains('"vless"'));
        expect(tester.takeException(), isNull);
      },
      variant: variant,
    );
  }

  if (!mobile) {
    editorTest('desktop accepts with Enter and Tab and dismisses with Escape', (
      tester,
    ) async {
      await pumpEditor(tester, kind: JsonEditorKind.outbound);
      await focusProtocol(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.text, contains('"vless"'));
      expect(controller.lineCount, 3);

      controller.undo();
      await focusProtocol(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('json-editor-completions')),
        findsNothing,
      );
      expect(controller.text, contains('"vl"'));

      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 16,
      );
      await focusProtocol(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(controller.text, contains('"vless"'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.lineCount, 4);
    }, variant: variant);

    editorTest('desktop arrows navigate candidates without moving the caret', (
      tester,
    ) async {
      controller.text = '{\n  "protocol": ""\n}';
      await pumpEditor(tester, kind: JsonEditorKind.outbound);
      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 15,
      );
      tester
          .widget<CodeEditor>(find.byType(CodeEditor))
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      final originalSelection = controller.selection;
      final firstCandidate = find
          .descendant(
            of: find.byKey(const ValueKey('json-editor-completions')),
            matching: find.byType(TextButton),
          )
          .first;
      final firstLabel =
          (tester.widget<TextButton>(firstCandidate).child! as Text).data!;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(controller.selection, originalSelection);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.text, contains('"$firstLabel"'));
    }, variant: variant);
  }
}
