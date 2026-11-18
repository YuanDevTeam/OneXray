import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/pigeon/messages.g.dart'
    show AppleVpnCapabilities, BridgeHostApi, VpnStatus;
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/details.dart';
import 'package:onexray/pages/advanced/tunnel/page.dart';
import 'package:onexray/pages/advanced/tunnel/widgets.dart';
import 'package:onexray/pages/main/adaptive_shell.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/shared/widgets/app_switch.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/advanced/tunnel/apple/removal.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
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
  testWidgets('APNs preset saves offline and keeps manual settings', (
    tester,
  ) async {
    _viewport(tester, const Size(390, 844));
    _stubApnsCapability();
    final service = _service();
    final base = service.configuration.policy.toJson();
    base['ipv6Enabled'] = false;
    service.configuration = ConnectionConfiguration(
      policy: PlatformPolicy.fromJson(base),
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
    final toggle = find.descendant(
      of: find.byKey(const ValueKey('tunnel-apns-preset')),
      matching: find.byType(AppSwitch),
    );

    await _tap(tester, toggle);

    expect(service.saves, 1);
    expect(service.configuration.policy.appleApnsProxyPreset, isTrue);
    expect(service.configuration.policy.ipv6Enabled, isFalse);
    expect(
      service.configuration.policy.toJson()['apple']['captureAllTraffic'],
      isFalse,
    );
    expect(root.effectiveIpv6, isTrue);
    expect(
      find.text('Applies the next time you start VPN from OneXray.'),
      findsOneWidget,
    );
    expect(find.byType(PolicyActions), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await _tap(tester, toggle);

    expect(service.saves, 2);
    expect(service.configuration.policy.toJson(), base);
    expect(root.effectiveIpv6, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('cancelling an APNs preset reconnect restores its switch', (
    tester,
  ) async {
    _viewport(tester, const Size(390, 844));
    _stubApnsCapability();
    final service = _service()..confirmApnsPresetSave = true;
    service.coordinator.state.value = const ConnectionView(
      phase: ConnectionPhase.connected,
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
    final toggle = find.descendant(
      of: find.byKey(const ValueKey('tunnel-apns-preset')),
      matching: find.byType(AppSwitch),
    );

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Enable and reconnect'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(ShadDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();

    expect(root.apnsPresetEnabled, isFalse);
    expect(service.configuration.policy.appleApnsProxyPreset, isFalse);
    expect(service.saves, 0);
    expect(find.byType(PolicyActions), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final scope in ['included', 'excluded']) {
    testWidgets(
      'Android $scope apps save after an offline configuration switch with the tunnel root mounted',
      (tester) async {
        _viewport(tester, const Size(390, 844));
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final coordinator = ConnectionCoordinator(
          database: db,
          statusEvents: const Stream.empty(),
          readRuntime: () async => null,
          inspect: (_, {observedStatus}) async =>
              const HostConnection(VpnStatus.disconnected),
          prepare: (_, _) async => fail('Must not prepare while disconnected'),
          start: (_) async => fail('Must not start while disconnected'),
          stop: () async => fail('Must not stop while disconnected'),
        );
        addTearDown(
          () => tester.runAsync(() async {
            coordinator.dispose();
            await db.close();
          }),
        );
        final service = PolicyEditorService(
          coordinator: coordinator,
          platform: ConnectionPlatform.android,
        );
        late PolicyEditorController root;
        await tester.runAsync(() async {
          await coordinator.initialize(
            observe: false,
            registerReferences: false,
          );
          root = PolicyEditorController(
            draft: await service.load(),
            service: service,
          );
        });
        addTearDown(root.close);
        final opened = Completer<PolicyEditorDraft>();
        await tester.pumpWidget(
          _app(
            VpnTunnelPane(
              createController: () => root,
              openTunnel: (_, destination, draft) async {
                expect(destination, TunnelDestination.android);
                opened.complete(draft);
                return false;
              },
            ),
            390,
          ),
        );
        await tester.pumpAndSettle();

        final next = ConnectionConfiguration(
          connection: ConnectionSettings(trafficMode: TrafficMode.allVpn),
          policy: root.draft!.original.policy,
        );
        await tester.runAsync(() => coordinator.apply(next));
        await tester.pumpAndSettle();
        final android = find.byKey(const ValueKey('tunnel-open-android'));
        await tester.ensureVisible(android);
        await tester.pumpAndSettle();
        await tester.runAsync(() => tester.tap(android));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final draft = await opened.future.timeout(const Duration(seconds: 5));
          draft.policy['android']['appScope'] = scope;
          draft.policy['android']['${scope}AppPackageNames'] = [
            'com.example.browser',
          ];
          expect(
            await service.save(
              draft: draft,
              confirm: (_) async => fail('Must not confirm while disconnected'),
            ),
            isTrue,
          );
          final saved = await coordinator.configuration;
          expect(saved.connection.toJson(), next.connection.toJson());
          expect(saved.policy.toJson()['android'], {
            'appScope': scope,
            'includedAppPackageNames': scope == 'included'
                ? ['com.example.browser']
                : [],
            'excludedAppPackageNames': scope == 'excluded'
                ? ['com.example.browser']
                : [],
          });
          expect(coordinator.state.value.phase, ConnectionPhase.disconnected);
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'desktop proxy settings preserve the TUN draft and disable unsupported automatic settings',
    (tester) async {
      _viewport(tester, const Size(1160, 1000));
      final service = _service(platform: ConnectionPlatform.macos);
      service.configuration = ConnectionConfiguration(
        policy: PlatformPolicy.fromJson({
          ...service.configuration.policy.toJson(),
          'captureMode': 'proxy',
          'proxyPort': 18081,
        }),
      );
      final controller = PolicyEditorController(
        draft: PolicyEditorDraft(service.configuration),
        service: service,
        appleVpnRemoval: AppleVpnRemovalService(
          coordinator: service.coordinator,
          platform: ConnectionPlatform.macos,
          useSystemExtension: () async => false,
        ),
      );
      await tester.pumpWidget(
        _app(VpnTunnelPane(createController: () => controller), 1160),
      );
      await tester.pumpAndSettle();
      expect(controller.state.systemProxyLoading, false);
      expect(controller.state.appleVpnRemovalLoading, false);
      final l = AppLocalizations.of(
        tester.element(find.byType(VpnTunnelPane)),
      )!;
      expect(
        find.byKey(const ValueKey('desktop-proxy-settings')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tunnel-open-interface')), findsNothing);
      expect(find.byKey(const ValueKey('tunnel-open-dns')), findsNothing);
      expect(find.byKey(const ValueKey('tunnel-open-apple')), findsNothing);
      expect(find.text(l.prototypeIpv4TunAddress), findsNothing);
      expect(find.text(l.desktopSystemProxyUnavailable), findsOneWidget);
      expect(controller.value['xrayOutboundInterfaceName'], 'Ethernet');
      final field = find.descendant(
        of: find.byKey(const ValueKey('desktop-proxy-port')),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '19091');
      expect(controller.value['proxyPort'], 19091);
      controller.restoreDefaults();
      await tester.pumpAndSettle();
      expect(controller.value['captureMode'], 'tun');
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in const [
    Size(390, 844),
    Size(1032, 1376),
    Size(1160, 720),
  ]) {
    testWidgets(
      'tunnel summaries open isolated drafts and reflect saved values at $size',
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
        expect(find.byType(SettingSection), findsNWidgets(3));
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(PolicyActions), findsNothing);
        expect(find.text('iOS'), findsOneWidget);
        for (final key in [
          'tunnel-system-capture',
          'tunnel-connection-parameters',
          'tunnel-apple-vpn-removal',
          'tunnel-presets',
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
        await _tap(tester, dns);
        await tester.enterText(ipv4, '2.2.2.2');
        await tester.pumpAndSettle();
        await _tap(tester, find.widgetWithText(FilledButton, l.prototypeSave));
        expect(find.byType(TunnelDnsPage), findsNothing);
        expect(root.value['dnsIpv4Address'], '2.2.2.2');
        expect(service.saves, 1);
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
    'a detail refresh does not navigate after leaving the tunnel branch',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final service = _service();
      final gate = Completer<void>();
      service.loadGate = gate.future;
      final root = PolicyEditorController(
        draft: PolicyEditorDraft(service.configuration),
        service: service,
      );
      addTearDown(root.close);
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      var opens = 0;
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, enabled, child) =>
                TickerMode(enabled: enabled, child: child!),
            child: VpnTunnelPane(
              createController: () => root,
              openTunnel: (_, destination, draft) async {
                opens++;
                return false;
              },
            ),
          ),
          390,
        ),
      );
      await tester.pumpAndSettle();
      final dns = find.byKey(const ValueKey('tunnel-open-dns'));
      await tester.tap(dns);
      await tester.pump();
      expect(root.busy, isTrue);
      final progress = find.byType(ButtonProgressIndicator);
      expect(find.descendant(of: dns, matching: progress), findsOneWidget);
      expect(progress, findsOneWidget);

      active.value = false;
      await tester.pumpAndSettle();
      expect(opens, 0);
      expect(root.busy, isFalse);

      service.loadGate = null;
      active.value = true;
      await tester.pumpAndSettle();
      await _tap(tester, dns);
      expect(opens, 1);

      // The first read can still fail after a fresh tap has succeeded.
      service.loadFailure = StateError('Obsolete read');
      gate.complete();
      await tester.pumpAndSettle();
      expect(root.error, isNull);
      expect(opens, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  for (final returnToTunnel in [false, true]) {
    testWidgets(
      returnToTunnel
          ? 'returning to the tunnel does not replay a pending detail tap'
          : 'switching tabs cancels a detail tap before the next frame',
      (tester) async {
        _viewport(tester, const Size(390, 844));
        final service = _service(platform: ConnectionPlatform.android);
        final read = Completer<void>();
        service.loadGate = read.future;
        final root = PolicyEditorController(
          draft: PolicyEditorDraft(service.configuration),
          service: service,
        );
        final events = AppEventBus();
        addTearDown(events.close);
        final router = GoRouter(
          initialLocation: '/tunnel',
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (_, _, shell) => AdaptiveMainShell(
                navigationShell: shell,
                hasActiveModal: (_) => false,
                initializeServices: (_) async {},
              ),
              branches: [
                for (final primary in AppPrimaryDestination.values)
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: primary.rootPath,
                        builder: (_, _) =>
                            primary == AppPrimaryDestination.tunnel
                            ? VpnTunnelPane(
                                createController: () => root,
                                openTunnel: (context, _, draft) =>
                                    context.pushScoped<bool>(
                                      AppPageDestination.tunnelDns,
                                      extra: draft,
                                    ),
                              )
                            : Center(child: Text(primary.name)),
                        routes: [
                          GoRoute(
                            path: AppPageDestination.tunnelDns.segment,
                            builder: (_, _) => const Text('DNS detail'),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          BlocProvider.value(
            value: events,
            child: MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.material(Brightness.light, mobile: true),
              localizationsDelegates: AppLocalePolicy.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (_, child) => ShadTheme(
                data: AppTheme.shad(Brightness.light, mobile: true),
                child: ShadToaster(child: child!),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final dns = find.byKey(const ValueKey('tunnel-open-dns'));
        await tester.tap(dns);
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('primary-navigation-servers')),
        );
        if (returnToTunnel) {
          await tester.pumpAndSettle();
          expect(find.text('servers'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('primary-navigation-tunnel')),
          );
          await tester.pumpAndSettle();
        }

        read.complete();
        await tester.pumpAndSettle();
        expect(find.text('DNS detail'), findsNothing);
        expect(returnToTunnel ? dns : find.text('servers'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('failed detail refresh keeps the root draft and can be retried', (
    tester,
  ) async {
    _viewport(tester, const Size(390, 844));
    final service = _service();
    const reason = 'Cannot read saved tunnel configuration';
    service.loadFailure = StateError(reason);
    final original = service.configuration;
    final root = PolicyEditorController(
      draft: PolicyEditorDraft(original),
      service: service,
    );
    addTearDown(root.close);
    PolicyEditorController? child;
    await tester.pumpWidget(
      _app(
        VpnTunnelPane(
          createController: () => root,
          openTunnel: (context, destination, draft) {
            expect(destination, TunnelDestination.dns);
            child = PolicyEditorController(draft: draft, service: service);
            return Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) =>
                    TunnelDnsPage(draft: draft, createController: () => child!),
              ),
            );
          },
        ),
        390,
      ),
    );
    await tester.pumpAndSettle();
    final dns = find.byKey(const ValueKey('tunnel-open-dns'));
    await _tap(tester, dns);

    expect(child, isNull);
    expect(find.byType(TunnelDnsPage), findsNothing);
    expect(root.draft!.original, same(original));
    expect(root.value, original.policy.toJson());
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data?.contains(reason) ?? false),
      ),
      findsOneWidget,
    );
    expect(find.byType(PolicyActions), findsNothing);
    expect(service.saves, 0);

    service.loadFailure = null;
    await _tap(tester, dns);
    expect(find.byType(TunnelDnsPage), findsOneWidget);
    expect(child!.value, original.policy.toJson());
    expect(root.error, isNull);
    expect(find.textContaining(reason, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'opening and cancelling details preserves unsaved root defaults',
    (tester) async {
      _viewport(tester, const Size(390, 844));
      final service = _service();
      final original = service.configuration;
      final root = PolicyEditorController(
        draft: PolicyEditorDraft(original),
        service: service,
      );
      addTearDown(root.close);
      late PolicyEditorController child;
      await tester.pumpWidget(
        _app(
          VpnTunnelPane(
            createController: () => root,
            openTunnel: (context, destination, draft) {
              expect(destination, TunnelDestination.dns);
              child = PolicyEditorController(draft: draft, service: service);
              return Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => TunnelDnsPage(
                    draft: draft,
                    createController: () => child,
                  ),
                ),
              );
            },
          ),
          390,
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(VpnTunnelPane)),
      )!;
      await _tap(tester, find.byKey(const ValueKey('tunnel-restore-defaults')));
      final pending = root.draft!.copy();
      expect(pending.original, same(original));
      expect(pending.policy, PlatformPolicy.defaults().toJson());
      expect(pending.policy['dnsIpv4Address'], '8.8.8.8');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await _tap(tester, find.byKey(const ValueKey('tunnel-open-dns')));
      expect(find.byType(TunnelDnsPage), findsOneWidget);
      expect(child.draft!.original, same(original));
      expect(child.value, pending.policy);
      final ipv4 = find.descendant(
        of: find.byKey(const ValueKey('tunnel-dns-ipv4')),
        matching: find.byType(TextField),
      );
      await tester.enterText(ipv4, '2.2.2.2');
      await _tap(
        tester,
        find.widgetWithText(OutlinedButton, l.prototypeCancel),
      );

      expect(find.byType(TunnelDnsPage), findsNothing);
      expect(root.draft!.original, same(original));
      expect(root.value, pending.policy);
      expect(service.configuration.encode(), original.encode());
      expect(service.configuration.policy.dnsIpv4Address, '1.1.1.1');
      expect(service.saves, 0);
      expect(find.byType(PolicyActions), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

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
  Object? loadFailure;
  Future<void>? loadGate;
  int saves = 0;
  bool confirmApnsPresetSave = false;
  @override
  Future<bool> apnsProxyPresetApplicable(
    ConnectionConfiguration configuration,
  ) async => true;
  @override
  Future<({bool supported, String? reason})> proxyCapability() async =>
      (supported: false, reason: null);
  @override
  Future<PolicyEditorDraft> load() async {
    await loadGate;
    final failure = loadFailure;
    if (failure != null) throw failure;
    return PolicyEditorDraft(configuration);
  }

  @override
  Future<bool> save({
    required PolicyEditorDraft draft,
    required Future<bool> Function(bool disconnect) confirm,
  }) async {
    if (confirmApnsPresetSave && !await confirm(false)) return false;
    final prepared = prepare(draft);
    configuration = ConnectionConfiguration(
      connection: draft.original.connection,
      policy: prepared.policy,
    );
    saves++;
    return true;
  }
}

void _stubApnsCapability() {
  const channel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.onexray.BridgeHostApi.appleVpnCapabilities',
    BridgeHostApi.pigeonChannelCodec,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockDecodedMessageHandler(
    channel,
    (_) async => [
      AppleVpnCapabilities(serviceExclusions: true, deviceCommunication: true),
    ],
  );
  addTearDown(() => messenger.setMockDecodedMessageHandler(channel, null));
}
