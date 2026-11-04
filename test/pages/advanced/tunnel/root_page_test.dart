import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/details.dart';
import 'package:onexray/pages/advanced/tunnel/page.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _app(Widget child, double width) => MaterialApp(
  theme: AppTheme.material(Brightness.light, mobile: width <= 720),
  locale: const Locale('en'),
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (_, child) => ShadTheme(
    data: AppTheme.shad(Brightness.light, mobile: width <= 720),
    child: ShadToaster(child: child!),
  ),
  home: child,
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

_UiService _service({ConnectionPlatform platform = ConnectionPlatform.ios}) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final coordinator = ConnectionCoordinator(
    database: db,
    statusEvents: const Stream.empty(),
  );
  addTearDown(() async {
    coordinator.dispose();
    await db.close();
  });
  return _UiService(coordinator, platform);
}

void main() {
  for (final size in const [
    Size(390, 844),
    Size(1032, 1376),
    Size(1160, 720),
  ]) {
    testWidgets(
      'tunnel summaries open isolated drafts and refresh only after save at $size',
      (tester) async {
        _viewport(tester, size);
        final service = _service();
        final root = PolicyEditorController(
          draft: PolicyEditorDraft(service.configuration),
          service: service,
        );
        addTearDown(root.close);
        PolicyEditorController? child;
        final opened = <TunnelDestination>[];
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => Scaffold(
                appBar: PageAppBar(
                  title: Text(AppLocalizations.of(context)!.prototypeVpnTunnel),
                ),
                body: VpnTunnelPane(
                  createController: () => root,
                  openTunnel: (context, destination, draft) {
                    opened.add(destination);
                    expect(
                      identical(draft.policy, root.draft!.policy),
                      isFalse,
                    );
                    child = PolicyEditorController(
                      draft: draft,
                      service: service,
                    );
                    return Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => switch (destination) {
                          TunnelDestination.dns => TunnelDnsPage(
                            draft: draft,
                            createController: () => child!,
                          ),
                          TunnelDestination.network => TunnelNetworkPage(
                            draft: draft,
                            createController: () => child!,
                          ),
                          _ => throw StateError(
                            'Unexpected destination $destination',
                          ),
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            size.width,
          ),
        );
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(VpnTunnelPane)),
        )!;
        expect(find.byType(SettingSection), findsNWidgets(2));
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(PolicyActions), findsNothing);
        expect(find.text('iOS'), findsOneWidget);
        for (final key in [
          'tunnel-system-capture',
          'tunnel-connection-parameters',
        ]) {
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(rect.left, greaterThanOrEqualTo(size.width <= 720 ? 16 : 28));
          expect(
            rect.right,
            lessThanOrEqualTo(size.width - (size.width <= 720 ? 16 : 28)),
          );
        }
        final dns = find.byKey(const ValueKey('tunnel-open-dns'));
        await _tap(tester, dns);
        expect(find.byType(TunnelDnsPage), findsOneWidget);
        final ipv4 = find.descendant(
          of: find.byKey(const ValueKey('tunnel-dns-ipv4')),
          matching: find.byType(TextField),
        );
        await tester.enterText(ipv4, '2.2.2.2');
        await tester.pumpAndSettle();
        expect(child!.value['dnsIpv4Address'], '2.2.2.2');
        expect(root.value['dnsIpv4Address'], '1.1.1.1');
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, l.prototypeCancel),
        );
        expect(root.value['dnsIpv4Address'], '1.1.1.1');
        expect(service.saves, 0);
        expect(service.loads, 0);
        await _tap(tester, dns);
        await tester.enterText(ipv4, '2.2.2.2');
        await tester.pumpAndSettle();
        await _tap(tester, find.widgetWithText(FilledButton, l.prototypeSave));
        expect(find.byType(TunnelDnsPage), findsNothing);
        expect(root.value['dnsIpv4Address'], '2.2.2.2');
        expect(service.saves, 1);
        expect(service.loads, 1);
        expect(find.textContaining('2.2.2.2'), findsOneWidget);
        expect(find.byType(PolicyActions), findsNothing);

        final network = find.byKey(const ValueKey('tunnel-open-network'));
        await _tap(tester, network);
        final toggle = find.descendant(
          of: find.byKey(const ValueKey('tunnel-ipv6-enabled')),
          matching: find.byType(ShadSwitch),
        );
        await _tap(tester, toggle);
        expect(child!.value['ipv6Enabled'], isFalse);
        expect(root.value['ipv6Enabled'], isTrue);
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, l.prototypeCancel),
        );
        expect(root.value['ipv6Enabled'], isTrue);
        await _tap(tester, network);
        await _tap(tester, toggle);
        await _tap(tester, find.widgetWithText(FilledButton, l.prototypeSave));
        expect(root.value['ipv6Enabled'], isFalse);
        expect(service.saves, 2);
        expect(service.loads, 2);
        expect(find.text(l.tunnelIpv6Disabled), findsNWidgets(2));
        expect(opened, [
          TunnelDestination.dns,
          TunnelDestination.dns,
          TunnelDestination.network,
          TunnelDestination.network,
        ]);
        expect(find.byType(PolicyActions), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'restore keeps its complete scope as a draft until Save and Cancel reloads',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final service = _service();
      final policy = service.configuration.policy.toJson();
      policy['apple']['alwaysOn'] = true;
      service.configuration = ConnectionConfiguration(
        policy: PlatformPolicy.fromJson(policy),
      );
      final root = PolicyEditorController(
        draft: PolicyEditorDraft(service.configuration),
        service: service,
      );
      addTearDown(root.close);
      await tester.pumpWidget(
        _app(VpnTunnelPane(createController: () => root), 390),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(VpnTunnelPane)),
      )!;
      final restore = find.byKey(const ValueKey('tunnel-restore-defaults'));
      expect(find.byType(PolicyActions), findsNothing);
      await _tap(tester, restore);
      expect(root.group('apple')['alwaysOn'], isFalse);
      expect(root.value['dnsIpv4Address'], '8.8.8.8');
      expect(
        service.configuration.policy.toJson()['apple']['alwaysOn'],
        isTrue,
      );
      expect(service.configuration.policy.dnsIpv4Address, '1.1.1.1');
      expect(service.saves, 0);
      expect(find.byType(PolicyActions), findsOneWidget);
      expect(find.text(l.settingsDefaultsRestored), findsOneWidget);
      // The transient bottom toast occupies the footer until it times out.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(l.settingsDefaultsRestored), findsNothing);
      await _tap(
        tester,
        find.widgetWithText(OutlinedButton, l.prototypeCancel),
      );
      expect(root.group('apple')['alwaysOn'], isTrue);
      expect(root.value['dnsIpv4Address'], '1.1.1.1');
      expect(find.byType(PolicyActions), findsNothing);
      await _tap(tester, restore);
      expect(find.text(l.settingsDefaultsRestored), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(l.settingsDefaultsRestored), findsNothing);
      await _tap(tester, find.widgetWithText(FilledButton, l.prototypeSave));
      expect(service.saves, 1);
      expect(service.configuration.policy.dnsIpv4Address, '8.8.8.8');
      expect(
        service.configuration.policy.toJson()['apple']['alwaysOn'],
        isFalse,
      );
      expect(find.byType(PolicyActions), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Windows network conflict keeps the existing validation and IPv6 DNS visible',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final service = _service(platform: ConnectionPlatform.windows);
      final policy = service.configuration.policy.toJson();
      policy['windows']['excludedCidrs'] = ['fd00::/64'];
      final draft = PolicyEditorDraft(
        ConnectionConfiguration(policy: PlatformPolicy.fromJson(policy)),
      );
      final controller = PolicyEditorController(draft: draft, service: service);
      addTearDown(controller.close);
      await tester.pumpWidget(
        _app(
          TunnelNetworkPage(draft: draft, createController: () => controller),
          390,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byType(ShadSwitch));
      final l = AppLocalizations.of(
        tester.element(find.byType(TunnelNetworkPage)),
      )!;
      expect(controller.ipv6Conflict, isTrue);
      expect(find.text(l.prototypeIpv6BypassConflict), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, l.prototypeSave),
            )
            .onPressed,
        isNull,
      );
      final dns = PolicyEditorController(
        draft: controller.draft!.copy(),
        service: service,
      );
      addTearDown(dns.close);
      await tester.pumpWidget(
        _app(
          TunnelDnsPage(draft: dns.draft!, createController: () => dns),
          390,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tunnel-dns-ipv6')), findsOneWidget);
      expect(find.byKey(const ValueKey('tunnel-dns-over-tls')), findsNothing);
      expect(
        find.byKey(const ValueKey('tunnel-dns-server-name')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}

class _UiService extends PolicyEditorService {
  _UiService(ConnectionCoordinator coordinator, ConnectionPlatform platform)
    : super(
        coordinator: coordinator,
        platform: platform,
        windowsMode: WindowsMode.msix,
      ) {
    final policy = PlatformPolicy.defaults().toJson();
    policy['dnsIpv4Address'] = '1.1.1.1';
    policy['xrayOutboundInterfaceName'] = 'Ethernet';
    configuration = ConnectionConfiguration(
      policy: PlatformPolicy.fromJson(policy),
    );
  }
  late ConnectionConfiguration configuration;
  int saves = 0;
  int loads = 0;
  @override
  Future<PolicyEditorDraft> load() async {
    loads++;
    return PolicyEditorDraft(configuration);
  }

  @override
  Future<bool> save({
    required PolicyEditorDraft draft,
    required Future<bool> Function(bool disconnect) confirm,
  }) async {
    final prepared = prepare(draft);
    configuration = ConnectionConfiguration(
      connection: draft.original.connection,
      policy: prepared.policy,
    );
    saves++;
    return true;
  }
}
