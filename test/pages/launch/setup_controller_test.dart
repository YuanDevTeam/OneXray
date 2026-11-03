import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/launch/setup/controller.dart';
import 'package:onexray/pages/launch/setup/selectors.dart';
import 'package:onexray/pages/launch/setup/view.dart';
import 'package:onexray/pages/connect/routing/smart/regions.dart';
import 'package:onexray/pages/main/url.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/launch/setup.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  setUp(() async => SharedPreferencesAsync().clear());

  for (final completedBeforePrivacy in [true, false]) {
    test(
      'real setup saves after firstRun becomes false '
      '${completedBeforePrivacy ? 'before privacy' : 'on the configuration page'}',
      () async {
        final preferences = PreferencesKey();
        await preferences.saveFirstRun(!completedBeforePrivacy);
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final service = _LocalSetupService(database);
        final controller = SetupController(service: service);
        addTearDown(controller.close);
        await _idle(controller);
        expect(controller.state.step, SetupStep.welcome);

        await controller.acceptPrivacy();
        expect(controller.state.step, SetupStep.configuration);
        expect(controller.state.localReady, isTrue);
        expect(controller.state.regions, ['RU']);
        if (!completedBeforePrivacy) await preferences.saveFirstRun(false);
        expect(await service.currentStep(), SetupStep.complete);

        await controller.finish();

        final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
        expect(
          controller.state.failure,
          isNull,
          reason: controller.failureText(l10n),
        );
        expect(controller.state.step, SetupStep.complete);
        expect(controller.state.busy, isFalse);
        expect((await service.configuration()).connection.smart.directRegions, [
          'RU',
        ]);
        expect(await preferences.readFirstRun(), isFalse);
      },
    );
  }

  test('privacy and configuration require explicit completion', () async {
    final service = _SetupService();
    final controller = SetupController(service: service);
    addTearDown(controller.close);
    await _idle(controller);
    expect(controller.state.step, SetupStep.welcome);
    expect(service.preparations, 0);

    await controller.acceptPrivacy();
    expect(controller.state.step, SetupStep.configuration);
    expect(controller.state.regions, ['RU']);
    expect(service.savedRegions, isNull);
    expect(service.finishes, 0);

    controller.showWelcome();
    await controller.acceptPrivacy();
    expect(controller.state.step, SetupStep.configuration);
    expect(service.finishes, 0);
    await controller.finish();
    expect(controller.state.step, SetupStep.complete);
    expect(service.savedRegions, ['RU']);
    expect(service.finishes, 1);
  });

  test(
    'unknown region remains optional without using default CN as a guess',
    () async {
      final service = _SetupService()
        ..step = SetupStep.configuration
        ..suggestedRegion = 'UNKNOWN';
      final controller = SetupController(service: service);
      addTearDown(controller.close);
      await _idle(controller);
      expect(controller.state.regions, isNull);
      expect(controller.state.ready(requiresInterface: false), isTrue);
      expect(service.finishes, 0);
      await controller.finish();
      expect(service.savedRegions, isNull);
      expect(controller.state.step, SetupStep.complete);
    },
  );

  test('local failure can retry without entering another step', () async {
    final service = _SetupService()
      ..step = SetupStep.configuration
      ..localFailure = true;
    final controller = SetupController(service: service);
    addTearDown(controller.close);
    await _idle(controller);
    expect(controller.state.failure?.component, 'local');
    expect(controller.state.localReady, isFalse);
    expect(controller.state.step, SetupStep.configuration);

    service.localFailure = false;
    await controller.retry();
    expect(controller.state.failure, isNull);
    expect(controller.state.localReady, isTrue);
    expect(controller.state.step, SetupStep.configuration);
    expect(service.finishes, 0);
  });

  test('save failure preserves the draft and allows retry', () async {
    final service = _SetupService()
      ..step = SetupStep.configuration
      ..saveFailure = true;
    final controller = SetupController(service: service);
    addTearDown(controller.close);
    await _idle(controller);
    await controller.finish();
    expect(controller.state.step, SetupStep.configuration);
    expect(controller.state.regions, ['RU']);
    expect(controller.state.busy, isFalse);
    expect(controller.state.failure, isNotNull);
    service.saveFailure = false;
    await controller.finish();
    expect(controller.state.step, SetupStep.complete);
  });

  for (final platform in [ConnectionPlatform.ios, ConnectionPlatform.windows]) {
    testWidgets('merged configuration reuses selector routes on $platform', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1160, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _SetupService(platform: platform)
        ..step = SetupStep.configuration
        ..suggestedRegion = null;
      final controller = SetupController(service: service);
      addTearDown(controller.close);
      await _idle(controller);
      expect(
        controller.state.ready(requiresInterface: service.requiresInterface),
        !service.requiresInterface,
      );

      final router = GoRouter(
        initialLocation: '/setup',
        routes: [
          GoRoute(
            path: '/setup',
            builder: (context, _) =>
                BlocBuilder<SetupController, SetupPageState>(
                  bloc: controller,
                  builder: (context, state) => SetupView(
                    state: state,
                    requiresInterface: service.requiresInterface,
                    onAction: (action) =>
                        controller.handleAction(context, action),
                  ),
                ),
          ),
          ...RouterPath.router.configuration.routes
              .whereType<GoRoute>()
              .where(
                (route) =>
                    route.path == '/setup/interface' ||
                    route.path == '/setup/region',
              )
              .map(
                (route) => route.path == '/setup/region'
                    ? GoRoute(
                        path: route.path,
                        redirect: route.redirect,
                        builder: (context, state) {
                          final page = route.builder!(
                            context,
                            state,
                          ) as DirectRegionsPage;
                          return DirectRegionsPage(
                            selectedCodes: page.selectedCodes,
                            loadRegions: () async => RegionCatalog.fromJson(
                              {
                                'geosite': <String, dynamic>{},
                                'geoip': {
                                  for (final code in ['CN', 'RU', 'US'])
                                    code: [code],
                                },
                              },
                              geositeCodes: [],
                              geoipCodes: ['CN', 'RU', 'US'],
                            ),
                          );
                        },
                      )
                    : route,
              ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          builder: (_, child) =>
              ShadTheme(data: AppTheme.shad(Brightness.light), child: child!),
        ),
      );
      await tester.pumpAndSettle();

      if (service.requiresInterface) {
        await tester.tap(find.text('Xray outbound interface'));
        await tester.pumpAndSettle();
        expect(find.byType(SetupInterfacePage), findsOneWidget);
        await tester.tap(find.text('Ethernet').last);
        await tester.pumpAndSettle();
        expect(controller.state.interfaceName, 'Ethernet');
        expect(controller.state.step, SetupStep.configuration);
        expect(service.savedInterface, '');
      }

      await tester.tap(find.text('Choose your country or region'));
      await tester.pumpAndSettle();
      expect(find.byType(DirectRegionsPage), findsOneWidget);
      await tester.tap(find.text('Russia'));
      router.pop();
      await tester.pumpAndSettle();
      expect(controller.state.regions, isNull);

      await tester.tap(find.text('Choose your country or region'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Russia'));
      await tester.tap(find.text('Mainland China'));
      await tester.tap(find.text('Mainland China'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(controller.state.regions, ['CN']);
      expect(controller.state.step, SetupStep.configuration);
      expect(service.savedRegions, isNull);
      expect(service.finishes, 0);

      await tester.tap(find.text('Go to Home'));
      await tester.pumpAndSettle();
      expect(service.savedRegions, ['CN']);
      expect(
        service.savedInterface,
        service.requiresInterface ? 'Ethernet' : '',
      );
      expect(controller.state.step, SetupStep.complete);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _idle(SetupController controller) async {
  if (controller.state.busy) {
    await controller.stream.firstWhere((state) => !state.busy);
  }
}

// Only external preparation and region lookup are replaced. Step decisions,
// completion and database persistence use the production SetupService.
class _LocalSetupService extends SetupService {
  _LocalSetupService(AppDatabase database)
    : super(
        database: database,
        platform: ConnectionPlatform.macos,
        prepareLocal: () async {},
        readRegionCodes: () async => ['CN', 'RU'],
      );

  @override
  Future<String?> suggestRegion() async => 'RU';
}

class _SetupService extends SetupService {
  _SetupService({super.platform = ConnectionPlatform.ios});
  SetupStep step = SetupStep.welcome;
  bool localFailure = false;
  bool saveFailure = false;
  String? suggestedRegion = 'RU';
  List<String>? savedRegions;
  String savedInterface = '';
  int preparations = 0;
  int finishes = 0;

  @override
  Future<SetupStep> currentStep() async => step;

  @override
  Future<void> acceptPrivacy() async => step = SetupStep.configuration;

  @override
  Future<void> prepareLocal() async {
    preparations++;
    if (localFailure) throw const SetupFailure('local');
  }

  @override
  Future<ConnectionConfiguration> configuration() async =>
      ConnectionConfiguration(
        policy: PlatformPolicy.fromJson({
          'xrayOutboundInterfaceName': savedInterface,
        }),
      );

  @override
  Future<List<String>> regionCodes() async => ['CN', 'RU', 'US'];

  @override
  Future<List<OutboundInterfaceOption>> interfaces() async => [
    const OutboundInterfaceOption('Ethernet', ['192.0.2.2'], true),
  ];

  @override
  Future<String?> suggestRegion() async => suggestedRegion;

  @override
  Future<void> finish({
    required String interfaceName,
    List<String>? regions,
  }) async {
    if (saveFailure) throw StateError('Cannot save');
    savedInterface = interfaceName;
    savedRegions = regions;
    finishes++;
    step = SetupStep.complete;
  }
}
