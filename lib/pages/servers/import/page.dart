import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/servers/import/controller.dart';
import 'package:onexray/pages/servers/subscription/form_view.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/app_activity.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/outbound_json_editor.dart';
import 'package:onexray/service/servers/import.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

export 'controller.dart' show ServerImportAction;

export 'package:onexray/service/servers/import.dart' show ServerImportResult;

class ServersImportPage extends StatefulWidget {
  final String? initialText;
  final ServerImportController? controller;
  const ServersImportPage({super.key, this.initialText, this.controller});

  @override
  State<ServersImportPage> createState() => _ServersImportPageState();
}

class _ServersImportPageState extends State<ServersImportPage> {
  late final controller = widget.controller ?? ServerImportController();

  @override
  void initState() {
    super.initState();
    final input = widget.initialText;
    if (input != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          controller.openText(context, input);
        }
      });
    }
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<ServerImportController, ServerImportPageState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        return PopScope(
          canPop: state.canClose,
          child: AppDialog(
            title: l10n.prototypeAddServersToOneXray,
            onClose: () => controller.closeFlow(context),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.all(mobile ? 14 : 20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = mobile
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 10) / 2;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (controller.supportsScan)
                            _choice(
                              context,
                              width,
                              ServerImportAction.scan,
                              LucideIcons.qrCode,
                              l10n.prototypeScanQrCode,
                            ),
                          _choice(
                            context,
                            width,
                            ServerImportAction.paste,
                            LucideIcons.clipboard,
                            l10n.prototypePasteLink,
                          ),
                          _choice(
                            context,
                            width,
                            ServerImportAction.subscription,
                            LucideIcons.link,
                            l10n.prototypeAddSubscription,
                          ),
                          _choice(
                            context,
                            width,
                            ServerImportAction.file,
                            LucideIcons.fileInput,
                            l10n.prototypeImportFile,
                          ),
                          _choice(
                            context,
                            width,
                            ServerImportAction.json,
                            LucideIcons.fileJson,
                            l10n.prototypeAddManually,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                _ImportFeedback(state: state),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _choice(
    BuildContext context,
    double width,
    ServerImportAction action,
    IconData icon,
    String title,
  ) {
    final palette = ColorManager.palette(context);
    return SizedBox(
      width: width,
      child: OutlinedButton(
        onPressed: controller.state.busy
            ? null
            : () => controller.open(context, action),
        style:
            OutlinedButton.styleFrom(
              minimumSize: const Size(0, 74),
              padding: const EdgeInsets.all(12),
              textStyle: AppTypography.importMethod,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
            ).copyWith(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? palette.mutedForeground
                    : states.contains(WidgetState.hovered)
                    ? palette.primary
                    : palette.foreground,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered)
                    ? palette.selectedSurface
                    : palette.card,
              ),
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.hovered)
                      ? palette.primary
                      : palette.border,
                ),
              ),
            ),
        child: Row(
          children: [
            AppActivityBuilder(
              builder: (context, activity) =>
                  controller.state.openingAction == action ||
                      (controller.state.activeAction == action &&
                          (activity.downloading || controller.state.busy))
                  ? const ButtonProgressIndicator(size: 22)
                  : Icon(icon, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
            const SizedBox(width: 10),
            const Icon(LucideIcons.arrowRightDir, size: 18),
          ],
        ),
      ),
    );
  }
}

class ServerImportFormPage extends StatelessWidget {
  final ServerImportController controller;
  final ServerImportAction action;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  const ServerImportFormPage({
    super.key,
    required this.controller,
    required this.action,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<ServerImportController, ServerImportPageState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        final subscription = action == ServerImportAction.subscription;
        final manual = action == ServerImportAction.json;
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        return PopScope(
          canPop: state.canClose,
          child: AppDialog(
            title: subscription
                ? controller.editingSubscription
                      ? l10n.prototypeEditSubscription
                      : l10n.prototypeAddSubscription
                : manual
                ? l10n.prototypeAddManually
                : l10n.prototypePasteLink,
            subtitle: controller.editingSubscription
                ? l10n.prototypeChangesApplyToFutureUpdates
                : null,
            onBack: onBack,
            onClose: onClose ?? () => controller.closeFlow(context),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subscription)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 16 : 20,
                      20,
                      mobile ? 16 : 20,
                      0,
                    ),
                    child: _subscription(context),
                  )
                else if (manual)
                  _manual(context, mobile: mobile)
                else
                  _paste(context),
                _ImportFeedback(state: state, showError: !manual),
                ConnectCallout(
                  icon: LucideIcons.lockKeyhole,
                  text: l10n.prototypeLocalInputPrivacy,
                ),
              ],
            ),
            actions: [
              ConnectDialogButton(
                label: l10n.prototypeCancel,
                secondary: true,
                onPressed: !state.canClose
                    ? null
                    : onClose ?? () => controller.closeFlow(context),
              ),
              AppActivityBuilder(
                builder: (context, activity) => ConnectDialogButton(
                  label: subscription
                      ? controller.editingSubscription
                            ? l10n.prototypeSave
                            : l10n.prototypeAddSubscription
                      : manual
                      ? l10n.prototypeAdd
                      : l10n.prototypeImportLinks,
                  busy:
                      state.submitting ||
                      (!controller.editingSubscription && activity.downloading),
                  onPressed: !controller.canSubmit(action)
                      ? null
                      : () => subscription
                            ? controller.subscribe(context)
                            : controller.detect(context, action),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _paste(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.prototypeImportLinks,
            style: AppTypography.importField.copyWith(
              color: palette.mutedStrong,
            ),
          ),
          SizedBox(
            height: 120,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ShadInput(
                controller: controller.text,
                placeholder: const Text(
                  'vless://, vmess://, trojan://, ss://, https://, onexray://',
                ),
                expands: true,
                editableTextSize: const Size(double.infinity, 98),
                maxLines: null,
                minLines: null,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.multiline,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                style: AppTypography.importField,
              ),
            ),
          ),
          Text(
            l10n.prototypeImportLinksHint,
            style: AppTypography.importHint.copyWith(
              color: palette.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _manual(BuildContext context, {required bool mobile}) {
    final l10n = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 16 : 20, 20, mobile ? 16 : 20, 0),
      child: Column(
        spacing: 7,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.prototypeXrayNodeJson,
            style: AppTypography.subscriptionField.copyWith(
              color: palette.mutedStrong,
            ),
          ),
          OutboundJsonEditor(
            controller: controller.jsonText,
            diagnostic:
                controller.state.jsonDiagnostic ??
                (controller.state.error == null
                    ? null
                    : JsonDiagnostic(controller.state.error!)),
          ),
          Text(
            l10n.prototypeNodeJsonHint,
            style: AppTypography.importJsonHint.copyWith(
              color: palette.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscription(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SubscriptionFormView(
      supportText: l10n.prototypeSubscriptionDescription,
      nameLabel: l10n.prototypeSubscriptionName,
      nameController: controller.name,
      nameHint: l10n.prototypeExampleService,
      nameErrorText: controller.subscriptionFieldError(
        l10n,
        SubscriptionFormField.name,
      ),
      nameFocusNode: controller.subscriptionFocusNode(
        SubscriptionFormField.name,
      ),
      urlLabel: l10n.prototypeSubscriptionLink,
      urlController: controller.url,
      userAgentController: controller.userAgent,
      urlHint: 'https://provider.example/subscription',
      urlErrorText: controller.subscriptionFieldError(
        l10n,
        SubscriptionFormField.url,
      ),
      urlFocusNode: controller.subscriptionFocusNode(SubscriptionFormField.url),
      userAgentErrorText: controller.subscriptionFieldError(
        l10n,
        SubscriptionFormField.userAgent,
      ),
      userAgentFocusNode: controller.subscriptionFocusNode(
        SubscriptionFormField.userAgent,
      ),
      panel: controller.state.panel,
      mode: controller.state.mode,
      automaticModeAllowed: !controller.editingSubscription,
      onPanelChanged:
          controller.state.busy ||
              controller.state.loadFailed ||
              controller.state.generatingAgeKey
          ? null
          : controller.setPanel,
      onModeChanged:
          controller.state.busy ||
              controller.state.loadFailed ||
              controller.state.generatingAgeKey
          ? null
          : controller.setMode,
      hwidTitle: l10n.subscriptionHwidTitle,
      hwidDescription: l10n.subscriptionHwidDescription,
      hwidEnabled: controller.state.hwidEnabled,
      onHwidChanged: controller.state.busy || controller.state.loadFailed
          ? null
          : controller.setHwidEnabled,
      encryptionTitle: l10n.prototypeAgeEncryption,
      ageProviderSupportTitle: l10n.prototypeAgeOptional,
      ageProviderSupportDescription: l10n.prototypeAgeSupportNotice,
      ageSecretKeyLabel: l10n.prototypeAgeSecretKey,
      ageSecretKeyHint: 'AGE-SECRET-KEY-1...',
      ageSecretKeyController: controller.secretKey,
      agePublicKeyLabel: l10n.prototypeAgePublicKey,
      agePublicKeyHint: 'age1...',
      agePublicKeyController: controller.publicKey,
      ageKeyPairErrorText: controller.state.incompleteKeys
          ? l10n.prototypeAgeBothKeysRequired
          : null,
      obscureAgeSecretKey: controller.state.obscureSecret,
      revealAgeSecretKeyLabel: l10n.prototypeRevealKey,
      hideAgeSecretKeyLabel: l10n.prototypeHideKey,
      generateAgeKeyLabel: l10n.subscriptionGenerateAgeKey,
      generateAgeX25519KeyLabel: 'X25519',
      generateAgeHybridKeyLabel: l10n.prototypeAgeHybrid,
      clearAgeKeyLabel: l10n.prototypeClear,
      onToggleAgeSecretKeyVisibility: controller.toggleSecret,
      onGenerateAgeKey: (type) => controller.generateKeys(context, type),
      onClearAgeKey: controller.clearKeys,
      generatingAgeKeyType: controller.state.generatingAgeKeyType,
      ageKeyActionsEnabled:
          !controller.state.busy && !controller.state.loadFailed,
      hasAgeKeys: controller.state.hasAgeKeys,
      ageExpanded: controller.state.ageExpanded,
      onToggleAgeExpanded: controller.toggleAgeExpanded,
    );
  }
}

class ServerImportPreviewPage extends StatelessWidget {
  final ServerImportController controller;
  final ServerImportPreview preview;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  const ServerImportPreviewPage({
    super.key,
    required this.controller,
    required this.preview,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<ServerImportController, ServerImportPageState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        final palette = ColorManager.palette(context);
        final committed = state.committedResult;
        final itemCount =
            preview.rows.length +
            preview.raw.length +
            preview.customRoutes.length +
            preview.geoData.length +
            preview.assets.length;
        return PopScope(
          canPop: !state.busy && committed == null,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && !state.busy && committed != null) {
              controller.closeFlow(context);
            }
          },
          child: AppDialog(
            title: l10n.prototypeImportPreview,
            onBack: committed == null ? onBack : null,
            onClose: onClose ?? () => controller.closeFlow(context),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: palette.runningSurface,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                  ),
                  child: Row(
                    spacing: 13,
                    children: [
                      Icon(
                        LucideIcons.circleCheck,
                        size: 26,
                        color: palette.running,
                      ),
                      Expanded(
                        child: Column(
                          spacing: 3,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.prototypeImportedLinks,
                              style: AppTypography.importSummary,
                            ),
                            Text(
                              l10n.prototypeItemCount(itemCount),
                              style: AppTypography.importSummaryMeta.copyWith(
                                color: palette.mutedForeground,
                              ),
                            ),
                            if (committed != null && preview.count > 0)
                              Text(
                                l10n.prototypeServersAdded,
                                style: AppTypography.importSummaryMeta.copyWith(
                                  color: palette.running,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (preview.hasItems)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                    child: Column(
                      children: [
                        for (final row in preview.rows)
                          _PreviewItem(
                            name: row.name.value,
                            description: committed != null
                                ? l10n.prototypeNameSaved(row.name.value)
                                : l10n.prototypeLocalServer,
                          ),
                        for (final raw in preview.raw)
                          _PreviewItem(
                            name: raw.name,
                            description: committed != null
                                ? l10n.prototypeNameSaved(raw.name)
                                : l10n.xrayRawPageTitle,
                          ),
                        for (final route in preview.customRoutes)
                          _PreviewItem(
                            name: route.name,
                            description: committed == null
                                ? l10n.prototypeCustomRouting
                                : l10n.prototypeNameSaved(route.name),
                          ),
                        for (final dependency in preview.assets)
                          _PreviewItem(
                            name: dependency.fileName,
                            description: l10n.prototypeDataSource,
                          ),
                        for (final source in preview.geoData)
                          _PreviewItem(
                            name: source.name,
                            description: committed == null
                                ? l10n.prototypeDataSource
                                : committed.failedGeoData.contains(source)
                                ? l10n.prototypeCannotReadContent
                                : l10n.prototypeGeodataAdded,
                            failed:
                                committed?.failedGeoData.contains(source) ??
                                false,
                          ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Text(
                      l10n.prototypeNoSupportedLinks,
                      style: AppTypography.importHint.copyWith(
                        color: palette.destructive,
                      ),
                    ),
                  ),
                _ImportFeedback(state: state),
                if (preview.count > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Expanded(
                          child: _stat(
                            context,
                            l10n.prototypeUsableNodes(preview.count),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              ConnectDialogButton(
                label: committed == null
                    ? l10n.prototypeCancel
                    : l10n.prototypeClose,
                secondary: true,
                onPressed: state.busy
                    ? null
                    : onClose ?? () => controller.closeFlow(context),
              ),
              AppActivityBuilder(
                builder: (context, activity) => ConnectDialogButton(
                  label: committed == null
                      ? l10n.prototypeConfirmAdd
                      : l10n.prototypeDone,
                  busy:
                      state.submitting ||
                      (committed == null &&
                          preview.geoData.isNotEmpty &&
                          activity.downloading),
                  onPressed: state.busy || !preview.hasItems
                      ? null
                      : () => controller.confirm(context, preview),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _stat(BuildContext context, String text) {
    final palette = ColorManager.palette(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.runningSurface,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text(
        text,
        style: AppTypography.importStat.copyWith(color: palette.running),
      ),
    );
  }
}

class _PreviewItem extends StatelessWidget {
  const _PreviewItem({
    required this.name,
    required this.description,
    this.failed = false,
  });

  final String name;
  final String description;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Expanded(child: Text(name, style: AppTypography.serverMenuTitle)),
          Expanded(
            child: Text(
              description,
              textAlign: TextAlign.end,
              style: AppTypography.serverMenuHint.copyWith(
                color: failed ? palette.destructive : palette.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ServerImportScannerPage extends StatelessWidget {
  final ServerImportController controller;
  final void Function(BarcodeCapture) onDetect;
  final Future<void> Function() onPickImage;
  const ServerImportScannerPage({
    super.key,
    required this.controller,
    required this.onDetect,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: controller,
    child: BlocBuilder<ServerImportController, ServerImportPageState>(
      builder: (context, state) => Scaffold(
        appBar: PageAppBar(
          title: Text(AppLocalizations.of(context)!.prototypeScanQrCode),
          actions: [
            IconButton(
              tooltip: AppLocalizations.of(context)!.menuPickImage,
              onPressed: state.scannerPickingImage ? null : onPickImage,
              icon: state.scannerPickingImage
                  ? const ButtonProgressIndicator()
                  : const Icon(LucideIcons.image),
            ),
          ],
        ),
        body: SafeArea(
          // mobile_scanner still uses the SDK's Material widgets.
          // ignore: deprecated_member_use
          child: MaterialUiCompatibilityBridge(
            child: MobileScanner(onDetect: onDetect),
          ),
        ),
      ),
    ),
  );
}

class _ImportFeedback extends StatelessWidget {
  final ServerImportPageState state;
  final bool showError;
  const _ImportFeedback({required this.state, this.showError = true});

  @override
  Widget build(BuildContext context) {
    if (state.subscriptionImports.isEmpty && state.error == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (state.importedSubscriptionCount > 0)
            Text(
              l10n.prototypeSubscriptionsImported(
                state.importedSubscriptionCount,
              ),
              style: AppTypography.importHint.copyWith(
                color: palette.mutedForeground,
              ),
            ),
          for (final item in state.subscriptionImports)
            Text(
              item.result.success
                  ? '${item.name}: ${l10n.prototypeUsableNodes(item.result.count)}'
                  : '${item.name}: ${ServerImportController.subscriptionError(l10n, item.result.status, error: item.result.error)}',
              style: AppTypography.importHint.copyWith(
                color: item.result.success
                    ? palette.mutedForeground
                    : palette.destructive,
              ),
            ),
          if (state.error case final error? when showError)
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: AppTypography.importHint.copyWith(
                  color: palette.destructive,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
