import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/page_help.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

enum _ModeChoice { automatic, appManaged, providerManaged }

class SubscriptionFormView extends StatelessWidget {
  const SubscriptionFormView({
    super.key,
    required this.supportText,
    required this.nameLabel,
    required this.nameController,
    this.nameHint,
    this.nameErrorText,
    this.nameFocusNode,
    this.onNameChanged,
    required this.urlLabel,
    required this.urlController,
    required this.userAgentController,
    this.urlHint,
    this.urlHelper,
    this.urlErrorText,
    this.urlFocusNode,
    this.onUrlChanged,
    this.userAgentErrorText,
    this.userAgentFocusNode,
    this.onUserAgentChanged,
    required this.panel,
    required this.mode,
    required this.onPanelChanged,
    required this.onModeChanged,
    this.automaticModeAllowed = true,
    required this.hwidTitle,
    required this.hwidDescription,
    required this.hwidEnabled,
    required this.onHwidChanged,
    required this.encryptionTitle,
    required this.ageProviderSupportTitle,
    required this.ageProviderSupportDescription,
    required this.ageSecretKeyLabel,
    required this.ageSecretKeyHint,
    required this.ageSecretKeyController,
    required this.agePublicKeyLabel,
    required this.agePublicKeyHint,
    required this.agePublicKeyController,
    this.ageKeyPairErrorText,
    required this.obscureAgeSecretKey,
    required this.revealAgeSecretKeyLabel,
    required this.hideAgeSecretKeyLabel,
    required this.generateAgeKeyLabel,
    required this.generateAgeX25519KeyLabel,
    required this.generateAgeHybridKeyLabel,
    required this.clearAgeKeyLabel,
    required this.onToggleAgeSecretKeyVisibility,
    required this.onGenerateAgeKey,
    required this.onClearAgeKey,
    this.generatingAgeKeyType,
    this.ageKeyActionsEnabled = true,
    required this.hasAgeKeys,
    required this.ageExpanded,
    required this.onToggleAgeExpanded,
  });

  final String supportText;
  final String nameLabel;
  final TextEditingController nameController;
  final String? nameHint;
  final String? nameErrorText;
  final FocusNode? nameFocusNode;
  final ValueChanged<String>? onNameChanged;
  final String urlLabel;
  final TextEditingController urlController;
  final TextEditingController userAgentController;
  final String? urlHint;
  final String? urlHelper;
  final String? urlErrorText;
  final FocusNode? urlFocusNode;
  final ValueChanged<String>? onUrlChanged;
  final String? userAgentErrorText;
  final FocusNode? userAgentFocusNode;
  final ValueChanged<String>? onUserAgentChanged;
  final SubscriptionPanel panel;
  final SubscriptionMode? mode;
  final ValueChanged<SubscriptionPanel>? onPanelChanged;
  final ValueChanged<SubscriptionMode?>? onModeChanged;
  final bool automaticModeAllowed;
  final String hwidTitle;
  final String hwidDescription;
  final bool hwidEnabled;
  final ValueChanged<bool>? onHwidChanged;
  final String encryptionTitle;
  final String ageProviderSupportTitle;
  final String ageProviderSupportDescription;
  final String ageSecretKeyLabel;
  final String ageSecretKeyHint;
  final TextEditingController ageSecretKeyController;
  final String agePublicKeyLabel;
  final String agePublicKeyHint;
  final TextEditingController agePublicKeyController;
  final String? ageKeyPairErrorText;
  final bool obscureAgeSecretKey;
  final String revealAgeSecretKeyLabel;
  final String hideAgeSecretKeyLabel;
  final String generateAgeKeyLabel;
  final String generateAgeX25519KeyLabel;
  final String generateAgeHybridKeyLabel;
  final String clearAgeKeyLabel;
  final VoidCallback onToggleAgeSecretKeyVisibility;
  final ValueChanged<AgeKeyType> onGenerateAgeKey;
  final VoidCallback onClearAgeKey;
  final AgeKeyType? generatingAgeKeyType;
  final bool ageKeyActionsEnabled;
  final bool hasAgeKeys;
  final bool ageExpanded;
  final VoidCallback onToggleAgeExpanded;
  bool get generatingAgeKey => generatingAgeKeyType != null;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _fields(context),
      const SizedBox(height: 12),
      _editableField(
        context,
        label: AppLocalizations.of(context)!.subscriptionUserAgentTitle,
        controller: userAgentController,
        hintText: AppLocalizations.of(context)!.subscriptionUserAgentHint,
        textDirection: TextDirection.ltr,
        errorText: userAgentErrorText,
        focusNode: userAgentFocusNode,
        onChanged: onUserAgentChanged,
      ),
      const SizedBox(height: 14),
      _configurationCard(context),
      const SizedBox(height: 14),
      _SubscriptionAdvanced(
        configured: hwidEnabled || hasAgeKeys,
        hasError: ageKeyPairErrorText != null,
        summary: hwidEnabled || hasAgeKeys
            ? AppLocalizations.of(context)!.subscriptionAdvancedConfigured(
                [if (hwidEnabled) 'HWID', if (hasAgeKeys) 'Age'].join(' · '),
              )
            : AppLocalizations.of(context)!.subscriptionAdvancedOff,
        child: Column(
          spacing: 14,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_hwidCard(context), _encryptionCard(context)],
        ),
      ),
    ],
  );

  Widget _configurationCard(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final choice = switch (mode) {
      null => _ModeChoice.automatic,
      SubscriptionMode.appManaged => _ModeChoice.appManaged,
      SubscriptionMode.providerManaged => _ModeChoice.providerManaged,
    };
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _configurationRow(
            context,
            title: l.subscriptionPanelTitle,
            help: supportText,
            trailing: SettingSelect<SubscriptionPanel>(
              key: const ValueKey('subscription-panel'),
              value: panel,
              entries: {
                SubscriptionPanel.generic: l.subscriptionPanelGeneric,
                SubscriptionPanel.remnawave: 'Remnawave',
              },
              onChanged: onPanelChanged == null
                  ? null
                  : (value) {
                      if (value != null) onPanelChanged!(value);
                    },
            ),
          ),
          Divider(height: 1, color: palette.border),
          _configurationRow(
            context,
            title: l.subscriptionModeTitle,
            help: l.subscriptionModeDescription,
            trailing: SettingSelect<_ModeChoice>(
              key: const ValueKey('subscription-mode'),
              value: choice,
              entries: {
                if (automaticModeAllowed || mode == null)
                  _ModeChoice.automatic: l.subscriptionModeAutomatic,
                _ModeChoice.appManaged: l.subscriptionModeAppManaged,
                _ModeChoice.providerManaged: l.subscriptionModeProviderManaged,
              },
              onChanged: onModeChanged == null
                  ? null
                  : (value) {
                      if (value == null) return;
                      onModeChanged!(switch (value) {
                        _ModeChoice.automatic => null,
                        _ModeChoice.appManaged => SubscriptionMode.appManaged,
                        _ModeChoice.providerManaged =>
                          SubscriptionMode.providerManaged,
                      });
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _configurationRow(
    BuildContext context, {
    required String title,
    required Widget trailing,
    String? help,
  }) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 400
        ? Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.subscriptionAgeTitle,
                      ),
                    ),
                    if (help != null)
                      PageHelpButton(title: title, messages: [help]),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: trailing,
                ),
              ],
            ),
          )
        : SettingRow(
            title: title,
            titleTrailing: help == null
                ? null
                : PageHelpButton(title: title, messages: [help]),
            titleMaxLines: 3,
            titleStyle: AppTypography.subscriptionAgeTitle,
            contentPadding: const EdgeInsets.all(13),
            trailing: trailing,
          ),
  );

  Widget _hwidCard(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: SettingRow(
        title: hwidTitle,
        titleMaxLines: 3,
        titleStyle: AppTypography.subscriptionAgeTitle,
        contentPadding: const EdgeInsets.all(13),
        titleTrailing: PageHelpButton(
          title: hwidTitle,
          messages: [hwidDescription],
        ),
        enabled: onHwidChanged != null,
        onTap: onHwidChanged == null
            ? null
            : () => onHwidChanged!(!hwidEnabled),
        trailing: ShadSwitch(
          value: hwidEnabled,
          enabled: onHwidChanged != null,
          onChanged: onHwidChanged,
        ),
      ),
    );
  }

  Widget _fields(BuildContext context) {
    final fields = [
      _editableField(
        context,
        label: nameLabel,
        controller: nameController,
        hintText: nameHint ?? nameLabel,
        errorText: nameErrorText,
        focusNode: nameFocusNode,
        onChanged: onNameChanged,
      ),
      _editableField(
        context,
        label: urlLabel,
        controller: urlController,
        hintText: urlHint,
        helperText: urlHelper,
        textDirection: TextDirection.ltr,
        keyboardType: TextInputType.url,
        errorText: urlErrorText,
        focusNode: urlFocusNode,
        onChanged: onUrlChanged,
      ),
    ];
    if (MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint) {
      return Column(
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: fields,
      );
    }
    return Row(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: fields[0]),
        Expanded(flex: 5, child: fields[1]),
      ],
    );
  }

  Widget _notice(BuildContext context, String text, {bool warning = false}) {
    final palette = ColorManager.palette(context);
    return Container(
      padding: EdgeInsets.all(warning ? 10 : 12),
      decoration: BoxDecoration(
        color: warning ? palette.warningSurface : palette.selectedSurface,
        borderRadius: BorderRadius.circular(
          warning ? AppRadii.control : AppRadii.card,
        ),
      ),
      child: Row(
        spacing: warning ? 8 : 10,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.info,
            size: warning ? 17 : 18,
            color: warning ? palette.restarting : palette.primary,
          ),
          Expanded(
            child: Text(
              text,
              style:
                  (warning
                          ? AppTypography.subscriptionAgeWarning
                          : AppTypography.subscriptionInfo)
                      .copyWith(color: palette.mutedStrong),
            ),
          ),
        ],
      ),
    );
  }

  Widget _encryptionCard(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: ageExpanded,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.card),
              onTap: onToggleAgeExpanded,
              child: Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                child: Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: Column(
                        spacing: 3,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            encryptionTitle,
                            style: AppTypography.subscriptionAgeTitle,
                          ),
                          Text(
                            ageProviderSupportTitle,
                            style: AppTypography.subscriptionAgeOptional
                                .copyWith(color: palette.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      ageExpanded
                          ? LucideIcons.arrowDown
                          : LucideIcons.arrowRightDir,
                      size: 18,
                      textDirection: Directionality.of(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (ageExpanded) ...[
            Divider(height: 0, color: palette.border),
            Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                spacing: 12,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _notice(
                    context,
                    ageProviderSupportDescription,
                    warning: true,
                  ),
                  Column(
                    spacing: 7,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fieldLabel(context, ageSecretKeyLabel),
                      Row(
                        spacing: 6,
                        children: [
                          Expanded(
                            child: _input(
                              context,
                              label: ageSecretKeyLabel,
                              controller: ageSecretKeyController,
                              hintText: ageSecretKeyHint,
                              obscureText: obscureAgeSecretKey,
                              enabled: !generatingAgeKey,
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                          IconButton(
                            tooltip: obscureAgeSecretKey
                                ? revealAgeSecretKeyLabel
                                : hideAgeSecretKeyLabel,
                            onPressed: onToggleAgeSecretKeyVisibility,
                            style: IconButton.styleFrom(
                              foregroundColor: palette.mutedStrong,
                              minimumSize: Size.square(
                                AppLayout.touchExtent(
                                  36,
                                  platform: Theme.of(context).platform,
                                ),
                              ),
                              maximumSize: Size.square(
                                AppLayout.touchExtent(
                                  36,
                                  platform: Theme.of(context).platform,
                                ),
                              ),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: Icon(
                              obscureAgeSecretKey
                                  ? LucideIcons.eye
                                  : LucideIcons.eyeOff,
                              size: 17,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  _editableField(
                    context,
                    label: agePublicKeyLabel,
                    controller: agePublicKeyController,
                    hintText: agePublicKeyHint,
                    enabled: !generatingAgeKey,
                    textDirection: TextDirection.ltr,
                  ),
                  if (ageKeyPairErrorText != null)
                    Text(
                      ageKeyPairErrorText!,
                      style: AppTypography.subscriptionAgeWarning.copyWith(
                        color: palette.destructive,
                      ),
                    ),
                  _keyActions(context),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _keyActions(BuildContext context) {
    final palette = ColorManager.palette(context);
    Widget generate(AgeKeyType type, String label) => OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.foreground,
        minimumSize: Size.square(
          AppLayout.touchExtent(36, platform: Theme.of(context).platform),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: AppTypography.subscriptionAgeAction,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      ),
      onPressed: generatingAgeKey || !ageKeyActionsEnabled
          ? null
          : () => onGenerateAgeKey(type),
      icon: generatingAgeKeyType == type
          ? const ButtonProgressIndicator()
          : const Icon(LucideIcons.keyRound, size: 16),
      label: Text(label),
    );
    final generators = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        generate(AgeKeyType.x25519, generateAgeX25519KeyLabel),
        generate(AgeKeyType.hybrid, generateAgeHybridKeyLabel),
      ],
    );
    final clear = TextButton(
      onPressed: generatingAgeKey || !ageKeyActionsEnabled || !hasAgeKeys
          ? null
          : onClearAgeKey,
      style: TextButton.styleFrom(
        minimumSize: Size.square(
          AppLayout.touchExtent(38, platform: Theme.of(context).platform),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: AppTypography.subscriptionClear,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(clearAgeKeyLabel),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: generateAgeKeyLabel,
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 400
            ? Column(
                spacing: 8,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  generators,
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: clear,
                  ),
                ],
              )
            : Row(
                spacing: 8,
                children: [
                  Expanded(child: generators),
                  clear,
                ],
              ),
      ),
    );
  }

  Widget _input(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? hintText,
    TextDirection? textDirection,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool enabled = true,
    ValueChanged<String>? onChanged,
    FocusNode? focusNode,
    String? errorText,
  }) {
    final palette = ColorManager.palette(context);
    return Directionality(
      textDirection: textDirection ?? Directionality.of(context),
      child: MergeSemantics(
        child: Semantics(
          label: label,
          hint: errorText ?? hintText,
          child: ShadInput(
            enabled: enabled,
            controller: controller,
            focusNode: focusNode,
            placeholder: hintText == null
                ? null
                : ExcludeSemantics(child: Text(hintText)),
            constraints: BoxConstraints(
              minHeight: AppLayout.touchExtent(
                42,
                platform: Theme.of(context).platform,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            style: AppTypography.subscriptionField,
            placeholderStyle: AppTypography.subscriptionField.copyWith(
              color: palette.mutedForeground,
            ),
            textDirection: textDirection,
            keyboardType: keyboardType,
            obscureText: obscureText,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: onChanged,
            decoration: ShadDecoration(
              hasError: errorText != null,
              border: ShadBorder.all(
                color: palette.border,
                radius: BorderRadius.circular(AppRadii.card),
              ),
              errorBorder: ShadBorder.all(
                color: palette.destructive,
                radius: BorderRadius.circular(AppRadii.card),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editableField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? hintText,
    String? helperText,
    TextDirection? textDirection,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    FocusNode? focusNode,
    String? errorText,
    bool enabled = true,
  }) {
    return Column(
      spacing: 7,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(context, label),
        _input(
          context,
          label: label,
          controller: controller,
          hintText: hintText,
          textDirection: textDirection,
          keyboardType: keyboardType,
          onChanged: onChanged,
          focusNode: focusNode,
          errorText: errorText,
          enabled: enabled,
        ),
        if (errorText != null)
          Semantics(
            liveRegion: true,
            child: Text(
              errorText,
              style: AppTypography.subscriptionAgeWarning.copyWith(
                color: ColorManager.palette(context).destructive,
              ),
            ),
          ),
        if (helperText != null && helperText.isNotEmpty)
          Text(
            helperText,
            style: AppTypography.subscriptionAgeWarning.copyWith(
              color: ColorManager.palette(context).mutedForeground,
            ),
          ),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String text) {
    final label = Text(
      text,
      style: AppTypography.subscriptionField.copyWith(
        color: ColorManager.palette(context).mutedStrong,
      ),
    );
    // macOS's native text input bridge does not expose the merged field label.
    // Keep the adjacent visible label available to accessibility traversal.
    return Theme.of(context).platform == TargetPlatform.macOS
        ? label
        : ExcludeSemantics(child: label);
  }
}

class _SubscriptionAdvanced extends StatefulWidget {
  const _SubscriptionAdvanced({
    required this.configured,
    required this.hasError,
    required this.summary,
    required this.child,
  });

  final bool configured;
  final bool hasError;
  final String summary;
  final Widget child;

  @override
  State<_SubscriptionAdvanced> createState() => _SubscriptionAdvancedState();
}

class _SubscriptionAdvancedState extends State<_SubscriptionAdvanced> {
  late bool _expanded = widget.configured || widget.hasError;

  @override
  void didUpdateWidget(covariant _SubscriptionAdvanced oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.configured && widget.configured) ||
        (!oldWidget.hasError && widget.hasError)) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          child: InkWell(
            key: const ValueKey('subscription-advanced'),
            borderRadius: BorderRadius.circular(AppRadii.card),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
                      spacing: 3,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.prototypeAdvanced,
                          style: AppTypography.subscriptionAgeTitle,
                        ),
                        Text(
                          widget.summary,
                          style: AppTypography.subscriptionAgeOptional.copyWith(
                            color: palette.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? LucideIcons.arrowDown
                        : LucideIcons.arrowRightDir,
                    size: 18,
                    textDirection: Directionality.of(context),
                  ),
                ],
              ),
            ),
          ),
        ),
        ExcludeFocus(
          excluding: !_expanded,
          child: Offstage(
            offstage: !_expanded,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}
