import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/shared/apple_widget/service.dart';
import 'package:zxing2/qrcode.dart';

final class IncomingAppLink {
  IncomingAppLink._(this.uri);

  final Uri uri;
}

final class ShareService {
  static final ShareService _singleton = ShareService._internal();

  factory ShareService() => _singleton;

  ShareService._internal([this._appLinks, this._receiveWidgetUri]);

  @visibleForTesting
  factory ShareService.forTesting({
    required Stream<Uri> appLinks,
    bool Function(Uri)? receiveWidgetUri,
  }) => ShareService._internal(appLinks, receiveWidgetUri);

  //==========================

  final Stream<Uri>? _appLinks;
  final bool Function(Uri)? _receiveWidgetUri;
  final Queue<IncomingAppLink> _pendingAppLinks = Queue<IncomingAppLink>();
  StreamSubscription<Uri>? _appLinkSubscription;
  StreamController<void>? _changes;
  IncomingAppLink? _activeAppLink;

  /// Wake-up only: receivers must atomically claim the cached event.
  Stream<void> get pendingAppLinksChanged =>
      (_changes ??= StreamController<void>.broadcast()).stream;

  IncomingAppLink? claimNextAppLink() {
    if (_activeAppLink != null || _pendingAppLinks.isEmpty) return null;
    return _activeAppLink = _pendingAppLinks.removeFirst();
  }

  void finishAppLink(IncomingAppLink event) {
    if (!identical(_activeAppLink, event)) return;
    _activeAppLink = null;
    if (_pendingAppLinks.isNotEmpty) _changes?.add(null);
  }

  void startAppLinks() {
    if (_appLinkSubscription != null) {
      return;
    }
    _appLinkSubscription = (_appLinks ?? AppLinks().uriLinkStream).listen(
      (uri) {
        if ((_receiveWidgetUri ?? AppleWidgetService().receiveOpenUri)(uri)) {
          return;
        }
        if (_activeAppLink?.uri == uri ||
            _pendingAppLinks.any((event) => event.uri == uri)) {
          return;
        }
        _pendingAppLinks.add(IncomingAppLink._(uri));
        _changes?.add(null);
      },
      onError: (Object error, StackTrace stackTrace) {
        // Native errors may contain private subscription URLs.
        ygLogger('receive app link failed');
      },
    );
  }

  Future<void> init() async {
    startAppLinks();
  }

  void dispose() {
    _pendingAppLinks.clear();
    _activeAppLink = null;
    final changes = _changes;
    _changes = null;
    if (changes != null) unawaited(changes.close());
    final subscription = _appLinkSubscription;
    _appLinkSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
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
