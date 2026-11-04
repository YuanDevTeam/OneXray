import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';

/// The common read-only surface for the two log files and runtime JSON.
class RuntimeCodeScaffold extends StatelessWidget {
  const RuntimeCodeScaffold({
    super.key,
    required this.title,
    required this.status,
    required this.exportLabel,
    required this.note,
    required this.code,
    this.onExport,
    this.onStatusPressed,
    this.exporting = false,
  });

  final String title;
  final String status;
  final String exportLabel;
  final String note;
  final Widget code;
  final VoidCallback? onExport;
  final VoidCallback? onStatusPressed;
  final bool exporting;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width <= AppLayout.mobileBreakpoint;
    final horizontal = mobile
        ? AppSpacing.mobilePage
        : AppSpacing.advancedDesktopGutter(width);
    const top = 20.0;
    final bottom = mobile ? 18.0 : 24.0;
    final pillContent = Material(
      color: palette.surfaceHover,
      borderRadius: BorderRadius.circular(AppRadii.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onStatusPressed,
        child: ConstrainedBox(
          constraints: onStatusPressed == null
              ? const BoxConstraints()
              : BoxConstraints(
                  minWidth: AppLayout.touchExtent(
                    36,
                    platform: Theme.of(context).platform,
                  ),
                  minHeight: AppLayout.touchExtent(
                    28,
                    platform: Theme.of(context).platform,
                  ),
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                status,
                style: AppTypography.runtimeCodePill.copyWith(
                  color: palette.mutedStrong,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final pill = Semantics(
      container: true,
      button: onStatusPressed != null,
      enabled: onStatusPressed == null ? null : true,
      child: pillContent,
    );
    final export = OutlinedButton(
      onPressed: onExport,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(
          0,
          AppLayout.touchExtent(
            mobile ? 48 : 42,
            platform: Theme.of(context).platform,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        textStyle: AppTypography.runtimeCodeAction,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (exporting)
            const ButtonProgressIndicator(size: 15)
          else
            const Icon(LucideIcons.download, size: 15),
          const SizedBox(width: 6),
          Flexible(child: Text(exportLabel, textAlign: TextAlign.center)),
        ],
      ),
    );
    return Scaffold(
      appBar: PageAppBar.forPage(context, title: Text(title)),
      body: SafeArea(
        child: ResponsiveContent(
          desktopMaxWidth: AppLayout.advancedMaxWidth,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                key: const ValueKey('runtime-code-page-scroll'),
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  top,
                  horizontal,
                  bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(
                      0,
                      constraints.maxHeight - top - bottom,
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (mobile) ...[
                          pill,
                          const SizedBox(height: 10),
                          export,
                        ] else
                          Row(children: [pill, const Spacer(), export]),
                        const SizedBox(height: 12),
                        Expanded(
                          child: SizedBox(
                            // Supplies an intrinsic minimum without measuring the
                            // scrollable code contents. Taller viewports fill it.
                            height: mobile ? 470 : 420,
                            child: Container(
                              key: const ValueKey('runtime-code-panel'),
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: palette.card,
                                border: Border.all(color: palette.border),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.card,
                                ),
                              ),
                              child: code,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.info,
                              size: 16,
                              color: palette.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                note,
                                style:
                                    (mobile
                                            ? AppTypography.runtimeCodeNote
                                            : AppTypography
                                                  .runtimeCodeDesktopNote)
                                        .copyWith(
                                          color: palette.mutedForeground,
                                        ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class RuntimeCodeUnavailable extends StatelessWidget {
  const RuntimeCodeUnavailable({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = ColorManager.palette(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.fileX, size: 36, color: palette.mutedForeground),
            const SizedBox(height: 12),
            SelectableText(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.supporting.copyWith(
                color: palette.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
