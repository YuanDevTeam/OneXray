import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/settings/controller.dart';
import 'package:onexray/pages/settings/page.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  for (final (locale, size) in const [
    (Locale('en'), Size(390, 844)),
    (Locale('ru'), Size(1160, 900)),
    (Locale('fa'), Size(390, 844)),
  ]) {
    testWidgets(
      'single-column settings keep cleanup scopes distinct and cancellation inert: $locale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final previous = SharedPreferencesAsyncPlatform.instance;
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
        await PreferencesKey().saveConnectOnAppLaunch(true);
        await SharedPreferencesAsync().setString(
          'cleanup-test-marker',
          'retained',
        );
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
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        await tester.pumpWidget(
          BlocProvider.value(
            value: bus,
            child: MaterialApp(
              theme: AppTheme.light,
              locale: locale,
              localizationsDelegates: AppLocalePolicy.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => ShadTheme(
                data: AppTheme.shad(Brightness.light),
                child: ShadToaster(child: child!),
              ),
              home: const SettingsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(SettingsPage)),
        )!;
        Finder section(String title) => find.byWidgetPredicate(
          (widget) => widget is SettingSection && widget.title == title,
        );
        Finder row(String title) => find.byWidgetPredicate(
          (widget) => widget is SettingRow && widget.title == title,
        );
        final sections = [
          l.prototypeAppearance,
          l.prototypeLanguage,
          l.prototypeStartup,
          l.prototypeData,
          l.prototypeAbout,
        ].map((title) => tester.getRect(section(title))).toList();
        for (var index = 0; index < sections.length; index++) {
          expect(sections[index].left, closeTo(sections.first.left, .01));
          expect(sections[index].width, closeTo(sections.first.width, .01));
          if (index > 0) {
            expect(
              sections[index].top,
              greaterThan(sections[index - 1].bottom),
            );
          }
        }
        final resources = row(l.clearConnectionResources);
        final all = row(l.clearAllAppData);
        expect(resources, findsOneWidget);
        expect(all, findsOneWidget);
        expect(
          tester.getRect(all).top,
          greaterThanOrEqualTo(tester.getRect(resources).bottom),
        );
        final context = tester.element(resources);
        final controller = context.read<SettingsController>();
        for (final resourcesOnly in [true, false]) {
          final entry = resourcesOnly ? resources : all;
          await tester.ensureVisible(entry);
          await tester.pumpAndSettle();
          await tester.tap(entry);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final confirmation = tester.widget<AppConfirmationDialog>(
            find.byType(AppConfirmationDialog),
          );
          expect(
            confirmation.title,
            resourcesOnly
                ? l.clearConnectionResources
                : l.prototypeClearAllDataQuestion,
          );
          expect(
            confirmation.content,
            resourcesOnly
                ? l.clearConnectionResourcesWarning
                : l.prototypeClearAllDataWarning,
          );
          expect(confirmation.barrierDismissible, isFalse);
          expect(controller.state.clearingData, isTrue);
          expect(
            controller.state.cleanupScope,
            resourcesOnly ? 'resources' : 'all',
          );
          expect(tester.widget<SettingRow>(resources).onTap, isNull);
          expect(tester.widget<SettingRow>(all).onTap, isNull);
          await controller.clearData(context, resourcesOnly: !resourcesOnly);
          expect(find.byType(AppConfirmationDialog), findsOneWidget);
          await tester.tap(
            find.widgetWithText(OutlinedButton, l.prototypeCancel),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AppConfirmationDialog), findsNothing);
          expect(controller.state.clearingData, isFalse);
          expect(controller.state.cleanupScope, isEmpty);
          expect(tester.widget<SettingRow>(resources).onTap, isNotNull);
          expect(tester.widget<SettingRow>(all).onTap, isNotNull);
          expect(await PreferencesKey().readConnectOnAppLaunch(), isTrue);
          expect(
            await SharedPreferencesAsync().getString('cleanup-test-marker'),
            'retained',
          );
          expect(find.text(l.prototypeDone), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
