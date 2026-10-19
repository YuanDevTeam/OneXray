import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/service/advanced/policy_editor.dart';
import 'package:onexray/service/connect/dialing.dart';

class ServerDialingController extends PolicyEditorController {
  ServerDialingController({super.draft, PolicyEditorService? service})
    : super(service: service ?? PolicyEditorService(validateInterface: false));

  ServerDialingSettings get dialing =>
      ServerDialingSettings.fromJson(group('dialing'));

  bool get happyEyeballsAvailable =>
      value['ipv6Enabled'] == true &&
      {
        ServerDomainStrategy.system,
        ServerDomainStrategy.useIp,
      }.contains(dialing.domainStrategy);

  void setDomainStrategy(ServerDomainStrategy? strategy) {
    if (strategy == null) return;
    update('domainStrategy', strategy.name, section: 'dialing');
  }

  void setHappyEyeballs(bool enabled) {
    if (!happyEyeballsAvailable) return;
    update('happyEyeballs', enabled, section: 'dialing');
  }

  @override
  String saveLabel(AppLocalizations l) => l.prototypeSave;
}
