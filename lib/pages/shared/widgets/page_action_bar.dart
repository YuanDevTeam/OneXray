import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A full-page footer. Use as Scaffold.bottomNavigationBar, not inside a scroll
/// view. Dialogs own their actions and do not use this component.
class PageActionBar extends StatelessWidget {
  const PageActionBar({
    super.key,
    required this.children,
    this.horizontalPadding,
    this.verticalPadding,
    this.spacing = AppSpacing.actionGap,
    this.expandDesktop = false,
    this.maxWidth = AppLayout.standardMaxWidth,
  });

  final List<Widget> children;
  final double? horizontalPadding;
  final double? verticalPadding;
  final double spacing;
  final bool expandDesktop;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final minHeight = mobile
        ? AppLayout.mobilePageActionMinHeight
        : AppLayout.pageActionMinHeight;
    final buttonMinHeight = AppLayout.touchExtent(
      mobile ? AppLayout.mobileButtonMinHeight : AppLayout.buttonMinHeight,
      platform: Theme.of(context).platform,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        horizontalPadding ??
                        (mobile ? AppSpacing.mobilePage : AppSpacing.page),
                    vertical:
                        verticalPadding ?? (minHeight - buttonMinHeight) / 2,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: mobile || expandDesktop
                        ? Theme(
                            data: mobile
                                ? AppTheme.pageActions(context)
                                : Theme.of(context),
                            child: ShadTheme(
                              data: mobile
                                  ? AppTheme.pageActionsShad(context)
                                  : ShadTheme.of(context),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  for (
                                    var index = 0;
                                    index < children.length;
                                    index++
                                  ) ...[
                                    if (index > 0) SizedBox(width: spacing),
                                    Expanded(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: buttonMinHeight,
                                        ),
                                        child: children[index],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : _wideButtons(
                            context,
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: spacing,
                              runSpacing: AppSpacing.actionRunGap,
                              children: [
                                for (final child in children)
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: buttonMinHeight,
                                    ),
                                    child: child,
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wideButtons(BuildContext context, Widget child) {
    final shad = ShadTheme.maybeOf(context);
    if (shad == null) return child;
    // Shad paints the outline's two border pixels outside its content height.
    final sizes = shad.outlineButtonTheme.sizesTheme ?? shad.buttonSizesTheme;
    final regular = sizes.regular ?? shad.buttonSizesTheme.regular!;
    return ShadTheme(
      data: shad.copyWith(
        outlineButtonTheme: shad.outlineButtonTheme.copyWith(
          sizesTheme: sizes.copyWith(
            regular: regular.copyWith(height: regular.height - 2),
          ),
        ),
      ),
      child: child,
    );
  }
}
