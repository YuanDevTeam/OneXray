import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/advanced/xray/runtime_files.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:path/path.dart' as p;

import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/shared/widgets/settings_page.dart';
import 'package:onexray/pages/advanced/xray/log/params.dart';

class LogFileViewerPageState {
  final String title;
  final List<String> lines;
  final bool fileExists;
  final bool followTail;
  final bool truncated;
  final bool exporting;
  final Object? failure;

  const LogFileViewerPageState({
    this.title = "",
    this.lines = const [],
    this.fileExists = false,
    this.followTail = true,
    this.truncated = false,
    this.exporting = false,
    this.failure,
  });

  LogFileViewerPageState copyWith({
    String? title,
    List<String>? lines,
    bool? fileExists,
    bool? followTail,
    bool? truncated,
    bool? exporting,
    Object? failure,
    bool clearFailure = false,
  }) {
    return LogFileViewerPageState(
      title: title ?? this.title,
      lines: lines ?? this.lines,
      fileExists: fileExists ?? this.fileExists,
      followTail: followTail ?? this.followTail,
      truncated: truncated ?? this.truncated,
      exporting: exporting ?? this.exporting,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }
}

class LogFileViewerController extends PageCubit<LogFileViewerPageState> {
  static const int _maxBufferBytes = 1024 * 1024;
  static const Duration _pollInterval = Duration(seconds: 1);

  final LogFileViewerParams params;
  final ConnectionCoordinator _coordinator;
  final Future<({Uint8List data, int offset, int size})?> Function(
    String path, {
    int offset,
  })
  _readLog;

  Timer? _timer;
  late String? _runtimeIdentity;
  late bool _connected;
  int _readGeneration = 0;
  int _offset = 0;
  var _droppedContent = false;
  var _reading = false;
  List<int> _buffer = const [];

  LogFileViewerController(
    this.params, {
    ConnectionCoordinator? coordinator,
    Future<({Uint8List data, int offset, int size})?> Function(
      String path, {
      int offset,
    })?
    readLog,
  }) : _coordinator = coordinator ?? ConnectionCoordinator.instance,
       _readLog = readLog ?? RuntimeDiagnosticFiles.readLog,
       super(LogFileViewerPageState(title: params.title)) {
    final connection = _coordinator.state.value;
    _runtimeIdentity = connection.runtime?.identity;
    _connected = connection.phase == ConnectionPhase.connected;
    _coordinator.state.addListener(_connectionChanged);
    _poll();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  void _connectionChanged() {
    if (!isPageActive) return;
    final connection = _coordinator.state.value;
    final identity = connection.runtime?.identity;
    final connected = connection.phase == ConnectionPhase.connected;
    final newRuntime = identity != null && identity != _runtimeIdentity;
    final enteredConnected = connected && !_connected;
    _connected = connected;
    // Stopping keeps the last session's diagnostics available at the same path.
    if (identity != null) _runtimeIdentity = identity;
    if (!newRuntime && !enteredConnected) return;
    _readGeneration++;
    _resetMissingFile();
    unawaited(_poll());
  }

  bool _readIsCurrent(int generation) =>
      isPageActive && generation == _readGeneration;

  Future<void> _poll() async {
    if (_reading || !isPageActive) return;
    _reading = true;
    final generation = _readGeneration;
    try {
      var replace = !state.fileExists;
      var chunk = await _readLog(params.path, offset: replace ? -1 : _offset);
      if (!_readIsCurrent(generation)) return;
      if (chunk != null &&
          !replace &&
          (chunk.size < _offset || chunk.size - _offset > _maxBufferBytes)) {
        chunk = await _readLog(params.path);
        if (!_readIsCurrent(generation)) return;
        replace = true;
      }
      if (chunk == null) {
        _resetMissingFile();
        return;
      }
      if (replace) {
        _droppedContent = chunk.offset > 0;
        _buffer = chunk.offset > 0
            ? _dropPartialFirstLine(chunk.data)
            : chunk.data;
      } else {
        _buffer = _trimBuffer([..._buffer, ...chunk.data]);
      }
      _offset = chunk.offset + chunk.data.length;
      _emitBuffer(
        fileExists: true,
        truncated: replace ? _droppedContent : state.truncated,
      );
    } catch (error) {
      if (!_readIsCurrent(generation)) return;
      // An unavailable file must not leave a stale successful view.
      _resetMissingFile();
      emit(state.copyWith(failure: error));
    } finally {
      _reading = false;
      if (isPageActive && generation != _readGeneration) unawaited(_poll());
    }
  }

  List<int> _trimBuffer(List<int> bytes) {
    if (bytes.length <= _maxBufferBytes) {
      return bytes;
    }
    _droppedContent = true;
    return _dropPartialFirstLine(bytes.sublist(bytes.length - _maxBufferBytes));
  }

  List<int> _dropPartialFirstLine(List<int> bytes) {
    final newlineIndex = bytes.indexOf(0x0a);
    if (newlineIndex < 0) {
      return const [];
    }
    if (newlineIndex + 1 >= bytes.length) {
      return const [];
    }
    return bytes.sublist(newlineIndex + 1);
  }

  void _emitBuffer({required bool fileExists, required bool truncated}) {
    if (!isPageActive) {
      return;
    }
    final text = utf8.decode(_buffer, allowMalformed: true);
    final lines = text.isEmpty
        ? const <String>[]
        : const LineSplitter().convert(text);
    emit(
      state.copyWith(
        lines: lines,
        fileExists: fileExists,
        truncated: truncated || _droppedContent,
        clearFailure: true,
      ),
    );
  }

  void _resetMissingFile() {
    _offset = 0;
    _droppedContent = false;
    _buffer = const [];
    _emitBuffer(fileExists: false, truncated: false);
  }

  void setFollowTail(bool value) {
    if (state.followTail == value) {
      return;
    }
    emit(state.copyWith(followTail: value));
  }

  Future<void> export(BuildContext context) async {
    if (state.exporting || !state.fileExists) return;
    final l = AppLocalizations.of(context)!;
    emit(state.copyWith(exporting: true));
    try {
      final confirmed = await AppConfirmationDialog(
        title: l.prototypeExport,
        subject: p.basename(params.path),
        content: l.prototypeLocalLogNotice,
        cancelLabel: l.prototypeCancel,
        confirmLabel: l.prototypeExport,
      ).show(context);
      if (confirmed != true || !isPageActive) return;
      await RuntimeDiagnosticFiles.exportLog(
        params.path,
        p.basename(params.path),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appFailureMessage(
                l,
                error,
                operation: l.actionResult(l.prototypeExport, l.resultFailed),
              ),
            ),
          ),
        );
      }
    } finally {
      emit(state.copyWith(exporting: false));
    }
  }

  @override
  Future<void> disposePageResources() async {
    _readGeneration++;
    _coordinator.state.removeListener(_connectionChanged);
    _timer?.cancel();
  }
}
