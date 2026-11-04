import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/launch/setup/widgets.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/service/shared/doc/helper.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

class _PrivacyController extends PageCubit<({bool busy, bool failed})> {
  _PrivacyController() : super((busy: false, failed: false));

  Future<void> openPolicy() async {
    if (state.busy) return;
    emit((busy: true, failed: false));
    try {
      final opened = await launchUrl(DocURLHelper.privacyUri());
      emit((busy: false, failed: !opened));
    } catch (_) {
      emit((busy: false, failed: true));
    }
  }

  void back(BuildContext context) => context.pop();
}

class SetupPrivacyPage extends StatelessWidget {
  const SetupPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => _PrivacyController(),
    child: BlocBuilder<_PrivacyController, ({bool busy, bool failed})>(
      builder: (context, state) {
        final controller = context.read<_PrivacyController>();
        return SetupPrivacyView(
          busy: state.busy,
          failureText: state.failed
              ? AppLocalizations.of(context)!.prototypeTemporarilyUnavailable
              : null,
          onBack: () => controller.back(context),
          onOpenPolicy: controller.openPolicy,
        );
      },
    ),
  );
}

class SetupPrivacyView extends StatelessWidget {
  const SetupPrivacyView({
    super.key,
    this.busy = false,
    this.failureText,
    required this.onBack,
    required this.onOpenPolicy,
  });

  final bool busy;
  final String? failureText;
  final VoidCallback onBack;
  final VoidCallback onOpenPolicy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final palette = ColorManager.palette(context);
    final detailStyle = AppTypography.rowValue.copyWith(
      color: palette.mutedForeground,
    );
    return Scaffold(
      appBar: PageAppBar(
        leading: IconButton(
          tooltip: l.prototypeBack,
          onPressed: onBack,
          icon: const Icon(LucideIcons.arrowLeftDir),
        ),
        title: Text(l.prototypePrivacyPolicy),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: SetupBody(
          children: [
            Text(l.prototypeNoDataUpload, style: AppTypography.rowValue),
            const SizedBox(height: 24),
            Text(l.prototypeConfiguredSourcesNotice, style: detailStyle),
            const SizedBox(height: 24),
            Text(l.prototypeRegionPrivacyNotice, style: detailStyle),
            const SizedBox(height: 24),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: busy ? null : onOpenPolicy,
                icon: const Icon(LucideIcons.externalLink, size: 18),
                label: ButtonProgress(
                  busy: busy,
                  child: Text(l.prototypeReadFullPrivacyPolicy),
                ),
              ),
            ),
            if (failureText != null) SetupError(text: failureText!),
          ],
        ),
      ),
      bottomNavigationBar: PageActionBar(
        children: [
          SetupActionButton(label: l.prototypeBack, onPressed: onBack),
        ],
      ),
    );
  }
}
