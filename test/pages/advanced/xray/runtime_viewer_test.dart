import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/pages/advanced/xray/config/controller.dart';
import 'package:onexray/pages/advanced/xray/config/page.dart';
import 'package:onexray/pages/advanced/xray/config/params.dart';
import 'package:onexray/pages/advanced/xray/log/controller.dart';
import 'package:onexray/pages/advanced/xray/log/page.dart';
import 'package:onexray/pages/advanced/xray/runtime_code_view.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';

const _panel = ValueKey('runtime-code-panel');
const _logLines = ValueKey('runtime-log-lines');
const _configScroll = ValueKey('runtime-config-code-scroll');
const _originalJson = ' {"log":{"loglevel":"warning"},"inbounds":[]} ';

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  bool mobile = true,
}) => MaterialApp(
  theme: AppTheme.material(Brightness.light, mobile: mobile),
  locale: locale,
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(padding: const EdgeInsets.only(bottom: 24)),
    child: child!,
  ),
  home: child,
);

void _viewport(WidgetTester tester, {Size size = const Size(427, 900)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

AppLocalizations _strings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(RuntimeCodeScaffold)))!;

void main() {
  testWidgets(
    'desktop runtime viewers use the shared content width and top spacing',
    (tester) async {
      _viewport(tester, size: const Size(1160, 688));
      for (final view in [
        LogFileViewerView(
          state: const LogFileViewerPageState(
            title: 'Access log',
            fileExists: true,
            lines: ['Desktop log line'],
          ),
          onExport: () {},
          onFollowTail: (_) {},
        ),
        ConfigFileViewerView(
          state: const ConfigFileViewerPageState(
            title: 'Runtime JSON',
            text: _originalJson,
            loading: false,
          ),
          onExport: () {},
        ),
      ]) {
        await tester.pumpWidget(_app(view, mobile: false));
        await tester.pumpAndSettle();
        final panel = tester.getRect(find.byKey(_panel));
        final export = tester.getRect(find.byType(OutlinedButton));
        final gutter = AppSpacing.advancedDesktopGutter(1160);
        expect(
          panel.left,
          closeTo((1160 - AppLayout.advancedMaxWidth) / 2 + gutter, .01),
        );
        expect(
          panel.width,
          closeTo(AppLayout.advancedMaxWidth - gutter * 2, .01),
        );
        expect(
          export.top,
          closeTo(tester.getRect(find.byType(PageAppBar)).bottom + 20, .01),
        );
        expect(export.bottom + 12, closeTo(panel.top, .01));
        expect(panel.height, greaterThanOrEqualTo(420));
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final locale in const [
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'TW'),
    Locale('ru'),
    Locale('fa'),
  ]) {
    testWidgets('log/config share bounded mobile presentation in $locale', (
      tester,
    ) async {
      _viewport(tester);
      await tester.pumpWidget(
        _app(
          LogFileViewerView(
            state: const LogFileViewerPageState(
              title: 'access.log',
              fileExists: true,
              lines: ['first line', 'second line'],
            ),
            onExport: () {},
            onFollowTail: (_) {},
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      var l = _strings(tester);
      final panel = tester.getRect(find.byKey(_panel));
      final export = find.widgetWithText(OutlinedButton, l.prototypeExport);
      expect(
        tester.getSize(export).height,
        greaterThanOrEqualTo(AppLayout.touchExtent(48)),
      );
      expect(tester.getRect(export).left, AppSpacing.mobilePage);
      expect(panel.width, 427 - AppSpacing.mobilePage * 2);
      expect(panel.height, greaterThanOrEqualTo(470));
      expect(
        tester.getRect(find.text(l.prototypeFollowing)).top,
        lessThan(tester.getRect(export).top),
      );
      expect(tester.getRect(export).bottom + 12, closeTo(panel.top, .01));
      expect(
        tester.getRect(find.text(l.prototypeLocalLogNotice)).top,
        greaterThanOrEqualTo(panel.bottom + 12),
      );
      final line = tester.widget<Text>(find.text('first line'));
      expect(line.textDirection, TextDirection.ltr);
      expect(line.style!.fontSize, 13);
      expect(line.style!.height, 1.45);
      expect(
        tester.widget<PageAppBar>(find.byType(PageAppBar)).actions ??
            const <Widget>[],
        isEmpty,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _app(
          ConfigFileViewerView(
            state: const ConfigFileViewerPageState(
              title: 'Runtime JSON',
              text: _originalJson,
              loading: false,
            ),
            onExport: () {},
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      l = _strings(tester);
      expect(find.text(l.prototypeReadOnly), findsOneWidget);
      expect(
        find.widgetWithText(
          OutlinedButton,
          l.prototypeExportOriginalConfiguration,
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.text(_originalJson)).textDirection,
        TextDirection.ltr,
      );
      expect(
        tester.getSize(find.byKey(_panel)).height,
        greaterThanOrEqualTo(470),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final (platform, minimum) in [
    (TargetPlatform.iOS, 44.0),
    (TargetPlatform.android, 48.0),
  ]) {
    testWidgets(
      'runtime viewer actions retain $minimum touch targets on a wide $platform window',
      (tester) async {
        _viewport(tester, size: const Size(956, 500));
        var exports = 0;
        var resumes = 0;
        await tester.pumpWidget(
          _app(
            RuntimeCodeScaffold(
              title: 'Runtime diagnostics',
              status: 'Resume following',
              exportLabel: 'Export',
              note: 'Read only',
              code: const SizedBox.shrink(),
              onExport: () => exports++,
              onStatusPressed: () => resumes++,
            ),
            mobile: false,
          ),
        );
        await tester.pumpAndSettle();
        final export = find.widgetWithText(OutlinedButton, 'Export');
        final resume = find
            .ancestor(
              of: find.text('Resume following'),
              matching: find.byType(InkWell),
            )
            .first;
        for (final control in [export, resume]) {
          expect(tester.getSize(control).width, greaterThanOrEqualTo(minimum));
          expect(tester.getSize(control).height, greaterThanOrEqualTo(minimum));
          await tester.tapAt(
            tester.getRect(control).bottomCenter - const Offset(0, 2),
          );
          await tester.pumpAndSettle();
        }
        expect(exports, 1);
        expect(resumes, 1);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets(
    'missing and empty logs remain distinct; exporting disables only export',
    (tester) async {
      _viewport(tester);
      for (final state in const [
        LogFileViewerPageState(title: 'error.log'),
        LogFileViewerPageState(title: 'error.log', fileExists: true),
        LogFileViewerPageState(
          title: 'error.log',
          fileExists: true,
          exporting: true,
        ),
        LogFileViewerPageState(
          title: 'error.log',
          fileExists: true,
          truncated: true,
          followTail: false,
          lines: ['Last retained line'],
        ),
      ]) {
        await tester.pumpWidget(
          _app(
            LogFileViewerView(
              state: state,
              onExport: () {},
              onFollowTail: (_) {},
            ),
          ),
        );
        if (state.exporting) {
          await tester.pump(const Duration(milliseconds: 100));
        } else {
          await tester.pumpAndSettle();
        }
        final l = _strings(tester);
        expect(
          find.text('${l.resultFailed}\nLog file does not exist.'),
          state.fileExists ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(_logLines),
          state.fileExists ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(l.logFileViewerShowingRecent),
          state.truncated ? findsOneWidget : findsNothing,
        );
        final export = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, l.prototypeExport),
        );
        expect(export.onPressed != null, state.fileExists && !state.exporting);
        expect(
          find.byType(ButtonProgressIndicator),
          state.exporting ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'long logs follow, preserve user scroll, and resume from the status pill',
    (tester) async {
      _viewport(tester);
      var state = LogFileViewerPageState(
        title: 'access.log',
        fileExists: true,
        lines: List.generate(200, (index) => 'Log line $index'),
      );
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return LogFileViewerView(
                state: state,
                onExport: () {},
                onFollowTail: (value) =>
                    setState(() => state = state.copyWith(followTail: value)),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(_logLines);
      final scroll = tester.widget<ListView>(list).controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
      await tester.drag(list, const Offset(0, 280));
      await tester.pumpAndSettle();
      expect(state.followTail, isFalse);
      final offset = scroll.offset;
      rebuild(
        () => state = state.copyWith(
          lines: [...state.lines, 'A new real-time line'],
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(offset, 1));
      expect(find.text(_strings(tester).prototypeFollowing), findsNothing);
      await tester.tap(
        find.text(_strings(tester).logFileViewerContinueFollowing),
      );
      await tester.pumpAndSettle();
      expect(state.followTail, isTrue);
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short viewport scrolls outside the panel; long JSON scrolls inside it',
    (tester) async {
      _viewport(tester, size: const Size(427, 600));
      final text = List.generate(
        200,
        (index) => '  "entry$index": $index,',
      ).join('\n');
      await tester.pumpWidget(
        _app(
          ConfigFileViewerView(
            state: ConfigFileViewerPageState(
              title: 'Runtime JSON',
              text: text,
              loading: false,
            ),
            onExport: () {},
          ),
          locale: const Locale('fa'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(_panel)).height,
        greaterThanOrEqualTo(470),
      );
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(_configScroll),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      await tester.drag(find.byKey(_configScroll), const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'configuration display is pretty but export source remains original; cancel is inert',
    (tester) async {
      _viewport(tester);
      final params = ConfigFileViewerParams(
        'Runtime JSON',
        '',
        text: _originalJson,
      );
      final controller = ConfigFileViewerController(params);
      addTearDown(controller.close);
      await controller.stream.firstWhere((state) => !state.loading);
      expect(controller.state.text, _originalJson);
      expect(
        controller.state.displayText,
        const JsonEncoder.withIndent('  ').convert(jsonDecode(_originalJson)),
      );
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => ConfigFileViewerView(
              state: controller.state,
              onExport: () => controller.shareFile(context),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = _strings(tester);
      await tester.tap(find.text(l.prototypeExportOriginalConfiguration));
      await tester.pumpAndSettle();
      expect(find.byType(AppConfirmationDialog), findsOneWidget);
      expect(
        find.text(l.prototypeExportOriginalConfigurationQuestion),
        findsOneWidget,
      );
      await tester.tap(find.text(l.prototypeCancel));
      await tester.pumpAndSettle();
      expect(find.byType(AppConfirmationDialog), findsNothing);
      expect(controller.state.exporting, isFalse);
      expect(controller.state.text, _originalJson);
      expect(tester.takeException(), isNull);
    },
  );
}
