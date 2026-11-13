import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/main/url.dart';
import 'package:onexray/pages/main/desktop_window.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/pages/theme/motion.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/service/shared/event_bus/state.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class GoRouteApp extends StatelessWidget {
  const GoRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppEventBus(),
      child: BlocBuilder<AppEventBus, AppEventBusState>(
        builder: (context, state) => _buildApp(context, state),
      ),
    );
  }

  Widget _buildApp(BuildContext context, AppEventBusState state) {
    final supportedLocales = AppLocalePolicy.normalizeSupportedLocales(
      AppLocalizations.supportedLocales,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth <= AppLayout.mobileBreakpoint;
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: "OneXray",
          themeMode: state.themeCode.themeMode,
          theme: AppTheme.material(Brightness.light, mobile: mobile),
          darkTheme: AppTheme.material(Brightness.dark, mobile: mobile),
          routerConfig: RouterPath.router,
          locale: state.languageCode == LanguageCode.system
              ? null
              : state.languageCode.locale,
          localizationsDelegates: AppLocalePolicy.localizationsDelegates,
          supportedLocales: supportedLocales,
          localeResolutionCallback: AppLocalePolicy.resolve,
          builder: (context, child) {
            final routedChild = Directionality(
              textDirection:
                  Localizations.localeOf(context).languageCode == 'fa'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
            final brightness = Theme.of(context).brightness;
            return ShadTheme(
              data: AppTheme.shad(
                brightness,
                mobile: mobile,
                textScaler: MediaQuery.textScalerOf(context),
                reduceMotion: AppMotion.reducedOf(context),
              ),
              child: ShadToaster(child: DesktopWindowFrame(child: routedChild)),
            );
          },
        );
      },
    );
  }
}
