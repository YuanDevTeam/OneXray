import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/setting_row.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';

class SettingsUpdateDot extends StatelessWidget {
  const SettingsUpdateDot({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      shape: BoxShape.circle,
    ),
  );
}

class SettingsVersionRow extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;
  final TextStyle? style;
  const SettingsVersionRow({
    super.key,
    required this.label,
    required this.value,
    this.compact = false,
    this.style,
  });
  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return SettingRow(
        title: label,
        trailing: Text(
          value,
          textDirection: TextDirection.ltr,
          style: AppTypography.code,
        ),
      );
    }
    return SettingRow(
      title: label,
      titleStyle: style ?? AppTypography.rowTitle,
      trailing: Text(
        value,
        textDirection: TextDirection.ltr,
        style: AppTypography.rowValue,
      ),
    );
  }
}

class SettingsThemeOptions extends StatelessWidget {
  const SettingsThemeOptions({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ThemeCode selected;
  final ValueChanged<ThemeCode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final labels = {
      ThemeCode.system: l.prototypeSystem,
      ThemeCode.light: l.prototypeLight,
      ThemeCode.dark: l.prototypeDark,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.themePageTitle, style: AppTypography.rowValue),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final theme in ThemeCode.values)
              Semantics(
                selected: selected == theme,
                child: selected == theme
                    ? ShadButton(
                        height: 48,
                        onPressed: () => onSelected(theme),
                        child: Text(labels[theme]!),
                      )
                    : ShadButton.outline(
                        height: 48,
                        onPressed: () => onSelected(theme),
                        child: Text(labels[theme]!),
                      ),
              ),
          ],
        ),
      ],
    );
  }
}

EdgeInsets settingsContentPadding(BuildContext context) {
  final mobile = MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
  return EdgeInsets.fromLTRB(
    mobile ? AppSpacing.mobilePage : AppSpacing.page,
    20,
    mobile ? AppSpacing.mobilePage : AppSpacing.page,
    36,
  );
}

/// Keeps short actions compact while letting localized labels wrap in tight rows.
class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ShadButtonVariant.primary,
    this.enabled = true,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ShadButtonVariant variant;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile =
          MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: AppTypography.control.copyWith(fontFamily: AppFontFamily.sans),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.localeOf(context),
      )..layout();
      final progressWidth = busy ? 24.0 : 0.0;
      // Shad's outline border sits outside the button's content constraints.
      final borderExtent = variant == ShadButtonVariant.outline ? 2.0 : 0.0;
      final available = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final outerWidth = math.min(
        available,
        painter.width.ceilToDouble() + 32 + progressWidth + borderExtent,
      );
      final width = math.max(0.0, outerWidth - borderExtent);
      painter.layout(maxWidth: math.max(1.0, width - 32 - progressWidth));
      final height = math.max(
        AppLayout.touchExtent(
              mobile ? 48 : 42,
              platform: Theme.of(context).platform,
            ) -
            borderExtent,
        painter.height.ceilToDouble() + 16,
      );
      painter.dispose();
      return ShadButton.raw(
        variant: variant,
        enabled: enabled && onPressed != null,
        onPressed: onPressed,
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        expands: true,
        child: ButtonProgress(
          busy: busy,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.control,
          ),
        ),
      );
    },
  );
}
