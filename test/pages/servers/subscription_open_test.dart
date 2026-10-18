import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/import/controller.dart';
import 'package:onexray/pages/servers/import/page.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
  late Completer<Map<String, Object?>> recoveredPackageInfo;

  setUpAll(() async {
    recoveredPackageInfo = Completer<Map<String, Object?>>();
    var firstRequest = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          if (firstRequest) {
            firstRequest = false;
            throw PlatformException(code: 'temporarily-unavailable');
          }
          return recoveredPackageInfo.future;
        });
    await NetClient().asyncInit();
    expect(NetClient().downloadUserAgent, startsWith('v2rayN/0.0.0 '));
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
  });

  testWidgets('single-link file import cannot overlap another import action', (
    tester,
  ) async {
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _SubscriptionFilePicker();
    addTearDown(() => FilePickerPlatform.instance = previous);
    final controller = ServerImportController(
      loadSubscription: (_) async => null,
    );
    addTearDown(controller.close);
    await _openMethods(tester, controller);
    final addSubscription = tester
        .widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Add subscription'),
        )
        .onPressed!;
    await tester.runAsync(() async {
      final loaded = controller.stream.firstWhere(
        (state) => state.url == 'https://provider.example/list' && !state.busy,
      );
      await tester.tap(find.text('Import file'));
      await loaded.timeout(const Duration(seconds: 5));
    });
    // Exercise the previous frame's enabled button before a form is rendered.
    addSubscription();
    await tester.runAsync(() async {
      recoveredPackageInfo.complete({
        'appName': 'OneXray',
        'packageName': 'net.yuandev.onexray',
        'version': '26.10.4',
        'buildNumber': '104',
        'buildSignature': '',
      });
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(
      find.byType(ServerImportFormPage, skipOffstage: false),
      findsOneWidget,
    );
    expect(controller.userAgent.text, NetClient().downloadUserAgent);
    expect(controller.url.text, 'https://provider.example/list');
    expect(controller.state.busy, isFalse);
    expect(controller.state.openingAction, isNull);
    expect(controller.canSubmit(ServerImportAction.subscription), isTrue);
    await _backAndReopen(tester);
  });

  testWidgets(
    'subscription form reuses the initialized UA across repeat taps',
    (tester) async {
      final controller = ServerImportController(
        loadSubscription: (_) async => null,
      );
      addTearDown(controller.close);
      await _openMethods(tester, controller);
      final addSubscription = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Add subscription'),
          )
          .onPressed!;
      await tester.tap(find.text('Add subscription'));
      addSubscription();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byType(ServerImportFormPage, skipOffstage: false),
        findsOneWidget,
      );
      expect(controller.userAgent.text, NetClient().downloadUserAgent);
      expect(controller.state.busy, isFalse);
      expect(controller.state.openingAction, isNull);
      controller.name.text = 'Test subscription';
      controller.url.text = 'https://provider.example/list';
      expect(controller.canSubmit(ServerImportAction.subscription), isTrue);
      await _backAndReopen(tester);
    },
  );
}

Future<void> _openMethods(
  WidgetTester tester,
  ServerImportController controller,
) async {
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
}

Future<void> _backAndReopen(WidgetTester tester) async {
  await tester.tap(find.text('Back'));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
  expect(find.byType(ServerImportFormPage, skipOffstage: false), findsNothing);
  expect(find.byType(ServersImportPage), findsOneWidget);
  await tester.tap(find.text('Add subscription'));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
  expect(
    find.byType(ServerImportFormPage, skipOffstage: false),
    findsOneWidget,
  );
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

class _SubscriptionFilePicker extends FilePickerPlatform {
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => _SubscriptionFile();
}

base class _SubscriptionFile extends PlatformFile {
  @override
  String get path =>
      File('test/pages/servers/fixtures/single-subscription.txt').absolute.path;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
