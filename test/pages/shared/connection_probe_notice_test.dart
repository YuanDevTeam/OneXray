import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/connection_probe_notice.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _message = "Node check didn't succeed. VPN remains connected.";

void main() {
  testWidgets('a failure shows one advisory without changing the page', (
    tester,
  ) async {
    final failures = _Failures();
    addTearDown(failures.dispose);
    final consumed = <int>[];
    var actions = 0;
    await tester.pumpWidget(
      _NoticeApp(
        failures: failures,
        consume: (session) {
          consumed.add(session);
          return true;
        },
        onAction: () => actions++,
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getRect(find.text('Connected'));
    expect(find.byType(ShadToast), findsNothing);
    expect(consumed, isEmpty);

    failures.value = 1;
    expect(
      consumed,
      isEmpty,
      reason: 'Notification is deferred until the frame ends.',
    );
    await tester.pumpAndSettle();

    expect(consumed, [1]);
    expect(find.text(_message), findsOneWidget);
    expect(find.byType(ShadToast), findsOneWidget);
    expect(find.byType(ShadDialog), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getRect(find.text('Connected')), before);
    final toast = tester.widget<ShadToast>(find.byType(ShadToast));
    expect(toast.duration, const Duration(seconds: 2));
    await tester.tap(find.text('Use app'));
    expect(actions, 1);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(ShadToast), findsNothing);
    failures.repeat();
    await tester.pumpAndSettle();
    expect(consumed, [1]);
    expect(find.byType(ShadToast), findsNothing);

    failures.value = 2;
    await tester.pumpAndSettle();
    expect(consumed, [1, 2]);
    expect(find.text(_message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an expired failure is dropped before consuming it', (
    tester,
  ) async {
    final failures = _Failures();
    addTearDown(failures.dispose);
    final consumed = <int>[];
    await tester.pumpWidget(
      _NoticeApp(
        failures: failures,
        consume: (session) {
          consumed.add(session);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    failures.value = 1;
    failures.value = null;
    await tester.pumpAndSettle();

    expect(consumed, isEmpty);
    expect(find.byType(ShadToast), findsNothing);
  });

  testWidgets('only the latest session is consumed in a pending frame', (
    tester,
  ) async {
    final failures = _Failures();
    addTearDown(failures.dispose);
    final consumed = <int>[];
    await tester.pumpWidget(
      _NoticeApp(
        failures: failures,
        consume: (session) {
          consumed.add(session);
          failures.value = null;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    failures.value = 1;
    failures.value = 2;
    await tester.pumpAndSettle();

    expect(consumed, [2]);
    expect(find.text(_message), findsOneWidget);
  });

  testWidgets('a rejected session does not show a notice', (tester) async {
    final failures = _Failures();
    addTearDown(failures.dispose);
    var checks = 0;
    await tester.pumpWidget(
      _NoticeApp(
        failures: failures,
        consume: (_) {
          checks++;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();
    failures.value = 1;
    await tester.pumpAndSettle();

    expect(checks, 1);
    expect(find.byType(ShadToast), findsNothing);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('disposing the listener cancels a queued notice', (tester) async {
    final failures = _Failures();
    addTearDown(failures.dispose);
    var checks = 0;
    await tester.pumpWidget(
      _NoticeApp(
        failures: failures,
        consume: (_) {
          checks++;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    failures.value = 1;
    await tester.pumpWidget(
      _NoticeApp(failures: failures, consume: (_) => true, showNotice: false),
    );
    await tester.pumpAndSettle();

    expect(checks, 0);
    expect(find.byType(ShadToast), findsNothing);
    failures.value = 2;
    await tester.pumpAndSettle();
    expect(checks, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a replaced source cannot consume its old queued failure', (
    tester,
  ) async {
    final oldFailures = _Failures();
    final nextFailures = _Failures()..value = 2;
    addTearDown(oldFailures.dispose);
    addTearDown(nextFailures.dispose);
    final consumed = <int>[];
    await tester.pumpWidget(
      _NoticeApp(
        failures: oldFailures,
        consume: (_) => throw StateError('Old consumer must not be called'),
      ),
    );
    await tester.pumpAndSettle();
    oldFailures.value = 1;
    await tester.pumpWidget(
      _NoticeApp(
        failures: nextFailures,
        consume: (session) {
          consumed.add(session);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(consumed, [2]);
    expect(find.text(_message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Failures extends ValueNotifier<int?> {
  _Failures() : super(null);

  void repeat() => notifyListeners();
}

class _NoticeApp extends StatelessWidget {
  const _NoticeApp({
    required this.failures,
    required this.consume,
    this.showNotice = true,
    this.onAction,
  });

  final ValueListenable<int?> failures;
  final bool Function(int) consume;
  final bool showNotice;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Connected'),
            TextButton(
              onPressed: onAction ?? () {},
              child: const Text('Use app'),
            ),
          ],
        ),
      ),
    );
    return MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => ShadTheme(
        data: AppTheme.shad(Brightness.light),
        child: ShadToaster(child: child ?? const SizedBox.shrink()),
      ),
      home: showNotice
          ? ConnectionProbeNotice(
              failures: failures,
              consume: consume,
              child: page,
            )
          : page,
    );
  }
}
