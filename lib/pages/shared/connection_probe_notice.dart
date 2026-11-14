import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/alert.dart';

/// Consumes a current session's advisory without changing the connection page.
class ConnectionProbeNotice extends StatefulWidget {
  const ConnectionProbeNotice({
    super.key,
    required this.failures,
    required this.consume,
    required this.child,
  });

  final ValueListenable<int?> failures;
  final bool Function(int session) consume;
  final Widget child;

  @override
  State<ConnectionProbeNotice> createState() => _ConnectionProbeNoticeState();
}

class _ConnectionProbeNoticeState extends State<ConnectionProbeNotice> {
  bool _scheduled = false;
  int? _lastShownSession;

  @override
  void initState() {
    super.initState();
    widget.failures.addListener(_scheduleNotice);
    _scheduleNotice();
  }

  @override
  void didUpdateWidget(ConnectionProbeNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.failures, widget.failures)) {
      oldWidget.failures.removeListener(_scheduleNotice);
      widget.failures.addListener(_scheduleNotice);
      _lastShownSession = null;
    }
    _scheduleNotice();
  }

  void _scheduleNotice() {
    if (!mounted || _scheduled || widget.failures.value == null) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final session = widget.failures.value;
      if (session == null ||
          session == _lastShownSession ||
          !widget.consume(session)) {
        return;
      }
      _lastShownSession = session;
      ContextAlert.showToast(
        context,
        AppLocalizations.of(context)!.connectionStartupProbeFailed,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.failures.removeListener(_scheduleNotice);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
