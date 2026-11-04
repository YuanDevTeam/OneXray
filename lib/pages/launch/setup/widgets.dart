import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';

/// Setup uses the same top-aligned, single-column content flow as other pages.
class SetupBody extends StatelessWidget {
  const SetupBody({super.key, required this.children, this.top = 16});

  final List<Widget> children;
  final double top;

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: ResponsiveContent(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            mobile ? AppSpacing.mobilePage : AppSpacing.page,
            top,
            mobile ? AppSpacing.mobilePage : AppSpacing.page,
            24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class SetupActionButton extends StatelessWidget {
  const SetupActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.outline = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool outline;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final palette = ColorManager.palette(context);
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, mobile ? 48 : 42)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      textStyle: WidgetStatePropertyAll(AppTypography.control),
      backgroundColor: outline
          ? null
          : WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? palette.border.withValues(alpha: .7)
                  : null,
            ),
      foregroundColor: outline
          ? null
          : WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? palette.mutedForeground.withValues(alpha: .7)
                  : null,
            ),
    );
    final text = ButtonProgress(
      busy: busy,
      child: Text(label, textAlign: TextAlign.center),
    );
    return outline
        ? OutlinedButton(onPressed: onPressed, style: style, child: text)
        : FilledButton(onPressed: onPressed, style: style, child: text);
  }
}

class SetupPoint extends StatelessWidget {
  const SetupPoint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    final palette = ColorManager.palette(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 23, color: palette.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style:
                (mobile
                        ? AppTypography.setupPoint
                        : AppTypography.setupDesktopPoint)
                    .copyWith(color: palette.mutedStrong),
          ),
        ),
      ],
    );
  }
}

class SetupError extends StatelessWidget {
  const SetupError({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: AppTypography.setupError.copyWith(
          color: ColorManager.palette(context).destructive,
        ),
      ),
    ),
  );
}
