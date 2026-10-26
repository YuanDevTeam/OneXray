import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/shared/apple_widget/service.dart';
import 'package:zxing2/qrcode.dart';

final class ShareService {
  static final ShareService _singleton = ShareService._internal();

  factory ShareService() => _singleton;

  ShareService._internal();

  //==========================

  final Queue<Uri> _pendingAppLinks = Queue<Uri>();
  StreamSubscription<Uri>? _appLinkSubscription;
  var _appLinksReady = false;
  var _processingAppLinks = false;
  Future<void> Function(String)? onIncomingShare;

  void startAppLinks() {
    if (_appLinkSubscription != null) {
      return;
    }
    _appLinkSubscription = AppLinks().uriLinkStream.listen(
      (uri) {
        if (AppleWidgetService().receiveOpenUri(uri)) return;
        _pendingAppLinks.add(uri);
        unawaited(_processAppLinks());
      },
      onError: (Object error, StackTrace stackTrace) {
        ygLogger('receive app link failed: $error\n$stackTrace');
      },
    );
  }

  Future<void> init() async {
    startAppLinks();
    _appLinksReady = onIncomingShare != null;
    await _processAppLinks();
  }

  void dispose() {
    _appLinksReady = false;
    onIncomingShare = null;
    _pendingAppLinks.clear();
    final subscription = _appLinkSubscription;
    _appLinkSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  Future<void> _processAppLinks() async {
    if (!_appLinksReady || _processingAppLinks) {
      return;
    }
    _processingAppLinks = true;
    try {
      while (_appLinksReady && _pendingAppLinks.isNotEmpty) {
        final uri = _pendingAppLinks.removeFirst();
        // All external imports go through the same user-visible preview/add
        // flow as clipboard input. Setup leaves this queue paused.
        await onIncomingShare?.call(uri.toString());
      }
    } finally {
      _processingAppLinks = false;
      if (_appLinksReady && _pendingAppLinks.isNotEmpty) {
        unawaited(_processAppLinks());
      }
    }
  }

  /// Decode only; callers own preview and explicit import confirmation.
  Future<String?> readImageFile(String path) async {
    if (await File(path).length() > 16 * 1024 * 1024) {
      throw const FormatException('Image is too large');
    }
    if (AppPlatform.isIOS || AppPlatform.isMacOS || AppPlatform.isAndroid) {
      return _readImageFileByMobileScanner(path);
    }
    return _readImageFileByZxing(path);
  }

  Future<String?> _readImageFileByMobileScanner(String path) async {
    final controller = MobileScannerController();
    try {
      final capture = await controller.analyzeImage(path);
      return capture?.barcodes.firstOrNull?.rawValue;
    } finally {
      await controller.dispose();
    }
  }

  Future<String?> _readImageFileByZxing(String path) async {
    final image = await img.decodeImageFile(path);
    if (image != null) {
      final source = RGBLuminanceSource(
        image.width,
        image.height,
        image
            .convert(numChannels: 4)
            .getBytes(order: img.ChannelOrder.abgr)
            .buffer
            .asInt32List(),
      );
      final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
      final reader = QRCodeReader();
      try {
        final result = reader.decode(bitmap);
        return result.text;
      } catch (_) {}
    }
    return null;
  }
}
