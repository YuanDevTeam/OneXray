import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';

/// Small setup forms fill the viewport but still scroll on a short screen or
/// with a larger system text size. Long selector lists use slivers instead.
class SetupBody extends StatelessWidget {
  const SetupBody({super.key, required this.children, this.top = 48});

  final List<Widget> children;
  final double top;

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: mobile ? 620 : AppLayout.setupContentMaxWidth + 48,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, top, 24, mobile ? 28 : 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SetupDesktopBody extends StatelessWidget {
  const SetupDesktopBody({
    super.key,
    required this.progress,
    required this.children,
    this.bodyTop = 48,
  });

  final Widget progress;
  final List<Widget> children;
  final double bodyTop;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.setupDesktopHorizontal,
        top: AppSpacing.setupDesktopTop,
        end: AppSpacing.setupDesktopHorizontal,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('OneXray', style: AppTypography.setupBrand),
          const SizedBox(height: 10),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.setupProgressMaxWidth,
              ),
              child: progress,
            ),
          ),
          _content(),
        ],
      ),
    ),
  );

  Widget _content() => Align(
    alignment: AlignmentDirectional.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppLayout.setupContentMaxWidth,
      ),
      child: Padding(
        padding: EdgeInsets.only(top: bodyTop, bottom: 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

class SetupFooter extends StatelessWidget {
  const SetupFooter({super.key, required this.children, this.note});

  final List<Widget> children;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    if (mobile) {
      return PageActionBar(
        horizontalPadding: 24,
        verticalPadding: 16,
        spacing: 14,
        children: children,
      );
    }
    final palette = ColorManager.palette(context);
    return Material(
      color: palette.card,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.setupFooterMaxWidth,
                minHeight: AppLayout.setupFooterMinHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.setupDesktopHorizontal,
                  vertical: 18,
                ),
                child: children.length == 1
                    ? Row(
                        children: [
                          const Spacer(),
                          SizedBox(
                            width: AppLayout.setupFooterButtonWidth,
                            child: children.single,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          SizedBox(
                            width: AppLayout.setupFooterButtonWidth,
                            child: children.first,
                          ),
                          Expanded(
                            child: note == null
                                ? const SizedBox.shrink()
                                : Text(
                                    note!,
                                    textAlign: TextAlign.center,
                                    style: AppTypography.setupStatus.copyWith(
                                      color: palette.mutedForeground,
                                    ),
                                  ),
                          ),
                          SizedBox(
                            width: AppLayout.setupFooterButtonWidth,
                            child: children.last,
                          ),
                        ],
                      ),
              ),
            ),
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
