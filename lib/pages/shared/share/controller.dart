import 'dart:isolate';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:image/image.dart' as img;
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/file.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/share/params.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:onexray/service/shared/share/app_link_share_service.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:zxing2/qrcode.dart';

enum ShareLinkFormat { original, onexray }

class SharePageState {
  const SharePageState({
    this.loading = true,
    this.savingQr = false,
    this.name = '',
    this.originalLink = '',
    this.appLink = '',
    this.linkError = '',
    this.format = ShareLinkFormat.original,
    this.supportsOriginal = true,
    this.qrExpanded = false,
    this.qrCode,
    this.qrError = '',
  });

  final bool loading;
  final bool savingQr;
  final String name;
  final String originalLink;
  final String appLink;
  final String linkError;
  final ShareLinkFormat format;
  final bool supportsOriginal;
  final bool qrExpanded;
  final Uint8List? qrCode;
  final String qrError;

  String get selectedLink =>
      format == ShareLinkFormat.original ? originalLink : appLink;

  SharePageState copyWith({
    bool? loading,
    bool? savingQr,
    String? name,
    String? originalLink,
    String? appLink,
    String? linkError,
    ShareLinkFormat? format,
    bool? supportsOriginal,
    bool? qrExpanded,
    Uint8List? qrCode,
    bool clearQr = false,
    String? qrError,
  }) => SharePageState(
    loading: loading ?? this.loading,
    savingQr: savingQr ?? this.savingQr,
    name: name ?? this.name,
    originalLink: originalLink ?? this.originalLink,
    appLink: appLink ?? this.appLink,
    linkError: linkError ?? this.linkError,
    format: format ?? this.format,
    supportsOriginal: supportsOriginal ?? this.supportsOriginal,
    qrExpanded: qrExpanded ?? this.qrExpanded,
    qrCode: clearQr ? null : qrCode ?? this.qrCode,
    qrError: qrError ?? this.qrError,
  );
}

class ShareController extends PageCubit<SharePageState> {
  ShareController(
    this.params, {
    AppDatabase? database,
    Future<Uint8List?> Function(String)? qrEncoder,
    Future<String> Function(Map<String, dynamic>)? originalLinkEncoder,
  }) : _database = database ?? AppDatabase(),
       _qrEncoder = qrEncoder ?? _encodeQr,
       _originalLinkEncoder =
           originalLinkEncoder ?? AppHostApi().convertXrayJsonToShareLinks,
       super(const SharePageState()) {
    _initialize();
  }

  final SharePageParams params;
  final AppDatabase _database;
  final Future<Uint8List?> Function(String) _qrEncoder;
  final Future<String> Function(Map<String, dynamic>) _originalLinkEncoder;
  late final _appLinkShareService = OneXrayAppLinkShareService(
    geoDataLookup: _database.geoDataDao.searchRowByName,
  );
  int _qrGeneration = 0;

  Future<void> _initialize() async {
    try {
      switch (params.type) {
        case ShareType.config:
          await _queryConfig(params.id);
        case ShareType.subscription:
          await _querySubscription(params.id);
      }
    } catch (error) {
      ygLogger('generate share link failed (${error.runtimeType})');
      _finishLinkError(error);
    } finally {
      emit(state.copyWith(loading: false));
    }
  }

  Future<void> _queryConfig(int configId) async {
    final config = configId == DBConstants.defaultId
        ? null
        : await _database.coreConfigDao.searchRow(configId);
    final type = config == null ? null : CoreConfigType.fromString(config.type);
    if (config == null || type == null) {
      _finishLinkError();
      return;
    }
    final supportsOriginal = type == CoreConfigType.outbound;
    emit(
      state.copyWith(
        name: config.name,
        supportsOriginal: supportsOriginal,
        format: supportsOriginal
            ? ShareLinkFormat.original
            : ShareLinkFormat.onexray,
      ),
    );
    final appLink = await _appLinkShareService.config(config) ?? '';
    emit(state.copyWith(appLink: appLink));
    if (!supportsOriginal) {
      if (appLink.isEmpty) _finishLinkError();
      return;
    }
    final outbound = readOutboundFromDbData(config);
    final url = await _originalLinkEncoder({
      'outbounds': [outbound],
    });
    if (url.trim().isEmpty) {
      _finishLinkError();
      return;
    }
    emit(
      state.copyWith(name: outboundDisplayName(outbound), originalLink: url),
    );
  }

  Future<void> _querySubscription(int subscriptionId) async {
    final source = subscriptionId == DBConstants.defaultId
        ? null
        : await _database.subscriptionDao.searchRow(subscriptionId);
    if (source == null) {
      _finishLinkError();
      return;
    }
    var url = source.url;
    final uri = Uri.tryParse(url);
    if (uri != null && uri.fragment.isEmpty) {
      url = '$url#${Uri.encodeComponent(source.name)}';
    }
    emit(state.copyWith(name: source.name, originalLink: url));
    emit(
      state.copyWith(appLink: _appLinkShareService.subscription(source) ?? ''),
    );
  }

  void _finishLinkError([Object? error]) {
    final l = appLocalizationsNoContext();
    emit(
      state.copyWith(
        linkError: appFailureMessage(
          l,
          error,
          operation: '${l.sharePageLink}: ${l.resultFailed}',
        ),
      ),
    );
  }

  void selectFormat(ShareLinkFormat format) {
    if (state.format == format ||
        (!state.supportsOriginal && format == ShareLinkFormat.original)) {
      return;
    }
    _qrGeneration++;
    emit(state.copyWith(format: format, clearQr: true, qrError: ''));
    if (state.qrExpanded) _generateQr();
  }

  void toggleQr() {
    _qrGeneration++;
    emit(
      state.copyWith(qrExpanded: !state.qrExpanded, clearQr: true, qrError: ''),
    );
    if (state.qrExpanded) _generateQr();
  }

  Future<void> _generateQr() async {
    final link = state.selectedLink;
    if (link.isEmpty) return;
    final generation = ++_qrGeneration;
    Uint8List? image;
    Object? failure;
    try {
      image = await _qrEncoder(link);
    } catch (error) {
      // Generation failure is shown only for the currently selected format.
      failure = error;
    }
    if (!isPageActive ||
        generation != _qrGeneration ||
        !state.qrExpanded ||
        link != state.selectedLink) {
      return;
    }
    final l = appLocalizationsNoContext();
    emit(
      state.copyWith(
        qrCode: image,
        clearQr: image == null,
        qrError: image == null
            ? appFailureMessage(
                l,
                failure,
                operation: '${l.sharePageQRCode}: ${l.resultFailed}',
              )
            : '',
      ),
    );
  }

  Future<void> saveQr(BuildContext context) async {
    final qrcode = state.qrCode;
    if (qrcode == null || state.savingQr) return;
    emit(state.copyWith(savingQr: true));
    try {
      final success = await FileTool.saveData(
        qrcode,
        '${state.name}.png',
        '.png',
      );
      if (context.mounted && success) {
        _showActionResult(
          context,
          success,
          AppLocalizations.of(context)!.sharePageSaveQRCode,
        );
      }
    } catch (error) {
      if (context.mounted) {
        _showActionResult(
          context,
          false,
          AppLocalizations.of(context)!.sharePageSaveQRCode,
          error: error,
        );
      }
    } finally {
      emit(state.copyWith(savingQr: false));
    }
  }

  void _showActionResult(
    BuildContext context,
    bool success,
    String action, {
    Object? error,
  }) {
    final l = AppLocalizations.of(context)!;
    ContextAlert.showToast(
      context,
      success
          ? l.actionResult(action, l.resultSuccess)
          : appFailureMessage(
              l,
              error,
              operation: l.actionResult(action, l.resultFailed),
            ),
    );
  }
}

Future<Uint8List?> _encodeQr(String link) =>
    Isolate.run(() => _drawQrcode(link));

Uint8List? _drawQrcode(String shareLink) {
  try {
    final qrcode = Encoder.encode(shareLink, ErrorCorrectionLevel.h);
    final matrix = qrcode.matrix!;
    var scale = (800 / matrix.width).toInt();
    if (scale < 1) scale = 1;
    const padding = 80;
    final image = img.Image(
      width: matrix.width * scale + padding * 2,
      height: matrix.height * scale + padding * 2,
      numChannels: 4,
    );
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    for (var x = 0; x < matrix.width; x++) {
      for (var y = 0; y < matrix.height; y++) {
        if (matrix.get(x, y) == 1) {
          img.fillRect(
            image,
            x1: x * scale + padding,
            y1: y * scale + padding,
            x2: x * scale + scale + padding,
            y2: y * scale + scale + padding,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }
    return img.encodePng(image);
  } catch (error) {
    throw AppFailure(FailureCategory.input, 'qrEncoding', cause: error);
  }
}
