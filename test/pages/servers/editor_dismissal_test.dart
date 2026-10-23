import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/servers/editor/controller.dart';
import 'package:onexray/pages/servers/editor/page.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;

const _initial = '{"tag":"Original","protocol":"freedom"}';
const _edited =
    '{\n  "tag": "Draft",\n  "protocol": "freedom",\n'
    '  "settings": {}\n}\n';
const _original = CoreConfigData(
  id: 7,
  name: 'Original',
  type: 'outbound',
  tags: '',
  delay: 0,
  subId: 0,
  manualSortOrder: 0,
  favorite: false,
);

enum _Exit { close, cancel, barrier, back, escape }

void main() {
  late AppDatabase database;
  late ConnectionCoordinator coordinator;
  late _EditorService service;
  late ServerEditorController controller;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(database: database);
    service = _EditorService(database: database, coordinator: coordinator);
    controller = ServerEditorController(7, service: service);
  });

  tearDown(() async {
    await controller.close();
    coordinator.dispose();
    await database.close();
  });

  Future<({BuildContext context, Completer<int?> result})> openEditor(
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final result = Completer<int?>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) => ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: ShadToaster(child: child!),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final savedId = await Navigator.of(context).push<int>(
                  DialogRoute<int>(
                    context: context,
                    builder: (_) => AppDialogFrame(
                      child: ServerEditorPage(
                        serverId: 7,
                        createController: () => controller,
                      ),
                    ),
                  ),
                );
                result.complete(savedId);
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    return (
      context: tester.element(find.byType(ServerEditorPage)),
      result: result,
    );
  }

  Future<void> requestExit(
    WidgetTester tester,
    _Exit exit, {
    bool settle = true,
  }) async {
    final l = AppLocalizations.of(
      tester.element(find.byType(ServerEditorPage)),
    )!;
    switch (exit) {
      case _Exit.close:
        await tester.tap(find.byTooltip(l.prototypeCloseDialog));
      case _Exit.cancel:
        await tester.tap(
          find.widgetWithText(ConnectDialogButton, l.prototypeCancel),
        );
      case _Exit.barrier:
        await tester.tapAt(const Offset(10, 10));
      case _Exit.back:
        await tester.binding.handlePopRoute();
      case _Exit.escape:
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    }
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  for (final restored in [false, true]) {
    testWidgets('clean editor closes without saving (restored: $restored)', (
      tester,
    ) async {
      final session = await openEditor(tester);
      expect(controller.state.dirty, isFalse);
      controller.text.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 5,
      );
      expect(controller.state.dirty, isFalse);
      if (restored) {
        controller.text.text = _edited;
        expect(controller.state.dirty, isTrue);
        controller.text.text = _initial;
        expect(controller.state.dirty, isFalse);
        await tester.pumpAndSettle();
      }
      await requestExit(tester, _Exit.escape);
      expect(find.byType(AppConfirmationDialog), findsNothing);
      expect(find.byType(ServerEditorPage), findsNothing);
      expect(session.result.isCompleted, isTrue);
      expect(await session.result.future, isNull);
      expect(service.submitted, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final exit in _Exit.values) {
    testWidgets('dirty editor confirms $exit and keeps its diagnostic', (
      tester,
    ) async {
      final session = await openEditor(tester);
      controller.text.text = _edited;
      controller.text.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 8,
      );
      service.saveDraft = (_) => Future.error(
        const FormatException('Original JSON diagnostic', null, 10),
      );
      await controller.save(session.context);
      await tester.pumpAndSettle();
      final diagnostic = controller.state.diagnostic;
      final selection = controller.text.selection;
      expect(diagnostic, isNotNull);
      expect(controller.state.dirty, isTrue);
      final l = AppLocalizations.of(session.context)!;

      await requestExit(tester, exit);
      expect(find.byType(AppConfirmationDialog), findsOneWidget);
      expect(session.result.isCompleted, isFalse);
      await tester.tap(find.text(l.jsonEditorKeepEditing));
      await tester.pumpAndSettle();
      expect(find.byType(ServerEditorPage), findsOneWidget);
      expect(controller.text.text, _edited);
      expect(controller.text.selection, selection);
      expect(controller.state.diagnostic, same(diagnostic));
      expect(controller.state.dirty, isTrue);

      await requestExit(tester, exit);
      await tester.tap(find.text(l.jsonEditorDiscardChanges));
      await tester.pumpAndSettle();
      expect(find.byType(ServerEditorPage), findsNothing);
      expect(find.byType(AppConfirmationDialog), findsNothing);
      expect(session.result.isCompleted, isTrue);
      expect(await session.result.future, isNull);
      expect(service.submitted, hasLength(1));
      expect(service.current.text, _initial);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'repeated dismissal shares one confirmation and Escape keeps it',
    (tester) async {
      final session = await openEditor(tester);
      controller.text.text = _edited;
      final first = controller.closePage(session.context);
      unawaited(controller.closePage(session.context));
      unawaited(controller.closePage(session.context));
      await tester.pumpAndSettle();
      expect(find.byType(AppConfirmationDialog), findsOneWidget);
      await controller.save(session.context);
      expect(service.submitted, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await first;
      expect(find.byType(AppConfirmationDialog), findsNothing);
      expect(find.byType(ServerEditorPage), findsOneWidget);
      expect(controller.state.confirmingClose, isFalse);
      expect(controller.text.text, _edited);
      expect(session.result.isCompleted, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'busy save blocks every dismissal and cancellation keeps it dirty',
    (tester) async {
      final pending = Completer<bool>();
      service.saveDraft = (_) => pending.future;
      final session = await openEditor(tester);
      controller.text.text = _edited;
      final saving = controller.save(session.context);
      await tester.pump();
      final l = AppLocalizations.of(session.context)!;
      expect(
        tester
            .widget<ConnectDialogButton>(
              find.widgetWithText(ConnectDialogButton, l.prototypeCancel),
            )
            .onPressed,
        isNull,
      );
      for (final exit in [
        _Exit.close,
        _Exit.barrier,
        _Exit.back,
        _Exit.escape,
      ]) {
        await requestExit(tester, exit, settle: false);
        expect(find.byType(ServerEditorPage), findsOneWidget);
        expect(find.byType(AppConfirmationDialog), findsNothing);
        expect(session.result.isCompleted, isFalse);
      }
      pending.complete(false);
      await saving;
      await tester.pumpAndSettle();
      expect(controller.state.draft?.text, _initial);
      expect(controller.state.dirty, isTrue);
      await requestExit(tester, _Exit.cancel);
      expect(find.byType(AppConfirmationDialog), findsOneWidget);
      await tester.tap(find.text(l.jsonEditorKeepEditing));
      await tester.pumpAndSettle();
      expect(controller.text.text, _edited);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('successful save closes once without discard confirmation', (
    tester,
  ) async {
    service.saveDraft = (_) async => true;
    final session = await openEditor(tester);
    controller.text.text = _edited;
    final l = AppLocalizations.of(session.context)!;
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ConnectDialogButton, l.prototypeSave));
    await tester.pumpAndSettle();
    expect(find.byType(ServerEditorPage), findsNothing);
    expect(find.byType(AppConfirmationDialog), findsNothing);
    expect(session.result.isCompleted, isTrue);
    expect(await session.result.future, 7);
    expect(service.submitted.single.text, _edited);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful save completes navigation without a deferred frame', (
    tester,
  ) async {
    service.saveDraft = (_) async => true;
    final session = await openEditor(tester);
    controller.text.text = _edited;
    await controller.save(session.context);
    expect(ModalRoute.of(session.context)!.isCurrent, isFalse);
    expect(service.submitted.single.text, _edited);
    await tester.pumpAndSettle();
    expect(await session.result.future, 7);
    expect(find.byType(ServerEditorPage), findsNothing);
    expect(find.byType(AppConfirmationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending load preserves early input and still confirms closing', (
    tester,
  ) async {
    final pending = Completer<ServerEditDraft>();
    service.loadDraft = () => pending.future;
    final session = await openEditor(tester);
    controller.text.text = _edited;
    pending.complete(const ServerEditDraft(_original, _initial));
    await tester.pumpAndSettle();
    expect(controller.state.loading, isFalse);
    expect(controller.text.text, _edited);
    expect(controller.state.draft?.text, _initial);
    expect(controller.state.dirty, isTrue);
    await requestExit(tester, _Exit.close);
    expect(find.byType(AppConfirmationDialog), findsOneWidget);
    final l = AppLocalizations.of(session.context)!;
    await tester.tap(find.text(l.jsonEditorKeepEditing));
    await tester.pumpAndSettle();
    expect(controller.text.text, _edited);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a load completing after clean dismissal cannot touch the editor',
    (tester) async {
      final pending = Completer<ServerEditDraft>();
      service.loadDraft = () => pending.future;
      final session = await openEditor(tester);
      await requestExit(tester, _Exit.close);
      expect(session.result.isCompleted, isTrue);
      expect(controller.isPageActive, isFalse);
      pending.complete(const ServerEditDraft(_original, _initial));
      await tester.pumpAndSettle();
      expect(find.byType(ServerEditorPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _EditorService extends ServerAssetService {
  _EditorService({required super.database, required super.coordinator});

  ServerEditDraft current = const ServerEditDraft(_original, _initial);
  final submitted = <ServerEditDraft>[];
  Future<ServerEditDraft> Function()? loadDraft;
  Future<bool> Function(ServerEditDraft)? saveDraft;

  @override
  Future<ServerEditDraft> load(int id) async =>
      loadDraft == null ? current : await loadDraft!();

  @override
  Future<bool> save(
    ServerEditDraft draft, {
    required Future<bool> Function() confirmReconnect,
  }) async {
    submitted.add(draft);
    return await saveDraft?.call(draft) ?? false;
  }
}
