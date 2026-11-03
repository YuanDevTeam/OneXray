import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/model/geo_dat.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/advanced/xray/geodata/view.dart';
import 'package:onexray/pages/advanced/xray/geodata/controller.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';

void main() {
  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
  });
  testWidgets(
    'Geodata updates guard only the same file and release on failure',
    (tester) async {
      final first = _file(42, 'first', 100);
      final second = _file(43, 'second', 100);
      final service = _PendingGeoDataService([first, second]);
      final controller = GeoDataController(service: service);
      addTearDown(controller.close);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await controller.initialize();
      await tester.pump();
      final firstUpdate = controller.update(context, first.row);
      await controller.update(context, first.row);
      final secondUpdate = controller.update(context, second.row);
      await controller.updateAll(context);
      expect(service.calls, [42, 43]);
      expect(controller.state.fileBusy(42), isTrue);
      expect(controller.state.fileBusy(43), isTrue);
      expect(controller.state.fileBusy(-1), isFalse);
      expect(controller.state.formBusy, isFalse);
      expect(controller.state.canUpdateAll, isFalse);
      service.pending[42]!.complete();
      await firstUpdate;
      expect(controller.state.fileBusy(42), isFalse);
      expect(controller.state.fileBusy(43), isTrue);
      service.pending[43]!.completeError(StateError('download failed'));
      await secondUpdate;
      expect(controller.state.errors[43], isNotNull);
      expect(controller.state.fileBusy(43), isFalse);
      expect(controller.state.canUpdateAll, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'busy Geodata row keeps other files and detail navigation enabled',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final actions = <int>[];
      final first = _file(42, 'first-long-custom-dataset-name', 100);
      final second = _file(43, 'second', 100);
      final release = Completer<void>();
      final download = AppEventBus.instance.trackDownload(() => release.future);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          home: Scaffold(
            body: GeoDataRows(
              files: [first, second],
              custom: true,
              busy: false,
              updating: const {42},
              onOpen: (file) => actions.add(file.row.id),
              onUpdate: (file) => actions.add(file.row.id),
              onDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      final l = AppLocalizations.of(tester.element(find.byType(GeoDataRows)))!;
      final buttons = tester
          .widgetList<TextButton>(
            find.widgetWithText(TextButton, l.prototypeUpdate),
          )
          .toList();
      expect(buttons.first.onPressed, isNull);
      expect(buttons.last.onPressed, isNotNull);
      expect(find.byType(ButtonProgressIndicator), findsOneWidget);
      await tester.tap(find.text(first.fileName));
      await tester.tap(find.text(l.prototypeUpdate).last);
      expect(actions, [42, 43]);
      expect(tester.takeException(), isNull);
      release.complete();
      await tester.pump();
      await download;
      expect(find.byType(ButtonProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final (locale, width) in const [
    (Locale('en'), 1160.0),
    (Locale('en'), 1032.0),
    (Locale('zh'), 390.0),
    (Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), 390.0),
    (Locale('ru'), 1160.0),
    (Locale('fa'), 390.0),
  ]) {
    testWidgets(
      'pending source has actions but no publication metadata ($locale, $width)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var downloads = 0;
        var deletions = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            locale: locale,
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PendingGeoDataRow(
                row: _file(
                  42,
                  'long-custom-dataset-name',
                  0,
                ).row.copyWith(installed: false),
                busy: false,
                deleting: false,
                onDownload: () => downloads++,
                onDelete: () => deletions++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(PendingGeoDataRow)),
        )!;
        expect(find.text(l.geodataPendingDownload), findsOneWidget);
        expect(find.text(l.prototypeSize), findsNothing);
        expect(find.text(l.prototypeLastSuccessfulUpdate), findsNothing);
        await tester.tap(find.text(l.prototypeDownload));
        await tester.tap(find.text(l.prototypeDelete));
        expect((downloads, deletions), (1, 1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Geodata rows render dates and route actions ($locale, $width)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final builtIn = _file(-1, 'geoip', 12 * 1024 * 1024);
        final custom = _file(42, 'custom-domain', 3 * 1024 * 1024);
        final actions = <(String, GeoDataFile)>[];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width > 720 ? 600 : double.infinity,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final file in [builtIn, custom])
                          GeoDataRows(
                            key: ValueKey(file.row.id),
                            files: [file],
                            custom: !file.builtIn,
                            busy: false,
                            onOpen: (value) => actions.add(('open', value)),
                            onUpdate: (value) => actions.add(('update', value)),
                            onDelete: (value) => actions.add(('delete', value)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final l = AppLocalizations.of(
          tester.element(find.byType(GeoDataRows).first),
        )!;
        for (final (file, size) in [
          (builtIn, '12.0 MiB'),
          (custom, '3.0 MiB'),
        ]) {
          final group = find.byKey(ValueKey(file.row.id));
          for (final text in [
            file.fileName,
            file.sourceHost,
            size,
            DateFormat.yMd(locale.toString())
                .add_Hm()
                .format(file.row.timestamp.toLocal()),
          ]) {
            expect(
              find.descendant(of: group, matching: find.text(text)),
              findsOneWidget,
            );
          }
          expect(
            find.descendant(of: group, matching: find.text(l.prototypeUpdate)),
            file.builtIn ? findsNothing : findsOneWidget,
          );
          expect(
            find.descendant(
              of: group,
              matching: find.byTooltip(l.prototypeDeleteCustomDataset),
            ),
            file.builtIn ? findsNothing : findsOneWidget,
          );
          await tester.tap(find.text(file.fileName));
        }
        expect(
          tester.getRect(find.text(custom.fileName)).top,
          greaterThan(tester.getRect(find.text(builtIn.fileName)).bottom),
        );
        await tester.tap(find.text(l.prototypeUpdate));
        await tester.tap(find.byTooltip(l.prototypeDeleteCustomDataset));
        expect(actions, [
          ('open', builtIn),
          ('open', custom),
          ('update', custom),
          ('delete', custom),
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _PendingGeoDataService implements GeoDataService {
  _PendingGeoDataService(this.files);

  final List<PublishedGeoData> files;
  final calls = <int>[];
  final pending = <int, Completer<void>>{};

  @override
  Future<void> ensureInstalled({bool resetOrphanedFiles = false}) async {}

  @override
  Stream<List<PublishedGeoData>> watchPublished() => Stream.value(files);

  @override
  Stream<List<GeoDataData>> watchPending() => Stream.value(const []);

  @override
  Future<void> updateCustom(GeoDataData original) {
    calls.add(original.id);
    return AppEventBus.instance.trackDownload(
      () => (pending[original.id] = Completer<void>()).future,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

PublishedGeoData _file(int id, String name, int bytes) => PublishedGeoData(
  row: GeoDataData(
    id: id,
    installed: true,
    name: name,
    type: id == -1 ? 'ip' : 'domain',
    url: 'https://$name.example/$name.dat',
    timestamp: DateTime(2026, 9, 3, 9, 42),
    categoryCount: 1,
    ruleCount: 100,
  ),
  data: File('/fixture/$name.dat'),
  indexFile: File('/fixture/$name.json'),
  index: XrayGeoList([XrayGeoListCodes('cn', 100)], 1, 100),
  bytes: bytes,
);
