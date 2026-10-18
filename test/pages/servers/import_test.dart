import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/servers/import/controller.dart';
import 'package:onexray/pages/servers/import/page.dart';
import 'package:onexray/pages/servers/subscription/form_view.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/servers/import.dart';
import 'package:onexray/service/shared/db/config_writer.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/share/app_link_model.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/connect/raw/validator.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
  });

  test(
    'panels share the default UA and preserve manual input while loading',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'OneXray',
        packageName: 'net.yuandev.onexray',
        version: '26.10.4',
        buildNumber: '104',
        buildSignature: '',
      );
      final controller = ServerImportController(
        loadSubscription: (_) async => null,
      );
      addTearDown(controller.close);

      await controller.setPanel(SubscriptionPanel.generic);
      expect(
        controller.userAgent.text,
        'v2rayN/26.10.4 OneXray/26.10.4 '
        '(net.yuandev.onexray; build:104; ${Platform.operatingSystem})',
      );
      expect(controller.state.userAgent, controller.userAgent.text);
      final generated = controller.userAgent.text;

      await controller.setPanel(SubscriptionPanel.remnawave);
      await controller.setPanel(SubscriptionPanel.generic);
      expect(controller.userAgent.text, generated);
      expect(controller.state.userAgent, generated);
      for (final custom in ['Custom/1.0', generated]) {
        controller.userAgent.clear();
        controller.userAgent.text = custom;
        await controller.setPanel(SubscriptionPanel.remnawave);
        await controller.setPanel(SubscriptionPanel.generic);
        expect(controller.userAgent.text, custom);
      }

      controller.userAgent.clear();
      final switching = controller.setPanel(SubscriptionPanel.remnawave);
      await controller.setPanel(SubscriptionPanel.generic);
      await switching;
      expect(controller.userAgent.text, generated);

      controller.userAgent.clear();
      final pending = controller.setPanel(SubscriptionPanel.remnawave);
      controller.userAgent.text = 'Typed while loading';
      await pending;
      expect(controller.userAgent.text, 'Typed while loading');

      controller.userAgent.clear();
      final closing = controller.setPanel(SubscriptionPanel.remnawave);
      await controller.close();
      await closing;
    },
  );

  testWidgets('adding an ordinary subscription displays the default UA', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'OneXray',
      packageName: 'net.yuandev.onexray',
      version: '26.10.4',
      buildNumber: '104',
      buildSignature: '',
    );
    final expectedUserAgent =
        'v2rayN/26.10.4 OneXray/26.10.4 '
        '(net.yuandev.onexray; build:104; ${Platform.operatingSystem})';
    final controller = ServerImportController(
      loadSubscription: (_) async => null,
    );
    addTearDown(controller.close);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppDialog<ServerImportResult>(
              context,
              (_) => ServersImportPage(controller: controller),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add subscription'));
    await tester.pumpAndSettle();

    expect(find.byType(SubscriptionFormView), findsOneWidget);
    expect(controller.state.panel, SubscriptionPanel.generic);
    expect(controller.userAgent.text, expectedUserAgent);
    expect(controller.state.userAgent, expectedUserAgent);
    expect(
      find.descendant(
        of: find.byType(SubscriptionFormView),
        matching: find.text(expectedUserAgent),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final panel in SubscriptionPanel.values) {
    for (final storedUserAgent in <String?>[null, ' \t ']) {
      final storedLabel = storedUserAgent == null ? 'missing' : 'blank';
      testWidgets(
        'editing $panel subscription displays the default for $storedLabel UA without saving',
        (tester) async {
          PackageInfo.setMockInitialValues(
            appName: 'OneXray',
            packageName: 'net.yuandev.onexray',
            version: '26.10.4',
            buildNumber: '104',
            buildSignature: '',
          );
          final expectedUserAgent =
              'v2rayN/26.10.4 OneXray/26.10.4 '
              '(net.yuandev.onexray; build:104; ${Platform.operatingSystem})';
          var saves = 0;
          final controller = ServerImportController(
            subscriptionId: 7,
            loadSubscription: (_) async => SubscriptionData(
              id: 7,
              name: 'Provider',
              url: 'https://provider.example/list',
              userAgent: storedUserAgent,
              panel: panel.name,
              mode: 'appManaged',
              hwidEnabled: false,
              timestamp: DateTime(2026),
            ),
            saveSubscriptionInput: (_, _) async {
              saves++;
              return SubscriptionUpdateResult.success;
            },
          );
          addTearDown(controller.close);
          await tester.pumpWidget(
            _app(
              Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    await controller.loadSubscription(context);
                    if (!context.mounted) return;
                    await showAppDialog<int>(
                      context,
                      (_) => ServerImportFormPage(
                        controller: controller,
                        action: ServerImportAction.subscription,
                      ),
                    );
                  },
                  child: const Text('Edit source'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Edit source'));
          await tester.pumpAndSettle();

          expect(find.byType(SubscriptionFormView), findsOneWidget);
          expect(controller.state.panel, panel);
          expect(controller.userAgent.text, expectedUserAgent);
          expect(controller.state.userAgent, expectedUserAgent);
          expect(
            find.descendant(
              of: find.byType(SubscriptionFormView),
              matching: find.text(expectedUserAgent),
            ),
            findsOneWidget,
          );
          expect(saves, 0);
          await _tapVisible(tester, find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.byType(SubscriptionFormView), findsNothing);
          expect(saves, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('file import keeps loading while subscriptions download', (
    tester,
  ) async {
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _SubscriptionFilePicker();
    addTearDown(() => FilePickerPlatform.instance = previous);
    late Completer<void> started;
    late Completer<SubscriptionInsertResult> release;
    await tester.runAsync(() async {
      started = Completer<void>();
      release = Completer<SubscriptionInsertResult>();
    });
    final urls = <String>[];
    final service = ServerImportService(
      subscribe: (link) {
        urls.add(link.url);
        if (!started.isCompleted) started.complete();
        return AppEventBus.instance.trackDownload(() => release.future);
      },
    );
    final controller = ServerImportController(
      service: service,
      loadSubscription: (_) async => null,
    );
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppDialog<ServerImportResult>(
              context,
              (_) => ServersImportPage(controller: controller),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Import file'));
      await started.future.timeout(const Duration(seconds: 5));
    });
    await tester.pump();
    try {
      expect(urls, ['https://example.com/personal.txt']);
      expect(controller.state.busy, isTrue);
      expect(controller.state.openingAction, isNull);
      expect(
        find.descendant(
          of: find.widgetWithText(OutlinedButton, 'Import file'),
          matching: find.byType(ButtonProgressIndicator),
        ),
        findsOneWidget,
      );
    } finally {
      await tester.runAsync(() async {
        release.complete(
          const SubscriptionInsertResult(
            status: SubscriptionUpdateResult.downloadFailed,
            error: HttpException('HTTP 403'),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
    }
    expect(urls.length, 3);
    expect(find.textContaining('HTTP 403'), findsNWidgets(3));
    expect(find.byType(ButtonProgressIndicator), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Import file'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('node import reports success without confirmation', (
    tester,
  ) async {
    var writes = 0;
    ServerImportResult? result;
    final controller = ServerImportController(
      loadSubscription: (_) async => null,
      service: ServerImportService(
        parse: (_) async => [
          outboundCompanion({'tag': 'local', 'protocol': 'freedom'}),
        ],
        write: (rows) async {
          writes++;
          return ConfigWriteResult(count: rows.length, ids: [1]);
        },
        schedule: (_) {},
      ),
    );
    addTearDown(controller.close);
    controller.text.text = 'vless://local';
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showAppDialog<ServerImportResult>(
                context,
                (_) => ServerImportFormPage(
                  controller: controller,
                  action: ServerImportAction.paste,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Import links'),
    );
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.byType(ServerImportPreviewPage), findsNothing);
    expect(result?.count, 1);
    expect(find.byType(ShadToast), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final action in [ServerImportAction.paste, ServerImportAction.json]) {
    testWidgets(
      'node import stays loading through parse and commit ($action)',
      (tester) async {
        final parsed = Completer<void>();
        final written = Completer<ConfigWriteResult>();
        var writes = 0;
        final queued = <int>[];
        final controller = ServerImportController(
          loadSubscription: (_) async => null,
          service: ServerImportService(
            parse: (_) async {
              await parsed.future;
              return [
                outboundCompanion({'tag': 'local', 'protocol': 'freedom'}),
              ];
            },
            validate: (_) async {
              await parsed.future;
              return '';
            },
            write: (_) {
              writes++;
              return written.future;
            },
            schedule: queued.addAll,
          ),
        );
        addTearDown(controller.close);
        controller.text.text = 'vless://local';
        controller.jsonText.text =
            '{"outbounds":[{"tag":"local","protocol":"freedom"}]}';
        ServerImportResult? result;
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showAppDialog<ServerImportResult>(
                    context,
                    (_) => ServerImportFormPage(
                      controller: controller,
                      action: action,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final submit = find.widgetWithText(
          FilledButton,
          action == ServerImportAction.json ? 'Add' : 'Import links',
        );
        await _tapVisible(tester, submit);
        await tester.pump();
        expect(controller.state.busy, isTrue);
        expect(find.byType(ButtonProgressIndicator), findsOneWidget);
        expect(find.byType(ServerImportPreviewPage), findsNothing);
        expect(writes, 0);
        parsed.complete();
        await tester.pump();
        expect(writes, 1);
        expect(controller.state.busy, isTrue);
        expect(find.byType(ButtonProgressIndicator), findsOneWidget);
        await controller.detect(tester.element(submit), action);
        expect(writes, 1);
        written.complete(const ConfigWriteResult(count: 1, ids: [42]));
        await tester.pumpAndSettle();
        expect(result?.count, 1);
        expect(controller.state.busy, isFalse);
        expect(queued, [42]);
        expect(find.byType(ServerImportPreviewPage), findsNothing);
        expect(find.byType(ServerImportFormPage), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final failure in ['empty', 'parse', 'write']) {
    testWidgets(
      'failed direct node import keeps input and permits retry ($failure)',
      (tester) async {
        var writes = 0;
        final controller = ServerImportController(
          loadSubscription: (_) async => null,
          service: ServerImportService(
            parse: (_) async {
              if (failure == 'parse') {
                throw const FormatException('Invalid input');
              }
              return failure == 'empty'
                  ? []
                  : [
                      outboundCompanion({
                        'tag': 'local',
                        'protocol': 'freedom',
                      }),
                    ];
            },
            write: (_) async {
              writes++;
              throw StateError('Write failed');
            },
          ),
        );
        addTearDown(controller.close);
        controller.text.text = 'vless://local';
        await tester.pumpWidget(
          _app(
            AppDialogFrame(
              child: ServerImportFormPage(
                controller: controller,
                action: ServerImportAction.paste,
              ),
            ),
          ),
        );
        final submit = find.widgetWithText(FilledButton, 'Import links');
        await _tapVisible(tester, submit);
        await tester.pumpAndSettle();
        expect(find.byType(ServerImportPreviewPage), findsNothing);
        expect(find.byType(ServerImportFormPage), findsOneWidget);
        expect(controller.text.text, 'vless://local');
        expect(controller.state.error, isNotNull);
        expect(controller.state.busy, isFalse);
        expect(writes, failure == 'write' ? 1 : 0);
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        expect(find.byType(ShadToast), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('submit availability follows text, HTTPS, and Age state', () async {
    final controller = ServerImportController(
      loadSubscription: (_) async => null,
    );
    addTearDown(controller.close);
    var changes = 0;
    final subscription = controller.stream.listen((_) => changes++);
    addTearDown(subscription.cancel);

    expect(controller.canSubmit(ServerImportAction.paste), isFalse);
    controller.text.text = 'vless://local';
    expect(controller.canSubmit(ServerImportAction.paste), isTrue);
    expect(controller.canSubmit(ServerImportAction.json), isFalse);
    controller.jsonText.text = '{"protocol":"vless"}';
    expect(controller.canSubmit(ServerImportAction.json), isTrue);
    controller.jsonText.text = '  ';
    expect(controller.canSubmit(ServerImportAction.json), isFalse);

    controller.name.text = 'Provider';
    expect(controller.canSubmit(ServerImportAction.subscription), isFalse);
    controller.url.text = 'http://provider.example/list';
    expect(controller.canSubmit(ServerImportAction.subscription), isFalse);
    controller.url.text = 'https://provider.example/list';
    expect(controller.canSubmit(ServerImportAction.subscription), isTrue);
    controller.secretKey.text = 'secret';
    expect(controller.canSubmit(ServerImportAction.subscription), isFalse);
    controller.publicKey.text = 'public';
    expect(controller.canSubmit(ServerImportAction.subscription), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(changes, 8);
  });

  testWidgets(
    'first download respects opt-in and failed retries keep the draft HWID',
    (tester) async {
      final inputs = <SubscriptionInput>[];
      final controller = ServerImportController(
        loadSubscription: (_) async => null,
        insertSubscription: (input, {confirmOrdinary}) async {
          inputs.add(input);
          return const SubscriptionInsertResult(
            status: SubscriptionUpdateResult.hwidRequired,
          );
        },
      );
      addTearDown(controller.close);
      controller.name.text = 'Provider';
      controller.url.text = 'https://provider.example/sub';
      await tester.pumpWidget(
        _app(
          ServerImportFormPage(
            controller: controller,
            action: ServerImportAction.subscription,
          ),
        ),
      );
      final context = tester.element(find.byType(ServerImportFormPage));
      await controller.subscribe(context);
      expect(inputs.single.hwidEnabled, isFalse);
      expect(inputs.single.hwid, isNull);
      expect(controller.state.hwidEnabled, isFalse);
      expect(
        controller.state.error,
        AppLocalizations.of(context)!.subscriptionHwidRequired,
      );

      controller.setHwidEnabled(true);
      await controller.subscribe(context);
      final hwid = inputs.last.hwid;
      expect(inputs.last.hwidEnabled, isTrue);
      expect(hwid, isNotNull);
      controller.setHwidEnabled(false);
      controller.setHwidEnabled(true);
      controller.url.text = 'https://provider.example/another-path';
      await controller.subscribe(context);
      expect(inputs.last.hwid, hwid);

      controller.url.clear();
      controller.url.text = 'https://provider.example/retry';
      controller.setHwidEnabled(true);
      await controller.subscribe(context);
      expect(inputs.last.hwid, hwid);

      controller.url.text = 'https://different.example/sub';
      expect(controller.state.hwidEnabled, isFalse);
      await controller.subscribe(context);
      expect(inputs.last.hwidEnabled, isFalse);
      expect(inputs.last.hwid, hwid);
      controller.setHwidEnabled(true);
      await controller.subscribe(context);
      expect(inputs.last.hwid, hwid);
      expect(controller.state.busy, isFalse);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Back returns to methods; Cancel closes only the import wizard', (
    tester,
  ) async {
    _mobileViewport(tester);
    var completed = false;
    ServerImportResult? result;
    var clipboardReads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          clipboardReads++;
          return {'text': 'Do not read automatically'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showAppDialog<ServerImportResult>(
                context,
                (_) => const ServersImportPage(),
              );
              completed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste link'));
    await tester.pumpAndSettle();
    expect(find.byType(ServerImportFormPage), findsOneWidget);
    final controller = tester
        .widget<ServerImportFormPage>(find.byType(ServerImportFormPage))
        .controller;
    expect(controller.text.text, isEmpty);
    expect(clipboardReads, 0);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Add servers to OneXray'), findsOneWidget);
    expect(completed, isFalse);

    await tester.tap(find.text('Paste link'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ServerImportFormPage>(find.byType(ServerImportFormPage))
          .controller,
      same(controller),
    );
    await tester.tap(find.byTooltip('Close dialog'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
    expect(find.byType(ServerImportFormPage), findsNothing);
    expect(find.text('Add servers to OneXray'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(Navigator.of(tester.element(find.text('Open'))).canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'node import writes directly and unwinds form and method dialogs',
    (tester) async {
      _mobileViewport(tester);
      var writes = 0;
      var completed = false;
      final controller = ServerImportController(
        loadSubscription: (_) async => null,
        service: ServerImportService(
          parse: (_) async => [
            outboundCompanion({'tag': 'local', 'protocol': 'freedom'}),
          ],
          write: (_) async {
            writes++;
            return const ConfigWriteResult(count: 1, ids: [1]);
          },
          schedule: (_) {},
        ),
      );
      addTearDown(controller.close);
      controller.text.text = 'vless://local';
      await tester.pumpWidget(_wizard(controller, (_) => completed = true));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste route'));
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Import links'),
      );
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(writes, 1);
      expect(find.byType(ServerImportPreviewPage), findsNothing);
      expect(find.byType(ServerImportFormPage), findsNothing);
      expect(find.text('Choose method'), findsNothing);
      expect(Navigator.of(tester.element(find.text('Open'))).canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'configuration preview Back and retry keep subscriptions; Cancel reports completed imports',
    (tester) async {
      var imported = 0;
      var writes = 0;
      ServerImportResult? result;
      final service = _ConfigurationImportService(
        subscribe: (_) async {
          imported++;
          return const SubscriptionInsertResult(
            status: SubscriptionUpdateResult.success,
            subId: 7,
            count: 2,
          );
        },
        write: (_) async {
          writes++;
          throw StateError('The user cancelled');
        },
      );
      final controller = ServerImportController(
        service: service,
        loadSubscription: (_) async => null,
      );
      addTearDown(controller.close);
      controller.text.text =
          'https://provider.example/list#Provider\n${_rawLink()}';
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<ServerImportResult>(
                  MaterialPageRoute(
                    builder: (_) => AppDialogFrame(
                      child: ServerImportFormPage(
                        controller: controller,
                        action: ServerImportAction.paste,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Import links'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ServerImportPreviewPage), findsOneWidget);
      expect(find.text('1 subscriptions imported.'), findsOneWidget);
      expect(imported, 1);
      expect(writes, 0);
      controller.closePage(
        tester.element(find.byType(ServerImportPreviewPage)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ServerImportFormPage), findsOneWidget);
      expect(result, isNull);
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Import links'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ServerImportPreviewPage), findsOneWidget);
      expect(imported, 1);
      await _tapVisible(tester, find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result?.count, 2);
      expect(result?.subscriptionCount, 1);
      expect(imported, 1);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing reuses the complete Age form and only saves metadata', (
    tester,
  ) async {
    SubscriptionInput? saved;
    int? savedId;
    int? routeResult;
    final saveCompletion = Completer<SubscriptionUpdateResult>();
    final controller = ServerImportController(
      subscriptionId: 7,
      loadSubscription: (_) async => SubscriptionData(
        panel: 'generic',
        mode: 'appManaged',
        id: 7,
        name: 'Provider',
        url: 'https://provider.example/list',
        userAgent: 'Example/old',
        ageSecretKey: 'secret',
        agePublicKey: 'public',
        hwidEnabled: true,
        hwid: 'saved-device-id',
        timestamp: DateTime(2026),
      ),
      saveSubscriptionInput: (id, input) async {
        savedId = id;
        saved = input;
        return saveCompletion.future;
      },
      modeAvailability: (_) async => const SubscriptionModeAvailability(
        count: 1,
        selectedCompatible: true,
      ),
    );
    addTearDown(controller.close);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              routeResult = await Navigator.of(context).push<int>(
                MaterialPageRoute(
                  builder: (_) => AppDialogFrame(
                    child: ServerImportFormPage(
                      controller: controller,
                      action: ServerImportAction.subscription,
                    ),
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await controller.loadSubscription(
      tester.element(find.byType(ServerImportFormPage)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionFormView), findsOneWidget);
    expect(
      find.text('Changes apply to future updates, not the running connection.'),
      findsOneWidget,
    );
    expect(controller.secretKey.text, 'secret');
    expect(controller.publicKey.text, 'public');
    expect(controller.userAgent.text, 'Example/old');
    expect(controller.state.hwidEnabled, isTrue);
    controller.toggleSecret();
    expect(controller.state.obscureSecret, false);
    controller.name.text = 'Renamed';
    controller.url.text = 'https://different.example/list';
    controller.userAgent.text = 'Example/new';
    expect(controller.state.hwidEnabled, isFalse);
    controller.setHwidEnabled(true);
    await _tapVisible(tester, find.text('Save'));
    await tester.pump();
    expect(find.text('Save'), findsOneWidget);
    expect(find.byType(ButtonProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester
          .widgetList<ShadInput>(find.byType(ShadInput))
          .every((input) => input.enabled),
      isTrue,
    );
    expect(controller.state.canClose, isFalse);
    controller.name.text = 'Another draft';
    expect(saved?.name, 'Renamed');
    saveCompletion.complete(SubscriptionUpdateResult.success);
    await tester.pumpAndSettle();
    expect(savedId, 7);
    expect(saved?.name, 'Renamed');
    expect(saved?.url, 'https://different.example/list');
    expect(saved?.userAgent, 'Example/new');
    expect(saved?.ageSecretKey, 'secret');
    expect(saved?.agePublicKey, 'public');
    expect(saved?.hwidEnabled, isTrue);
    expect(saved?.hwid, 'saved-device-id');
    expect(routeResult, 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading subscription preserves input and does not block closing',
    (tester) async {
      final loaded = Completer<SubscriptionData?>();
      final controller = ServerImportController(
        subscriptionId: 7,
        loadSubscription: (_) => loaded.future,
      );
      addTearDown(controller.close);
      await tester.pumpWidget(
        _app(
          ServerImportFormPage(
            controller: controller,
            action: ServerImportAction.subscription,
          ),
        ),
      );
      final pending = controller.loadSubscription(
        tester.element(find.byType(ServerImportFormPage)),
      );
      await tester.pump();
      expect(controller.state.canClose, isTrue);
      expect(controller.state.submitting, isFalse);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(ButtonProgressIndicator), findsNothing);
      controller.name.text = 'Typed while loading';
      loaded.complete(
        SubscriptionData(
          panel: 'generic',
          mode: 'appManaged',
          id: 7,
          name: 'Provider',
          hwidEnabled: false,
          url: 'https://provider.example/list',
          timestamp: DateTime(2026),
        ),
      );
      await pending;
      await tester.pumpAndSettle();
      expect(controller.name.text, 'Typed while loading');
      expect(controller.url.text, 'https://provider.example/list');
      expect(tester.takeException(), isNull);
    },
  );

  for (final exit in ['done', 'system', 'barrier']) {
    testWidgets(
      'partial local completion returns committed results without rewriting ($exit)',
      (tester) async {
        _mobileViewport(tester);
        var writes = 0;
        var downloads = 0;
        ServerImportResult? result;
        final service = ServerImportService(
          write: (rows) async {
            writes++;
            return ConfigWriteResult(count: rows.length, ids: [1]);
          },
          schedule: (_) {},
          writeGeoData: (_) async {
            downloads++;
            return false;
          },
        );
        final controller = ServerImportController(
          service: service,
          loadSubscription: (_) async => null,
        );
        addTearDown(controller.close);
        final preview = ServerImportPreview(
          [
            outboundCompanion({'tag': 'local', 'protocol': 'freedom'}),
          ],
          geoData: [
            const OneXrayGeoDataLink(
              name: 'Data source',
              type: GeoDataType.domain,
              url: 'https://data.example/list.dat',
            ),
          ],
        );
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showAppDialog<ServerImportResult>(
                    context,
                    (_) => ServerImportPreviewPage(
                      controller: controller,
                      preview: preview,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await _tapVisible(tester, find.text('Confirm add'));
        await tester.pumpAndSettle();
        expect(find.text('Servers added'), findsOneWidget);
        expect(find.text('Data source'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
        expect(controller.state.committedResult?.writeFailureCount, 1);
        if (exit == 'done') {
          await _tapVisible(tester, find.text('Done'));
        } else if (exit == 'system') {
          await Navigator.of(
            tester.element(find.byType(ServerImportPreviewPage)),
          ).maybePop();
        } else {
          await tester.tapAt(const Offset(5, 5));
        }
        await tester.pumpAndSettle();
        expect(find.byType(ServerImportPreviewPage), findsNothing);
        expect(result?.count, 1);
        expect(result?.writeFailureCount, 1);
        expect(writes, 1);
        expect(downloads, 1);
        expect(
          Navigator.of(tester.element(find.text('Open'))).canPop(),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'new subscription submits automatic or explicitly selected mode',
    (tester) async {
      for (final mode in [null, SubscriptionMode.providerManaged]) {
        SubscriptionInput? submitted;
        final controller = ServerImportController(
          loadSubscription: (_) async => null,
          insertSubscription: (input, {confirmOrdinary}) async {
            submitted = input;
            return const SubscriptionInsertResult(
              status: SubscriptionUpdateResult.success,
              subId: 8,
              count: 3,
            );
          },
        );
        controller.name.text = 'Provider';
        controller.url.text = 'https://example.test/subscription';
        controller.userAgent.text = 'Example/test';
        controller.setPanel(SubscriptionPanel.remnawave);
        controller.setMode(mode);
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppDialog<ServerImportResult>(
                  context,
                  (_) => ServerImportFormPage(
                    controller: controller,
                    action: ServerImportAction.subscription,
                  ),
                ),
                child: const Text('Add source'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Add source'));
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(ServerImportFormPage)),
        )!;
        await _tapVisible(tester, find.text(l.prototypeAddSubscription).last);
        await tester.pumpAndSettle();
        expect(submitted!.panel, SubscriptionPanel.remnawave);
        expect(submitted!.mode, mode);
        expect(submitted!.userAgent, 'Example/test');
        expect(find.byType(ServerImportFormPage), findsNothing);
        expect(tester.takeException(), isNull);
        await controller.close();
      }
    },
  );

  for (final approved in [false, true]) {
    testWidgets(
      'non-JSON subscription conversion can be ${approved ? "accepted" : "cancelled"}',
      (tester) async {
        var parsed = false;
        final controller = ServerImportController(
          loadSubscription: (_) async => null,
          insertSubscription: (input, {confirmOrdinary}) async {
            expect(confirmOrdinary, isNotNull);
            if (!await confirmOrdinary!(input.name)) {
              return const SubscriptionInsertResult(
                status: SubscriptionUpdateResult.invalidContent,
                error: AppFailure(FailureCategory.conflict, 'cancelled'),
              );
            }
            parsed = true;
            return const SubscriptionInsertResult(
              status: SubscriptionUpdateResult.success,
              subId: 8,
              count: 2,
            );
          },
        );
        addTearDown(controller.close);
        controller.name.text = 'Provider';
        controller.url.text = 'https://example.test/subscription';
        controller.userAgent.text = 'Custom/1.0';
        await controller.setPanel(SubscriptionPanel.remnawave);
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppDialog<ServerImportResult>(
                  context,
                  (_) => ServerImportFormPage(
                    controller: controller,
                    action: ServerImportAction.subscription,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final l = AppLocalizations.of(
          tester.element(find.byType(ServerImportFormPage)),
        )!;
        await _tapVisible(tester, find.text(l.prototypeAddSubscription).last);
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text(l.subscriptionRemnawaveFormatTitle), findsOneWidget);
        expect(
          find.text(l.subscriptionConvertToOrdinaryMessage('Provider')),
          findsOneWidget,
        );
        expect(parsed, isFalse);
        await tester.tap(
          find
              .text(approved ? l.subscriptionConvertToOrdinary : l.buttonCancel)
              .last,
        );
        await tester.pumpAndSettle();
        expect(parsed, approved);
        expect(controller.state.busy, isFalse);
        expect(controller.state.error, isNull);
        expect(
          find.byType(ServerImportFormPage),
          approved ? findsNothing : findsOneWidget,
        );
        if (!approved) {
          expect(controller.state.panel, SubscriptionPanel.remnawave);
          expect(controller.url.text, 'https://example.test/subscription');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'mode edit saves locally and reports refresh plus incompatible selection',
    (tester) async {
      SubscriptionInput? submitted;
      var downloads = 0;
      var availabilityReads = 0;
      final controller = ServerImportController(
        subscriptionId: 7,
        loadSubscription: (_) async => SubscriptionData(
          id: 7,
          name: 'Provider',
          url: 'https://example.test/subscription',
          panel: 'generic',
          mode: 'appManaged',
          hwidEnabled: false,
          timestamp: DateTime(2026),
        ),
        saveSubscriptionInput: (_, input) async {
          submitted = input;
          return SubscriptionUpdateResult.success;
        },
        insertSubscription: (_, {confirmOrdinary}) async {
          downloads++;
          throw StateError('Editing must not import or download');
        },
        modeAvailability: (_) async {
          availabilityReads++;
          return const SubscriptionModeAvailability(
            count: 0,
            selectedCompatible: false,
          );
        },
      );
      addTearDown(controller.close);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await controller.loadSubscription(context);
                if (!context.mounted) return;
                await showAppDialog<int>(
                  context,
                  (_) => ServerImportFormPage(
                    controller: controller,
                    action: ServerImportAction.subscription,
                  ),
                );
              },
              child: const Text('Edit source'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit source'));
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(ServerImportFormPage)),
      )!;
      expect(controller.state.mode, SubscriptionMode.appManaged);
      final selector = find.byKey(const ValueKey('subscription-mode'));
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text(l.subscriptionModeAutomatic), findsNothing);
      await tester.tap(find.text(l.subscriptionModeProviderManaged));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text(l.prototypeSave));
      await tester.pumpAndSettle();
      expect(submitted!.mode, SubscriptionMode.providerManaged);
      expect(downloads, 0);
      expect(availabilityReads, 1);
      expect(find.byType(ServerImportFormPage), findsNothing);
      expect(
        find.textContaining(l.subscriptionModeNeedsRefresh),
        findsOneWidget,
      );
      expect(
        find.textContaining(l.subscriptionModeNeedsReselection),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

String _rawLink() => Uri(
  scheme: 'onexray',
  host: 'onexray.com',
  path: '/config/add',
  fragment: 'Expert',
  queryParameters: {
    'type': 'raw',
    'data': base64Encode(
      utf8.encode('{"name":"Expert","outbounds":[{"protocol":"freedom"}]}'),
    ),
  },
).toString();

// Configuration parsing is covered by service tests. Keep this navigation test
// independent of the process-wide Geodata file queue and its async zone.
class _ConfigurationImportService extends ServerImportService {
  _ConfigurationImportService({super.subscribe, super.write});

  @override
  Future<ServerImportPreview> previewDetected(
    ServerImportDetection detection,
  ) async => ServerImportPreview(
    [],
    raw: [
      XrayRawValidator.normalize(
        '{"name":"Expert","outbounds":[{"protocol":"freedom"}]}',
      ),
    ],
  );
}

void _mobileViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

Widget _wizard(
  ServerImportController controller,
  ValueChanged<ServerImportResult?> onResult,
) => _app(
  Builder(
    builder: (context) => TextButton(
      onPressed: () async {
        onResult(
          await showAppDialog<ServerImportResult>(
            context,
            (dialogContext) => AppDialog(
              title: 'Choose method',
              body: TextButton(
                onPressed: () =>
                    controller.open(dialogContext, ServerImportAction.paste),
                child: const Text('Paste route'),
              ),
            ),
          ),
        );
      },
      child: const Text('Open'),
    ),
  ),
);

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  builder: (_, child) => ShadTheme(
    data: AppTheme.shad(Brightness.light),
    child: ShadToaster(child: child!),
  ),
  home: Scaffold(body: child),
);

class _SubscriptionFilePicker extends FilePickerPlatform {
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => _SubscriptionFile();
}

base class _SubscriptionFile extends PlatformFile {
  @override
  String get path => File('test/pages/servers/fixtures/sub.txt').absolute.path;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
