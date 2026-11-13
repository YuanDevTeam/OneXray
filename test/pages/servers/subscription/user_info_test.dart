import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/subscription/user_info.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/servers/subscription/user_info.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  const gib = 1024 * 1024 * 1024;
  final retrieved = DateTime(2026, 9, 1, 9, 42);

  Future<void> pumpInfo(
    WidgetTester tester,
    SubscriptionUserInfo info, {
    double width = 390,
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.material(Brightness.light, mobile: width < 720),
        locale: locale,
        localizationsDelegates: AppLocalePolicy.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: ShadTheme(
            data: AppTheme.shad(Brightness.light, mobile: width < 720),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingSection(
              title: '',
              padding: EdgeInsets.zero,
              children: [SubscriptionPackageDetails(info: info)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String summary(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byType(SubscriptionPackageSummary),
          matching: find.byType(Text),
        ),
      )
      .data!;

  testWidgets('finite plan shows provider counters, remaining and cache time', (
    tester,
  ) async {
    await pumpInfo(
      tester,
      SubscriptionUserInfo(
        uploadBytes: gib,
        downloadBytes: 2 * gib,
        totalBytes: 10 * gib,
        expireTimestamp:
            DateTime.now()
                .add(const Duration(days: 12))
                .millisecondsSinceEpoch ~/
            1000,
        updatedAt: retrieved,
      ),
    );
    final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    expect(summary(tester), contains('7.0 GiB'));
    expect(summary(tester), contains(l.subscriptionPackageExpiresInDays(12)));
    expect(find.text('1.0 GiB'), findsOneWidget);
    expect(find.text('2.0 GiB'), findsOneWidget);
    expect(find.text('3.0 GiB'), findsOneWidget);
    expect(find.text('10.0 GiB'), findsOneWidget);
    expect(find.text('7.0 GiB'), findsOneWidget);
    expect(find.textContaining('2026'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial counters never imply unlimited data or zero usage', (
    tester,
  ) async {
    await pumpInfo(
      tester,
      SubscriptionUserInfo(uploadBytes: gib, updatedAt: retrieved),
    );
    final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    expect(summary(tester), contains(l.prototypeUpload));
    expect(summary(tester), contains('1.0 GiB'));
    expect(find.text(l.subscriptionPackageNotProvided), findsNWidgets(5));
    expect(find.text(l.subscriptionPackageUnlimited), findsNothing);
    expect(find.text(l.subscriptionPackageNoExpiry), findsNothing);
    expect(find.text('0 B'), findsNothing);
  });

  testWidgets('explicit unlimited and no expiry remain distinct from missing', (
    tester,
  ) async {
    await pumpInfo(
      tester,
      SubscriptionUserInfo(
        totalBytes: 0,
        expireTimestamp: 0,
        updatedAt: retrieved,
      ),
    );
    final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    expect(summary(tester), contains(l.subscriptionPackageUnlimited));
    expect(summary(tester), contains(l.subscriptionPackageNoExpiry));
    expect(find.text(l.subscriptionPackageUnlimited), findsNWidgets(2));
    expect(find.text(l.subscriptionPackageNotProvided), findsNWidgets(3));
    expect(find.text('0 B'), findsNothing);
  });

  testWidgets('expired and exhausted plan preserves reported usage', (
    tester,
  ) async {
    await pumpInfo(
      tester,
      SubscriptionUserInfo(
        uploadBytes: gib,
        downloadBytes: 4 * gib,
        totalBytes: 3 * gib,
        expireTimestamp: 1,
        updatedAt: retrieved,
      ),
    );
    final l = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    expect(summary(tester), contains(l.subscriptionPackageExhausted));
    expect(summary(tester), contains(l.subscriptionPackageExpired));
    expect(find.text('5.0 GiB'), findsOneWidget);
    expect(find.text('0 B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (locale, width, textScale) in const [
    (Locale('en'), 320.0, 1.0),
    (Locale('zh'), 390.0, 1.0),
    (Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), 580.0, 1.0),
    (Locale('ru'), 320.0, 2.0),
    (Locale('fa'), 390.0, 2.0),
    (Locale('en'), 580.0, 2.0),
  ]) {
    testWidgets(
      'package details wrap long values ($locale, $width, $textScale)',
      (tester) async {
        await pumpInfo(
          tester,
          SubscriptionUserInfo(
            uploadBytes: gib,
            downloadBytes: gib,
            totalBytes: 0x7fffffffffffffff,
            expireTimestamp: 253402214400,
            updatedAt: retrieved,
          ),
          locale: locale,
          width: width,
          textScale: textScale,
        );
        final element = tester.element(find.byType(SubscriptionPackageDetails));
        final l = AppLocalizations.of(element)!;
        expect(find.text(l.subscriptionPackageTitle), findsOneWidget);
        expect(
          Directionality.of(element),
          locale.languageCode == 'fa' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
        final uploadTop = tester.getTopLeft(find.text(l.prototypeUpload)).dy;
        final downloadTop = tester
            .getTopLeft(find.text(l.prototypeDownload))
            .dy;
        expect(
          downloadTop,
          textScale == 1 ? uploadTop : greaterThan(uploadTop),
        );
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(SubscriptionPackageDetails),
            matching: find.byType(Text),
          ),
        )) {
          expect(text.maxLines, isNull);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
        }
      },
    );
  }
}
