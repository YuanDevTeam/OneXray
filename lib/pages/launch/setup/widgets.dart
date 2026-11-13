import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';

/// A full-page setup layout. The surrounding Scaffold owns fixed actions.
class SetupBody extends StatelessWidget {
  const SetupBody({
    super.key,
    required this.children,
    this.header,
    this.bottom,
    this.top = 24,
  });

  final List<Widget> children;
  final Widget? header;
  final Widget? bottom;
  final double top;

  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ResponsiveContent(
          desktopMaxWidth: AppLayout.setupContentMaxWidth,
          adaptiveBreakpoint: AppLayout.setupContentMaxWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                mobile ? AppSpacing.mobilePage : AppSpacing.page,
                top,
                mobile ? AppSpacing.mobilePage : AppSpacing.page,
                mobile ? 24 : 32,
              ),
              child: Column(
                mainAxisAlignment: header != null || bottom != null
                    ? MainAxisAlignment.spaceBetween
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?header,
                  Padding(
                    padding: EdgeInsets.only(
                      top: header == null ? 0 : 32,
                      bottom: bottom == null ? 0 : 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                  ?bottom,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SetupProgress extends StatelessWidget {
  const SetupProgress({super.key, required this.current, required this.labels});

  final int current;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          if (index > 0)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 16, 12, 0),
              child: SizedBox(
                width: 24,
                child: Divider(height: 1, color: palette.borderStrong),
              ),
            ),
          Expanded(
            child: Semantics(
              selected: index == current,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: const EdgeInsets.all(4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index == current
                          ? palette.primarySolid
                          : index < current
                          ? palette.selectedSurface
                          : palette.card,
                      shape: BoxShape.circle,
                      border: index > current
                          ? Border.all(color: palette.borderStrong)
                          : null,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: AppTypography.control.copyWith(
                        color: index == current
                            ? palette.primaryForeground
                            : index < current
                            ? palette.primaryText
                            : palette.mutedForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        labels[index],
                        style:
                            (index == current
                                    ? AppTypography.setupStepActive
                                    : AppTypography.setupStepLabel)
                                .copyWith(
                                  color: index == current
                                      ? palette.foreground
                                      : palette.mutedForeground,
                                ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class SetupIntro extends StatelessWidget {
  const SetupIntro({
    super.key,
    required this.icon,
    required this.title,
    this.description,
  });

  final IconData icon;
  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.selectedSurface,
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Icon(icon, color: palette.primaryText, size: 28),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint
              ? AppTypography.setupTitle
              : AppTypography.setupDesktopTitle,
        ),
        if (description != null) ...[
          const SizedBox(height: 10),
          Text(
            description!,
            style: AppTypography.rowValue.copyWith(color: palette.mutedStrong),
          ),
        ],
      ],
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
    final palette = ColorManager.palette(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 22, color: palette.primaryText),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: AppTypography.rowValue.copyWith(color: palette.mutedStrong),
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
