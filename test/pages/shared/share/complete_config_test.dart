import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/share/controller.dart';
import 'package:onexray/pages/shared/share/page.dart';
import 'package:onexray/pages/shared/share/params.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/share/app_link_model.dart';
import 'package:onexray/service/shared/share/app_link_parser.dart';
import 'package:onexray/service/shared/share/outgoing_share.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'test_app.dart';

void main() {
  late AppDatabase db;
  late int sourceId;

  setUp(() async {
    final bus = AppEventBus();
    addTearDown(bus.close);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sourceId = await db.subscriptionDao.insertRow(
      SubscriptionCompanion.insert(
        name: 'Provider source',
        url: 'https://example.test/provider',
        mode: const Value('providerManaged'),
        timestamp: DateTime(2026, 10, 12),
      ),
    );
  });
  tearDown(() => db.close());

  for (final type in [CoreConfigType.Remnawave, CoreConfigType.raw]) {
    testWidgets('${type.name} page copies the complete Raw link after consent', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const original =
          '{"remarks":"Source title","inbounds":[{"tag":"provider-socks","protocol":"socks","port":1080}],"outbounds":[{"protocol":"freedom","tag":"provider-direct"}],"routing":{"rules":[{"type":"field","inboundTag":["provider-socks"],"outboundTag":"provider-direct"}]},"unknownExtension":{"preserved":true}}';
      late CoreConfigData before;
      late SubscriptionData sourceBefore;
      await tester.runAsync(() async {
        final id = await db.coreConfigDao.insertAssetRow(
          CoreConfigCompanion.insert(
            name: 'Complete profile',
            type: type.name,
            tags: '',
            data: Value(base64Encode(utf8.encode(original))),
            delay: -1,
            subId: type == CoreConfigType.raw ? 0 : sourceId,
          ),
        );
        before = (await db.coreConfigDao.searchRow(id))!;
        sourceBefore = (await db.subscriptionDao.searchRow(sourceId))!;
      });
      final copied = <String>[];
      await tester.pumpWidget(
        ShareTestApp(
          child: SharePage(
            params: SharePageParams(ShareType.config, before.id),
            database: db,
            outgoingShare: OutgoingShare(
              destination: ShareDestination.clipboard,
              writeClipboard: (text) async => copied.add(text),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(AppDialog));
      final controller = context.read<ShareController>();
      final l = AppLocalizations.of(context)!;
      await tester.runAsync(() async {
        if (controller.state.loading) {
          await controller.stream
              .firstWhere((state) => !state.loading)
              .timeout(const Duration(seconds: 5));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.state.linkError, isEmpty);
      expect(controller.state.format, ShareLinkFormat.onexray);
      expect(find.text(l.prototypeOriginalLink), findsNothing);
      expect(find.text(l.sharePageOneXrayLink), findsOneWidget);
      expect(find.text(l.sharePageShowQRCode), findsOneWidget);
      expect(find.text(l.prototypeRawJsonShareWarning), findsOneWidget);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, controller.state.appLink);
      final copy = find.widgetWithText(FilledButton, l.sharePageCopyLink);
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(copied, isEmpty);
      expect(find.byType(ShadDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ShadDialog),
          matching: find.text(l.prototypeRawJsonShareWarning),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ShadButton, l.buttonCancel));
      await tester.pumpAndSettle();
      expect(copied, isEmpty);
      await tester.tap(copy);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ShadButton, l.sharePageCopyLink));
      await tester.pumpAndSettle();
      final link =
          OneXrayAppLinkParser.parse(Uri.parse(copied.single))!
              as OneXrayConfigLink;
      expect(link.type, OneXrayConfigLinkType.raw);
      expect(link.name, 'Complete profile');
      if (type == CoreConfigType.Remnawave) {
        final config = jsonDecode(link.xrayJson) as Map<String, dynamic>;
        expect(config['name'], 'Complete profile');
        expect(config['remarks'], 'Source title');
        expect(config['unknownExtension'], {'preserved': true});
        expect(
          (config['inbounds'] as List).where(
            (value) => value['tag'] == 'tunIn',
          ),
          hasLength(1),
        );
        expect(config['routing']['rules'][0], {
          'type': 'field',
          'inboundTag': ['tunIn'],
          'network': 'tcp,udp',
          'port': '53',
          'outboundTag': 'app-remna-dns',
        });
        expect(config['routing']['rules'][1]['inboundTag'], [
          'provider-socks',
          'tunIn',
        ]);
      } else {
        expect(link.xrayJson, original);
      }
      await tester.runAsync(() async {
        expect((await db.coreConfigDao.searchRow(before.id))!, before);
        expect((await db.subscriptionDao.searchRow(sourceId))!, sourceBefore);
      });
      expect(find.byType(SharePage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
