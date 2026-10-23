import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/page.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Finder _field(String name) => find.descendant(
  of: find.byKey(ValueKey('tunnel-dns-$name')),
  matching: find.byType(TextField),
);

Widget _app(Widget page) => MaterialApp(
  theme: AppTheme.material(Brightness.light, mobile: true),
  locale: const Locale('en'),
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (_, child) => ShadTheme(
    data: AppTheme.shad(Brightness.light, mobile: true),
    child: ShadToaster(child: child!),
  ),
  home: page,
);

Future<AppLocalizations> _mount(
  WidgetTester tester,
  PolicyEditorController controller,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 640);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    _app(VpnTunnelPane(createController: () => controller)),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(VpnTunnelPane)))!;
}

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late _DnsService service;
  late PolicyEditorController controller;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(
      database: db,
      statusEvents: const Stream.empty(),
    );
    service = _DnsService(coordinator);
    controller = PolicyEditorController(
      draft: PolicyEditorDraft(service.configuration),
      service: service,
    );
    addTearDown(() async {
      await controller.close();
      coordinator.dispose();
      await db.close();
    });
  });

  testWidgets('DNS errors appear after blur and survive unrelated edits', (
    tester,
  ) async {
    controller.update('dnsIpv4Address', 'invalid-v4');
    final l = await _mount(tester, controller);
    final ipv4 = _field('ipv4');
    final ipv6 = _field('ipv6');
    expect(tester.widget<TextField>(ipv4).decoration!.errorText, isNull);
    await tester.ensureVisible(ipv4);
    await tester.tap(ipv4);
    await tester.pumpAndSettle();
    await tester.ensureVisible(ipv6);
    await tester.tap(ipv6);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.widget<TextField>(ipv4).decoration!.errorText,
      l.tunnelDnsIpv4Invalid,
    );
    expect(controller.error, isNull);
    controller.update('recordDns', false, section: 'log');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(ipv4).decoration!.errorText,
      l.tunnelDnsIpv4Invalid,
    );
    expect(service.saves, 0);
    await tester.ensureVisible(ipv4);
    await tester.enterText(ipv4, '1.1.1.1');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(ipv4).decoration!.errorText, isNull);
    expect(controller.value['dnsIpv4Address'], '1.1.1.1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('submit reveals the first DNS error and keeps the raw cause', (
    tester,
  ) async {
    controller.update('dnsIpv4Address', 'invalid-v4');
    controller.update('dnsIpv6Address', 'invalid-v6');
    controller.update('dnsServerName', '');
    controller.update('dnsOverTls', true, section: 'apple');
    final l = await _mount(tester, controller);
    for (final (name, field, text, error) in [
      ('ipv4', TunnelDnsField.ipv4, '1.1.1.1', l.tunnelDnsIpv4Invalid),
      (
        'ipv6',
        TunnelDnsField.ipv6,
        '2606:4700:4700::1111',
        l.tunnelDnsIpv6Invalid,
      ),
      (
        'server-name',
        TunnelDnsField.serverName,
        'cloudflare-dns.com',
        l.tunnelDnsServerNameRequired,
      ),
    ]) {
      await tester.tap(find.text(l.prototypeSave));
      await tester.pumpAndSettle();
      expect(controller.state.dnsFailure?.field, field);
      expect(
        tester.widget<TextField>(_field(name)).decoration!.errorText,
        error,
      );
      expect(controller.dnsFocusNode(field).hasFocus, isTrue);
      expect(controller.error, contains('DNS'));
      expect(find.byType(SelectableText), findsOneWidget);
      expect(service.saves, 0);
      await tester.enterText(_field(name), text);
      await tester.pumpAndSettle();
    }
    expect(controller.state.dnsFailure, isNull);
    await tester.tap(find.text(l.prototypeSave));
    await tester.pumpAndSettle();
    expect(service.saves, 1);
    expect(service.configuration.policy.dnsIpv4Address, '1.1.1.1');
    expect(service.configuration.policy.dnsServerName, 'cloudflare-dns.com');
    expect(controller.error, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('DNS errors follow the effective IPv6 and DoT switches', (
    tester,
  ) async {
    controller.update('dnsIpv6Address', 'invalid-v6');
    controller.update('dnsServerName', '');
    final l = await _mount(tester, controller);
    await tester.tap(find.text(l.prototypeSave));
    await tester.pumpAndSettle();
    expect(controller.state.dnsFailure?.field, TunnelDnsField.ipv6);
    controller.update('ipv6Enabled', false);
    await tester.pumpAndSettle();
    expect(controller.state.dnsFailure, isNull);
    expect(controller.value['dnsIpv6Address'], 'invalid-v6');
    controller.update('ipv6Enabled', true);
    await tester.pumpAndSettle();
    expect(controller.state.dnsFailure?.field, TunnelDnsField.ipv6);
    controller.update('dnsIpv6Address', '2606:4700:4700::1111');
    controller.update('dnsOverTls', true, section: 'apple');
    await tester.pumpAndSettle();
    expect(controller.state.dnsFailure?.field, TunnelDnsField.serverName);
    controller.update('recordDns', false, section: 'log');
    await tester.pumpAndSettle();
    expect(controller.state.dnsFailure?.field, TunnelDnsField.serverName);
    controller.update('dnsOverTls', false, section: 'apple');
    await tester.pumpAndSettle();
    expect(controller.state.dnsFailure, isNull);
    expect(controller.value['dnsServerName'], isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('storage failures stay page errors and preserve the DNS draft', (
    tester,
  ) async {
    controller.update('dnsIpv4Address', '1.1.1.1');
    service.failure = StateError('policy-storage-unavailable');
    final l = await _mount(tester, controller);
    await tester.tap(find.text(l.prototypeSave));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(controller.error, contains('policy-storage-unavailable'));
    expect(find.textContaining('policy-storage-unavailable'), findsOneWidget);
    expect(controller.state.dnsFailure, isNull);
    expect(
      tester.widget<TextField>(_field('ipv4')).decoration!.errorText,
      isNull,
    );
    expect(controller.value['dnsIpv4Address'], '1.1.1.1');
    expect(service.saves, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a subpage without DNS inputs retains the original DNS failure', (
    tester,
  ) async {
    controller.update('dnsIpv4Address', 'invalid-v4');
    await tester.pumpWidget(
      _app(
        BlocBuilder<PolicyEditorController, PolicyEditorPageState>(
          bloc: controller,
          builder: (context, state) => PolicyDetailScaffold(
            title: 'Platform policy',
            controller: controller,
            body: const Text('Platform policy options'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.error, contains('invalid-v4'));
    expect(find.textContaining('invalid-v4'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    controller.update('dnsOverTls', true, section: 'apple');
    await tester.pumpAndSettle();
    expect(controller.error, contains('invalid-v4'));
    expect(find.textContaining('invalid-v4'), findsOneWidget);
    expect(controller.state.dnsFailure?.field, TunnelDnsField.ipv4);
    controller.update('dnsIpv4Address', '1.1.1.1');
    await tester.pumpAndSettle();
    expect(controller.error, isNull);
    expect(find.textContaining('invalid-v4'), findsNothing);
    expect(service.saves, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing the page cancels a pending DNS focus reveal', (
    tester,
  ) async {
    controller.update('dnsIpv4Address', 'invalid-v4');
    await _mount(tester, controller);
    await controller.save(
      tester.element(find.byType(VpnTunnelPane)),
      pop: false,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(service.saves, 0);
  });
}

class _DnsService extends PolicyEditorService {
  _DnsService(ConnectionCoordinator coordinator)
    : super(coordinator: coordinator, platform: ConnectionPlatform.ios);

  ConnectionConfiguration configuration = ConnectionConfiguration();
  Object? failure;
  int saves = 0;

  @override
  Future<PolicyEditorDraft> load() async => PolicyEditorDraft(configuration);

  @override
  Future<bool> save({
    required PolicyEditorDraft draft,
    required Future<bool> Function(bool disconnect) confirm,
  }) async {
    final prepared = prepare(draft);
    if (failure case final error?) throw error;
    configuration = ConnectionConfiguration(
      connection: draft.original.connection,
      policy: prepared.policy,
    );
    saves++;
    return true;
  }
}
