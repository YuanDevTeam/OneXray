import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/controller.dart';
import 'package:onexray/pages/advanced/xray/dialing/controller.dart';
import 'package:onexray/pages/advanced/xray/dialing/page.dart';
import 'package:onexray/pages/advanced/xray/page.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/dialing.dart';
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
  late _DialingService service;

  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    coordinator = ConnectionCoordinator(database: db);
    service = _DialingService(coordinator);
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
    testWidgets('dialing settings fit ${locale.toLanguageTag()}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = ServerDialingController(
        draft: await service.load(),
        service: service,
      );
      registerCleanup(tester, controller.close);
      await tester.pumpWidget(
        _app(
          ServerDialingPage(createController: () => controller),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerDialingPage)),
      )!;
      expect(find.text(l.serverDialingSystem), findsOneWidget);
      expect(find.byType(SettingSelect<ServerDomainStrategy>), findsOneWidget);
      expect(find.byType(ShadSwitch), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(ShadSwitch)).label,
        'Happy Eyeballs',
      );
      expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isFalse);
      expect(find.text(l.serverDialingScopeHelp), findsNothing);
      await tester.tap(
        find.byTooltip('${l.pageHelp} · ${l.serverDialingTitle}'),
      );
      await tester.pumpAndSettle();
      for (final help in [
        l.serverDialingScopeHelp,
        l.serverDialingFallbackHelp,
        l.serverDialingDnsHelp,
        l.serverDialingHappyEyeballsHelp,
        l.serverDialingIpv6Help,
      ]) {
        expect(find.text(help), findsOneWidget);
      }
      await tester.tap(find.byTooltip(l.prototypeCloseDialog));
      await tester.pumpAndSettle();
      expect(find.byType(PageActionBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(controller.close);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      semantics.dispose();
    });
  }

  testWidgets('strategy selection retains disabled Happy Eyeballs preference', (
    tester,
  ) async {
    final controller = ServerDialingController(
      draft: await service.load(),
      service: service,
    );
    registerCleanup(tester, controller.close);
    await tester.pumpWidget(
      _app(ServerDialingPage(createController: () => controller)),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('server-dialing-happy-eyeballs'));
    final strategy = find.byKey(const ValueKey('server-dialing-strategy'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(controller.dialing.happyEyeballs, isTrue);
    await tester.tap(strategy);
    await tester.pumpAndSettle();
    for (final label in [
      'System default',
      'IPv4 + IPv6',
      'IPv4',
      'IPv6',
      'IPv4 first',
      'IPv6 first',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('IPv4 first').last);
    await tester.pumpAndSettle();
    final inactive = tester.widget<ShadSwitch>(toggle);
    expect(inactive.enabled, isFalse);
    expect(inactive.value, isTrue);
    expect(controller.dialing.domainStrategy, ServerDomainStrategy.ipv4First);
    await tester.tap(strategy);
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default').last);
    await tester.pumpAndSettle();
    expect(tester.widget<ShadSwitch>(toggle).enabled, isTrue);
    expect(tester.widget<ShadSwitch>(toggle).value, isTrue);
    expect(service.saves, 0);
    expect(tester.takeException(), isNull);
    await tester.runAsync(controller.close);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('IPv6 off keeps the saved preference visibly disabled', (
    tester,
  ) async {
    service.configuration = ConnectionConfiguration(
      policy: PlatformPolicy.fromJson({
        'ipv6Enabled': false,
        'dialing': {'happyEyeballs': true},
      }),
    );
    final controller = ServerDialingController(
      draft: await service.load(),
      service: service,
    );
    registerCleanup(tester, controller.close);
    await tester.pumpWidget(
      _app(ServerDialingPage(createController: () => controller)),
    );
    await tester.pumpAndSettle();
    final toggle = tester.widget<ShadSwitch>(find.byType(ShadSwitch));
    expect(toggle.enabled, isFalse);
    expect(toggle.value, isTrue);
    expect(
      find.text('Requires IPv6 and System default or IPv4 + IPv6.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.runAsync(controller.close);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('save asks before reconnect and cancellation retains the draft', (
    tester,
  ) async {
    coordinator.state.value = const ConnectionView(
      phase: ConnectionPhase.connected,
    );
    service.requireConfirmation = true;
    final controller = ServerDialingController(
      draft: await service.load(),
      service: service,
    );
    registerCleanup(tester, controller.close);
    await tester.pumpWidget(
      _app(ServerDialingPage(createController: () => controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('server-dialing-happy-eyeballs')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ShadDialog), findsOneWidget);
    expect(service.saves, 0);
    await tester.tap(
      find.descendant(
        of: find.byType(ShadDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.dialing.happyEyeballs, isTrue);
    expect(service.configuration.policy.dialing.happyEyeballs, isFalse);
    expect(controller.busy, isFalse);
    expect(service.saves, 0);
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save and reconnect'));
    await tester.pumpAndSettle();
    expect(service.saves, 1);
    expect(service.configuration.policy.dialing.happyEyeballs, isTrue);
    expect(tester.takeException(), isNull);
    await tester.runAsync(controller.close);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('macOS SE runtime keeps the dialing entry and page editable', (
    tester,
  ) async {
    final runtime = _SystemExtensionRuntimeController(
      coordinator: coordinator,
      policyEditor: service,
    );
    final controller = ServerDialingController(
      draft: await service.load(),
      service: service,
    );
    registerCleanup(tester, () async {
      await runtime.close();
      await controller.close();
    });
    var opened = false;
    await tester.pumpWidget(
      _app(
        XrayRuntimePage(
          createController: () => runtime,
          onGeodata: (_) {},
          onUpdates: (_) {},
          onSpeedTest: (_) {},
          onLog: (_, _) {},
          onConfig: (_, _) {},
          onServerDialing: (context) {
            opened = true;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ServerDialingPage(createController: () => controller),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(runtime.state.systemExtension, isTrue);
    final entry = find.text('Server dialing').last;
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(find.byType(ServerDialingPage), findsOneWidget);
    final toggle = find.byKey(const ValueKey('server-dialing-happy-eyeballs'));
    expect(tester.widget<ShadSwitch>(toggle).enabled, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.saves, 1);
    expect(service.configuration.policy.dialing.happyEyeballs, isTrue);
    expect(find.byType(ServerDialingPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.runAsync(runtime.close);
    await tester.runAsync(controller.close);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

class _DialingService extends PolicyEditorService {
  _DialingService(ConnectionCoordinator coordinator)
    : super(
        coordinator: coordinator,
        platform: ConnectionPlatform.macos,
        validateInterface: false,
      );

  ConnectionConfiguration configuration = ConnectionConfiguration();
  bool requireConfirmation = false;
  int saves = 0;

  @override
  Future<PolicyEditorDraft> load() async => PolicyEditorDraft(configuration);

  @override
  Future<bool> save({
    required PolicyEditorDraft draft,
    required Future<bool> Function(bool disconnect) confirm,
  }) async {
    if (requireConfirmation && !await confirm(false)) return false;
    configuration = ConnectionConfiguration(
      connection: draft.original.connection,
      policy: PlatformPolicy.fromJson(draft.policy),
    );
    saves++;
    return true;
  }
}

class _SystemExtensionRuntimeController extends XrayRuntimeController {
  _SystemExtensionRuntimeController({
    required super.coordinator,
    required super.policyEditor,
  });

  @override
  Future<void> load({bool showLoading = true}) async {
    final configuration = (policyEditor as _DialingService).configuration;
    emit(
      state.copyWith(
        base: configuration,
        log: configuration.policy.toJson()['log'] as Map<String, dynamic>,
        systemExtension: true,
        loading: false,
      ),
    );
  }
}
