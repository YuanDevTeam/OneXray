import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/pages/main/router.dart';
import 'package:onexray/service/launch/app_startup.dart';
import 'package:onexray/service/shared/menu/short_cut/service.dart';
import 'package:onexray/service/shared/menu/settings/service.dart';
import 'package:onexray/service/shared/menu/window/service.dart';
import 'package:onexray/service/shared/share/service.dart';
import 'package:onexray/service/shared/apple_widget/service.dart';

const _desktopWindowSize = Size(1160, 720);
const _minimumDesktopWindowSize = Size(480, 600);

Future<void> main(List<String> _) async {
  WidgetsFlutterBinding.ensureInitialized();

  await ShortCutService().initialize();
  ShareService().startAppLinks();
  await _initBridge();
  await AppleWidgetService().initialize();
  final appStartup = AppStartupService();
  await appStartup.prepare();

  if (AppPlatform.isDesktop) {
    await WindowService().prepare(
      size: _desktopWindowSize,
      minimumSize: _minimumDesktopWindowSize,
    );
  }

  MacOSSettingsMenuService().initialize();
  runApp(GoRouteApp());
  // Hidden windows may not render frames. Keep visibility independent from
  // first-frame callbacks and preserve the existing hidden-start policy.
  await appStartup.onWindowReady();
}

Future<void> _initBridge() async {
  BridgeFlutterApi.setUp(AppFlutterApi());
  await AppHostApi().initTunFilesDir();
}
