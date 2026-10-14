import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/controller.dart';
import 'package:onexray/pages/advanced/xray/lan_proxy/controller.dart';
import 'package:onexray/pages/advanced/xray/lan_proxy/page.dart';
import 'package:onexray/pages/advanced/xray/page.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: AppTheme.light,
  locale: locale,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (_, child) => ShadTheme(
    data: AppTheme.shad(Brightness.light),
    child: ShadToaster(child: child!),
  ),
  home: child,
);

void main() {
  late AppDatabase db;
  late ConnectionCoordinator coordinator;
  late _LanService service;

  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(database: db);
    service = _LanService(coordinator);
  });

  void registerCleanup(WidgetTester tester, Future<void> Function() closePage) {
    addTearDown(
      () => tester.runAsync(() async {
        await closePage();
        coordinator.dispose();
        await db.close();
      }),
    );
  }

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('sharing detail fits ${locale.toLanguageTag()}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = LanProxyController(
        draft: await service.load(),
        service: service,
      );
      registerCleanup(tester, controller.close);
      await tester.pumpWidget(
        _app(LanProxyPage(createController: () => controller), locale: locale),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(tester.element(find.byType(LanProxyPage)))!;
      expect(find.text(l.lanProxyProtocolHint), findsNothing);
      expect(find.text(l.lanProxyRawJsonNotice), findsNothing);
      await tester.tap(find.byTooltip('${l.pageHelp} · ${l.lanProxyTitle}'));
      await tester.pumpAndSettle();
      expect(find.text(l.lanProxyProtocolHint), findsOneWidget);
      expect(find.text(l.lanProxyRawJsonNotice), findsOneWidget);
      await tester.tap(find.byTooltip(l.prototypeCloseDialog));
      await tester.pumpAndSettle();
      expect(find.text(l.lanProxySecurityHint), findsOneWidget);
      expect(find.text(l.lanProxyNextStartNotice), findsOneWidget);
      expect(find.text(l.prototypeSave), findsOneWidget);
      expect(find.text(l.prototypeSaveAndReconnect), findsNothing);
      expect(find.text('0.0.0.0'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(controller.portController.text, '11024');
      expect(find.byType(PageActionBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(controller.close);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  for (final connected in [false, true]) {
    testWidgets(
      'switch saves for next App start without restarting: $connected',
      (tester) async {
        coordinator.state.value = ConnectionView(
          phase: connected
              ? ConnectionPhase.connected
              : ConnectionPhase.disconnected,
        );
        final controller = _RuntimeController(
          coordinator: coordinator,
          policyEditor: service,
        );
        registerCleanup(tester, controller.close);
        await tester.pumpWidget(
          _app(
            XrayRuntimePage(
              createController: () => controller,
              onGeodata: (_) {},
              onUpdates: (_) {},
              onSpeedTest: (_) {},
              onLog: (_, _) {},
              onConfig: (_, _) {},
              onLanProxy: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('lan-proxy-switch'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(service.configuration.policy.lanProxyEnabled, isTrue);
        expect(controller.lanProxyEnabled, isTrue);
        expect(service.saves, 1);
        expect(controller.state.lanProxySaving, isFalse);
        expect(controller.state.systemExtension, isTrue);
        expect(
          coordinator.state.value.phase,
          connected ? ConnectionPhase.connected : ConnectionPhase.disconnected,
        );
        expect(find.byType(PageActionBar), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.runAsync(controller.close);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('Raw saves the shared port without a restart affordance', (
    tester,
  ) async {
    service.configuration = ConnectionConfiguration(
      connection: ConnectionSettings(expert: true, rawId: 1),
      policy: PlatformPolicy.fromJson({
        'lanProxy': {'enabled': true},
      }),
    );
    coordinator.state.value = const ConnectionView(
      phase: ConnectionPhase.connected,
    );
    final controller = LanProxyController(
      draft: await service.load(),
      service: service,
    );
    registerCleanup(tester, controller.close);
    await tester.pumpWidget(
      _app(LanProxyPage(createController: () => controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save and reconnect'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('lan-proxy-port')),
      '11026',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.configuration.policy.lanProxyPort, 11026);
    expect(service.saves, 1);
    expect(tester.takeException(), isNull);
    await tester.runAsync(controller.close);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final connected in [false, true]) {
    testWidgets(
      'port saves for next App start without restarting: $connected',
      (tester) async {
        service.configuration = ConnectionConfiguration(
          policy: PlatformPolicy.fromJson({
            'lanProxy': {'enabled': true},
          }),
        );
        coordinator.state.value = ConnectionView(
          phase: connected
              ? ConnectionPhase.connected
              : ConnectionPhase.disconnected,
        );
        final controller = LanProxyController(
          draft: await service.load(),
          service: service,
        );
        registerCleanup(tester, controller.close);
        await tester.pumpWidget(
          _app(LanProxyPage(createController: () => controller)),
        );
        await tester.enterText(
          find.byKey(const ValueKey('lan-proxy-port')),
          '11026',
        );
        expect(find.text('Save and reconnect'), findsNothing);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(service.configuration.policy.lanProxyPort, 11026);
        expect(service.saves, 1);
        expect(
          coordinator.state.value.phase,
          connected ? ConnectionPhase.connected : ConnectionPhase.disconnected,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(controller.close);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}

class _LanService extends PolicyEditorService {
  _LanService(ConnectionCoordinator coordinator)
    : super(coordinator: coordinator, platform: ConnectionPlatform.android);

  ConnectionConfiguration configuration = ConnectionConfiguration();
  int saves = 0;

  @override
  Future<PolicyEditorDraft> load() async => PolicyEditorDraft(configuration);

  @override
  Future<bool> save({
    required PolicyEditorDraft draft,
    required Future<bool> Function(bool disconnect) confirm,
  }) async {
    configuration = ConnectionConfiguration(
      connection: draft.original.connection,
      policy: PlatformPolicy.fromJson(draft.policy),
    );
    saves++;
    return true;
  }
}

class _RuntimeController extends XrayRuntimeController {
  _RuntimeController({required super.coordinator, required super.policyEditor});

  @override
  Future<void> load({bool showLoading = true}) async {
    final configuration = (policyEditor as _LanService).configuration;
    emit(
      state.copyWith(
        base: configuration,
        log: configuration.policy.toJson()['log'] as Map<String, dynamic>,
        systemExtension: true,
        loading: false,
      ),
    );
  }

  @override
  Future<void> refreshLanProxy() async {
    emit(state.copyWith(base: (policyEditor as _LanService).configuration));
  }
}
