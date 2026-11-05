import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/navigation.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/service/settings/backup/service.dart';

class PageEmptyState extends StatelessWidget {
  const PageEmptyState({
    super.key,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.scrollController,
  });

  final String title, description, primaryLabel;
  final String? secondaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final palette = ColorManager.palette(context);
    final padding = mobile
        ? const EdgeInsets.fromLTRB(15, 13, 15, 22)
        : const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.desktopPageTop,
            AppSpacing.page,
            AppSpacing.desktopPageBottom,
          );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        controller: scrollController,
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: mobile && constraints.hasBoundedHeight
                ? (constraints.maxHeight - padding.vertical).clamp(
                    0.0,
                    double.infinity,
                  )
                : AppLayout.emptyStateDesktopMinHeight,
          ),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: AppDashedBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
                side: BorderSide(color: palette.borderStrong),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(mobile ? 28 : 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.layers3,
                    size: 34,
                    color: palette.mutedForeground,
                  ),
                  const SizedBox(height: 13),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTypography.panelTitle.copyWith(
                      color: palette.foreground,
                    ),
                  ),
                  const SizedBox(height: 13),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppLayout.emptyStateTextMaxWidth,
                    ),
                    child: Text(
                      description,
                      textAlign: TextAlign.center,
                      style: AppTypography.dialogBody.copyWith(
                        color: palette.mutedForeground,
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  FilledButton.icon(
                    onPressed: onPrimary,
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text(primaryLabel),
                  ),
                  if (BackupService.supported) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.pushScoped(AppPageDestination.backup),
                      icon: const Icon(LucideIcons.rotateCcw, size: 18),
                      label: Text(
                        AppLocalizations.of(context)!.backupRestoreFrom,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  if (secondaryLabel != null && onSecondary != null) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: onSecondary,
                      child: Text(secondaryLabel!, textAlign: TextAlign.center),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
