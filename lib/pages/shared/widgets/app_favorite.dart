import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/theme/theme.dart';

/// The owning action supplies the accessible name for this decorative glyph.
class AppFavoriteIcon extends StatelessWidget {
  const AppFavoriteIcon({
    super.key,
    required this.selected,
    this.enabled = true,
    this.busy = false,
    this.size = 18,
  });

  final bool selected;
  final bool enabled;
  final bool busy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.favoriteForeground(
      context,
      selected: selected,
      enabled: enabled && !busy,
    );
    return SizedBox.square(
      dimension: size,
      child: busy
          ? DefaultTextStyle.merge(
              style: TextStyle(color: color),
              child: ButtonProgressIndicator(size: size),
            )
          : Icon(
              // The pinned Lucide star weights are all outlines.
              selected ? Icons.star_rounded : Icons.star_border_rounded,
              color: color,
              size: size,
            ),
    );
  }
}

class AppFavoriteButton extends StatelessWidget {
  const AppFavoriteButton({
    super.key,
    required this.selected,
    required this.tooltip,
    this.onPressed,
    this.busy = false,
    this.size = 18,
  });

  final bool selected;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    isSelected: selected,
    onPressed: busy ? null : onPressed,
    style: AppTheme.favoriteButton(context),
    icon: AppFavoriteIcon(
      selected: selected,
      enabled: onPressed != null,
      busy: busy,
      size: size,
    ),
  );
}
