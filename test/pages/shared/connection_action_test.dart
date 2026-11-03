import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/connection_action.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  for (final stale in [false, true]) {
    testWidgets(
      'tray selection uses normal commit without starting VPN (stale: $stale)',
      (tester) async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.runAsync(() async {
          final coordinator = ConnectionCoordinator(
            database: db,
            readRuntime: () async => null,
            inspect: (_, {observedStatus}) async =>
                const HostConnection(VpnStatus.disconnected),
            start: (_) async =>
                throw StateError('A disconnected selection must not start VPN'),
          );
          addTearDown(coordinator.dispose);
          await coordinator.initialize(
            observe: false,
            registerReferences: false,
          );
          final before = await coordinator.configuration;
          final applying = applyConnectionChange(
            context,
            coordinator,
            {'expert': true, 'rawId': 5},
            label: (_) => 'Raw 5',
            validateAssets: () async {
              if (stale) {
                throw const AppFailure(FailureCategory.conflict, 'notFound');
              }
            },
            rethrowErrors: true,
          );
          if (stale) {
            await expectLater(applying, throwsA(isA<AppFailure>()));
            expect((await coordinator.configuration).encode(), before.encode());
          } else {
            final saved = await applying;
            expect(
              (saved!.connection.expert, saved.connection.rawId),
              (true, 5),
            );
            expect(
              (await coordinator.configuration).policy.toJson(),
              before.policy.toJson(),
            );
          }
        });
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final (error, message) in [
    (
      const ConnectionResolutionException(
        ConnectionResolutionFailure.selectionUnavailable,
      ),
      'No available entry servers · Add servers',
    ),
    (
      const ConnectionResolutionException(
        ConnectionResolutionFailure.insufficientCandidates,
        requiredCount: 3,
        availableCount: 1,
      ),
      'Not enough available servers (1/3)',
    ),
    (
      const ConnectionResolutionException(
        ConnectionResolutionFailure.cancelled,
      ),
      null,
    ),
  ]) {
    testWidgets('connection action feedback: ${error.reason.name}', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final coordinator = ConnectionCoordinator(database: db);
      addTearDown(db.close);
      addTearDown(coordinator.dispose);
      bool? succeeded;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => ShadTheme(
            data: AppTheme.shad(Brightness.light),
            child: ShadToaster(child: child!),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: ShadButton(
                child: const Text('Connect'),
                onPressed: () async {
                  succeeded = await runConnectionAction(
                    context,
                    coordinator,
                    () async => throw error,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Connect'));
      await tester.pump();
      expect(succeeded, isFalse);
      if (message != null) {
        expect(find.text(message), findsOneWidget);
      } else {
        expect(find.byType(ShadToast), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
