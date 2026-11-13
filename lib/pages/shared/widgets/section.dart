import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SectionView extends StatelessWidget {
  final String title;
  final String? description;
  final IconData? icon;
  final Widget? action;
  final Widget? child;
  final EdgeInsetsGeometry padding;
  final bool descriptionBelow;
  final double? headerInset;

  const SectionView({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.action,
    this.child,
    this.padding = const EdgeInsetsDirectional.fromSTEB(16, 11, 16, 11),
    this.descriptionBelow = false,
    this.headerInset,
  });

  @override
  Widget build(BuildContext context) {
    final hasDescription = description != null && description!.isNotEmpty;
    final hasHeader =
        title.isNotEmpty ||
        (hasDescription && !descriptionBelow) ||
        action != null;
    if (!hasHeader && child == null && !hasDescription) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasHeader || child != null)
            ShadCard(
              width: double.infinity,
              padding: EdgeInsets.zero,
              radius: const BorderRadius.all(Radius.circular(AppRadii.card)),
              shadows: const [],
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasHeader)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.cardContent,
                          vertical: AppSpacing.sectionHeaderVertical,
                        ),
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: headerInset ?? 0,
                          ),
                          child: _header(context, hasDescription),
                        ),
                      ),
                    if (child != null)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.cardContent,
                          hasHeader ? 0 : AppSpacing.cardContent,
                          AppSpacing.cardContent,
                          AppSpacing.cardContent,
                        ),
                        child: child,
                      ),
                  ],
                ),
              ),
            ),
          if (hasDescription && descriptionBelow)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 10),
              child: Text(
                description!,
                style: AppTypography.settingsDetailNote.copyWith(
                  color: ColorManager.secondaryText(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool hasDescription) {
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Padding(
            padding: EdgeInsets.only(
              top: math.max(
                0.0,
                (MediaQuery.textScalerOf(context)
                                .scale(AppTypography.sectionTitle.fontSize!) *
                            AppTypography.sectionTitle.height! -
                        20) /
                    2,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: ColorManager.palette(context).primaryText,
            ),
          ),
          const SizedBox(width: AppSpacing.rowIconGap),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: AppTypography.sectionTitle.copyWith(
                      color: ColorManager.primaryText(context),
                    ),
                  ),
                ),
              if (hasDescription && !descriptionBelow) ...[
                if (title.isNotEmpty) const SizedBox(height: 4),
                Text(
                  description!,
                  style: AppTypography.supporting.copyWith(
                    color: ColorManager.secondaryText(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    if (action == null) return identity;
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        if (constraints.maxWidth < 280 * textScale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [identity, const SizedBox(height: 12), action!],
          );
        }
        return Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
              child: action!,
            ),
          ],
        );
      },
    );
  }
}
