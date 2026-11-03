import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/l10n/localizations/app_localizations_en.dart';
import 'package:onexray/l10n/localizations/app_localizations_fa.dart';
import 'package:onexray/l10n/localizations/app_localizations_ru.dart';
import 'package:onexray/l10n/localizations/app_localizations_zh.dart';
import 'package:onexray/pages/launch/setup/selectors.dart';
import 'package:onexray/pages/connect/routing/smart/controller.dart';
import 'package:onexray/pages/connect/routing/smart/regions.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/routing/smart/editor.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme;

void main() {
  test('Smart preview retains direct sources after merging rules', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final coordinator = ConnectionCoordinator(database: db);
    addTearDown(coordinator.dispose);
    final controller = SmartRoutingEditorController(
      service: SmartRoutingEditorService(
        database: db,
        coordinator: coordinator,
      ),
    );
    addTearDown(controller.close);
    final l = AppLocalizationsZh();
    expect(controller.directPreview(l), l.prototypeNone);
    controller.emit(
      SmartRoutingEditorState(
        original: SmartRoutingEditorDraft(
          configuration: ConnectionConfiguration(),
          regions: RegionCatalog.fromJson(
            {'geosite': <String, dynamic>{}, 'geoip': <String, dynamic>{}},
            geositeCodes: [],
            geoipCodes: [],
          ),
        ),
        busy: false,
      ),
    );
    expect(controller.rulesFor('direct'), hasLength(2));
    expect(
      controller.directPreview(l),
      [
        l.prototypeLocalNetworkPrivateAddresses,
        l.prototypeAppleServices,
        l.windowsServices,
      ].join(' / '),
    );
    controller.update('directPrivate', false);
    expect(
      controller.directPreview(l),
      [l.prototypeAppleServices, l.windowsServices].join(' / '),
    );
    controller.update('directApple', false);
    expect(controller.directPreview(l), l.windowsServices);
    controller.update('directWindows', false);
    expect(controller.rulesFor('direct'), isEmpty);
    expect(controller.directPreview(l), l.prototypeNone);
    controller.update('directWindows', true);
    expect(controller.rulesFor('direct'), hasLength(1));
    expect(controller.directPreview(l), l.windowsServices);
    controller.update('blockAds', true);
    expect(controller.state.draft.directWindows, true);
    controller.update('directWindows', false);
    expect(controller.rulesFor('direct'), isEmpty);
    expect(controller.directPreview(l), l.prototypeNone);
  });

  test('direct regions select one installed category and leave historical input unchanged', () async {
    final selected = ['CN', 'RU'];
    var available = ['CN', 'RU', 'US', 'JP'];
    final controller = DirectRegionsController(
      selected,
      loadRegions: () async => RegionCatalog.fromJson(
        {
          'geosite': {
            'RU': ['CATEGORY-RU'],
          },
          'geoip': {
            for (final code in ['CN', 'RU', 'IR', 'US', 'JP']) code: [code],
          },
        },
        geositeCodes: [],
        geoipCodes: available,
      ),
    );
    addTearDown(controller.close);
    expect(controller.state.selected, {'CN'});
    await controller.load();
    expect(controller.state.codes, ['CN', 'JP', 'RU', 'US']);
    expect(controller.state.selected, {'CN'});
    controller.select('US');
    controller.select('JP');
    expect(controller.state.selected, {'JP'});
    controller.select('RU');
    expect(controller.state.selected, {'RU'});
    controller.select('JP');
    expect(controller.state.selected, {'JP'});
    controller.select('JP');
    expect(controller.state.selected, {'JP'});
    controller.select('IR');
    expect(controller.state.selected, {'JP'});
    controller.search('russia');
    expect(controller.visibleCodes(AppLocalizationsEn()), ['RU']);
    expect(controller.visibleCodes(AppLocalizationsZh()), ['RU']);
    expect(controller.detail('RU'), 'Russia · RU');
    expect(controller.detail('AD'), 'Andorra · AD');
    controller.search('us');
    expect(controller.visibleCodes(AppLocalizationsEn()), ['RU', 'US']);
    controller.clear();
    expect(controller.state.selected, isEmpty);
    expect(selected, ['CN', 'RU']);
    available = ['US'];
    controller.select('CN');
    controller.select('US');
    await controller.load();
    expect(controller.state.codes, ['US']);
    expect(controller.state.selected, {'US'});
  });

  testWidgets(
    'region cancel preserves historical input; Done returns one region or explicit empty',
    (tester) async {
      final initial = ['CN', 'RU'];
      List<String>? saved;
      final catalog = RegionCatalog.fromJson(
        {
          'geosite': <String, dynamic>{},
          'geoip': {
            for (final code in ['CN', 'RU', 'US', 'JP']) code: [code],
          },
        },
        geositeCodes: [],
        geoipCodes: ['CN', 'RU', 'US', 'JP'],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.material(Brightness.light),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          builder: (context, child) =>
              ShadTheme(data: AppTheme.shad(Brightness.light), child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  saved = await Navigator.of(context).push<List<String>>(
                    MaterialPageRoute(
                      builder: (_) => DirectRegionsPage(
                        selectedCodes: initial,
                        loadRegions: () async => catalog,
                      ),
                    ),
                  );
                },
                child: const Text('Open regions'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open regions'));
      await tester.pumpAndSettle();
      Iterable<Semantics> regionChoices() => tester.widgetList<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.inMutuallyExclusiveGroup == true,
        ),
      );
      expect(
        regionChoices().where((widget) => widget.properties.checked == true),
        hasLength(1),
      );
      await tester.tap(find.text('United States'));
      await tester.pumpAndSettle();
      expect(
        regionChoices().where((widget) => widget.properties.checked == true),
        hasLength(1),
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(initial, ['CN', 'RU']);

      await tester.tap(find.text('Open regions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Japan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Japan'));
      await tester.pumpAndSettle();
      expect(
        regionChoices().where((widget) => widget.properties.checked == true),
        hasLength(1),
      );
      await tester.tap(find.text(AppLocalizationsEn().prototypeDone));
      await tester.pumpAndSettle();
      expect(saved, ['JP']);
      expect(initial, ['CN', 'RU']);

      await tester.tap(find.text('Open regions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppLocalizationsEn().prototypeClearAll));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppLocalizationsEn().prototypeDone));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(initial, ['CN', 'RU']);
    },
  );

  test('every bundled region has a name in every supported language', () {
    final mapping = jsonDecode(
      File(RegionCatalog.assetPath).readAsStringSync(),
    ) as Map<String, dynamic>;
    final codes = (mapping['geoip'] as Map<String, dynamic>).keys;
    final localizations = <AppLocalizations>[
      AppLocalizationsEn(),
      AppLocalizationsFa(),
      AppLocalizationsRu(),
      AppLocalizationsZh(),
      AppLocalizationsZhHant(),
    ];

    for (final l10n in localizations) {
      for (final code in codes) {
        expect(
          setupRegionLabel(l10n, code),
          isNot(code),
          reason: '${l10n.localeName}: $code',
        );
      }
    }
    expect(setupRegionLabel(AppLocalizationsEn(), 'zz'), 'ZZ');
  });
}
