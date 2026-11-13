import 'package:onexray/service/shared/failure.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/xray/config/controller.dart';
import 'package:onexray/pages/advanced/xray/config/params.dart';
import 'package:onexray/pages/advanced/xray/runtime_code_view.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/pages/theme/layout.dart';

class ConfigFileViewerPage extends StatelessWidget {
  final ConfigFileViewerParams params;

  const ConfigFileViewerPage({super.key, required this.params});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ConfigFileViewerController(params),
    child: BlocBuilder<ConfigFileViewerController, ConfigFileViewerPageState>(
      builder: (context, state) => ConfigFileViewerView(
        state: state,
        onExport: () =>
            context.read<ConfigFileViewerController>().shareFile(context),
      ),
    ),
  );
}

class ConfigFileViewerView extends StatelessWidget {
  const ConfigFileViewerView({
    super.key,
    required this.state,
    required this.onExport,
  });

  final ConfigFileViewerPageState state;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final mobile =
        MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
    return RuntimeCodeScaffold(
      title: state.title,
      status: l.prototypeReadOnly,
      exportLabel: l.prototypeExportOriginalConfiguration,
      exporting: state.exporting,
      onExport: state.loading || state.failed || state.exporting
          ? null
          : onExport,
      code: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.failed
          ? RuntimeCodeUnavailable(message: appFailureMessage(l, state.failure))
          : SelectionArea(
              child: SingleChildScrollView(
                key: const ValueKey('runtime-config-code-scroll'),
                padding: const EdgeInsets.all(18),
                child: Text(
                  state.displayText ?? state.text,
                  textDirection: TextDirection.ltr,
                  style:
                      (mobile
                              ? AppTypography.runtimeCodeMobile
                              : AppTypography.runtimeCodeDesktop)
                          .copyWith(
                            color: ColorManager.palette(context).foreground,
                            fontFamily: AppFontFamily.mono,
                          ),
                ),
              ),
            ),
    );
  }
}
