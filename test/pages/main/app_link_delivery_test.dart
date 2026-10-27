import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/adaptive_shell.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/main/modal_route_observer.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/share/service.dart';

void main() {
  testWidgets('cold link waits for ready UI and is consumed only once', (
    tester,
  ) async {
    final links = StreamController<Uri>.broadcast(sync: true);
    final share = ShareService.forTesting(
      appLinks: links.stream,
      receiveWidgetUri: (_) => false,
    );
    final ready = Completer<void>();
    final eventBus = AppEventBus();
    var importCount = 0;
    final received = <String>[];
    final first = Uri.parse(
      'onexray://onexray.com/sub/add?url=https://a.example',
    );
    final second = Uri.parse(
      'onexray://onexray.com/sub/add?url=https://b.example',
    );
    share.startAppLinks();
    links.add(first);
    final modalObserver = AppModalRouteObserver();
    final router = GoRouter(
      initialLocation: '/connect',
      observers: [modalObserver],
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AdaptiveMainShell(
            navigationShell: shell,
            hasActiveModal: (_) => modalObserver.hasPopupRoute,
            modalChanges: modalObserver,
            shareService: share,
            initializeServices: (_) async {
              await share.init();
              await ready.future;
            },
          ),
          branches: [
            for (final primary in AppPrimaryDestination.values)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: primary.rootPath,
                    builder: (_, _) => const Text('home'),
                    routes: [
                      GoRoute(
                        path: AppPageDestination.serversImport.segment,
                        builder: (_, state) {
                          importCount++;
                          received.add(state.extra! as String);
                          return Scaffold(body: Text(state.extra! as String));
                        },
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(() async {
      share.dispose();
      await links.close();
      router.dispose();
      await eventBus.close();
    });
    await tester.pumpWidget(
      BlocProvider.value(
        value: eventBus,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    expect(importCount, 0);
    ready.complete();
    await tester.pumpAndSettle();
    expect(received, [first.toString()]);

    links.add(first);
    links.add(second);
    links.add(second);
    await tester.pumpAndSettle();
    expect(importCount, 1);
    router.pop();
    await tester.pumpAndSettle();
    expect(received, [first.toString(), second.toString()]);
    router.pop();
    await tester.pumpAndSettle();
    expect(importCount, 2);

    // A manually opened import must finish before the cached link opens.
    unawaited(router.push('/connect/servers-import', extra: 'manual'));
    await tester.pumpAndSettle();
    links.add(first);
    await tester.pumpAndSettle();
    expect(received.last, 'manual');
    router.pop();
    await tester.pumpAndSettle();
    expect(received.last, first.toString());
    expect(importCount, 4);
    router.pop();
    await tester.pumpAndSettle();
    unawaited(
      showDialog<void>(
        context: tester.element(find.text('home').first),
        builder: (_) => const AlertDialog(content: Text('manual-popup')),
      ),
    );
    await tester.pumpAndSettle();
    links.add(second);
    await tester.pumpAndSettle();
    expect(importCount, 4);
    router.pop();
    await tester.pumpAndSettle();
    expect(received.last, second.toString());
    expect(importCount, 5);
    router.pop();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
