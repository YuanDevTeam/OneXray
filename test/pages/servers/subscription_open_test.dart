import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/import/controller.dart';
import 'package:onexray/pages/servers/import/page.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  // Keep the package-info cache empty in this test's isolate until it replies.
  testWidgets('subscription opening blocks repeat taps while loading its UA', (
    tester,
  ) async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
    final packageInfo = Completer<Map<String, Object?>>();
    var firstRequest = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (firstRequest) {
        firstRequest = false;
        throw PlatformException(code: 'temporarily-unavailable');
      }
      return packageInfo.future;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    // Startup can continue with the fallback UA after a platform failure.
    await NetClient().asyncInit();
    expect(NetClient().downloadUserAgent, startsWith('v2rayN/0.0.0 '));
    final controller = ServerImportController(
      loadSubscription: (_) async => null,
    );
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        builder: (_, child) => ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: ShadToaster(child: child!),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppDialog<void>(
                context,
                (_) => ServersImportPage(controller: controller),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // Tap twice before rebuilding so even the old enabled callback is covered.
    await tester.tap(find.text('Add subscription'));
    await tester.tap(find.text('Add subscription'));
    await tester.pump();

    expect(controller.state.busy, isTrue);
    expect(controller.state.openingAction, ServerImportAction.subscription);
    expect(find.byType(ButtonProgressIndicator), findsOneWidget);
    expect(
      tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .every((button) => button.onPressed == null),
      isTrue,
    );
    expect(find.byType(ServerImportFormPage), findsNothing);

    packageInfo.complete({
      'appName': 'OneXray',
      'packageName': 'net.yuandev.onexray',
      'version': '26.10.4',
      'buildNumber': '104',
      'buildSignature': '',
    });
    await tester.pumpAndSettle();

    expect(
      find.byType(ServerImportFormPage, skipOffstage: false),
      findsOneWidget,
    );
    expect(controller.state.busy, isFalse);
    expect(controller.state.openingAction, isNull);
    expect(controller.userAgent.text, startsWith('v2rayN/26.10.4 OneXray/'));
    controller.name.text = 'Test subscription';
    controller.url.text = 'https://provider.example/list';
    expect(controller.canSubmit(ServerImportAction.subscription), isTrue);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(
      find.byType(ServerImportFormPage, skipOffstage: false),
      findsNothing,
    );
    expect(find.byType(ServersImportPage), findsOneWidget);
    expect(find.text('Add subscription'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
