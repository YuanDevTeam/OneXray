import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/interface/page.dart';
import 'package:onexray/pages/advanced/tunnel/windows/page.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

PolicyEditorService _service(ConnectionPlatform platform) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final coordinator = ConnectionCoordinator(database: db);
  addTearDown(() async {
    coordinator.dispose();
    await db.close();
  });
  return PolicyEditorService(
    coordinator: coordinator,
    platform: platform,
    windowsMode: WindowsMode.msix,
  );
}

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: AppTheme.material(Brightness.light, mobile: true),
  locale: locale,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => ShadTheme(
    data: AppTheme.shad(Brightness.light, mobile: true),
    child: child!,
  ),
  home: child,
);

void _viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(427, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets(
    'Windows CIDRs use inline drafts and the existing validation gate',
    (tester) async {
      _viewport(tester);
      final original = ConnectionConfiguration();
      final controller = PolicyEditorController(
        draft: PolicyEditorDraft(original),
        service: _service(ConnectionPlatform.windows),
      );
      addTearDown(controller.close);
      var openedInterfaces = 0;
      await tester.pumpWidget(
        _app(
          WindowsVpnView(
            controller: controller,
            openInterface: (_, _) async {
              openedInterfaces++;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(WindowsVpnView)),
      )!;
      FilledButton save() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l.prototypeSave),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SettingSection &&
              widget.title == l.prototypeSystemVpnPolicy,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SettingSection &&
              widget.title == l.prototypeBypassNetworks,
        ),
        findsOneWidget,
      );
      expect(find.text('0 / 64'), findsOneWidget);
      expect(find.text(l.prototypeNoBypassNetworks), findsOneWidget);
      expect(save().onPressed, isNull);
      await tester.ensureVisible(
        find.text(l.prototypeChooseInterfaceBeforeSaving),
      );
      await tester.tap(find.text(l.prototypeChooseInterfaceBeforeSaving));
      await tester.pumpAndSettle();
      expect(openedInterfaces, 1);
      await tester.ensureVisible(find.text(l.prototypeAddNetwork));
      await tester.tap(find.text(l.prototypeAddNetwork));
      await tester.pumpAndSettle();
      expect(find.text(l.prototypeNoBypassNetworks), findsNothing);
      expect(find.text('0 / 64'), findsOneWidget);
      final cidrRow = tester.getRect(
        find.byKey(const ValueKey('windows-cidr-row:0')),
      );
      expect(cidrRow.height, greaterThanOrEqualTo(50));
      expect(
        cidrRow.contains(tester.getCenter(find.byType(TextField))),
        isTrue,
      );
      expect(
        cidrRow.contains(
          tester.getCenter(
            find.byTooltip(l.prototypeRemoveBypassNetworkNumber(1)),
          ),
        ),
        isTrue,
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textDirection, TextDirection.ltr);
      expect(field.decoration!.labelText, isNull);
      expect(field.decoration!.hintText, '192.168.1.0/24');
      await tester.enterText(find.byType(TextField), ' 192.168.1.0/24 ');
      await tester.pumpAndSettle();
      expect(find.text('1 / 64'), findsOneWidget);
      expect(controller.strings('windows', 'excludedCidrs'), [
        ' 192.168.1.0/24 ',
      ]);
      controller.update('xrayOutboundInterfaceName', 'Ethernet');
      await tester.pumpAndSettle();
      expect(save().onPressed, isNotNull);
      expect(
        controller.service
            .prepare(controller.draft!)
            .policy
            .toWindowsPolicy()
            .toJson()['excludedCidrs'],
        ['192.168.1.0/24'],
      );
      await tester.enterText(find.byType(TextField), 'fd00::/64');
      controller.update('ipv6Enabled', false);
      await tester.pumpAndSettle();
      expect(save().onPressed, isNull);
      expect(controller.validationHint(l), l.prototypeIpv6BypassConflict);
      await tester.tap(find.byTooltip(l.prototypeRemoveBypassNetworkNumber(1)));
      await tester.pumpAndSettle();
      expect(find.text('0 / 64'), findsOneWidget);
      expect(controller.strings('windows', 'excludedCidrs'), isEmpty);
      expect(original.policy.toJson()['windows']['excludedCidrs'], isEmpty);
      expect(original.policy.xrayOutboundInterfaceName, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Windows counts nonblank CIDRs while limiting fields to 64 in RTL',
    (tester) async {
      _viewport(tester);
      final controller = PolicyEditorController(
        draft: PolicyEditorDraft(ConnectionConfiguration()),
        service: _service(ConnectionPlatform.windows),
      );
      addTearDown(controller.close);
      controller.update('excludedCidrs', [
        ...List.generate(63, (index) => '192.168.$index.0/24'),
        ' ',
      ], section: 'windows');
      await tester.pumpWidget(
        _app(
          WindowsVpnView(
            controller: controller,
            openInterface: (_, _) async => null,
          ),
          locale: const Locale('fa'),
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(WindowsVpnView)),
      )!;
      expect(find.text('63 / 64'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('63 / 64')).textDirection,
        TextDirection.ltr,
      );
      expect(find.byType(TextField), findsNWidgets(64));
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, l.prototypeAddNetwork),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).textDirection,
        TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [
    ConnectionPlatform.windows,
    ConnectionPlatform.linux,
  ]) {
    testWidgets(
      '$platform interface selection preserves names, addresses and retry',
      (tester) async {
        _viewport(tester);
        final original = ConnectionConfiguration();
        var fail = false;
        final controller = OutboundInterfaceController(
          draft: PolicyEditorDraft(original),
          service: _service(platform),
          loadInterfaces: () async {
            if (fail) throw StateError('interface read failed');
            return const [
              OutboundInterfaceOption('Wi-Fi (en0)', [
                '192.0.2.10',
                '2001:db8::10',
              ], true),
              OutboundInterfaceOption('Ethernet', ['192.0.2.20'], false),
            ];
          },
        );
        await controller.readInterfaces();
        addTearDown(controller.close);
        var retries = 0;
        await tester.pumpWidget(
          _app(
            OutboundInterfaceView(
              controller: controller,
              onRetry: () => retries++,
            ),
            locale: const Locale('fa'),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(OutboundInterfaceView));
        final l = AppLocalizations.of(context)!;
        FilledButton save() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l.prototypeSave),
        );
        expect(controller.value['xrayOutboundInterfaceName'], isEmpty);
        expect(save().onPressed, isNull);
        expect(find.text('Wi-Fi (en0)'), findsOneWidget);
        expect(find.text('192.0.2.10\n2001:db8::10'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.text('192.0.2.10\n2001:db8::10'))
              .textDirection,
          TextDirection.ltr,
        );
        expect(
          tester
              .widget<Text>(find.text(l.prototypeCurrentInternetInterface))
              .style!
              .color,
          ColorManager.palette(context).primary,
        );
        expect(
          tester.getSize(find.byType(ShadRadio<String>).first),
          const Size(17, 17),
        );
        expect(find.text(l.prototypeManagedInterfaceNotice), findsOneWidget);
        await tester.tap(find.text('Ethernet'));
        await tester.pumpAndSettle();
        expect(controller.value['xrayOutboundInterfaceName'], 'Ethernet');
        expect(save().onPressed, isNotNull);
        expect(original.policy.xrayOutboundInterfaceName, isEmpty);
        fail = true;
        await controller.readInterfaces();
        await tester.pumpAndSettle();
        expect(save().onPressed, isNull);
        expect(find.text('interface read failed'), findsOneWidget);
        await tester.tap(find.text(l.prototypeRetry));
        await tester.pumpAndSettle();
        expect(retries, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
