import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/pages/servers/resource_json.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';

CoreConfigData _row(String type, String text) => CoreConfigData(
  id: 1,
  name: 'Stored asset',
  type: type,
  tags: '',
  data: base64Encode(utf8.encode(text)),
  delay: 9000,
  subId: 0,
  manualSortOrder: 0,
  favorite: false,
);

Widget _app(CoreConfigData row) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('en'),
  localizationsDelegates: AppLocalePolicy.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(child: ServerResourceJsonPreview(row: row)),
  ),
);

String _shown(WidgetTester tester) => tester
    .widget<SelectableText>(
      find.byKey(const ValueKey('server-resource-json-text')),
    )
    .data!;

void main() {
  testWidgets(
    'ordinary preview reads the stored outbound and refreshes when its data changes',
    (tester) async {
      final outbound = <String, Object>{
        'tag': 'Actual node',
        'protocol': 'socks',
        'settings': {
          'servers': [
            {'address': '127.0.0.1', 'port': 18080},
          ],
        },
        'unknownField': {'keep': true},
      };
      final row = _row(
        'outbound',
        jsonEncode({
          'outbounds': [outbound],
        }),
      );
      final original = row.data;
      await tester.pumpWidget(_app(row));
      await tester.pumpAndSettle();
      expect(jsonDecode(_shown(tester)), outbound);
      expect(row.data, original);
      final replacement = {...outbound, 'tag': 'Updated stored node'};
      await tester.pumpWidget(
        _app(
          _row(
            'outbound',
            jsonEncode({
              'outbounds': [replacement],
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(jsonDecode(_shown(tester)), replacement);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'complete JSON remains verbatim and its preview scrolls within a bounded height',
    (tester) async {
      final text =
          '  ${const JsonEncoder.withIndent('  ').convert({'outbounds': [], 'unknown': List.generate(90, (i) => 'stored-$i')})}\n';
      await tester.pumpWidget(_app(_row('raw', text)));
      await tester.pumpAndSettle();
      expect(_shown(tester), text);
      expect(
        tester.getSize(find.byType(ServerResourceJsonPreview)).height,
        lessThanOrEqualTo(320),
      );
      final scroll = tester
          .widget<SingleChildScrollView>(
            find
                .descendant(
                  of: find.byType(ServerResourceJsonPreview),
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
          )
          .controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      await tester.drag(
        find.byKey(const ValueKey('server-resource-json-scrollbar')),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      await tester.pumpWidget(_app(_row('Remnawave', text)));
      await tester.pumpAndSettle();
      expect(_shown(tester), text);
      expect(
        tester
            .widget<SelectableText>(find.byType(SelectableText))
            .textDirection,
        TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unreadable data replaces the previous preview with a real error instead of empty JSON',
    (tester) async {
      final row = _row('raw', '{"stored":"valid"}');
      await tester.pumpWidget(_app(row));
      await tester.pumpAndSettle();
      expect(_shown(tester), '{"stored":"valid"}');
      for (final bad in [
        row.copyWith(data: const Value('not-base64!')),
        _row('raw', '[]'),
      ]) {
        await tester.pumpWidget(_app(bad));
        await tester.pumpAndSettle();
        final text = tester.widget<SelectableText>(find.byType(SelectableText));
        expect(text.data, isNot('{}'));
        expect(text.data, isNot(contains('"stored":"valid"')));
        expect(text.data, isNotEmpty);
        expect(
          text.style!.color,
          ColorManager.palette(
            tester.element(find.byType(ServerResourceJsonPreview)),
          ).destructive,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
