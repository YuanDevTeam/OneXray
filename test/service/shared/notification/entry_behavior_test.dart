import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/controller.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/menu/tray/entry.dart';
import 'package:onexray/service/shared/menu/tray/service.dart';
import 'package:onexray/service/shared/notification/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('public notification entry behavior', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    TargetPlatform? previousTarget;

    setUp(() {
      calls.clear();
      previousTarget = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      MacOSFlutterLocalNotificationsPlugin.registerWith();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return call.method == 'show' ? null : true;
      });
      final bus = AppEventBus();
      addTearDown(bus.close);
      addTearDown(() {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = previousTarget;
      });
    });

    test(
      'Darwin initialization leaves notification authorization deferred',
      () async {
        await NotificationService().asyncInit();

        expect(calls.map((call) => call.method), ['initialize']);
        final settings = calls.single.arguments as Map;
        expect(settings['requestAlertPermission'], isFalse);
        expect(settings['requestSoundPermission'], isFalse);
        expect(settings['requestBadgePermission'], isFalse);
      },
    );

    test('Darwin notification delivery requests alert authorization before showing the message', () async {
      await NotificationService().asyncInit();
      calls.clear();

      await NotificationService().pushNotification(
        'Connection needs attention',
      );

      expect(calls.map((call) => call.method), ['requestPermissions', 'show']);
      final permissions = calls.first.arguments as Map;
      expect(permissions['alert'], isTrue);
      expect(permissions['sound'], isFalse);
      expect(permissions['badge'], isFalse);
      expect(
        (calls.last.arguments as Map)['title'],
        'Connection needs attention',
      );
      expect((calls.last.arguments as Map)['id'], 0);
    }, skip: !AppPlatform.isMacOS);

    test('tray resolver failures reach the notification service without taking focus', () async {
      await NotificationService().asyncInit();
      calls.clear();
      var shown = 0;
      final tray = TrayService.forTesting(
        connect: () async => throw const ConnectionResolutionException(
          ConnectionResolutionFailure.insufficientCandidates,
          requiredCount: 3,
          availableCount: 1,
        ),
        notify: NotificationService().pushNotification,
        showMainWindow: () async => shown++,
      );

      await tray.onMenuAction(TrayMenuEntry(key: 'startVpn'));

      final delivered = calls.where((call) => call.method == 'show').single;
      expect(
        (delivered.arguments as Map)['title'],
        '${appLocalizationsNoContext().prototypeNotEnoughServers} (1/3)',
      );
      expect(shown, 0);
    });

    test(
      'cancelled tray connections do not reach the notification service',
      () async {
        await NotificationService().asyncInit();
        calls.clear();
        final tray = TrayService.forTesting(
          connect: () async => throw const ConnectionResolutionException(
            ConnectionResolutionFailure.cancelled,
          ),
          notify: NotificationService().pushNotification,
          showMainWindow: () async => fail('Cancellation must not take focus'),
        );

        await tray.onMenuAction(TrayMenuEntry(key: 'startVpn'));

        expect(calls, isEmpty);
      },
    );

    testWidgets(
      'connection page shows resolver counts without a system notification',
      (tester) async {
        try {
          await NotificationService().asyncInit();
        } finally {
          debugDefaultTargetPlatformOverride = previousTarget;
        }
        calls.clear();
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final coordinator = _FailingCoordinator(db);
        addTearDown(coordinator.dispose);
        final controller = ConnectController(
          database: db,
          coordinator: coordinator,
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
            home: const Scaffold(body: SizedBox()),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(Scaffold));

        await controller.connectionAction(context);
        await tester.pump(const Duration(milliseconds: 300));

        final l = AppLocalizations.of(context)!;
        expect(
          find.text('${l.prototypeNotEnoughServers} (1/3)'),
          findsOneWidget,
        );
        expect(controller.pendingChange, isNull);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}

final class _FailingCoordinator extends ConnectionCoordinator {
  _FailingCoordinator(AppDatabase database)
    : super(database: database, disposeStatus: () {});

  @override
  Future<void> connect() async => throw const ConnectionResolutionException(
    ConnectionResolutionFailure.insufficientCandidates,
    requiredCount: 3,
    availableCount: 1,
  );
}
