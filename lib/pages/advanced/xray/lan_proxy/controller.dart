import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/advanced/tunnel/controller.dart';
import 'package:onexray/service/advanced/policy_editor.dart';

class LanProxyController extends PolicyEditorController {
  LanProxyController({super.draft, PolicyEditorService? service})
    : super(service: service ?? PolicyEditorService(validateInterface: false)) {
    portController.addListener(_portChanged);
    if (draft != null) _readPort();
  }

  final portController = TextEditingController();
  final portFocusNode = FocusNode();
  bool _invalidPort = false;
  String _lastPortText = '';

  String? get portError => _invalidPort ? state.error : null;

  @override
  String? get error => _invalidPort ? null : super.error;

  void _portChanged() {
    final text = portController.text;
    if (text == _lastPortText) return;
    _lastPortText = text;
    if (!_invalidPort) return;
    _invalidPort = false;
    emit(state.copyWith(error: null));
  }

  void _revealPort() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isPageActive) return;
      portFocusNode.requestFocus();
      final fieldContext = portFocusNode.context;
      if (fieldContext != null && fieldContext.mounted) {
        Scrollable.ensureVisible(
          fieldContext,
          alignment: .5,
          duration: const Duration(milliseconds: 120),
        );
      }
    });
  }

  void _readPort() {
    portController.text = '${group('lanProxy')['port']}';
  }

  @override
  Future<void> load(BuildContext context) async {
    await super.load(context);
    if (isPageActive && draft != null) _readPort();
  }

  @override
  String saveLabel(AppLocalizations l) => l.prototypeSave;

  @override
  Future<bool> save(BuildContext context, {bool pop = true}) {
    if (blocked || runtimeBusy || draft == null) return Future.value(false);
    final port = int.tryParse(portController.text.trim());
    if (port == null || port < 1024 || port > 65535) {
      _invalidPort = true;
      emit(
        state.copyWith(
          error: AppLocalizations.of(context)!.localApiPortInvalid,
        ),
      );
      _revealPort();
      return Future.value(false);
    }
    _invalidPort = false;
    update('port', port, section: 'lanProxy');
    return super.save(context, pop: pop);
  }

  @override
  void disposePageResources() {
    portController.removeListener(_portChanged);
    portController.dispose();
    portFocusNode.dispose();
    super.disposePageResources();
  }
}
