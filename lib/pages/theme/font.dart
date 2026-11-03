import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

abstract final class AppFontFamily {
  static const sans = "packages/shadcn_ui/Geist";
  static const mono = "packages/shadcn_ui/GeistMono";
  static const windowsSansFallback = <String>[
    "Microsoft YaHei UI",
    "Microsoft YaHei",
  ];

  static List<String>? get sansFallback =>
      AppPlatform.isWindows ? windowsSansFallback : null;
}

abstract final class AppTypography {
  // Semantic roles from the prototype's src/theme/tokens.json. Use logical
  // pixels and leave system text scaling and locale-specific glyphs to Flutter.
  static TextStyle _style(int size, [int weight = 400]) => TextStyle(
    fontSize: size.toDouble(),
    fontWeight: FontWeight.values[weight ~/ 100 - 1],
    fontFamilyFallback: AppFontFamily.sansFallback,
  );

  static final pageTitle = _style(26, 600);
  static final panelTitle = _style(16, 600);
  static final sectionTitle = _style(16, 600);
  static final rowTitle = _style(14, 600);
  static final rowValue = _style(14);
  static final supporting = _style(13);
  static final metadata = _style(13);
  static final control = _style(14, 600);
  static final navigationLabel = _style(14, 500);
  static final selectedNavigationLabel = _style(14, 600);
  static final badge = _style(12, 600);
  static final code = _style(12);
  static final metric = _style(22, 500);

  static final pageAction = _style(12, 600);
  static final settingsSectionTitle = _style(16, 600);
  static final settingsSectionDesktopTitle = _style(16, 600);
  static final settingsRow = _style(14, 600);
  static final settingsFieldTitle = _style(14, 600);
  static final settingsValueLabel = _style(13, 400);
  static final settingsValue = _style(13, 500);
  static final settingsStatus = _style(13, 600);
  static final desktopSettingsValueLabel = _style(13, 400);
  static final desktopSettingsValue = _style(13, 500);
  static final desktopSettingsStatus = _style(13, 600);
  static final desktopSettingsRowValue = _style(13, 400);
  static final desktopSettingsVersion = _style(14, 400);
  static final desktopSettingsHint = _style(12, 400);
  static final desktopSettingsNote = _style(12, 400);
  static final desktopSettingsDanger = _style(14, 600);
  static final settingsHint = _style(12, 400);
  static final settingsThemeOption = _style(14, 400);
  static final settingsThemeOptionMobile = _style(13, 400);
  static final settingsVersion = _style(13, 400);
  static final settingsNote = _style(12, 400);
  static final settingsDetailNote = _style(12, 400);
  static final settingsSelect = _style(14, 400);
  static final settingsInput = _style(13, 400);
  static final routingCardTitle = _style(16, 600);
  static final routingCardDescription = _style(12, 400);
  static final routingRowTitle = _style(13, 700);
  static final routingRowTitleMobile = _style(12, 700);
  static final routingRowDescription = _style(12, 400);
  static final routingRowValue = _style(12, 600);
  static final routingCount = _style(12, 700);
  static final routingPreviewTitle = _style(13, 700);
  static final routingPreviewBody = _style(12, 400);
  static final routingPreviewHint = _style(12, 400);
  static final routingPreviewMeta = _style(12, 400);
  static final routingSelectionTitle = _style(12, 700);
  static final routingSelectionDescription = _style(12, 400);
  static final routingSelectionGroup = _style(12, 700);
  static final routingSelectionInput = _style(12, 400);
  static final routingSelectionCount = _style(12, 600);
  static final routingSelectionNote = _style(12, 400);
  static final routingRegionCode = _style(12, 700);
  static final routeIdentityLabel = _style(12, 600);
  static final routeCount = _style(12, 400);
  static final ruleTitleMobile = _style(12, 700);
  static final ruleTitleDesktop = _style(13, 700);
  static final ruleSummaryDesktop = _style(12, 400);
  static final ruleSummary = _style(12, 400);
  static final ruleAction = _style(12, 700);
  static final ruleNumber = _style(12, 400);
  static final conditionTitle = _style(12, 700);
  static final conditionSummary = _style(12, 400);
  static final routingInput = _style(16, 400);
  static final conditionRelation = _style(12, 400);
  static final actionOption = _style(12, 400);
  static final selectedActionOption = _style(12, 700);
  static final actionHelp = _style(12, 400);
  static final ruleAdd = _style(12, 600);
  static final configurationTool = _style(12, 600);
  static final rawField = _style(14, 600);
  static final rawNote = _style(12, 400);
  static final runtimeCodePill = _style(12, 600);
  static final runtimeCodeAction = _style(12, 600);
  static final runtimeCodeMobile = _style(12, 400);
  static final runtimeCodeDesktop = _style(12, 400);
  static final runtimeCodeNote = _style(12, 400);
  static final runtimeCodeDesktopNote = _style(12, 400);
  static final routingConditionInput = _style(16, 400);
  static final subscriptionField = _style(12, 600);
  static final subscriptionInfo = _style(12, 400);
  static final subscriptionAgeTitle = _style(13, 700);
  static final subscriptionAgeOptional = _style(12, 500);
  static final subscriptionAgeWarning = _style(12, 400);
  static final subscriptionAgeAction = _style(12, 600);
  static final subscriptionClear = _style(13, 600);
  static final importMethod = _style(16, 400);
  static final importField = _style(13, 600);
  static final importHint = _style(12, 500);
  static final importJson = _style(12, 400);
  static final importJsonHint = _style(12, 500);
  static final importSummary = _style(16, 700);
  static final importSummaryMeta = _style(12, 400);
  static final importStat = _style(12, 400);
  static final dialogBack = _style(13, 400);
  static final shareLink = _style(12, 400);
  static final shareQr = _style(13, 400);
  static final shareHint = _style(12, 400);
  static final aboutBrandTitle = _style(19, 700);
  static final aboutBrandDescription = _style(12, 400);
  static final settingsChoiceTitle = _style(14, 600);
  static final settingsChoiceDetail = _style(12, 400);
  static final iconPreviewBrand = _style(16, 700);
  static final iconChoice = _style(13, 400);
  static final iconPreviewCaption = _style(12, 400);
  static final platformDetailTitle = _style(19, 700);
  static final platformDetailBody = _style(16, 400);
  static final platformChoiceTitle = _style(13, 700);
  static final platformChoiceHint = _style(12, 400);
  static final windowsPolicyHint = _style(12, 400);
  static final windowsNetworkTitle = _style(15, 700);
  static final windowsNetworkMeta = _style(12, 400);
  static final windowsNetworkInput = _style(13, 400);
  static final windowsNetworkNote = _style(12, 400);
  static final setupBrand = _style(19, 700);
  static final setupTitle = _style(27, 700);
  static final setupDesktopTitle = _style(40, 700);
  static final setupWelcomeTitle = _style(25, 700);
  static final setupSubtitle = _style(14, 400);
  static final setupDesktopSubtitle = _style(16, 400);
  static final setupPoint = _style(13, 400);
  static final setupDesktopPoint = _style(14, 400);
  static final setupProgress = _style(14, 700);
  static final setupStepLabel = _style(14, 400);
  static final setupStepActive = _style(14, 600);
  static final setupReady = _style(16, 600);
  static final setupDesktopReady = _style(17, 400);
  static final setupPermission = _style(16, 400);
  static final setupStatus = _style(13, 400);
  static final setupHint = _style(12, 400);
  static final setupSkipNote = _style(12, 400);
  static final setupRowTitle = _style(16, 600);
  static final setupDesktopRowTitle = _style(19, 600);
  static final setupDesktopRowDetail = _style(16, 400);
  static final setupDesktopTrailing = _style(14, 400);
  static final setupImport = _style(14, 400);
  static final setupDesktopImport = _style(15, 400);
  static final setupAction = _style(16, 600);
  static final setupDesktopAction = _style(17, 600);
  static final setupChildTitle = _style(23, 700);
  static final setupSelectorTitle = _style(15, 600);
  static final setupSelectorDetail = _style(13, 400);
  static final setupSearch = _style(15, 400);
  static final setupError = _style(13, 400);
  static final setupPrivacyLink = _style(14, 600);
  static final appleSettingTitle = _style(12, 700);
  static final appleSettingTitleDesktop = _style(13, 700);
  static final appleSettingHint = _style(12, 400);
  static final appleSettingHintDesktop = _style(12, 400);
  static final appleAutoTitle = _style(14, 700);
  static final appleAutoTitleDesktop = _style(15, 700);
  static final appleRuleTitle = _style(12, 700);
  static final appleRuleTitleDesktop = _style(12, 700);
  static final appleRuleHint = _style(12, 400);
  static final appleRuleHintDesktop = _style(12, 400);
  static final appleWifiToken = _style(12, 600);
  static final appleWifiTokenDesktop = _style(12, 600);
  static final appleNetworkAction = _style(12, 600);
  static final appleNetworkActionDesktop = _style(12, 600);
  static final appleFallbackPill = _style(12, 600);
  static final appleFallbackPillDesktop = _style(12, 600);
  static final appleWifiEdit = _style(12, 700);
  static final appleWifiEditDesktop = _style(12, 700);
  static final appleWifiHeading = _style(15, 700);
  static final appleWifiHeadingDesktop = _style(18, 700);
  static final appleWifiDescription = _style(12, 400);
  static final appleWifiDescriptionDesktop = _style(13, 400);
  static final appleWifiInput = _style(12, 400);
  static final appleWifiInputDesktop = _style(16, 400);
  static final appleWifiAdd = _style(12, 700);
  static final appleWifiAddDesktop = _style(13, 700);
  static final appleWifiMatchNote = _style(12, 400);
  static final appleWifiMatchNoteDesktop = _style(12, 400);
  static final updateTitle = _style(18, 600);
  static final updateVersionLabel = _style(13, 400);
  static final updateVersion = _style(12, 400);
  static final updateNotesHeading = _style(14, 700);
  static final updateNotes = _style(13, 400);
  static final settingsDanger = _style(14, 600);

  static final geodataIntro = _style(12, 400);
  static final geodataDesktopIntro = _style(12, 400);
  static final geodataDesktopTitle = _style(14, 700);
  static final geodataTableHeading = _style(12, 400);
  static final geodataTableBody = _style(12, 400);
  static final geodataDesktopAction = _style(12, 700);
  static final geodataTitle = _style(13, 700);
  static final geodataMeta = _style(12, 500);
  static final geodataValue = _style(12, 400);
  static final geodataAction = _style(12, 600);
  static final geodataPrimaryAction = _style(12, 600);
  static final geodataField = _style(12, 600);
  static final geodataEmpty = _style(12, 400);
  static final geodataCategory = _style(13, 700);
  static final geodataReference = _style(12, 400);
  static final geodataSourceUrl = _style(12, 400);
  static final geodataReadonly = _style(12, 600);
  static final geodataBody = _style(16, 400);
  static final geodataSourceLabel = _style(12, 400);

  static final androidTitle = _style(19, 700);
  static final androidBody = _style(16, 400);
  static final androidModeTitle = _style(13, 700);
  static final androidModeHint = _style(12, 400);
  static final androidRowTitle = _style(12, 700);
  static final androidRowHint = _style(12, 400);
  static final androidPackage = _style(12, 400);
  static final androidCount = _style(12, 700);
  static final androidBadge = _style(12, 700);
  static final androidEmpty = _style(12, 400);

  static final runtimeLabel = _style(12, 400);
  static final runtimeDesktopLabel = _style(12, 400);
  static final runtimeValue = _style(14, 600);
  static final runtimeDesktopValue = _style(14, 600);
  static final runtimeNavigationHint = _style(12, 400);
  static final runtimePushHint = _style(12, 400);
  static final runtimeDesktopPushHint = _style(12, 400);
  static final runtimeSelector = _style(12, 400);
  static final runtimeDesktopSelector = _style(14, 400);

  static final serverBody = _style(16, 400);
  static final serverTitle = _style(14, 600);
  // HTML small rounds up from 5/6 of the prototype's 16px body text.
  static final serverDetail = _style(14, 400);
  static final serverGroupDetail = _style(14, 400);
  static final serverSectionTitle = _style(12, 700);
  static final serverRegionCode = _style(12, 700);
  static final serverSelectionHealth = _style(12, 600);
  static final serverSelectionLabel = _style(12, 400);
  static final serverSelectionTitle = _style(14, 700);
  static final serverSelectionDetail = _style(12, 400);
  static final serverUseLabel = _style(12, 600);
  static final serverUseCount = _style(14, 600);
  static final serverGroupCode = _style(13, 700);
  static final serverGroupTitle = _style(18, 700);
  static final serverGroupSummary = _style(12, 400);
  static final serverNodeTitle = _style(13, 700);
  static final serverProtocol = _style(12, 600);
  static final serverGroupAction = _style(13, 600);
  static final serverGroupUseCount = _style(12, 700);
  static final serverConnectedBadge = _style(12, 700);

  static final connectStatusTitle = _style(17, 700);
  static final connectStatusDetail = _style(13, 400);
  static final connectButton = _style(16, 700);
  static final connectCaption = _style(12, 600);
  static final connectChoiceLabel = _style(12, 500);
  static final connectChoiceTitle = _style(14, 600);
  static final connectChoiceDetail = _style(12, 400);
  static final connectChoiceMeta = _style(12, 600);
  static final connectWhy = _style(14, 600);
  static final connectTrafficTitle = _style(15, 700);
  static final connectTrafficGroupTitle = _style(12, 500);
  static final connectTrafficLabel = _style(12, 400);
  static final connectTrafficValue = _style(15, 600);
  static final connectRawTitle = _style(12, 700);
  static final connectRawCount = _style(12, 600);
  static final connectRawEmptyTitle = _style(12, 700);
  static final connectRawEmptyDetail = _style(12, 400);
  static final connectRawNotice = _style(12, 400);
  static final connectRawRowTitle = _style(13, 600);
  static final connectRawRowDetail = _style(12, 400);

  static final desktopBrand = _style(25, 700);
  static final desktopUpdateLabel = _style(13, 600);
  static final connectDesktopStatusTitle = _style(21, 700);
  static final connectDesktopStatusDetail = _style(15, 400);
  static final connectDesktopAction = _style(20, 700);
  static final connectDesktopCaption = _style(14, 600);
  static final connectDesktopChoiceLabel = _style(16, 500);
  static final connectDesktopChoiceTitle = _style(16, 600);
  static final connectDesktopChoiceDetail = _style(12, 400);
  static final connectDesktopChoiceMeta = _style(13, 600);
  static final connectDesktopWhy = _style(16, 600);
  static final connectDesktopTrafficTitle = _style(20, 700);
  static final connectDesktopTrafficGroupTitle = _style(15, 500);
  static final connectDesktopTrafficLabel = _style(13, 400);
  static final connectDesktopRawTitle = _style(15, 700);
  static final connectDesktopRawEmptyTitle = _style(14, 700);
  static final connectDesktopRawEmptyDetail = _style(12, 400);

  static final dialogTitle = _style(18, 700);
  static final dialogSubtitle = _style(13, 400);
  static final dialogBody = _style(14, 400);
  static final dialogCallout = _style(13, 400);
  static final dialogOptionTitle = _style(14, 700);
  static final dialogOptionDescription = _style(12, 400);
  static final dialogOptionEdit = _style(12, 700);
  static final dialogGroupTitle = _style(13, 700);
  static final dialogGroupMeta = _style(12, 400);
  static final dialogAddAction = _style(12, 600);
  static final confirmationDesktopTitle = _style(20, 700);
  static final confirmationSubject = _style(14, 700);
  static final confirmationBody = _style(14, 400);
  static final serverMenuTitle = _style(13, 700);
  static final serverMenuHint = _style(12, 400);

  static final shad = ShadTextTheme.custom(
    h1Large: pageTitle,
    h1: pageTitle,
    h2: panelTitle,
    h3: sectionTitle,
    h4: sectionTitle,
    p: rowValue,
    blockquote: rowValue,
    table: rowValue,
    list: rowValue,
    lead: supporting,
    large: panelTitle,
    small: control,
    muted: supporting,
    family: AppFontFamily.sans,
  );

  static final material = TextTheme(
    displayLarge: pageTitle,
    displayMedium: pageTitle,
    displaySmall: panelTitle,
    headlineLarge: pageTitle,
    headlineMedium: panelTitle,
    headlineSmall: panelTitle,
    titleLarge: panelTitle,
    titleMedium: sectionTitle,
    titleSmall: rowTitle,
    bodyLarge: rowValue,
    bodyMedium: rowValue,
    bodySmall: supporting,
    labelLarge: control,
    labelMedium: control,
    labelSmall: badge,
  );
}
