import 'package:material_ui/material_ui.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/log/controller.dart';
import 'package:onexray/pages/advanced/xray/log/params.dart';
import 'package:onexray/pages/advanced/xray/runtime_code_view.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';

class LogFileViewerPage extends StatelessWidget {
  final LogFileViewerParams params;

  const LogFileViewerPage({super.key, required this.params});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => LogFileViewerController(params),
    child: BlocBuilder<LogFileViewerController, LogFileViewerPageState>(
      builder: (context, state) {
        final controller = context.read<LogFileViewerController>();
        return LogFileViewerView(
          state: state,
          onExport: () => controller.export(context),
          onFollowTail: controller.setFollowTail,
        );
      },
    ),
  );
}

class LogFileViewerView extends StatefulWidget {
  const LogFileViewerView({
    super.key,
    required this.state,
    required this.onExport,
    required this.onFollowTail,
  });

  final LogFileViewerPageState state;
  final VoidCallback onExport;
  final ValueChanged<bool> onFollowTail;

  @override
  State<LogFileViewerView> createState() => _LogFileViewerViewState();
}

class _LogFileViewerViewState extends State<LogFileViewerView> {
  final _scrollController = ScrollController();
  var _autoScrolling = false;

  @override
  void initState() {
    super.initState();
    if (widget.state.followTail) _scrollToBottom();
  }

  @override
  void didUpdateWidget(LogFileViewerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.followTail &&
        (oldWidget.state.lines != widget.state.lines ||
            !oldWidget.state.followTail ||
            oldWidget.state.fileExists != widget.state.fileExists)) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return RuntimeCodeScaffold(
      title: state.title,
      status: state.followTail
          ? l.prototypeFollowing
          : l.logFileViewerContinueFollowing,
      exportLabel: l.prototypeExport,
      exporting: state.exporting,
      onExport: state.exporting || !state.fileExists ? null : widget.onExport,
      onStatusPressed: state.followTail || !state.fileExists
          ? null
          : () {
              widget.onFollowTail(true);
              _scrollToBottom();
            },
      code: !state.fileExists
          ? RuntimeCodeUnavailable(
              message: appFailureMessage(
                l,
                state.failure ?? 'Log file does not exist.',
              ),
            )
          : SelectionArea(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  _handleScrollNotification(notification);
                  return false;
                },
                child: ListView.builder(
                  key: const ValueKey('runtime-log-lines'),
                  controller: _scrollController,
                  padding: const EdgeInsets.all(18),
                  itemCount: state.lines.length + (state.truncated ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (state.truncated && index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Text(
                          l.logFileViewerShowingRecent,
                          style: AppTypography.badge.copyWith(
                            color: palette.mutedForeground,
                          ),
                        ),
                      );
                    }
                    return Text(
                      state.lines[index - (state.truncated ? 1 : 0)],
                      textDirection: TextDirection.ltr,
                      style:
                          (mobile
                                  ? AppTypography.runtimeCodeMobile
                                  : AppTypography.runtimeCodeDesktop)
                              .copyWith(
                                color: palette.foreground,
                                fontFamily: AppFontFamily.mono,
                              ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (_autoScrolling ||
        notification is! ScrollUpdateNotification ||
        notification.dragDetails == null) {
      return;
    }
    widget.onFollowTail(notification.metrics.extentAfter < 48);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _autoScrolling = true;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      _autoScrolling = false;
    });
  }
}
