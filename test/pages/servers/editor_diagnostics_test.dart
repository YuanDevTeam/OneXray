import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/editor/controller.dart';
import 'package:onexray/pages/servers/import/controller.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/servers/import.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _initialText = '{"tag":"Original","protocol":"freedom"}';
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

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(database: db);
    addTearDown(() async {
      coordinator.dispose();
      await db.close();
    });
  });

  testWidgets(
    'node save reaches syntax validation and clears only on text edits',
    (tester) async {
      final service = _EditorService(database: db, coordinator: coordinator);
      final controller = ServerEditorController(7, service: service);
      addTearDown(controller.close);
      final context = await _mount(tester);
      await controller.load(context);
      const source = ' \n {"tag":"😀", "protocol": #}\n';
      controller.text.text = source;

      await controller.save(context);

      expect(service.submitted.single.text, source);
      expect(controller.state.diagnostic?.offset, source.indexOf('#'));
      expect(controller.state.error, isNotNull);
      expect(controller.state.busy, false);
      final diagnostic = controller.state.diagnostic;
      final error = controller.state.error;
      controller.text.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 2,
      );
      expect(controller.state.diagnostic, same(diagnostic));
      expect(controller.state.error, error);
      controller.text.text = _initialText;
      expect(controller.state.diagnostic, isNull);
      expect(controller.state.error, isNull);
    },
  );

  testWidgets('a delayed node failure cannot annotate a newer draft', (
    tester,
  ) async {
    final completion = Completer<bool>();
    final service = _EditorService(database: db, coordinator: coordinator)
      ..saveDraft = (_) => completion.future;
    final controller = ServerEditorController(7, service: service);
    addTearDown(controller.close);
    final context = await _mount(tester);
    await controller.load(context);
    final saving = controller.save(context);
    expect(controller.state.busy, true);
    controller.text.text = '{"tag":"New draft","protocol":"freedom"}';
    completion.completeError(
      const FormatException('Older source error', null, 1),
    );
    await saving;
    expect(controller.state.error, isNull);
    expect(controller.state.diagnostic, isNull);
    expect(controller.state.jsonText, contains('New draft'));
    expect(controller.state.busy, false);
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets(
    'a delayed node save preserves new text and advances its original',
    (tester) async {
      final completion = Completer<bool>();
      final service = _EditorService(database: db, coordinator: coordinator)
        ..saveDraft = (_) => completion.future;
      final controller = ServerEditorController(7, service: service);
      addTearDown(controller.close);
      final context = await _mount(tester);
      await controller.load(context);
      const submitted = '{"tag":"Submitted","protocol":"freedom"}';
      const newer = '{"tag":"Newer draft","protocol":"freedom"}';
      controller.text.text = submitted;
      final saving = controller.save(context);
      controller.text.text = newer;
      final savedOriginal = _original.copyWith(name: 'Submitted');
      service.current = ServerEditDraft(savedOriginal, submitted);
      completion.complete(true);
      await saving;
      await tester.pump();

      expect(find.text('Draft'), findsOneWidget);
      expect(controller.text.text, newer);
      expect(controller.state.jsonText, newer);
      expect(controller.state.draft?.original, savedOriginal);
      expect(controller.state.busy, false);
      expect(controller.state.error, isNull);
      service.saveDraft = (_) async => false;
      await controller.save(context);
      expect(service.submitted.last.original, savedOriginal);
      expect(service.submitted.last.text, newer);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual JSON reports local syntax but never guesses core locations',
    (tester) async {
      const coreError = 'outbounds[0].settings: invalid (offset 27)';
      final controller = _importController(
        ServerImportService(validate: (_) async => coreError),
      );
      addTearDown(controller.close);
      final context = await _mount(tester);
      const malformed = ' \n {"name":"😀", "outbounds":[#]}';
      controller.jsonText.text = malformed;
      await controller.detect(context, ServerImportAction.json);
      expect(controller.state.jsonDiagnostic?.offset, malformed.indexOf('#'));
      final diagnostic = controller.state.jsonDiagnostic;
      final error = controller.state.error;
      controller.jsonText.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 2,
      );
      expect(controller.state.jsonDiagnostic, same(diagnostic));
      expect(controller.state.error, error);
      controller.jsonText.text = '{"outbounds":[{}]}';
      expect(controller.state.jsonDiagnostic, isNull);
      expect(controller.state.error, isNull);
      await controller.detect(context, ServerImportAction.json);
      expect(controller.state.error, contains(coreError));
      expect(controller.state.jsonDiagnostic, isNull);
      expect(controller.state.busy, false);
    },
  );

  testWidgets('a delayed manual JSON error cannot annotate a newer draft', (
    tester,
  ) async {
    final service = _PendingImportService();
    final controller = _importController(service);
    addTearDown(controller.close);
    final context = await _mount(tester);
    controller.jsonText.text = '{"outbounds":[{}]}';
    final detecting = controller.detect(context, ServerImportAction.json);
    expect(controller.state.busy, true);
    controller.jsonText.text = '{"outbounds":[{"protocol":"freedom"}]}';
    service.result.completeError(
      const AppFailure(
        FailureCategory.configuration,
        'xrayValidation',
        cause: FormatException('Older JSON error', null, 3),
      ),
    );
    await detecting;
    expect(controller.state.error, isNull);
    expect(controller.state.jsonDiagnostic, isNull);
    expect(controller.state.jsonInput, contains('freedom'));
    expect(controller.state.busy, false);
    expect(find.text('Draft'), findsOneWidget);
  });
}

class _EditorService extends ServerAssetService {
  _EditorService({required super.database, required super.coordinator});
  ServerEditDraft current = const ServerEditDraft(_original, _initialText);
  final submitted = <ServerEditDraft>[];
  Future<bool> Function(ServerEditDraft)? saveDraft;

  @override
  Future<ServerEditDraft> load(int id) async => current;

  @override
  Future<bool> save(
    ServerEditDraft draft, {
    required Future<bool> Function() confirmReconnect,
  }) {
    submitted.add(draft);
    return saveDraft?.call(draft) ??
        super.save(draft, confirmReconnect: confirmReconnect);
  }
}

class _PendingImportService extends ServerImportService {
  final result = Completer<ServerImportPreview>();
  @override
  Future<ServerImportPreview> preview(String text, {bool manual = false}) =>
      result.future;
}

ServerImportController _importController(ServerImportService service) =>
    ServerImportController(
      service: service,
      loadSubscription: (_) async => null,
    );

Future<BuildContext> _mount(WidgetTester tester) async {
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
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Draft'))),
    ),
  );
  await tester.pumpAndSettle();
  return tester.element(find.text('Draft'));
}
