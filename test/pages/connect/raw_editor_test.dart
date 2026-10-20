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
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/json_editor.dart';
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

  for (final advanced in [false, true]) {
    final label = advanced ? 'advanced' : 'Raw';
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
  _DiagnosticFixture(bool advanced, {ConfigurationTransferService? transfer}) {
    coordinator = ConnectionCoordinator(database: db);
    raw = _DiagnosticRawSave(database: db, coordinator: coordinator);
    custom = _DiagnosticAdvancedSave(database: db, coordinator: coordinator);
    controller = JsonConfigurationEditorController(
      configurationId: null,
      kind: advanced ? ConfigurationKind.customAdvanced : ConfigurationKind.raw,
      service: raw,
      customService: custom,
      transferService: transfer,
    );
  }
  final db = AppDatabase.forTesting(NativeDatabase.memory());
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
