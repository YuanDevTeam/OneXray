import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/advanced/tunnel/apple/page.dart';
import 'package:onexray/pages/advanced/tunnel/apple/wifi.dart';
import 'package:onexray/pages/advanced/tunnel/apple/widgets.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(427, 876);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void _desktop(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1160, 688);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _app(
  Widget view, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppTheme.material(brightness, mobile: true),
  builder: (context, child) =>
      ShadTheme(data: AppTheme.shad(brightness, mobile: true), child: child!),
  home: Scaffold(body: SingleChildScrollView(child: view)),
);

PolicyEditorController _controller({
  ConnectionPlatform platform = ConnectionPlatform.ios,
  Map<String, Object>? apple,
}) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final coordinator = ConnectionCoordinator(
    database: db,
    statusEvents: const Stream.empty(),
  );
  final draft = PolicyEditorDraft(ConnectionConfiguration());
  (draft.policy['apple'] as Map<String, dynamic>).addAll(apple ?? {});
  final controller = PolicyEditorController(
    draft: draft,
    service: PolicyEditorService(coordinator: coordinator, platform: platform),
  );
  addTearDown(() async {
    await controller.close();
    coordinator.dispose();
    await db.close();
  });
  return controller;
}

final _supported = AppleVpnCapabilities(
  serviceExclusions: true,
  deviceCommunication: true,
);

Finder _toggle(String field) => find.descendant(
  of: find.byKey(ValueKey(field)),
  matching: find.byType(ShadSwitch),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final desktop in [false, true]) {
    testWidgets(
      'Apple excluded networks can be edited and survive capture all ($desktop)',
      (tester) async {
        if (desktop) {
          _desktop(tester);
        } else {
          _phone(tester);
        }
        final controller = _controller();
        await tester.pumpWidget(
          _app(AppleVpnView(controller: controller, capabilities: _supported)),
        );
        expect(find.text('No bypass networks added.'), findsOneWidget);
        await _tap(tester, find.text('Add network'));
        final field = find.byType(TextField);
        await tester.enterText(field, '10.250.0.0/16');
        await tester.pumpAndSettle();
        expect(controller.strings('apple', 'excludedCidrs'), ['10.250.0.0/16']);

        await _tap(tester, _toggle('captureAllTraffic'));
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Add network'), findsNothing);
        expect(
          find.text(
            'Excluded networks are not applied while Capture all traffic is on. Your saved list is kept.',
          ),
          findsOneWidget,
        );
        expect(controller.strings('apple', 'excludedCidrs'), ['10.250.0.0/16']);
        await _tap(tester, _toggle('captureAllTraffic'));
        expect(
          tester.widget<TextField>(field).controller!.text,
          '10.250.0.0/16',
        );

        await tester.enterText(field, 'invalid-cidr');
        await tester.pumpAndSettle();
        expect(
          await controller.save(
            tester.element(find.byType(AppleVpnView)),
            pop: false,
          ),
          false,
        );
        expect(controller.error, contains('invalid-cidr'));
        expect(controller.error, contains('CIDR'));
        expect(controller.busy, false);

        await _tap(tester, find.byTooltip('Remove bypass network 1'));
        expect(controller.strings('apple', 'excludedCidrs'), isEmpty);
        expect(controller.error, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('iOS VPN icon toggle preserves its value while inactive', (
    tester,
  ) async {
    _phone(tester);
    final controller = _controller();
    await tester.pumpWidget(
      _app(AppleVpnView(controller: controller, capabilities: _supported)),
    );
    final icon = _toggle('hideVpnIcon');
    expect(tester.widget<ShadSwitch>(icon).value, isFalse);
    expect(tester.widget<ShadSwitch>(icon).enabled, isTrue);
    await _tap(tester, icon);
    expect(controller.group('apple')['hideVpnIcon'], isTrue);
    expect(controller.strings('apple', 'excludedCidrs'), isEmpty);
    await _tap(tester, _toggle('captureAllTraffic'));
    expect(tester.widget<ShadSwitch>(icon).value, isTrue);
    expect(tester.widget<ShadSwitch>(icon).enabled, isFalse);
    expect(
      find.text(
        'Unavailable while Capture all traffic is on. Your preference is kept.',
      ),
      findsOneWidget,
    );
    await _tap(tester, _toggle('captureAllTraffic'));
    expect(tester.widget<ShadSwitch>(icon).value, isTrue);
    expect(tester.widget<ShadSwitch>(icon).enabled, isTrue);
    controller.restoreDefaults();
    await tester.pumpAndSettle();
    expect(tester.widget<ShadSwitch>(icon).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop network actions stay content-sized', (tester) async {
    _desktop(tester);
    final controller = _controller(
      platform: ConnectionPlatform.macos,
      apple: {'onDemandEnabled': true},
    );
    await tester.pumpWidget(
      _app(
        AppleVpnView(
          controller: controller,
          capabilities: _supported,
          onEditWifi: () {},
        ),
      ),
    );

    final selector = find.byKey(const ValueKey('apple-network-action-choice'));
    expect(_toggle('hideVpnIcon'), findsNothing);
    expect(
      find.textContaining('Incorrect settings may block network access.'),
      findsOneWidget,
    );
    expect(
      find.descendant(of: selector, matching: find.byType(Expanded)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Apple master toggles preserve subordinate drafts and edit navigation',
    (tester) async {
      _phone(tester);
      final controller = _controller(
        apple: {
          'connectWifiSsids': ['Home Wi-Fi'],
          'disconnectWifiSsids': ['Office'],
          'onDemandEnabled': true,
        },
      );
      var editCount = 0;
      await tester.pumpWidget(
        _app(
          AppleVpnView(
            controller: controller,
            capabilities: _supported,
            onEditWifi: () => editCount++,
          ),
        ),
      );
      expect(find.text('System VPN policy'), findsNothing);
      expect(find.byType(ShadSwitch), findsNWidgets(5));
      final warning = find.textContaining(
        'Incorrect settings may block network access.',
      );
      expect(warning, findsOneWidget);
      await _tap(tester, _toggle('captureAllTraffic'));
      expect(warning, findsOneWidget);
      expect(find.byType(ShadSwitch), findsNWidgets(9));
      expect(
        tester.widget<ShadSwitch>(_toggle('allowLocalNetwork')).value,
        isTrue,
      );
      await _tap(tester, _toggle('allowLocalNetwork'));
      await _tap(tester, _toggle('captureAllTraffic'));
      expect(_toggle('allowLocalNetwork'), findsNothing);
      await _tap(tester, _toggle('captureAllTraffic'));
      expect(
        tester.widget<ShadSwitch>(_toggle('allowLocalNetwork')).value,
        isFalse,
      );
      await _tap(tester, _toggle('alwaysOn'));
      expect(_toggle('onDemandEnabled'), findsNothing);
      expect(find.byType(AppleWifiPreview), findsNothing);
      expect(controller.group('apple')['onDemandEnabled'], isTrue);
      await _tap(tester, _toggle('alwaysOn'));
      expect(find.byType(AppleWifiPreview), findsOneWidget);
      await _tap(
        tester,
        find.byKey(const ValueKey('cellularAction-disconnect')),
      );
      expect(controller.group('apple')['cellularAction'], 'disconnect');
      expect(controller.group('apple')['ethernetAction'], 'connect');
      await _tap(tester, find.text('Edit Wi-Fi rules'));
      expect(editCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Apple capability failures and unavailable exclusions stay explicit',
    (tester) async {
      _phone(tester);
      final controller = _controller(apple: {'captureAllTraffic': true});
      var retries = 0;
      await tester.pumpWidget(
        _app(
          AppleVpnView(
            controller: controller,
            capabilities: null,
            onRetry: () => retries++,
          ),
        ),
      );
      expect(find.text('Temporarily unavailable'), findsOneWidget);
      await _tap(tester, find.text('Retry'));
      expect(retries, 1);
      expect(
        tester.widget<ShadSwitch>(_toggle('bypassCellularServices')).enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ShadSwitch>(_toggle('bypassApplePushNotifications'))
            .enabled,
        isFalse,
      );
      expect(
        tester.widget<ShadSwitch>(_toggle('allowDeviceCommunication')).enabled,
        isFalse,
      );
      expect(
        tester.widget<ShadSwitch>(_toggle('allowLocalNetwork')).enabled,
        isTrue,
      );
      await tester.pumpWidget(
        _app(
          AppleVpnView(
            controller: controller,
            capabilities: null,
            capabilityLoading: true,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Wi-Fi editor preserves exact SSIDs, exposes conflicts and edits individual fields',
    (tester) async {
      _phone(tester);
      final controller = _controller(
        apple: {
          'connectWifiSsids': [' Home Wi-Fi '],
          'disconnectWifiSsids': ['Office'],
        },
      );
      await tester.pumpWidget(_app(AppleWifiView(controller: controller)));
      expect(find.byType(TextField), findsNWidgets(2));
      await tester.enterText(find.byType(TextField).first, 'Office');
      await tester.pumpAndSettle();
      expect(controller.wifiConflict, isTrue);
      expect(
        find.text(
          'Choose one action for each Wi-Fi name. The same name cannot appear in both groups.',
        ),
        findsOneWidget,
      );
      expect(find.byType(AppleWifiPreview), findsNothing);
      await tester.enterText(find.byType(TextField).first, ' Home Wi-Fi ');
      await tester.pumpAndSettle();
      expect(controller.wifiConflict, isFalse);
      expect(find.byType(AppleWifiPreview), findsOneWidget);
      expect(controller.strings('apple', 'connectWifiSsids'), [' Home Wi-Fi ']);
      await _tap(tester, find.text('Add Wi-Fi').first);
      expect(find.byType(TextField), findsNWidgets(3));
      await tester.enterText(find.byType(TextField).at(1), 'New Wi-Fi');
      await tester.pumpAndSettle();
      expect(controller.strings('apple', 'connectWifiSsids'), [
        ' Home Wi-Fi ',
        'New Wi-Fi',
      ]);
      await _tap(tester, find.byTooltip('Remove Wi-Fi 2'));
      expect(controller.strings('apple', 'connectWifiSsids'), [' Home Wi-Fi ']);
      expect(controller.strings('apple', 'disconnectWifiSsids'), ['Office']);
      expect(
        controller.draft!.original.policy.toJson()['apple']['connectWifiSsids'],
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in const [
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ru'),
    Locale('fa'),
  ]) {
    testWidgets('VPN icon setting fits an iOS phone ($locale)', (tester) async {
      _phone(tester);
      final controller = _controller();
      await tester.pumpWidget(
        _app(
          AppleVpnView(controller: controller, capabilities: _supported),
          locale: locale,
        ),
      );
      final l = AppLocalizations.of(tester.element(find.byType(AppleVpnView)))!;
      expect(find.text(l.appleHideVpnIcon), findsOneWidget);
      expect(find.text(l.appleHideVpnIconHint), findsOneWidget);
      await _tap(tester, _toggle('hideVpnIcon'));
      expect(controller.group('apple')['hideVpnIcon'], isTrue);
      await _tap(tester, _toggle('captureAllTraffic'));
      expect(find.text(l.appleHideVpnIconInactive), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Apple and Wi-Fi views fit a phone with long names ($locale)', (
      tester,
    ) async {
      _phone(tester);
      final controller = _controller(
        platform: ConnectionPlatform.macos,
        apple: {
          'captureAllTraffic': true,
          'onDemandEnabled': true,
          'connectWifiSsids': [
            'Home Wi-Fi',
            'A very long exact network name that must remain unchanged',
          ],
          'disconnectWifiSsids': ['Office'],
        },
      );
      final brightness = locale.languageCode == 'fa'
          ? Brightness.dark
          : Brightness.light;
      await tester.pumpWidget(
        _app(
          AppleVpnView(
            controller: controller,
            capabilities: _supported,
            onEditWifi: () {},
          ),
          locale: locale,
          brightness: brightness,
        ),
      );
      final l = AppLocalizations.of(tester.element(find.byType(AppleVpnView)))!;
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('captureAllTraffic')),
          matching: find.text(l.prototypeCaptureAllTrafficHint),
        ),
        findsOneWidget,
      );
      expect(find.text(l.prototypeEthernet), findsOneWidget);
      expect(find.text(l.prototypeCellularNetwork), findsNothing);
      await _tap(
        tester,
        find.byKey(const ValueKey('ethernetAction-disconnect')),
      );
      expect(controller.group('apple')['ethernetAction'], 'disconnect');
      expect(controller.group('apple')['cellularAction'], 'connect');
      expect(tester.takeException(), isNull);
      await _tap(tester, _toggle('captureAllTraffic'));
      await _tap(tester, find.text(l.prototypeAddNetwork));
      await tester.enterText(find.byType(TextField), '2001:db8:1234:5678::/64');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).textDirection,
        TextDirection.ltr,
      );
      expect(find.text(l.appleExcludedNetworksInputHint), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        _app(
          AppleWifiView(controller: controller),
          locale: locale,
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text(l.prototypeWifiExactMatchNotice), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).style!.fontSize,
        12,
      );
      expect(
        Directionality.of(tester.element(find.byType(AppleWifiView))),
        locale.languageCode == 'fa' ? TextDirection.rtl : TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
