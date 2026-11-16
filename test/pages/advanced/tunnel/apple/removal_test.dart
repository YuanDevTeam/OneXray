import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/pages/advanced/tunnel/page.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/advanced/tunnel/apple/removal.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadTheme, ShadToaster;

final _entry = find.byKey(const ValueKey('tunnel-remove-apple-vpn'));

class _Removal extends AppleVpnRemovalService {
  _Removal(ConnectionCoordinator coordinator) : super(coordinator: coordinator);

  bool systemExtension = false;
  Object? editionError;
  Object? removalError;
  Future<AppleVpnRemovalResult>? pendingResult;
  AppleVpnRemovalResult result = AppleVpnRemovalResult.removed;
  int editionQueries = 0;
  int removals = 0;

  @override
  Future<bool> useSystemExtension() async {
    editionQueries++;
    if (editionError case final error?) throw error;
    return systemExtension;
  }

  @override
  Future<AppleVpnRemovalResult> remove() async {
    removals++;
    if (removalError case final error?) throw error;
    final pending = pendingResult;
    return pending == null ? result : await pending;
  }
}

class _PolicyService extends PolicyEditorService {
  _PolicyService(ConnectionCoordinator coordinator, ConnectionPlatform platform)
    : super(coordinator: coordinator, platform: platform);

  final configuration = ConnectionConfiguration();
  int loads = 0;
  int saves = 0;

  @override
  Future<PolicyEditorDraft> load() async {
    loads++;
    return PolicyEditorDraft(configuration);
  }

  @override
  Future<bool> save({
    required PolicyEditorDraft draft,
    required Future<bool> Function(bool disconnect) confirm,
  }) async {
    saves++;
    return true;
  }
}

({PolicyEditorController controller, _Removal removal, _PolicyService policy})
_fixture(ConnectionPlatform platform) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final coordinator = ConnectionCoordinator(
    database: db,
    statusEvents: const Stream.empty(),
  );
  final removal = _Removal(coordinator);
  final policy = _PolicyService(coordinator, platform);
  final controller = PolicyEditorController(
    draft: PolicyEditorDraft(policy.configuration),
    service: policy,
    appleVpnRemoval: removal,
  );
  addTearDown(() async {
    await controller.close();
    coordinator.dispose();
    await db.close();
  });
  return (controller: controller, removal: removal, policy: policy);
}

Future<AppLocalizations> _mount(
  WidgetTester tester,
  PolicyEditorController controller, {
  Locale locale = const Locale('en'),
  Size size = const Size(900, 1000),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: ShadTheme(
          data: AppTheme.shad(Brightness.light),
          child: ShadToaster(child: child!),
        ),
      ),
      home: VpnTunnelPane(createController: () => controller),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(VpnTunnelPane)))!;
}

Future<void> _openConfirmation(WidgetTester tester) async {
  await tester.ensureVisible(_entry);
  await tester.pumpAndSettle();
  await tester.tap(_entry);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _confirm(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final (platform, extension) in [
    (ConnectionPlatform.ios, false),
    (ConnectionPlatform.macos, false),
    (ConnectionPlatform.macos, true),
  ]) {
    testWidgets('root removal label matches $platform extension=$extension', (
      tester,
    ) async {
      final fixture = _fixture(platform);
      fixture.removal.systemExtension = extension;
      final l = await _mount(tester, fixture.controller);
      expect(_entry, findsOneWidget);
      final row = tester.widget<SettingRow>(_entry);
      expect(
        row.title,
        extension
            ? l.tunnelUninstallSystemExtension
            : l.tunnelDeleteVpnConfiguration,
      );
      expect(
        (row.leading! as Icon).icon,
        extension ? LucideIcons.packageMinus : LucideIcons.trash2,
      );
      expect(row.subtitle, isNull);
      expect(
        fixture.removal.editionQueries,
        platform == ConnectionPlatform.ios ? 0 : 1,
      );
      expect(fixture.removal.removals, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [
    ConnectionPlatform.android,
    ConnectionPlatform.windows,
    ConnectionPlatform.linux,
  ]) {
    testWidgets('no Apple removal entry or native query on $platform', (
      tester,
    ) async {
      final fixture = _fixture(platform);
      await _mount(tester, fixture.controller);
      expect(_entry, findsNothing);
      expect(
        find.byKey(const ValueKey('tunnel-apple-vpn-removal')),
        findsNothing,
      );
      expect(fixture.removal.editionQueries, 0);
      expect(fixture.removal.removals, 0);
    });
  }

  testWidgets('cancelling confirms no removal and preserves unsaved policy', (
    tester,
  ) async {
    final fixture = _fixture(ConnectionPlatform.ios);
    fixture.controller.update('dnsIpv4Address', '2.2.2.2');
    final draftBefore = jsonEncode(fixture.controller.value);
    final savedBefore = fixture.policy.configuration.encode();
    final l = await _mount(tester, fixture.controller);
    await _openConfirmation(tester);
    final dialog = tester.widget<AppConfirmationDialog>(
      find.byType(AppConfirmationDialog),
    );
    expect(dialog.content, l.tunnelDeleteVpnConfigurationConfirmation);
    expect(dialog.destructive, isTrue);
    expect(dialog.barrierDismissible, isFalse);
    expect(fixture.controller.blocked, isTrue);
    expect(tester.widget<SettingRow>(_entry).onTap, isNull);
    await tester.tap(
      find.descendant(
        of: find.byType(AppConfirmationDialog),
        matching: find.widgetWithText(OutlinedButton, l.prototypeCancel),
      ),
    );
    await tester.pumpAndSettle();
    expect(fixture.controller.blocked, isFalse);
    expect(fixture.removal.removals, 0);
    expect(fixture.policy.loads, 0);
    expect(fixture.policy.saves, 0);
    expect(jsonEncode(fixture.controller.value), draftBefore);
    expect(fixture.policy.configuration.encode(), savedBefore);
    expect(find.text(l.tunnelVpnConfigurationRemoved), findsNothing);
  });

  for (final extension in [false, true]) {
    testWidgets(
      'confirmed removal shows correct success: extension=$extension',
      (tester) async {
        final fixture = _fixture(ConnectionPlatform.macos);
        fixture.removal.systemExtension = extension;
        fixture.controller.update('dnsIpv4Address', '2.2.2.2');
        final draftBefore = jsonEncode(fixture.controller.value);
        final l = await _mount(tester, fixture.controller);
        await _openConfirmation(tester);
        expect(
          tester
              .widget<AppConfirmationDialog>(find.byType(AppConfirmationDialog))
              .content,
          extension
              ? l.tunnelUninstallSystemExtensionConfirmation
              : l.tunnelDeleteVpnConfigurationConfirmation,
        );
        await _confirm(
          tester,
          extension
              ? l.tunnelUninstallSystemExtension
              : l.tunnelDeleteVpnConfiguration,
        );
        await tester.pumpAndSettle();
        expect(fixture.removal.removals, 1);
        expect(
          find.text(
            extension
                ? l.tunnelSystemExtensionRemoved
                : l.tunnelVpnConfigurationRemoved,
          ),
          findsOneWidget,
        );
        expect(
          fixture.controller.state.appleVpnRemovalRestartRequired,
          isFalse,
        );
        expect(fixture.controller.blocked, isFalse);
        expect(fixture.policy.loads, 0);
        expect(fixture.policy.saves, 0);
        expect(jsonEncode(fixture.controller.value), draftBefore);
      },
    );
  }

  testWidgets('restart required stays visible after the toast expires', (
    tester,
  ) async {
    final fixture = _fixture(ConnectionPlatform.macos);
    fixture.removal.systemExtension = true;
    fixture.removal.result = AppleVpnRemovalResult.restartRequired;
    final l = await _mount(tester, fixture.controller);
    await _openConfirmation(tester);
    await _confirm(tester, l.tunnelUninstallSystemExtension);
    await tester.pumpAndSettle();
    expect(fixture.controller.state.appleVpnRemovalRestartRequired, isTrue);
    expect(find.text(l.tunnelSystemExtensionRemoved), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tunnel-apple-vpn-restart-required')),
      findsOneWidget,
    );
    expect(find.text(l.tunnelSystemExtensionRestartRequired), findsOneWidget);
    expect(tester.widget<SettingRow>(_entry).onTap, isNull);
    fixture.controller.update('dnsIpv4Address', '2.2.2.2');
    await tester.pumpAndSettle();
    expect(find.text(l.tunnelSystemExtensionRestartRequired), findsOneWidget);
  });

  testWidgets('native failure exposes real details without a success toast', (
    tester,
  ) async {
    final fixture = _fixture(ConnectionPlatform.macos);
    fixture.removal.systemExtension = true;
    fixture.removal.removalError = PlatformException(
      code: 'removeFailed',
      message: 'Permission denied by macOS',
    );
    fixture.controller.update('dnsIpv4Address', '2.2.2.2');
    final draftBefore = jsonEncode(fixture.controller.value);
    final l = await _mount(tester, fixture.controller);
    await _openConfirmation(tester);
    await _confirm(tester, l.tunnelUninstallSystemExtension);
    await tester.pumpAndSettle();
    expect(find.textContaining('Permission denied by macOS'), findsOneWidget);
    expect(find.textContaining(l.tunnelVpnRemovalFailed), findsOneWidget);
    expect(find.text(l.tunnelSystemExtensionRemoved), findsNothing);
    expect(fixture.controller.state.appleVpnRemovalRestartRequired, isFalse);
    expect(tester.widget<SettingRow>(_entry).onTap, isNotNull);
    expect(jsonEncode(fixture.controller.value), draftBefore);
    expect(fixture.policy.saves, 0);
  });

  testWidgets('Persian SE confirmation and restart notice fit a scaled phone', (
    tester,
  ) async {
    final fixture = _fixture(ConnectionPlatform.macos);
    fixture.removal.systemExtension = true;
    fixture.removal.result = AppleVpnRemovalResult.restartRequired;
    const size = Size(360, 780);
    final l = await _mount(
      tester,
      fixture.controller,
      locale: const Locale('fa'),
      size: size,
      textScale: 1.4,
    );
    expect(Directionality.of(tester.element(_entry)), TextDirection.rtl);
    await _openConfirmation(tester);
    final dialog = find.byType(AppConfirmationDialog);
    expect(Directionality.of(tester.element(dialog)), TextDirection.rtl);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(l.tunnelUninstallSystemExtensionConfirmation),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final confirm = find.descendant(
      of: dialog,
      matching: find.widgetWithText(
        FilledButton,
        l.tunnelUninstallSystemExtension,
      ),
    );
    await tester.ensureVisible(confirm);
    await tester.pump();
    expect(confirm.hitTestable(), findsOneWidget);
    await _confirm(tester, l.tunnelUninstallSystemExtension);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final notice = find.byKey(
      const ValueKey('tunnel-apple-vpn-restart-required'),
    );
    await tester.ensureVisible(notice);
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(notice)), TextDirection.rtl);
    expect(find.text(l.tunnelSystemExtensionRestartRequired), findsOneWidget);
    final rect = tester.getRect(notice);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(size.width));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(size.height));
    expect(fixture.removal.removals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Russian SE confirmation and native error fit a short window', (
    tester,
  ) async {
    final fixture = _fixture(ConnectionPlatform.macos);
    fixture.removal.systemExtension = true;
    fixture.removal.removalError = PlatformException(
      code: 'removeFailed',
      message: 'macOS: не удалось получить разрешение администратора.',
    );
    const size = Size(940, 430);
    final l = await _mount(
      tester,
      fixture.controller,
      locale: const Locale('ru'),
      size: size,
    );
    expect(Directionality.of(tester.element(_entry)), TextDirection.ltr);
    await _openConfirmation(tester);
    final dialog = find.byType(AppConfirmationDialog);
    expect(Directionality.of(tester.element(dialog)), TextDirection.ltr);
    expect(
      tester.widget<AppConfirmationDialog>(dialog).content,
      l.tunnelUninstallSystemExtensionConfirmation,
    );
    expect(tester.takeException(), isNull);
    final confirm = find.descendant(
      of: dialog,
      matching: find.widgetWithText(
        FilledButton,
        l.tunnelUninstallSystemExtension,
      ),
    );
    await tester.ensureVisible(confirm);
    await tester.pump();
    expect(confirm.hitTestable(), findsOneWidget);
    await _confirm(tester, l.tunnelUninstallSystemExtension);
    await tester.pumpAndSettle();
    final error = find.byKey(const ValueKey('tunnel-apple-vpn-removal-error'));
    await tester.ensureVisible(error);
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(error)), TextDirection.ltr);
    expect(find.textContaining(l.tunnelVpnRemovalFailed), findsOneWidget);
    expect(
      find.textContaining('не удалось получить разрешение администратора'),
      findsOneWidget,
    );
    final rect = tester.getRect(error);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(size.width));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(size.height));
    expect(fixture.removal.removals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unknown macOS edition offers retry without guessing the action',
    (tester) async {
      final fixture = _fixture(ConnectionPlatform.macos);
      fixture.removal.editionError = StateError('Edition query unavailable');
      final l = await _mount(tester, fixture.controller);
      expect(_entry, findsNothing);
      expect(find.textContaining('Edition query unavailable'), findsOneWidget);
      expect(find.text(l.tunnelDeleteVpnConfiguration), findsNothing);
      fixture.removal.editionError = null;
      fixture.removal.systemExtension = true;
      final retry = find.byKey(
        const ValueKey('tunnel-apple-vpn-removal-edition'),
      );
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(fixture.removal.editionQueries, 2);
      expect(
        tester.widget<SettingRow>(_entry).title,
        l.tunnelUninstallSystemExtension,
      );
      expect(find.textContaining('Edition query unavailable'), findsNothing);
    },
  );

  testWidgets('pending removal rejects duplicates, edits, reset and save', (
    tester,
  ) async {
    final fixture = _fixture(ConnectionPlatform.ios);
    final completion = Completer<AppleVpnRemovalResult>();
    fixture.removal.pendingResult = completion.future;
    fixture.controller.update('dnsIpv4Address', '2.2.2.2');
    final draftBefore = jsonEncode(fixture.controller.value);
    final l = await _mount(tester, fixture.controller);
    await _openConfirmation(tester);
    await _confirm(tester, l.tunnelDeleteVpnConfiguration);
    expect(fixture.removal.removals, 1);
    expect(fixture.controller.state.appleVpnRemovalBusy, isTrue);
    final context = tester.element(_entry);
    await fixture.controller.removeAppleVpn(context);
    fixture.controller.update('dnsIpv4Address', '9.9.9.9');
    fixture.controller.restoreDefaults();
    expect(await fixture.controller.save(context, pop: false), isFalse);
    expect(fixture.removal.removals, 1);
    expect(fixture.policy.saves, 0);
    expect(jsonEncode(fixture.controller.value), draftBefore);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('tunnel-restore-defaults')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, l.prototypeSave),
          )
          .onPressed,
      isNull,
    );
    completion.complete(AppleVpnRemovalResult.removed);
    await tester.pumpAndSettle();
    expect(fixture.controller.state.appleVpnRemovalBusy, isFalse);
    expect(tester.widget<SettingRow>(_entry).onTap, isNotNull);
    expect(jsonEncode(fixture.controller.value), draftBefore);
  });
}
