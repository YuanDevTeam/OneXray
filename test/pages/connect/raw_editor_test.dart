import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/connect/json_editor/controller.dart';
import 'package:onexray/pages/connect/json_editor/page.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/json_editor.dart';
import 'package:onexray/pages/shared/widgets/json_editor_workspace.dart';
import 'package:onexray/pages/shared/widgets/configuration_transfer.dart';
import 'package:onexray/service/connect/raw/editor.dart';
import 'package:onexray/service/connect/routing/custom/advanced.dart';
import 'package:onexray/service/connect/routing/custom/editor.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/fake_geodata_import.dart';

void main() {
  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
  });
  testWidgets(
    'Raw save follows name and JSON while draft loading does not connect',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final coordinator = ConnectionCoordinator(database: db);
      final controller = JsonConfigurationEditorController(
        configurationId: null,
        service: RawEditorService(database: db, coordinator: coordinator),
      );
      addTearDown(() async {
        await controller.close();
        coordinator.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('Draft')),
        ),
      );
      await controller.load(tester.element(find.text('Draft')));
      expect(controller.canSave, isFalse);
      final changed = controller.stream.firstWhere(
        (state) => state.name == 'Private configuration',
      );
      controller.name.text = 'Private configuration';
      await changed;
      expect(controller.canSave, isTrue);
      controller.text.text = '';
      expect(controller.canSave, isFalse);
      controller.text.text = '{}';
      expect(controller.canSave, isTrue);
      expect(await db.coreConfigDao.allRawRowsWithData, isEmpty);
    },
  );

  testWidgets('Raw save retains transfer resources until the save finishes', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final coordinator = ConnectionCoordinator(database: db);
    final service = _PendingRawSave(database: db, coordinator: coordinator);
    final controller = JsonConfigurationEditorController(
      configurationId: null,
      service: service,
    );
    addTearDown(() async {
      coordinator.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('Draft')),
      ),
    );
    final context = tester.element(find.text('Draft'));
    await controller.load(context);
    controller.name.text = 'Private configuration';

    final saving = controller.save(context);
    await service.started.future;
    unawaited(controller.close());
    await tester.pump();
    expect(controller.transfers.isClosed, isFalse);

    service.result.complete(1);
    await saving;
    await tester.pump();
    expect(controller.transfers.isClosed, isTrue);
  });

  testWidgets('plain JSON editor scrolls long content without a second frame', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(427, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = CodeLineEditingController.fromText(
      List.generate(100, (i) => '  "line$i": $i,').join('\n'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.material(Brightness.light, mobile: true),
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            height: 390,
            child: AppJsonEditor(controller: controller),
          ),
        ),
      ),
    );
    expect(find.text('xray.json'), findsNothing);
    final editor = find.byType(CodeEditor);
    final vertical = find.descendant(
      of: editor,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            (widget.axisDirection == AxisDirection.down ||
                widget.axisDirection == AxisDirection.up),
      ),
    );
    expect(vertical, findsOneWidget);
    final position = tester.state<ScrollableState>(vertical).position;
    expect(position.maxScrollExtent, greaterThan(500));
    position.jumpTo(500);
    await tester.pumpAndSettle();
    expect(position.pixels, 500);
    expect(tester.takeException(), isNull);
  });

  for (final advanced in [false, true]) {
    for (final size in const [
      Size(390, 844),
      Size(1032, 1376),
      Size(1160, 720),
    ]) {
      testWidgets(
        '${advanced ? "advanced" : "Raw"} JSON fills the remaining workspace at $size',
        (tester) async {
          final fixture = _DiagnosticFixture(advanced);
          addTearDown(fixture.dispose);
          final session = await _mountFullEditor(tester, fixture, size: size);
          final l = AppLocalizations.of(session.context)!;
          final workspace = find.byType(JsonEditorWorkspace);
          final editor = find.byType(AppJsonEditor);
          final slot = find.byKey(
            const ValueKey('json-editor-workspace-editor'),
          );
          final header = find.byKey(
            const ValueKey('json-editor-workspace-header'),
          );
          final footer = find.byKey(
            const ValueKey('json-editor-workspace-footer'),
          );
          expect(workspace, findsOneWidget);
          expect(editor, findsOneWidget);
          expect(
            find.ancestor(
              of: editor,
              matching: find.byType(SingleChildScrollView),
            ),
            findsNothing,
          );
          expect(
            find.ancestor(of: editor, matching: find.byType(ShadCard)),
            findsNothing,
          );
          final editorRect = tester.getRect(editor);
          expect(editorRect, tester.getRect(slot));
          final gutter = size.width <= 720 ? 16.0 : 28.0;
          expect(editorRect.left, closeTo(gutter, .01));
          expect(editorRect.right, closeTo(size.width - gutter, .01));
          expect(editorRect.top, greaterThan(tester.getRect(header).bottom));
          expect(editorRect.bottom, lessThan(tester.getRect(footer).top));
          expect(editorRect.height, greaterThan(0));
          if (size.width > 1000) {
            expect(editorRect.width, greaterThan(960));
          }
          expect(
            find.descendant(
              of: footer,
              matching: find.byType(ConfigurationTransferTools),
            ),
            findsOneWidget,
          );
          final nameField = find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                identical(widget.controller, fixture.controller.name),
          );
          expect(
            find.descendant(of: header, matching: nameField),
            findsOneWidget,
          );
          expect(tester.widget<TextField>(nameField).maxLength, 32);
          if (advanced) {
            expect(
              find.ancestor(
                of: nameField,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Semantics &&
                      widget.properties.label == l.configurationNameLabel,
                ),
              ),
              findsOneWidget,
            );
            expect(find.byTooltip(l.prototypeDocumentation), findsOneWidget);
            expect(
              find.byTooltip('${l.pageHelp} · ${l.routingAdvancedCardTitle}'),
              findsOneWidget,
            );
          }
          await tester.enterText(nameField, 'Workspace draft');
          final source = const JsonEncoder.withIndent('  ').convert({
            'outbounds': [{}],
            'routing': {'rules': []},
            'notes': List.generate(160, (index) => 'Line $index'),
          });
          fixture.controller.text.text = source;
          await tester.pumpAndSettle();
          final vertical = find.descendant(
            of: find.byType(CodeEditor),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  (widget.axisDirection == AxisDirection.down ||
                      widget.axisDirection == AxisDirection.up),
            ),
          );
          expect(vertical, findsOneWidget);
          final position = tester.state<ScrollableState>(vertical).position;
          expect(position.maxScrollExtent, greaterThan(400));
          position.jumpTo(320);
          await tester.pumpAndSettle();
          expect(position.pixels, 320);
          final previousHeight = tester.getSize(editor).height;
          final previousWorkspaceHeight = tester.getSize(workspace).height;
          final previousHeaderHeight = tester.getSize(header).height;
          final previousFooterRect = tester.getRect(footer);
          tester.view.physicalSize = Size(size.width, size.height + 200);
          await tester.pumpAndSettle();
          // Wrapped tools (including Linux's Copy link) can expand their capped
          // footer as the viewport grows. The editor fills the space left over.
          final headerGrowth =
              tester.getSize(header).height - previousHeaderHeight;
          final footerGrowth =
              tester.getSize(footer).height - previousFooterRect.height;
          expect(
            tester.getSize(workspace).height,
            closeTo(previousWorkspaceHeight + 200, .01),
          );
          expect(
            tester.getSize(editor).height,
            closeTo(previousHeight + 200 - headerGrowth - footerGrowth, .01),
          );
          expect(tester.getRect(editor), tester.getRect(slot));
          expect(
            tester.getRect(footer).bottom,
            closeTo(previousFooterRect.bottom + 200, .01),
          );
          expect(fixture.controller.name.text, 'Workspace draft');
          expect(fixture.controller.text.text, source);
          expect(fixture.controller.state.dirty, isTrue);
          expect(position.pixels, 320);
          expect(session.result.isCompleted, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'advanced editor uses its own template and keeps imported fields on save',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final coordinator = ConnectionCoordinator(database: db);
      final service = _PendingAdvancedSave(
        database: db,
        coordinator: coordinator,
      );
      final controller = JsonConfigurationEditorController(
        configurationId: null,
        kind: ConfigurationKind.customAdvanced,
        customService: service,
      );
      addTearDown(() async {
        await controller.close();
        coordinator.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('Advanced draft')),
        ),
      );
      final context = tester.element(find.text('Advanced draft'));
      await controller.load(context);
      expect(controller.advanced, isTrue);
      expect(controller.canSave, isFalse);
      expect(controller.text.text, contains('"routeOnly": true'));
      controller.name.text = 'Independent DNS';
      controller.text.text = '''{"outbounds":[{},{}],"dns":{"hosts":{"example.test":"192.0.2.1"}},"inbounds":[{"tag":"tunIn","sniffing":{"enabled":false}}],"routing":{"domainStrategy":"AsIs","rules":[]}}''';
      final expected = AdvancedRoutingDocument.parse(controller.text.text).state
          .toJson();
      final saving = controller.save(context);
      final draft = await service.started.future;
      expect(draft.state.advanced, isTrue);
      expect(draft.state.entryCount, 2);
      expect(draft.state.toJson(), expected);
      expect(draft.state.name, 'Independent DNS');
      expect(controller.state.busy, isTrue);
      expect(controller.state.deleting, isFalse);
      service.result.complete(null);
      await saving;
      expect(controller.error, isNull);
      expect(controller.canSave, isTrue);
      expect(await db.routingProfileDao.allRows, isEmpty);
      expect(await db.coreConfigDao.allRawRowsWithData, isEmpty);
    },
  );

  for (final (advanced, existing) in [
    (false, false),
    (true, false),
    (true, true),
  ]) {
    testWidgets(
      '${advanced ? "advanced" : "Raw"} mobile footer keeps cancel guarded with large text and keyboard (existing: $existing)',
      (tester) async {
        final fixture = _DiagnosticFixture(
          advanced,
          configurationId: existing ? 7 : null,
        );
        addTearDown(fixture.dispose);
        final session = await _mountFullEditor(
          tester,
          fixture,
          size: const Size(320, 844),
          textScale: 1.5,
          locale: const Locale('ru'),
        );
        final controller = fixture.controller;
        final l = AppLocalizations.of(session.context)!;
        controller.name.text = 'Unsaved';
        controller.text.text = '{"outbounds":[{}]}';
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        tester
            .widget<CodeEditor>(find.byType(CodeEditor))
            .focusNode!
            .requestFocus();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(JsonEditorWorkspace), findsOneWidget);
        expect(
          tester.getSize(find.byType(AppJsonEditor)).height,
          greaterThanOrEqualTo(AppLayout.jsonEditorMinHeight),
        );

        final cancel = find.widgetWithText(ShadButton, l.prototypeCancel);
        final save = find.widgetWithText(ShadButton, l.prototypeSave);
        final delete = find.widgetWithText(ShadButton, l.prototypeDelete);
        for (final action in [cancel, save, if (existing) delete]) {
          expect(action.hitTestable(), findsOneWidget);
          final rect = tester.getRect(action);
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          expect(rect.bottom, lessThanOrEqualTo(544));
        }
        expect(
          tester.getRect(cancel).top,
          closeTo(tester.getRect(save).top, .01),
        );
        if (existing) {
          expect(
            tester.getRect(cancel).top - tester.getRect(delete).bottom,
            closeTo(8, .01),
          );
          expect(tester.widget<ShadButton>(delete).enabled, isTrue);
        } else {
          expect(delete, findsNothing);
        }
        expect(tester.takeException(), isNull);

        await _requestFullEditorExit(tester, 'cancel', settle: false);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AppConfirmationDialog), findsOneWidget);
        expect(controller.state.confirmingClose, isTrue);
        expect(tester.widget<ShadButton>(cancel).enabled, isFalse);
        expect(tester.widget<ShadButton>(cancel).onPressed, isNull);
        await tester.tap(find.text(l.jsonEditorKeepEditing));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(controller.name.text, 'Unsaved');
        expect(controller.text.text, '{"outbounds":[{}]}');
        expect(session.result.isCompleted, isFalse);

        final completion = Completer<int?>();
        addTearDown(() {
          if (!completion.isCompleted) completion.complete(null);
        });
        fixture.onSave(() => completion.future);
        final saving = controller.save(session.context);
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.state.busy, isTrue);
        for (final action in [cancel, save, if (existing) delete]) {
          expect(tester.widget<ShadButton>(action).enabled, isFalse);
          expect(tester.widget<ShadButton>(action).onPressed, isNull);
        }
        expect(session.result.isCompleted, isFalse);
        completion.completeError(
          const FormatException('Configuration rejected'),
        );
        await saving.timeout(const Duration(seconds: 3));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(controller.state.dirty, isTrue);
        expect(tester.widget<ShadButton>(cancel).enabled, isTrue);

        await _requestFullEditorExit(tester, 'cancel', settle: false);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text(l.jsonEditorDiscardChanges));
        await tester.pump();
        // The dialog and editor reverse in sequence. The popped result can
        // complete before the editor's own route transition has been removed.
        for (
          var frame = 0;
          frame < 20 &&
              find.byType(JsonConfigurationEditorPage).evaluate().isNotEmpty;
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(session.result.isCompleted, isTrue);
        expect(await session.result.future, isNull);
        expect(find.byType(JsonConfigurationEditorPage), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final advanced in [false, true]) {
    final label = advanced ? 'advanced' : 'Raw';
    for (final restored in [false, true]) {
      testWidgets(
        '$label clean or manually restored document exits without confirmation: $restored',
        (tester) async {
          final fixture = _DiagnosticFixture(advanced);
          addTearDown(fixture.dispose);
          final session = await _mountFullEditor(tester, fixture);
          final controller = fixture.controller;
          final initialName = controller.name.text;
          final initialText = controller.text.text;
          expect(controller.state.dirty, isFalse);
          controller.text.selection = const CodeLineSelection.collapsed(
            index: 0,
            offset: 0,
          );
          expect(controller.state.dirty, isFalse);
          if (restored) {
            controller.name.text = 'Temporary';
            controller.text.text = '$initialText\n';
            expect(controller.state.dirty, isTrue);
            controller.name.text = initialName;
            controller.text.text = initialText;
            expect(controller.state.dirty, isFalse);
          }
          await tester.pumpAndSettle();
          if (restored) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else {
            await tester.tap(find.byType(BackButton));
          }
          await tester.pumpAndSettle();
          expect(find.byType(AppConfirmationDialog), findsNothing);
          expect(find.byType(JsonConfigurationEditorPage), findsNothing);
          expect(await session.result.future, isNull);
          expect(fixture.raw.submitted, isEmpty);
          expect(fixture.custom.submitted, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final exit in ['close', 'cancel', 'back', 'escape']) {
      testWidgets(
        '$label modified document shares its discard guard through $exit',
        (tester) async {
          final fixture = _DiagnosticFixture(advanced);
          addTearDown(fixture.dispose);
          final session = await _mountFullEditor(tester, fixture);
          final controller = fixture.controller;
          final l = AppLocalizations.of(session.context)!;
          controller.name.text = 'Unsaved';
          controller.text.text = '{"outbounds":[{}]}';
          await tester.pumpAndSettle();
          final text = controller.text.text;
          await _requestFullEditorExit(tester, exit);
          expect(find.byType(AppConfirmationDialog), findsOneWidget);
          expect(controller.state.confirmingClose, isTrue);
          await controller.closePage(session.context);
          await tester.pump();
          expect(find.byType(AppConfirmationDialog), findsOneWidget);
          await tester.tap(find.text(l.jsonEditorKeepEditing));
          await tester.pumpAndSettle();
          expect(find.byType(JsonConfigurationEditorPage), findsOneWidget);
          expect(controller.name.text, 'Unsaved');
          expect(controller.text.text, text);
          expect(controller.state.dirty, isTrue);
          expect(session.result.isCompleted, isFalse);
          await _requestFullEditorExit(tester, exit);
          await tester.tap(find.text(l.jsonEditorDiscardChanges));
          await tester.pumpAndSettle();
          expect(await session.result.future, isNull);
          expect(find.byType(JsonConfigurationEditorPage), findsNothing);
          expect(fixture.raw.submitted, isEmpty);
          expect(fixture.custom.submitted, isEmpty);
          expect(await fixture.db.coreConfigDao.allRawRowsWithData, isEmpty);
          expect(await fixture.db.routingProfileDao.allRows, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$label saving blocks all exits and a failed save retains its dirty draft',
      (tester) async {
        final fixture = _DiagnosticFixture(advanced);
        addTearDown(fixture.dispose);
        final session = await _mountFullEditor(tester, fixture);
        final controller = fixture.controller;
        final l = AppLocalizations.of(session.context)!;
        controller.name.text = 'Submitted';
        controller.text.text = '{"outbounds":[{}]}';
        final completion = Completer<int?>();
        fixture.onSave(() => completion.future);
        final saving = controller.save(session.context);
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.state.canPop, isFalse);
        for (final exit in ['close', 'cancel', 'back', 'escape']) {
          await _requestFullEditorExit(tester, exit, settle: false);
          expect(find.byType(AppConfirmationDialog), findsNothing);
          expect(find.byType(JsonConfigurationEditorPage), findsOneWidget);
          expect(session.result.isCompleted, isFalse);
        }
        completion.completeError(
          const FormatException('Configuration rejected'),
        );
        await saving;
        await tester.pumpAndSettle();
        expect(controller.error, contains('Configuration rejected'));
        expect(controller.state.dirty, isTrue);
        expect(controller.state.closeAllowed, isFalse);
        await _requestFullEditorExit(tester, 'back');
        await tester.tap(find.text(l.jsonEditorDiscardChanges));
        await tester.pumpAndSettle();
        expect(await session.result.future, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$label successful save returns directly without asking to discard',
      (tester) async {
        final fixture = _DiagnosticFixture(advanced);
        addTearDown(fixture.dispose);
        final session = await _mountFullEditor(tester, fixture);
        fixture.controller.name.text = 'Submitted';
        fixture.controller.text.text = '{"outbounds":[{}]}';
        fixture.onSave(() async => 7);
        await fixture.controller.save(session.context);
        await tester.pumpAndSettle();
        expect(await session.result.future, 7);
        expect(find.byType(JsonConfigurationEditorPage), findsNothing);
        expect(find.byType(AppConfirmationDialog), findsNothing);
        expect(fixture.controller.state.dirty, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '$label releases committed Geodata imports before saving newer edits',
      (tester) async {
        var disposed = 0;
        final geodata = _SingleUseGeoDataImport(
          onDispose: () async => disposed++,
        );
        final transfer = ConfigurationTransferService(
          prepare: (_) async => geodata,
          lookup: (_) async => GeoDataData(
            id: 1,
            name: 'rules',
            type: 'domain',
            url: 'https://example.com/rules.dat',
            timestamp: DateTime(2026),
            categoryCount: 1,
            ruleCount: 1,
            installed: true,
          ),
        );
        final fixture = _DiagnosticFixture(advanced, transfer: transfer);
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        final context = await _mountDiagnosticEditor(tester);
        await controller.load(context);
        controller.text.text = '';
        const submitted =
            '{"outbounds":[{}],"routing":{"rules":[{"domain":["ext:rules.dat:CN"],"balancerTag":"proxy"}]}}';
        final shared = await transfer.shareLinks(
          kind: controller.kind,
          name: 'Imported',
          text: submitted,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async =>
              call.method == 'Clipboard.getData' ? {'text': shared} : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await controller.transfers.import(context, clipboard: true);
        await tester.pump();
        final imported = controller.transfers.imported;
        expect(imported, isNotNull);
        expect(controller.transfers.assets, hasLength(1));

        // Cancelling a reconnect or failing validation must retain the import
        // so the user can retry without downloading its dependencies again.
        fixture.onSave(() async => null);
        await controller.save(context);
        expect(controller.transfers.imported, same(imported));
        fixture.onSaveWithImport(
          (draft) => draft!.save(
            (_) async => throw const FormatException('Invalid test config'),
          ),
        );
        await controller.save(context);
        expect(controller.error, contains('Invalid test config'));
        expect(controller.transfers.imported, same(imported));
        expect(disposed, 0);

        final entered = Completer<void>();
        final release = Completer<int>();
        final received = <ConfigurationImportDraft?>[];
        fixture.onSaveWithImport((draft) async {
          received.add(draft);
          Future<int> commit(Future<void> Function() writeMetadata) async {
            await writeMetadata();
            if (received.length == 1) {
              entered.complete();
              return release.future;
            }
            return 7;
          }

          return draft?.save(commit) ?? commit(() async {});
        });
        final saving = controller.save(context);
        await entered.future;
        controller.name.text = 'Newer draft';
        final newer = jsonEncode({
          ...jsonDecode(submitted) as Map,
          'name': 'Newer draft',
        });
        controller.text.text = newer;
        release.complete(7);
        await saving;
        await tester.pump();
        expect(controller.name.text, 'Newer draft');
        expect(controller.text.text, newer);
        expect(controller.canSave, isTrue);
        expect(controller.error, isNull);
        expect(find.text('Diagnostic draft'), findsOneWidget);

        await controller.save(context);
        expect(controller.error, isNull);
        expect(received, [same(imported), isNull]);
        expect(controller.transfers.imported, isNull);
        expect(controller.transfers.assets, isEmpty);
        expect(disposed, 1);
        expect(geodata.events, [
          'publish',
          'rollback',
          'publish',
          'commit',
          'complete',
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Root'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$label diagnostics retain source offsets and clear with draft changes',
      (tester) async {
        final fixture = _DiagnosticFixture(advanced);
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        final context = await _mountDiagnosticEditor(tester);
        await controller.load(context);
        controller.name.text = 'Route';
        const malformed = ' \n {"name":"😀", "outbounds":[#]}';
        controller.text.text = malformed;
        await controller.save(context);
        expect(controller.state.diagnostic?.offset, malformed.indexOf('#'));
        expect(controller.error, isNotNull);
        final diagnostic = controller.state.diagnostic;
        final error = controller.error;
        controller.text.selection = const CodeLineSelection.collapsed(
          index: 1,
          offset: 2,
        );
        expect(controller.state.diagnostic, same(diagnostic));
        expect(controller.error, error);
        controller.name.text = 'Renamed';
        expect(controller.state.diagnostic, isNull);
        expect(controller.error, isNull);

        controller.text.text = advanced
            ? '{"outbounds":[{}],"dns":{"servers":["8.8.8.8",{"queryStrategy":"UseIP"}]}}'
            : '[]';
        await controller.save(context);
        expect(
          controller.state.diagnostic?.path,
          advanced ? ['dns', 'servers', 1, 'queryStrategy'] : isEmpty,
        );
        controller.text.text = '{"outbounds":[{}]}';
        expect(controller.state.diagnostic, isNull);
        expect(controller.error, isNull);
        const coreError = 'outbounds[0].settings: invalid (offset 27)';
        fixture.onSave(
          () async => throw const AppFailure(
            FailureCategory.configuration,
            'xrayValidation',
            cause: coreError,
          ),
        );
        await controller.save(context);
        expect(controller.error, contains(coreError));
        expect(controller.state.diagnostic, isNull);
        expect(controller.canSave, true);
      },
    );

    testWidgets('$label ignores a delayed error after the name changes', (
      tester,
    ) async {
      final fixture = _DiagnosticFixture(advanced);
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      final context = await _mountDiagnosticEditor(tester);
      await controller.load(context);
      controller.name.text = 'Submitted';
      controller.text.text = '{"outbounds":[{}]}';
      final completion = Completer<int?>();
      fixture.onSave(() => completion.future);
      final saving = controller.save(context);
      expect(controller.busy, true);
      controller.name.text = 'New name';
      completion.completeError(
        const FormatException('Old draft failed', null, 1),
      );
      await saving;
      expect(controller.name.text, 'New name');
      expect(controller.error, isNull);
      expect(controller.state.diagnostic, isNull);
      expect(controller.canSave, true);
      expect(find.text('Diagnostic draft'), findsOneWidget);
    });

    testWidgets(
      '$label keeps newer text after saving and advances the original row',
      (tester) async {
        final fixture = _DiagnosticFixture(advanced);
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        final context = await _mountDiagnosticEditor(tester);
        await controller.load(context);
        controller.name.text = 'Submitted';
        const submitted = '{"outbounds":[{}]}';
        const newer = '{"outbounds":[{},{}]}';
        controller.text.text = submitted;
        final completion = Completer<int?>();
        fixture.onSave(() => completion.future);
        final saving = controller.save(context);
        controller.text.text = newer;
        fixture.raw.current = const RawEditorDraft(
          original: CoreConfigData(
            manualSortOrder: 0,
            id: 7,
            name: 'Submitted',
            type: 'raw',
            tags: '',
            delay: 0,
            subId: 0,
            favorite: false,
          ),
          name: 'Submitted',
          text: submitted,
        );
        fixture.custom.current = CustomRoutingEditorDraft(
          original: const RoutingProfileData(
            id: 7,
            name: 'Submitted',
            advanced: true,
            data: '',
          ),
          state: AdvancedRoutingDocument.parse(
            submitted,
            name: 'Submitted',
          ).state,
        );
        completion.complete(7);
        await saving;
        await tester.pump();
        expect(find.text('Diagnostic draft'), findsOneWidget);
        expect(controller.text.text, newer);
        expect(controller.state.text, newer);
        expect(controller.state.savedText, submitted);
        expect(controller.state.savedName, 'Submitted');
        expect(controller.state.dirty, isTrue);
        expect(controller.error, isNull);
        expect(controller.canSave, true);

        fixture.onSave(() async => null);
        await controller.save(context);
        if (advanced) {
          expect(
            fixture.custom.submitted.last.original,
            fixture.custom.current.original,
          );
          expect(fixture.custom.submitted.last.state.entryCount, 2);
        } else {
          expect(
            fixture.raw.submitted.last.original,
            fixture.raw.current.original,
          );
          expect(fixture.raw.submitted.last.text, newer);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _DiagnosticFixture {
  _DiagnosticFixture(
    this.advanced, {
    this.configurationId,
    ConfigurationTransferService? transfer,
  }) {
    coordinator = ConnectionCoordinator(database: db);
    raw = _DiagnosticRawSave(database: db, coordinator: coordinator);
    custom = _DiagnosticAdvancedSave(database: db, coordinator: coordinator);
    if (advanced && configurationId != null) {
      custom.current = CustomRoutingEditorDraft(
        original: RoutingProfileData(
          id: configurationId!,
          name: 'Saved advanced',
          advanced: true,
          data: '{"outbounds":[{}]}',
        ),
        state: AdvancedRoutingDocument.parse(
          '{"outbounds":[{}]}',
          name: 'Saved advanced',
        ).state,
      );
    }
    controller = JsonConfigurationEditorController(
      configurationId: configurationId,
      kind: advanced ? ConfigurationKind.customAdvanced : ConfigurationKind.raw,
      service: raw,
      customService: custom,
      transferService: transfer,
    );
  }
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final bool advanced;
  final int? configurationId;
  late final ConnectionCoordinator coordinator;
  late final _DiagnosticRawSave raw;
  late final _DiagnosticAdvancedSave custom;
  late final JsonConfigurationEditorController controller;

  void onSave(Future<int?> Function() save) {
    onSaveWithImport((_) => save());
  }

  void onSaveWithImport(Future<int?> Function(ConfigurationImportDraft?) save) {
    raw.onSave = save;
    custom.onSave = save;
  }

  Future<void> dispose() async {
    await controller.close();
    coordinator.dispose();
    await db.close();
  }
}

Future<({BuildContext context, Completer<int?> result})> _mountFullEditor(
  WidgetTester tester,
  _DiagnosticFixture fixture, {
  Size size = const Size(1200, 1000),
  double textScale = 1,
  Locale locale = const Locale('en'),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final result = Completer<int?>();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: ShadToaster(child: child!),
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result.complete(
              await Navigator.of(context).push<int>(
                MaterialPageRoute(
                  builder: (_) => JsonConfigurationEditorPage(
                    configurationId: fixture.configurationId,
                    kind: fixture.advanced
                        ? ConfigurationKind.customAdvanced
                        : ConfigurationKind.raw,
                    createController: () => fixture.controller,
                  ),
                ),
              ),
            ),
            child: const Text('Open full editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open full editor'));
  await tester.pumpAndSettle();
  return (
    context: tester.element(find.byType(JsonConfigurationEditorPage)),
    result: result,
  );
}

Future<void> _requestFullEditorExit(
  WidgetTester tester,
  String exit, {
  bool settle = true,
}) async {
  final l = AppLocalizations.of(
    tester.element(find.byType(JsonConfigurationEditorPage)),
  )!;
  switch (exit) {
    case 'close':
      await tester.tap(find.byType(BackButton));
    case 'cancel':
      await tester.tap(find.widgetWithText(ShadButton, l.prototypeCancel));
    case 'back':
      await tester.binding.handlePopRoute();
    case 'escape':
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  }
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _DiagnosticRawSave extends RawEditorService {
  _DiagnosticRawSave({required super.database, required super.coordinator});
  RawEditorDraft current = const RawEditorDraft(name: '', text: '{}');
  final submitted = <RawEditorDraft>[];
  Future<int?> Function(ConfigurationImportDraft?)? onSave;

  @override
  Future<RawEditorDraft> load(int? id) async => current;

  @override
  Future<int?> save(
    RawEditorDraft draft, {
    required Future<bool> Function() confirmReconnect,
    ConfigurationImportDraft? imported,
  }) async {
    submitted.add(draft);
    RawEditorService.namedText(draft.name, draft.text);
    return onSave?.call(imported);
  }
}

class _DiagnosticAdvancedSave extends CustomRoutingEditorService {
  _DiagnosticAdvancedSave({
    required super.database,
    required super.coordinator,
  });
  CustomRoutingEditorDraft current = CustomRoutingEditorDraft(
    state: AdvancedRoutingDocument.parse('{"outbounds":[{}]}').state,
  );
  final submitted = <CustomRoutingEditorDraft>[];
  Future<int?> Function(ConfigurationImportDraft?)? onSave;

  @override
  Future<CustomRoutingEditorDraft> load(int? id) async => current;

  @override
  Future<int?> save(
    CustomRoutingEditorDraft draft, {
    required Future<bool> Function() confirmReconnect,
    ConfigurationImportDraft? imported,
  }) async {
    submitted.add(draft);
    return onSave?.call(imported);
  }
}

class _SingleUseGeoDataImport extends FakeGeoDataImport {
  _SingleUseGeoDataImport({super.onDispose});
  bool _completed = false;

  @override
  Future<T> save<T>(
    Future<T> Function(Future<void> Function() writeMetadata) action,
  ) async {
    if (_completed) throw StateError('Routing data draft is unavailable');
    final result = await super.save(action);
    _completed = true;
    return result;
  }
}

Future<BuildContext> _mountDiagnosticEditor(WidgetTester tester) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => ShadTheme(
        data: AppTheme.shad(Brightness.light),
        child: ShadToaster(child: child!),
      ),
      home: const Scaffold(body: Text('Root')),
    ),
  );
  unawaited(
    navigator.currentState!.push<int>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Diagnostic draft')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.element(find.text('Diagnostic draft'));
}

class _PendingAdvancedSave extends CustomRoutingEditorService {
  _PendingAdvancedSave({super.database, super.coordinator});
  final started = Completer<CustomRoutingEditorDraft>();
  final result = Completer<int?>();
  @override
  Future<int?> save(
    CustomRoutingEditorDraft draft, {
    required Future<bool> Function() confirmReconnect,
    ConfigurationImportDraft? imported,
  }) {
    started.complete(draft);
    return result.future;
  }
}

class _PendingRawSave extends RawEditorService {
  _PendingRawSave({super.database, super.coordinator});

  final started = Completer<void>();
  final result = Completer<int?>();

  @override
  Future<RawEditorDraft> load(int? id) async =>
      const RawEditorDraft(name: '', text: '{}');

  @override
  Future<int?> save(
    RawEditorDraft draft, {
    required Future<bool> Function() confirmReconnect,
    ConfigurationImportDraft? imported,
  }) {
    started.complete();
    return result.future;
  }
}
