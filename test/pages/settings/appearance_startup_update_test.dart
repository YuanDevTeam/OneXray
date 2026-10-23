import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/desktop_startup/model.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/settings/app_update/dialog.dart';
import 'package:onexray/pages/settings/app_update/controller.dart';
import 'package:onexray/pages/settings/desktop/controller.dart';
import 'package:onexray/pages/settings/desktop/page.dart';
import 'package:onexray/pages/settings/page.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/settings/theme/page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/app_update/service.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  Widget app(Widget child) {
    return MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, appChild) => ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadBlueColorScheme.light(),
          radius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: ShadToaster(child: appChild ?? const SizedBox.shrink()),
      ),
      home: Scaffold(body: SafeArea(child: child)),
    );
  }

  testWidgets('desktop startup switches forward the selected values', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final changes = <String, bool>{};
    await tester.pumpWidget(
      app(
        DesktopSettingsView(
          state: const DesktopSettingsPageState(
            launchAtLogin: LaunchAtLoginStatus.enabled(),
            startHidden: true,
            hideDockIcon: true,
            loading: false,
          ),
          showMacOSOptions: true,
          onLaunchAtLoginChanged: (value) => changes['login'] = value,
          onStartHiddenChanged: (value) => changes['hidden'] = value,
          onHideDockIconChanged: (value) => changes['dock'] = value,
          onOpenSystemSettings: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Launch at login'), findsOneWidget);
    expect(find.text('Start hidden'), findsOneWidget);
    expect(find.text('Connect on App Launch'), findsNothing);
    expect(find.text('Hide Dock icon'), findsOneWidget);
    expect(find.byType(ShadSwitch), findsNWidgets(3));
    final switches = find.byType(ShadSwitch);
    for (var index = 0; index < 3; index++) {
      await tester.tap(switches.at(index));
      await tester.pump();
    }
    expect(changes, {'login': false, 'hidden': false, 'dock': false});
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop window behavior does not depend on login registration', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    bool? startHidden;
    var loginChanges = 0;
    await tester.pumpWidget(
      app(
        DesktopSettingsView(
          state: const DesktopSettingsPageState(
            launchAtLogin: LaunchAtLoginStatus.unavailable(),
            loading: false,
          ),
          showMacOSOptions: false,
          onLaunchAtLoginChanged: (_) => loginChanges++,
          onStartHiddenChanged: (value) => startHidden = value,
          onHideDockIconChanged: (_) {},
          onOpenSystemSettings: () {},
        ),
      ),
    );
    await tester.pump();

    final switches = tester.widgetList<ShadSwitch>(find.byType(ShadSwitch));
    expect(switches.map((item) => item.enabled), [false, true]);
    await tester.tap(find.byType(ShadSwitch).first);
    await tester.tap(find.byType(ShadSwitch).last);
    await tester.pump();
    expect(loginChanges, 0);
    expect(startHidden, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final (locale, width, scale, vertical) in const [
    (Locale('en'), 390.0, 1.0, false),
    (Locale('en'), 390.0, 2.0, true),
    (Locale('ru'), 390.0, 2.0, true),
    (Locale('en'), 834.0, 2.0, false),
    (Locale('fa'), 390.0, 2.0, true),
  ]) {
    testWidgets(
      'settings appearance adapts to labels at $locale / $width / $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final previousPreferences = SharedPreferencesAsyncPlatform.instance;
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        addTearDown(
          () => SharedPreferencesAsyncPlatform.instance = previousPreferences,
        );
        await PreferencesKey().saveThemeCode(ThemeCode.system.name);
        final bus = AppEventBus();
        addTearDown(bus.close);
        const iconChannel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.onexray.BridgeHostApi.getCurrentAppIcon',
          BridgeHostApi.pigeonChannelCodec,
        );
        const invokeChannel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.onexray.BridgeHostApi.invoke',
          BridgeHostApi.pigeonChannelCodec,
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockDecodedMessageHandler(
          iconChannel,
          (_) async => ['IconBlue'],
        );
        messenger.setMockDecodedMessageHandler(
          invokeChannel,
          (_) async => [
            '{"apiVersion":3,"success":true,"data":{"version":"v26.10.21"}}',
          ],
        );
        addTearDown(() {
          messenger.setMockDecodedMessageHandler(iconChannel, null);
          messenger.setMockDecodedMessageHandler(invokeChannel, null);
        });
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            BlocProvider.value(
              value: bus,
              child: MaterialApp(
                theme: AppTheme.material(Brightness.light, mobile: true),
                locale: locale,
                localizationsDelegates: AppLocalePolicy.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: ShadTheme(
                    data: AppTheme.shad(Brightness.light, mobile: true),
                    child: ShadToaster(child: child!),
                  ),
                ),
                home: const SettingsPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l = AppLocalizations.of(
            tester.element(find.byType(SettingsPage)),
          )!;
          final system = find.text(l.prototypeSystem);
          final light = find.text(l.prototypeLight);
          final dark = find.text(l.prototypeDark);
          final systemRect = tester.getRect(system);
          final lightRect = tester.getRect(light);
          final darkRect = tester.getRect(dark);
          if (vertical) {
            expect(lightRect.top, greaterThanOrEqualTo(systemRect.bottom));
            expect(darkRect.top, greaterThanOrEqualTo(lightRect.bottom));
          } else {
            expect(lightRect.center.dy, systemRect.center.dy);
            expect(darkRect.center.dy, systemRect.center.dy);
          }
          final selected = find.ancestor(
            of: dark,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.selected != null,
            ),
          );
          expect(
            tester.widget<Semantics>(selected).properties.selected,
            isFalse,
          );
          await tester.ensureVisible(dark);
          await tester.tap(dark);
          await tester.pumpAndSettle();
          expect(bus.state.themeCode, ThemeCode.dark);
          expect(await PreferencesKey().readThemeCode(), ThemeCode.dark.name);
          expect(
            tester.widget<Semantics>(selected).properties.selected,
            isTrue,
          );

          if ((AppPlatform.isIOS || AppPlatform.isMacOS) && width == 390) {
            final iconRow = tester.widget<SettingRow>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is SettingRow && widget.title == l.prototypeAppIcon,
              ),
            );
            if (scale == 1) {
              expect(iconRow.value, isNotNull);
              expect(iconRow.subtitleWidget, isNull);
            } else {
              expect(iconRow.value, isNull);
              expect(iconRow.subtitleWidget, isA<Text>());
              expect((iconRow.subtitleWidget! as Text).maxLines, isNull);
            }
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets('theme choice uses the shared selected indicator', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      app(ThemeChoiceView(selected: ThemeCode.dark, onSelected: (_) {})),
    );
    await tester.pump();

    final l = AppLocalizations.of(
      tester.element(find.byType(ThemeChoiceView)),
    )!;
    expect(find.text(l.themePageSystem), findsOneWidget);
    expect(find.text(l.themePageDark), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme selection stays a draft until Save persists and returns', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final previousPreferences = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(
      () => SharedPreferencesAsyncPlatform.instance = previousPreferences,
    );
    await PreferencesKey().saveThemeCode(ThemeCode.system.name);
    final bus = AppEventBus();
    addTearDown(bus.close);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/theme'),
              child: const Text('Open theme'),
            ),
          ),
        ),
        GoRoute(path: '/theme', builder: (_, _) => const ThemePage()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ShadTheme(
          data: ShadThemeData(colorScheme: const ShadBlueColorScheme.light()),
          child: ShadToaster(child: child!),
        ),
      ),
    );
    await tester.tap(find.text('Open theme'));
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(ThemePage)))!;
    await tester.tap(find.text(l.themePageDark));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ThemeChoiceView>(find.byType(ThemeChoiceView)).selected,
      ThemeCode.dark,
    );
    expect(bus.state.themeCode, ThemeCode.system);
    expect(await PreferencesKey().readThemeCode(), ThemeCode.system.name);

    await tester.tap(find.text(l.buttonSave));
    await tester.pumpAndSettle();
    expect(await PreferencesKey().readThemeCode(), ThemeCode.dark.name);
    expect(bus.state.themeCode, ThemeCode.dark);
    expect(find.byType(ThemePage), findsNothing);
    expect(find.text('Open theme'), findsOneWidget);
    expect(find.text(l.prototypeSettingsSaved), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('update dialog keeps long notes scrollable with all actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final notes = List.generate(
      30,
      (index) => '- Release note item ${index + 1}',
    ).join('\n');
    final info = AppUpdateInfo(
      currentVersion: '26.7.3',
      latestVersion: '26.8.0',
      releaseNotes: notes,
      releaseUri: Uri.parse('https://example.com/release'),
      updateUri: Uri.parse('https://example.com/update'),
      destination: AppUpdateDestination.githubRelease,
    );
    final actions = <String>[];
    await tester.pumpWidget(
      app(
        AppUpdateDialogView(
          updateInfo: info,
          onLater: () => actions.add('later'),
          onSkip: () => actions.add('skip'),
          onUpdate: () => actions.add('update'),
          onOpenLink: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Skip this version'), findsOneWidget);
    expect(find.text('Go to update'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Release note item 30'), findsWidgets);
    for (final label in ['Later', 'Skip this version', 'Go to update']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(actions, ['later', 'skip', 'update']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed update launch reports back after the dialog closes', (
    tester,
  ) async {
    final launched = Completer<bool>();
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) => launched.future);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final controller = AppUpdateDialogController(
      AppUpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '2.0.0',
        releaseNotes: '',
        releaseUri: Uri.parse('https://example.com/release'),
        updateUri: Uri.parse('https://example.com/update'),
        destination: AppUpdateDestination.githubRelease,
      ),
    );
    addTearDown(controller.close);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                actions: [
                  TextButton(
                    onPressed: () => controller.update(context),
                    child: const Text('Update'),
                  ),
                ],
              ),
            ),
            child: const Text('Show update'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    launched.complete(false);
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.text('Show update')))!;
    expect(
      find.text('${l.resultFailed}\nCould not open update page'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
