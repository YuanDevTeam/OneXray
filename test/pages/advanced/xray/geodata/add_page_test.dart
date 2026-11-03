import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/geodata/add.dart';
import 'package:onexray/pages/advanced/xray/geodata/controller.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Finder _input(String name) => find.descendant(
  of: find.byKey(ValueKey('geodata-source-$name')),
  matching: find.byType(EditableText),
);

Future<AppLocalizations> _mount(
  WidgetTester tester,
  GeoDataController controller, {
  ValueChanged<bool?>? returned,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 640);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.material(Brightness.light, mobile: true),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalePolicy.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => ShadTheme(
        data: AppTheme.shad(Brightness.light, mobile: true),
        child: ShadToaster(child: child!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const Key('open-geodata-add'),
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) =>
                      GeoDataAddPage(createController: () => controller),
                ),
              );
              returned?.call(saved);
            },
            child: const Text('Open source form'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-geodata-add')));
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(GeoDataAddPage)))!;
}

Future<void> _fill(WidgetTester tester, String url) async {
  await tester.enterText(_input('name'), 'custom-routing');
  await tester.ensureVisible(_input('url'));
  await tester.pumpAndSettle();
  await tester.enterText(_input('url'), url);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final bus = AppEventBus();
    addTearDown(bus.close);
  });
  testWidgets(
    'source form keeps the real HTTPS validation and cancellation is not a save',
    (tester) async {
      final controller = GeoDataController();
      addTearDown(controller.close);
      var returned = false;
      final l = await _mount(
        tester,
        controller,
        returned: (value) => returned = value == true,
      );
      await _fill(tester, 'http://example.test/custom.dat');
      await tester.tap(find.byKey(const ValueKey('geodata-source-add')));
      await tester.pumpAndSettle();
      expect(controller.state.formError, isNotNull);
      expect(find.text(controller.state.formError!), findsOneWidget);
      expect(controller.name.text, 'custom-routing');
      expect(controller.url.text, 'http://example.test/custom.dat');
      expect(controller.state.formBusy, isFalse);
      expect(find.byType(GeoDataAddPage), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, l.prototypeCancel));
      await tester.pumpAndSettle();
      expect(find.byType(GeoDataAddPage), findsNothing);
      expect(returned, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source form waits for add, retains a failure and returns true only after success',
    (tester) async {
      final controller = _ControlledAdd();
      addTearDown(controller.close);
      bool? returned;
      final l = await _mount(
        tester,
        controller,
        returned: (value) => returned = value,
      );
      await _fill(tester, 'https://example.test/custom.dat');
      final add = find.byKey(const ValueKey('geodata-source-add'));
      await tester.tap(add);
      await tester.pump();
      expect(controller.submitted!.fileName, 'custom-routing');
      expect(controller.submitted!.url, 'https://example.test/custom.dat');
      expect(tester.widget<FilledButton>(add).onPressed, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, l.prototypeCancel),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(find.byType(GeoDataAddPage), findsOneWidget);
      controller.result.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('source-download-failed'), findsOneWidget);
      expect(controller.name.text, 'custom-routing');
      expect(controller.url.text, 'https://example.test/custom.dat');
      expect(find.byType(GeoDataAddPage), findsOneWidget);
      controller.result = Completer<bool>();
      await tester.tap(add);
      await tester.pump();
      controller.result.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(GeoDataAddPage), findsNothing);
      expect(returned, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

/// Only the completion boundary is controlled here; the first test exercises
/// the production controller's HTTPS validation before any database access.
class _ControlledAdd extends GeoDataController {
  Completer<bool> result = Completer<bool>();
  GeoDataInput? submitted;
  @override
  Future<void> add(BuildContext context) async {
    if (state.formBusy) return;
    submitted = GeoDataInput(
      fileName: name.text,
      type: state.type,
      url: url.text,
    );
    emit(state.copyWith(formBusy: true, clearFormError: true));
    final saved = await result.future;
    if (saved) {
      name.clear();
      url.clear();
    }
    emit(
      state.copyWith(
        formBusy: false,
        adding: !saved,
        formError: saved ? null : 'source-download-failed',
        clearFormError: saved,
      ),
    );
  }
}
