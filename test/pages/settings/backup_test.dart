import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/backup/codec.dart';
import 'package:onexray/core/backup/storage.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/backup/page.dart';
import 'package:onexray/pages/settings/page.dart';
import 'package:onexray/pages/settings/widgets.dart';
import 'package:onexray/pages/settings/backup/existing_file_dialog.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';
import 'package:onexray/service/settings/backup/assets.dart';
import 'package:onexray/service/settings/backup/service.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../service/settings/backup/service_test.dart'
    show MemoryBackupPreferences, MemoryBackupStorage;

void main() {
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(
      done(),
      true,
      reason: 'The bounded async operation did not complete',
    );
    await tester.pump();
  }

  late BackupService service;
  late MemoryBackupPreferences preferences;
  late MemoryBackupStorage storage;
  late BackupAssets assets;
  var restored = 0;

  setUp(() {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final geodata = GeoDataService.forTesting(
      database: db,
      directory: '../references/onexray-tests/unused-backup-ui',
      download: (_, _) async => fail('No download'),
      count: (_, _, _) async => fail('No indexing'),
      copyBundled: (_) async => fail('No bundled copy'),
    );
    assets = BackupAssets(db, geodata);
    preferences = MemoryBackupPreferences();
    storage = MemoryBackupStorage();
    restored = 0;
    service = BackupService.forTesting(
      storage: storage,
      preferences: preferences,
      assets: assets,
      now: () => DateTime(2026, 9, 16),
      restore: (commit) async {
        await commit();
        restored++;
      },
    );
    addTearDown(service.close);
  });

  Widget app(Locale locale) => MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalePolicy.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => ShadTheme(
      data: ShadThemeData(colorScheme: const ShadBlueColorScheme.light()),
      child: ShadToaster(child: child ?? const SizedBox.shrink()),
    ),
    home: BackupPage(service: service),
  );

  testWidgets(
    'settings summary follows the existing backup binding without file operations',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: SettingsBackupSummaryRow(
                service: service,
                onTap: () => opened++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(SettingsBackupSummaryRow));
      final l = AppLocalizations.of(context)!;
      expect(find.text(l.backupNotConfigured), findsOneWidget);
      final name =
          'iCloud Drive / ${List.filled(12, 'long-folder/').join()}OneXray-backup.json';
      preferences.settings = BackupSettings(
        target: BackupTarget('summary-target', name),
      );
      await service.load();
      await tester.pump();
      final label = find.text(name);
      expect(label, findsOneWidget);
      expect(tester.widget<Text>(label).maxLines, 2);
      expect(tester.widget<Text>(label).overflow, TextOverflow.ellipsis);
      expect(find.text(l.backupNotConfigured), findsNothing);
      await tester.tap(find.byType(SettingsBackupSummaryRow));
      await tester.pump();
      expect(opened, 1);
      preferences.settings = const BackupSettings();
      await service.load();
      await tester.pump();
      expect(find.text(l.backupNotConfigured), findsOneWidget);
      expect(storage.selections, isEmpty);
      expect(storage.reads, 0);
      expect(storage.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (label, width, scale, busy, locale) in [
    ('使用 iCloud Drive', 640.0, 1.0, false, const Locale('zh')),
    ('Use iCloud Drive', 640.0, 1.0, false, const Locale('en')),
    ('Сохранить и переподключить', 130.0, 2.0, false, const Locale('ru')),
    ('ذخیره و اتصال مجدد', 140.0, 2.0, true, const Locale('fa')),
  ]) {
    testWidgets(
      'backup action measures its rendered label at $width/$scale/$locale',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.material(Brightness.light, mobile: width < 390),
            locale: locale,
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: ShadTheme(
                data: AppTheme.shad(Brightness.light),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: SettingsActionButton(
                    label: label,
                    busy: busy,
                    enabled: !busy,
                    variant: busy
                        ? ShadButtonVariant.outline
                        : ShadButtonVariant.primary,
                    onPressed: () => calls++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final action = find.byType(SettingsActionButton);
        final bounds = tester.getRect(action);
        expect(bounds.width, lessThanOrEqualTo(width));
        final labelFinder = find.text(label);
        final rich = tester.widget<RichText>(
          find.descendant(of: labelFinder, matching: find.byType(RichText)),
        );
        final labelBounds = tester.getRect(labelFinder);
        expect(rich.text.style!.fontFamily, AppFontFamily.sans);
        expect(rich.text.style!.fontSize, 14);
        expect(labelBounds.left, greaterThanOrEqualTo(bounds.left));
        expect(labelBounds.right, lessThanOrEqualTo(bounds.right));
        expect(labelBounds.top, greaterThanOrEqualTo(bounds.top));
        expect(labelBounds.bottom, lessThanOrEqualTo(bounds.bottom));
        final painter = TextPainter(
          text: rich.text,
          textDirection:
              rich.textDirection ??
              Directionality.of(tester.element(labelFinder)),
          textScaler: rich.textScaler,
          locale: rich.locale,
        )..layout(maxWidth: labelBounds.width);
        if (width == 640) {
          expect(painter.computeLineMetrics(), hasLength(1));
          expect(bounds.height, 44);
        } else {
          expect(painter.computeLineMetrics().length, greaterThan(1));
          expect(bounds.height, greaterThan(48));
        }
        expect(labelBounds.height, closeTo(painter.height, .01));
        painter.dispose();
        await tester.tap(action);
        await tester.pump();
        expect(calls, busy ? 0 : 1);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'sensitive backup notice keeps a readable foreground in $brightness',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.material(brightness),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) => ShadTheme(
              data: AppTheme.shad(brightness),
              child: ShadToaster(child: child!),
            ),
            home: BackupPage(service: service),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(BackupPage));
        final l = AppLocalizations.of(context)!;
        final notice = find.text(l.backupSensitiveWarning);
        await tester.ensureVisible(notice);
        await tester.pumpAndSettle();
        final text = tester.widget<RichText>(
          find.descendant(of: notice, matching: find.byType(RichText)),
        );
        final foreground = text.text.style!.color!;
        final palette = ColorManager.palette(context);
        expect(foreground, palette.mutedStrong);
        final first = foreground.computeLuminance();
        final second = palette.background.computeLuminance();
        final contrast = first > second
            ? (first + .05) / (second + .05)
            : (second + .05) / (first + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    for (final locale in [
      const Locale('en'),
      const Locale('zh'),
      const Locale('ru'),
    ]) {
      testWidgets(
        'Apple bindings show only unbind and the other backup type on $platform / $locale',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(
            platform == TargetPlatform.iOS ? 390 : 1160,
            844,
          );
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(app(locale));
          await tester.pumpAndSettle();
          final l = AppLocalizations.of(
            tester.element(find.byType(PageActionBar)),
          )!;
          Future<void> tapVisible(Finder target) async {
            // Binding changes can reflow long labels and retain a scroll offset.
            await tester.ensureVisible(target);
            // Reveal uses a zero-duration jump. Flush its new geometry without
            // waiting for the busy spinner behind a pending confirmation.
            await tester.pump();
            expect(target.hitTestable(), findsOneWidget);
            await tester.tap(target.hitTestable());
          }

          expect(find.text(l.backupChooseExisting), findsOneWidget);
          expect(find.text(l.backupCreateFile), findsOneWidget);
          for (final (label, request, menu) in [
            (l.backupUseICloud, (false, false), false),
            (l.backupChooseExisting, (false, true), true),
            (l.backupSwitchToCloud, (false, false), false),
            (l.backupCreateFile, (true, true), true),
          ]) {
            storage.target = BackupTarget(
              request.$2
                  ? 'fixture-${storage.selections.length}'
                  : backupContainerId,
              request.$2
                  ? '/backups/local.json'
                  : 'iCloud Drive / OneXray-backup.json',
            );
            storage.bytes = null;
            if (menu) {
              await tapVisible(find.text(l.backupSwitchToLocal));
              await tester.pumpAndSettle();
            }
            final expectedWrites = storage.writes + 1;
            await tapVisible(find.text(label));
            await pumpUntil(
              tester,
              () =>
                  storage.writes == expectedWrites &&
                  service.state.operation == null,
            );
            await tester.pumpAndSettle();
            expect(storage.selections.last, request);
            expect(storage.reads, 0);
            expect(storage.writes, storage.selections.length);
            expect(find.byType(AppConfirmationDialog), findsNothing);
            expect(find.text(l.backupUseICloud), findsNothing);
            expect(find.text(l.backupChooseExisting), findsNothing);
            expect(find.text(l.backupCreateFile), findsNothing);
            expect(find.text(l.backupUnbind), findsOneWidget);
            expect(
              find.text(
                request.$2 ? l.backupSwitchToCloud : l.backupSwitchToLocal,
              ),
              findsOneWidget,
            );
            final actions = find.descendant(
              of: find.byType(SettingSection).first,
              matching: find.byWidgetPredicate(
                (widget) => widget is ShadButton,
              ),
            );
            expect(actions, findsNWidgets(2));
          }
          await tapVisible(find.text(l.backupUnbind));
          await pumpUntil(
            tester,
            () => find.byType(AppConfirmationDialog).evaluate().isNotEmpty,
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tapVisible(
            find.descendant(
              of: find.byType(AppConfirmationDialog),
              matching: find.widgetWithText(FilledButton, l.backupUnbind),
            ),
          );
          await pumpUntil(
            tester,
            () =>
                service.state.settings.target == null &&
                service.state.operation == null,
          );
          await tester.pumpAndSettle();
          expect(service.state.settings.target, null);
          expect(find.text(l.backupUseICloud), findsOneWidget);
          expect(find.text(l.backupChooseExisting), findsOneWidget);
          expect(find.text(l.backupCreateFile), findsOneWidget);
          expect(find.text(l.backupSwitchToCloud), findsNothing);
          expect(find.text(l.backupSwitchToLocal), findsNothing);
          expect(tester.takeException(), null);
          await tester.pumpWidget(const SizedBox());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }

  for (final (locale, width) in const [
    (Locale('en'), 1160.0),
    (Locale('zh'), 390.0),
    (Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), 390.0),
    (Locale('ru'), 1160.0),
    (Locale('fa'), 390.0),
  ]) {
    testWidgets('backup page and direct manual writes fit $locale / $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      preferences.settings = const BackupSettings(
        target: BackupTarget(
          'fixture',
          'OneDrive / a-very-long-selected-directory-name / OneXray-backup.json',
        ),
      );
      await tester.pumpWidget(app(locale));
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(PageActionBar)),
      )!;
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('page-heading')),
          matching: find.text(l.backupTitle),
        ),
        findsOneWidget,
      );
      expect(find.text(l.backupAutomatic), findsOneWidget);
      expect(storage.writes, 0);
      final sections = find.byType(SettingSection);
      final cards = [
        for (var i = 0; i < 2; i++)
          tester.getRect(
            find.descendant(
              of: sections.at(i),
              matching: find.byType(ShadCard),
            ),
          ),
      ];
      expect(cards.first.left, cards.last.left);
      expect(cards.first.right, cards.last.right);
      final headers = [
        tester.getRect(find.text(l.backupLocation)),
        tester.getRect(find.text(l.backupAutomatic).first),
      ];
      final rtl =
          Directionality.of(tester.element(sections.first)) ==
          TextDirection.rtl;
      expect(
        rtl ? headers.first.right : headers.first.left,
        rtl ? headers.last.right : headers.last.left,
      );
      final bottom = tester.getBottomRight(find.byType(PageActionBar)).dy;
      await tester.drag(find.byType(SettingsPageScroll), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(find.byType(PageActionBar)).dy, bottom);
      await tester.tap(find.text(l.backupNow));
      await pumpUntil(
        tester,
        () => storage.writes == 1 && service.state.operation == null,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppConfirmationDialog), findsNothing);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'backup interval saves inline with local progress and no cloud access',
    (tester) async {
      final save = Completer<void>();
      preferences.beforeSaveInterval = () => save.future;
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(PageActionBar)),
      )!;
      final select = find.byType(SettingSelect<AutoUpdateInterval>);
      expect(
        tester.widget<SettingSelect<AutoUpdateInterval>>(select).value,
        AutoUpdateInterval.threeDays,
      );
      await tester.ensureVisible(select);
      await tester.tap(find.text(l.prototypeEveryThreeDays));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.prototypeEveryDay));
      await pumpUntil(
        tester,
        () => service.state.operation == BackupOperation.saving,
      );
      expect(find.byType(BackupPage), findsOneWidget);
      expect(find.byType(ButtonProgressIndicator), findsOneWidget);
      expect(tester.takeException(), null);
      save.complete();
      await tester.pumpAndSettle();
      expect(preferences.period, AutoUpdateInterval.oneDay);
      expect(
        tester.widget<SettingSelect<AutoUpdateInterval>>(select).value,
        AutoUpdateInterval.oneDay,
      );
      expect(find.text(l.prototypeSettingsSaved), findsOneWidget);
      expect((storage.reads, storage.writes), (0, 0));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SettingSelect<AutoUpdateInterval>>(select).value,
        AutoUpdateInterval.oneDay,
      );
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'restore preview shows empty manual groups without the empty-backup warning',
    (tester) async {
      preferences.enabled = false;
      preferences.settings = BackupSettings(target: storage.target);
      await tester.runAsync(() async {
        await assets.db.manualServerGroupDao.insertRow(
          ManualServerGroupCompanion.insert(name: 'Empty group'),
        );
        storage.bytes = encodeBackup(await assets.capture());
      });
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(PageActionBar)),
      )!;
      await tester.tap(find.text(l.backupRestore));
      await pumpUntil(
        tester,
        () => find.byType(AppConfirmationDialog).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining(l.manualGroupCount(1)), findsOneWidget);
      expect(find.textContaining(l.backupEmptyWarning), findsNothing);
      expect(restored, 0);
      await tester.tap(find.text(l.prototypeCancel));
      await tester.pumpAndSettle();
      expect(restored, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'manual backup writes directly; offline restore still requires confirmation',
    (tester) async {
      preferences.enabled = false;
      preferences.settings = BackupSettings(target: storage.target);
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(PageActionBar)),
      )!;
      await tester.tap(find.text(l.backupNow));
      await pumpUntil(
        tester,
        () => storage.bytes != null && service.state.operation == null,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppConfirmationDialog), findsNothing);
      expect(decodeBackup(storage.bytes!).coreConfigs, isEmpty);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.backupRestore));
      await pumpUntil(
        tester,
        () => find.byType(AppConfirmationDialog).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AppConfirmationDialog), findsOneWidget);
      expect(find.textContaining(l.backupEmptyWarning), findsOneWidget);
      expect(restored, 0);
      await tester.tap(find.text(l.prototypeCancel));
      await tester.pumpAndSettle();
      expect(restored, 0);
      expect(storage.writes, 1);
      await tester.tap(find.text(l.backupRestore));
      await pumpUntil(
        tester,
        () => find.byType(AppConfirmationDialog).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.descendant(
          of: find.byType(AppConfirmationDialog),
          matching: find.text(l.backupRestore),
        ),
      );
      await pumpUntil(
        tester,
        () => restored == 1 && service.state.operation == null,
      );
      expect(storage.writes, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'binding starts automatic backup without a dialog and it can be disabled',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(app(const Locale('en')));
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(PageActionBar)),
        )!;
        expect(find.text(l.backupAutomatic), findsOneWidget);
        expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, true);
        expect(
          tester.getSemantics(find.byType(ShadSwitch)).label,
          l.backupAutomatic,
        );
        expect(storage.writes, 0);
        expect(storage.reads, 0);
        await tester.tap(find.text(l.backupChooseExisting));
        await pumpUntil(
          tester,
          () => storage.writes == 1 && service.state.operation == null,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppConfirmationDialog), findsNothing);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(ShadSwitch));
        await tester.tap(find.byType(ShadSwitch));
        await tester.pumpAndSettle();
        expect(preferences.enabled, false);
        expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, false);
        expect(
          tester.getSemantics(find.byType(ShadSwitch)).label,
          l.backupAutomatic,
        );
        expect(storage.writes, 1);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'provider read shows only local loading; leaving skips late preview',
    (tester) async {
      preferences.enabled = false;
      final held = _HeldRead();
      service = BackupService.forTesting(
        storage: held,
        preferences: preferences,
        assets: assets,
        now: DateTime.now,
        restore: (commit) => commit(),
      );
      addTearDown(service.close);
      preferences.settings = BackupSettings(target: held.target);
      held.bytes = await tester.runAsync(
        () async => encodeBackup(await assets.capture()),
      );
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pump();
      expect(find.byType(ButtonProgressIndicator), findsOneWidget);
      expect(
        tester.widget<ShadSwitch>(find.byType(ShadSwitch)).enabled,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      held.finish.complete();
      await pumpUntil(tester, () => service.state.operation == null);
      await tester.pump();
      expect(find.byType(AppConfirmationDialog), findsNothing);
      expect(restored, 0);
      expect(tester.takeException(), null);
    },
  );

  for (final (locale, width) in const [
    (Locale('en'), 1160.0),
    (Locale('zh'), 390.0),
    (Locale('ru'), 390.0),
  ]) {
    testWidgets(
      'existing-file choice fits $locale; cancel preserves and overwrite replaces',
      (tester) async {
        debugDefaultTargetPlatformOverride = width > 700
            ? TargetPlatform.macOS
            : TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final original = BackupSettings(
          target: const BackupTarget(backupContainerId, 'Old backup'),
          lastSuccess: DateTime(2026, 9, 16),
        );
        preferences.settings = original;
        storage.target = const BackupTarget(
          'fixture',
          '/chosen/backups/existing.json',
        );
        storage.bytes = Uint8List.fromList([42]);
        final bytes = storage.bytes;
        await tester.pumpWidget(app(locale));
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(PageActionBar)),
        )!;
        Future<void> choose() async {
          await tester.tap(find.text(l.backupSwitchToLocal));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l.backupChooseExisting));
          await pumpUntil(
            tester,
            () => find.byType(ExistingBackupDialog).evaluate().isNotEmpty,
          );
          await tester.pump(const Duration(milliseconds: 400));
        }

        await choose();
        expect(find.text('existing.json'), findsOneWidget);
        expect((storage.reads, storage.writes), (0, 0));
        await tester.tap(
          find.descendant(
            of: find.byType(ExistingBackupDialog),
            matching: find.text(l.prototypeCancel),
          ),
        );
        await tester.pumpAndSettle();
        expect(preferences.settings, original);
        expect(storage.bytes, bytes);
        await choose();
        await tester.tap(
          find.descendant(
            of: find.byType(ExistingBackupDialog),
            matching: find.text(l.backupOverwrite),
          ),
        );
        await pumpUntil(
          tester,
          () => storage.writes == 1 && service.state.operation == null,
        );
        await tester.pumpAndSettle();
        expect(storage.reads, 0);
        expect(preferences.settings.target!.identifier, 'fixture');
        expect(decodeBackup(storage.bytes!).coreConfigs, isEmpty);
        expect(find.byType(AppConfirmationDialog), findsNothing);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'binding restore previews before confirmation and never overwrites the source',
    (tester) async {
      final original = const BackupSettings(
        target: BackupTarget('old', 'Old backup'),
      );
      preferences.settings = original;
      storage.bytes = await tester.runAsync(
        () async => encodeBackup(await assets.capture()),
      );
      final bytes = storage.bytes;
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(PageActionBar)),
      )!;
      Future<void> chooseRestore() async {
        await tester.tap(find.text(l.backupChangeLocation));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.backupChooseExisting));
        await pumpUntil(
          tester,
          () => find.byType(ExistingBackupDialog).evaluate().isNotEmpty,
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.descendant(
            of: find.byType(ExistingBackupDialog),
            matching: find.text(l.backupRestore),
          ),
        );
        await pumpUntil(
          tester,
          () => find.byType(AppConfirmationDialog).evaluate().isNotEmpty,
        );
        await tester.pump(const Duration(milliseconds: 400));
      }

      await chooseRestore();
      expect((restored, storage.writes), (0, 0));
      expect(find.textContaining(l.backupEmptyWarning), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AppConfirmationDialog),
          matching: find.text(l.prototypeCancel),
        ),
      );
      await tester.pumpAndSettle();
      expect(preferences.settings, original);
      await chooseRestore();
      await tester.tap(
        find.descendant(
          of: find.byType(AppConfirmationDialog),
          matching: find.text(l.backupRestore),
        ),
      );
      await pumpUntil(
        tester,
        () => restored == 1 && service.state.operation == null,
      );
      await tester.pumpAndSettle();
      expect(preferences.settings.target!.identifier, 'fixture');
      expect(storage.bytes, bytes);
      expect(storage.writes, 0);
      await service.checkAutomatic();
      expect(storage.writes, 0);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _HeldRead extends MemoryBackupStorage {
  final finish = Completer<void>();
  @override
  Future<Uint8List> read(BackupTarget target) async {
    await finish.future;
    return super.read(target);
  }
}
