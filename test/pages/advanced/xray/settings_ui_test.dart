import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/advanced/xray/controller.dart';
import 'package:onexray/pages/advanced/xray/log/controller.dart';
import 'package:onexray/pages/advanced/xray/log/params.dart';
import 'package:onexray/pages/advanced/xray/page.dart';
import 'package:onexray/pages/advanced/xray/ping/page.dart';
import 'package:onexray/pages/advanced/xray/ping/controller.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/advanced/xray/data_update/page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/ping/state.dart';
import 'package:onexray/service/advanced/xray/data_update/state.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  late AppEventBus eventBus;
  final preferences = _PingPreferences();

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = preferences;
    preferences.failRead = false;
    preferences.failWrite = false;
    await PreferencesKey().clearUserDataPreferences();
    eventBus = AppEventBus();
  });

  tearDown(() async {
    await eventBus.close();
  });

  Widget app(Widget child, {Locale locale = const Locale('en')}) {
    return MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, appChild) => ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadBlueColorScheme.light(),
          radius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: ShadToaster(child: appChild ?? const SizedBox.shrink()),
      ),
      home: child,
    );
  }

  testWidgets('ping settings remain scrollable on phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(app(const PingPage()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Speed test URL'), findsWidgets);
    expect(find.text('Auto ping new nodes'), findsNothing);
    expect(find.byType(PageActionBar), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(SettingSelect<double>), findsOneWidget);
    expect(find.byType(ShadSwitch), findsNothing);
    final l = AppLocalizations.of(tester.element(find.byType(PingPage)))!;
    expect(find.text(l.pingVpnAccuracyHint), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid ping URL stays beside the field without saving', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await (PingState()
          ..url = PingUrl.custom
          ..customUrl = 'https://example.com/old')
        .saveToPreferences();
    await tester.pumpWidget(app(const PingPage()));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('ping-custom-url'));
    final controller = tester.element(field).read<PingController>();
    final l = AppLocalizations.of(tester.element(field))!;

    await tester.ensureVisible(field);
    await tester.enterText(field, 'invalid');
    await tester.tap(find.text(l.prototypeSave));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.widget<TextField>(field).decoration?.errorText,
      l.prototypeEnterHttpUrl,
    );
    expect(find.text(l.prototypeEnterHttpUrl), findsOneWidget);
    expect(controller.customUrlFocusNode.hasFocus, isTrue);
    expect(controller.state.error, isNull);
    expect(controller.state.saving, isFalse);
    controller.customUrlController.selection = const TextSelection.collapsed(
      offset: 2,
    );
    await tester.pumpAndSettle();
    expect(controller.state.invalidUrl, isTrue);
    final stored = PingState();
    await stored.readFromPreferences();
    expect(stored.customUrl, 'https://example.com/old');

    await tester.enterText(field, 'https://example.com/new');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).decoration?.errorText, isNull);
    expect(controller.state.invalidUrl, isFalse);
    await stored.readFromPreferences();
    expect(stored.customUrl, 'https://example.com/old');

    await tester.enterText(field, 'invalid again');
    await tester.tap(find.text(l.prototypeSave));
    await tester.pumpAndSettle();
    controller.updateUrl(PingUrl.google.name);
    await tester.pumpAndSettle();
    expect(controller.state.invalidUrl, isFalse);
    expect(find.text(l.prototypeEnterHttpUrl), findsNothing);
    expect(controller.customUrlController.text, 'invalid again');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ping read and save failures remain visible separately', (
    tester,
  ) async {
    preferences.failRead = true;
    await tester.pumpWidget(app(const PingPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ping preferences unavailable'), findsOneWidget);

    preferences.failRead = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    preferences.failWrite = true;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('Ping storage unavailable'), findsOneWidget);
    final controller = tester
        .element(find.byType(PageActionBar))
        .read<PingController>();
    expect(controller.state.invalidUrl, isFalse);
    expect(controller.state.saving, isFalse);
    controller.updateTimeout(6);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ping storage unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final save in [false, true]) {
    testWidgets(
      'ping settings ${save ? 'save and refresh' : 'cancel and retain'} the Xray summary',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1160, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await (PingState()
              ..url = PingUrl.google
              ..customUrl = 'https://example.com/old'
              ..timeout = 5)
            .saveToPreferences();
        const systemExtensionChannel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.onexray.BridgeHostApi.useSystemExtension',
          BridgeHostApi.pigeonChannelCodec,
        );
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockDecodedMessageHandler(
          systemExtensionChannel,
          (_) async => [false],
        );
        addTearDown(
          () => messenger.setMockDecodedMessageHandler(
            systemExtensionChannel,
            null,
          ),
        );
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final coordinator = ConnectionCoordinator(
          database: db,
          readRuntime: () async => null,
        );
        late XrayRuntimeController root;
        await tester.runAsync(() async {
          root = XrayRuntimeController(coordinator: coordinator);
          await root.stream.firstWhere((state) => !state.loading);
        });
        addTearDown(
          () => tester.runAsync(() async {
            await root.close();
            coordinator.dispose();
            await db.close();
          }),
        );
        expect(root.failed, isFalse);
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => XrayRuntimePage(
                createController: () => root,
                onGeodata: (_) {},
                onUpdates: (_) {},
                onSpeedTest: (context) => context.push<void>('/ping'),
                onConfig: (_, _) {},
              ),
            ),
            GoRoute(path: '/ping', builder: (_, _) => const PingPage()),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalePolicy.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
            builder: (_, child) => ShadTheme(
              data: AppTheme.shad(Brightness.light),
              child: ShadToaster(child: child!),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(XrayRuntimePage)),
        )!;
        final originalSummary = '${l.prototypeSeconds(5)} · Google';
        final savedSummary =
            '${l.prototypeSeconds(3)} · ${l.prototypeCustomUrl}';
        expect(find.text(originalSummary), findsOneWidget);
        await tester.ensureVisible(find.text(l.prototypeSpeedTest));
        await tester.tap(find.text(l.prototypeSpeedTest));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ping-url-preset')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.prototypeCustom).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ping-timeout')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.prototypeSeconds(3)).last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(
          find.byType(TextField),
          'https://example.com/new',
        );
        await tester.pumpAndSettle();
        final storedDraft = PingState();
        await storedDraft.readFromPreferences();
        expect(storedDraft.customUrl, 'https://example.com/old');
        expect(storedDraft.url, PingUrl.google);
        expect(storedDraft.timeout, 5);

        await tester.tap(find.text(save ? l.prototypeSave : l.prototypeCancel));
        await tester.pumpAndSettle();
        expect(find.byType(PingPage), findsNothing);
        final restored = PingState();
        await restored.readFromPreferences();
        expect(
          restored.customUrl,
          'https://example.com/${save ? 'new' : 'old'}',
        );
        expect(restored.url, save ? PingUrl.custom : PingUrl.google);
        expect(restored.timeout, save ? 3 : 5);
        expect(
          find.text(save ? savedSummary : originalSummary),
          findsOneWidget,
        );

        await tester.tap(find.text(l.prototypeSpeedTest));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SettingSelect<String>>(
                find.byKey(const ValueKey('ping-url-preset')),
              )
              .value,
          restored.url.name,
        );
        expect(
          tester
              .widget<SettingSelect<double>>(
                find.byKey(const ValueKey('ping-timeout')),
              )
              .value,
          restored.timeout,
        );
        if (!save) {
          await tester.tap(find.byKey(const ValueKey('ping-url-preset')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l.prototypeCustom).last);
          await tester.pumpAndSettle();
        }
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          restored.customUrl,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(root.close);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('runtime preference fields fit ${locale.toLanguageTag()}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final page in [const PingPage(), const AutoUpdatePage()]) {
        await tester.pumpWidget(app(page, locale: locale));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(PageActionBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('backup does not enable the disabled Geodata interval', (
    tester,
  ) async {
    final updates = AutoUpdateState()..geoDataEnable = false;
    await updates.saveToPreferences();
    await PreferencesKey().saveAutomaticBackup(true);
    await tester.pumpWidget(app(const AutoUpdatePage()));
    await tester.pumpAndSettle();
    final intervals = tester
        .widgetList<SettingSelect<AutoUpdateInterval>>(
          find.byType(SettingSelect<AutoUpdateInterval>),
        )
        .toList();
    expect(intervals, hasLength(2));
    expect(intervals.first.onChanged, isNotNull);
    expect(intervals.last.onChanged, null);
    expect(tester.takeException(), null);
  });

  for (final size in const [
    Size(390, 844),
    Size(1032, 1376),
    Size(1160, 720),
  ]) {
    testWidgets(
      'Xray preference choices fill their single form card at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        for (final (page, choices) in <(Widget, List<String>)>[
          (const PingPage(), ['ping-url', 'ping-timeout']),
          (
            const AutoUpdatePage(),
            ['subscription-update-interval', 'geodata-update-interval'],
          ),
        ]) {
          await tester.pumpWidget(app(page));
          await tester.pumpAndSettle();
          expect(find.byType(ShadCard), findsOneWidget);
          final l = AppLocalizations.of(
            tester.element(find.byType(PageActionBar)),
          )!;
          expect(
            find.widgetWithText(
              AppBar,
              page is PingPage
                  ? l.xrayLatencyTitle
                  : l.prototypeAutomaticUpdates,
            ),
            findsOneWidget,
          );
          expect(find.text(l.pageXrayConfigurationDescription), findsNothing);
          for (final choice in choices) {
            final field = find.byKey(ValueKey('$choice-field'));
            final control = find.byKey(
              ValueKey(choice == 'ping-url' ? 'ping-url-preset' : choice),
            );
            expect(field, findsOneWidget);
            expect(control, findsOneWidget);
            final fieldRect = tester.getRect(field);
            final controlRect = tester.getRect(control);
            expect(controlRect.left, closeTo(fieldRect.left, .5));
            expect(controlRect.right, closeTo(fieldRect.right, .5));
            expect(controlRect.top, greaterThan(fieldRect.top));
            expect(
              find.ancestor(of: control, matching: find.byType(ShadCard)),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('ping settings restore a custom URL', (tester) async {
    final pingState = PingState()
      ..url = PingUrl.custom
      ..customUrl = 'https://example.com/ping';
    await pingState.saveToPreferences();

    await tester.pumpWidget(app(const PingPage()));
    await tester.pump(const Duration(milliseconds: 100));

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, 'https://example.com/ping');
    expect(find.text('Resolved URL'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('log viewer controller reads the current file tail', () async {
    final fixtures = await Directory('../references/onexray-tests').absolute
        .create(recursive: true);
    final tempDir = await fixtures.createTemp('onexray-log-test');
    addTearDown(() => tempDir.delete(recursive: true));
    final logFile = File('${tempDir.path}/access.log');
    await logFile.writeAsString('first line\nsecond line\n');
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final coordinator = ConnectionCoordinator(
      database: database,
      statusEvents: const Stream.empty(),
      disposeStatus: () {},
    );
    addTearDown(coordinator.dispose);

    final controller = LogFileViewerController(
      LogFileViewerParams(title: 'access log', path: logFile.path),
      coordinator: coordinator,
    );
    addTearDown(controller.close);
    await controller.stream
        .firstWhere((state) => state.fileExists || state.failure != null)
        .timeout(const Duration(seconds: 5));

    expect(controller.state.lines, ['first line', 'second line']);
    expect(controller.state.fileExists, isTrue);
  });
}

final class _PingPreferences extends InMemorySharedPreferencesAsync {
  _PingPreferences() : super.empty();

  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> getString(
    String key,
    SharedPreferencesOptions options,
  ) async {
    if (failRead && key == 'app2.pingState') {
      throw StateError('Ping preferences unavailable');
    }
    return super.getString(key, options);
  }

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {
    if (failWrite && key == 'app2.pingState') {
      throw StateError('Ping storage unavailable');
    }
    return super.setString(key, value, options);
  }
}
