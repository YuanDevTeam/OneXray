import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/local_api/controller.dart';
import 'package:onexray/pages/advanced/local_api/page.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/main/url.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/advanced/xray/fields.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/local_api/settings.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _secret = 'secret-must-never-appear-in-the-page';
const _newSecret = 'replacement-secret-for-the-client';
const _port = ValueKey('local-api-port');
const _save = ValueKey('local-api-save');
const _copy = ValueKey('local-api-copy-token');
const _reset = ValueKey('local-api-reset-token');

class _Api {
  LocalApiSettings saved;
  bool listening = false;
  String? lastError;
  Completer<LocalApiSettings>? saveResult;
  Completer<LocalApiSettings>? resetResult;
  int saveCalls = 0;
  int? submittedPort;
  bool? submittedEnabled;
  String? copied;

  _Api({this.saved = const LocalApiSettings(token: _secret)});

  LocalApiController controller() => LocalApiController(
    loadSettings: () async => saved,
    configure: ({required enabled, required port}) async {
      saveCalls++;
      submittedEnabled = enabled;
      submittedPort = port;
      final result = saveResult;
      if (result != null) return saved = await result.future;
      listening = enabled;
      return saved = LocalApiSettings(
        enabled: enabled,
        port: port,
        token: saved.token,
      );
    },
    resetToken: () async {
      final result = resetResult;
      if (result != null) return saved = await result.future;
      return saved = LocalApiSettings(
        enabled: saved.enabled,
        port: saved.port,
        token: _newSecret,
      );
    },
    listening: () => listening,
    lastError: () => lastError,
    copyToken: (value) async {
      copied = value;
    },
  );
}

Widget _app(_Api api, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: AppTheme.light,
  locale: locale,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => ShadTheme(
    data: AppTheme.shad(Brightness.light),
    child: ShadToaster(child: child!),
  ),
  home: LocalApiPage(createController: api.controller),
);

void _viewport(WidgetTester tester, [Size size = const Size(1160, 950)]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  test('local API routes exist only on desktop within the shared registry', () {
    final desktop = buildScopedPageRoutes(desktop: true);
    final mobile = buildScopedPageRoutes(desktop: false);
    final segment = AppPageDestination.localApi.segment;
    expect(desktop.where((route) => route.path == segment), hasLength(1));
    expect(mobile.where((route) => route.path == segment), isEmpty);
    expect(
      mobile.where((route) => route.path == AppPageDestination.ping.segment),
      hasLength(1),
    );
  });

  testWidgets('disabled settings do not expose an ungenerated token', (
    tester,
  ) async {
    _viewport(tester);
    final api = _Api(saved: const LocalApiSettings());
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(_port)).controller!.text,
      '18587',
    );
    expect(find.text('http://127.0.0.1:18587'), findsOneWidget);
    expect(find.text('Not listening'), findsOneWidget);
    final enable = find.byType(XrayToggleField);
    final l = AppLocalizations.of(tester.element(enable))!;
    expect(
      tester.widget<XrayToggleField>(enable).description,
      l.localApiAppRequired,
    );
    final title = find.descendant(
      of: enable,
      matching: find.text(l.localApiEnable),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('local-api-enabled'))).dx,
      lessThan(tester.getCenter(title).dx),
    );
    final authorization = find.byWidgetPredicate(
      (widget) => widget is SettingSection && widget.title == l.localApiToken,
    );
    expect(
      find.descendant(
        of: authorization,
        matching: find.text(l.localApiTokenHint),
      ),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(find.byKey(_copy)).onPressed, isNull);
    expect(api.saveCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save is bounded by progress and reports actual listening', (
    tester,
  ) async {
    _viewport(tester);
    final api = _Api()..saveResult = Completer<LocalApiSettings>();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('local-api-enabled')));
    await tester.enterText(find.byKey(_port), '19587');
    await tester.tap(find.byKey(_save));
    await tester.pump();

    expect(api.submittedEnabled, isTrue);
    expect(api.submittedPort, 19587);
    expect(find.byType(ButtonProgressIndicator), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(_port)).enabled, isFalse);
    expect(tester.widget<OutlinedButton>(find.byKey(_reset)).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.byKey(_save)).onPressed, isNull);
    expect(find.text('Settings saved'), findsNothing);

    api.listening = true;
    api.saveResult!.complete(
      const LocalApiSettings(enabled: true, port: 19587, token: _secret),
    );
    await tester.pumpAndSettle();
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('http://127.0.0.1:19587'), findsOneWidget);
    expect(find.text('Settings saved'), findsOneWidget);
    expect(find.text(_secret), findsNothing);
    expect(find.byType(ButtonProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('binding failure preserves draft and does not claim success', (
    tester,
  ) async {
    _viewport(tester);
    final api = _Api()..saveResult = Completer<LocalApiSettings>();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_port), '19588');
    await tester.tap(find.byKey(_save));
    await tester.pump();
    api.lastError = 'Address is already in use';
    api.saveResult!.completeError(StateError('Address is already in use'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(_port)).controller!.text,
      '19588',
    );
    expect(find.text('http://127.0.0.1:18587'), findsOneWidget);
    expect(find.text('Not listening'), findsOneWidget);
    expect(find.text('Address is already in use'), findsWidgets);
    expect(find.text('Settings saved'), findsNothing);
    expect(find.byType(ButtonProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid port does not submit a configure request', (
    tester,
  ) async {
    _viewport(tester);
    final api = _Api();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    for (final input in ['1023', '65536', 'invalid']) {
      await tester.enterText(find.byKey(_port), input);
      await tester.tap(find.byKey(_save));
      await tester.pumpAndSettle();
      expect(api.saveCalls, 0);
      expect(find.text('Enter a port between 1024 and 65535.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(_port)).controller!.text,
        input,
      );
    }
  });

  testWidgets('reset updates the copied token and preserves other drafts', (
    tester,
  ) async {
    _viewport(tester);
    final api = _Api()..resetResult = Completer<LocalApiSettings>();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('local-api-enabled')));
    await tester.enterText(find.byKey(_port), '19589');
    await tester.ensureVisible(find.byKey(_reset));
    await tester.tap(find.byKey(_reset));
    await tester.pump();
    expect(find.byType(ButtonProgressIndicator), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(_copy)).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.byKey(_save)).onPressed, isNull);

    api.resetResult!.complete(const LocalApiSettings(token: _newSecret));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(_port)).controller!.text,
      '19589',
    );
    expect(tester.widget<ShadSwitch>(find.byType(ShadSwitch)).value, isTrue);
    expect(find.text(_secret), findsNothing);
    expect(find.text(_newSecret), findsNothing);
    await tester.ensureVisible(find.byKey(_copy));
    await tester.tap(find.byKey(_copy));
    await tester.pumpAndSettle();
    expect(api.copied, _newSecret);
    expect(find.text('Access token copied'), findsOneWidget);
    expect(api.saveCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabled preferences never stand in for listener status', (
    tester,
  ) async {
    _viewport(tester);
    final api = _Api(
      saved: const LocalApiSettings(enabled: true, token: _secret),
    )..lastError = 'Listener failed ($_secret)';
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('Not listening'), findsOneWidget);
    expect(find.text('Listener failed ([redacted])'), findsOneWidget);
    expect(find.textContaining(_secret), findsNothing);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('compact desktop settings fit ${locale.toLanguageTag()}', (
      tester,
    ) async {
      _viewport(tester, const Size(430, 900));
      await tester.pumpWidget(_app(_Api(), locale: locale));
      await tester.pumpAndSettle();
      expect(find.byType(PageActionBar), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('local-api-endpoint')),
            )
            .textDirection,
        TextDirection.ltr,
      );
      expect(
        tester.widget<TextField>(find.byKey(_port)).textDirection,
        TextDirection.ltr,
      );
      await tester.ensureVisible(find.byKey(_reset));
      await tester.pumpAndSettle();
      expect(find.text(_secret), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
