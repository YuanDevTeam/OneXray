import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:onexray/core/pigeon/flutter_api.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/launch/app_startup.dart';
import 'package:onexray/service/settings/language/locale.dart';
import 'package:onexray/service/shared/menu/short_cut/service.dart';

/// Native intents publish navigation and cancellation effects to the App.
final class AppleWidgetService with WidgetsBindingObserver {
  static final _instance = AppleWidgetService._(
    AppPlatform.isIOS,
    AppFlutterApi().appleWidgetActions.stream,
    AppleWidgetHostApi().takeAction,
    AppleWidgetHostApi().setLanguage,
    ShortCutService().receive,
    AppStartupService().suppressConnectOnAppLaunch,
    (tokens) => ConnectionCoordinator.instance.invalidatePreparations(tokens),
  );

  factory AppleWidgetService() => _instance;

  AppleWidgetService._(
    this._enabled,
    this._events,
    this._takeAction,
    this._setLanguage,
    this._receive,
    this._suppressAutoConnect,
    this._invalidatePreparations,
  );

  @visibleForTesting
  factory AppleWidgetService.forTesting({
    bool enabled = true,
    required Stream<void> events,
    required Future<String?> Function() takeAction,
    required Future<void> Function(String) setLanguage,
    required Future<void> Function(String) receive,
    void Function()? suppressAutoConnect,
    void Function(Iterable<String>)? invalidatePreparations,
  }) => AppleWidgetService._(
    enabled,
    events,
    takeAction,
    setLanguage,
    receive,
    suppressAutoConnect ?? () {},
    invalidatePreparations ?? (_) {},
  );

  final bool _enabled;
  final Stream<void> _events;
  final Future<String?> Function() _takeAction;
  final Future<void> Function(String) _setLanguage;
  final Future<void> Function(String) _receive;
  final void Function() _suppressAutoConnect;
  final void Function(Iterable<String>) _invalidatePreparations;
  StreamSubscription<void>? _subscription;
  Future<void>? _draining;
  bool _needsDrain = false;

  Future<void> initialize() async {
    if (!_enabled) return;
    if (_subscription == null) {
      _subscription = _events.listen((_) => unawaited(_drain()));
      WidgetsBinding.instance.addObserver(this);
    }
    // Consume a cold-launch intent before automatic Connect is considered.
    await _drain();
  }

  Future<void> _drain() {
    _needsDrain = true;
    return _draining ??= _takeActions().whenComplete(() {
      _draining = null;
      if (_needsDrain && _subscription != null) unawaited(_drain());
    });
  }

  Future<void> _takeActions() async {
    try {
      while (_subscription != null) {
        _needsDrain = false;
        final action = await _takeAction();
        if (_subscription == null) return;
        if (action != null) _receiveNativeAction(action);
        if (action == null && !_needsDrain) return;
      }
    } catch (error, stack) {
      _needsDrain = false;
      ygLogger('Apple widget action unavailable: $error\n$stack');
    }
  }

  void _receiveNativeAction(String action) {
    // Retain the old internal action format while consuming only envelopes
    // from the current native intent implementation.
    if (action == 'startVpn' || action == 'stopVpn') {
      unawaited(_receive(action));
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(action);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['suppressAutoConnect'] is! bool ||
        decoded['openConnect'] is! bool ||
        decoded['invalidatedPreparations'] is! List ||
        (decoded['invalidatedPreparations'] as List).any(
          (value) => value is! String,
        )) {
      return;
    }
    if (decoded['suppressAutoConnect'] == true) _suppressAutoConnect();
    final tokens = (decoded['invalidatedPreparations'] as List).cast<String>();
    if (tokens.isNotEmpty) _invalidatePreparations(tokens);
    if (decoded['openConnect'] == true) {
      unawaited(_receive(ShortCutAction.openConnect.name));
    }
  }

  /// Public URLs only navigate. Connection commands are private intent input.
  bool receiveOpenUri(Uri uri) {
    if (!_enabled || !isOpenUri(uri)) return false;
    unawaited(_receive(ShortCutAction.openConnect.name));
    return true;
  }

  static bool isOpenUri(Uri uri) =>
      uri.scheme == 'onexray' &&
      uri.host == 'widget' &&
      uri.path == '/connect' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;

  Future<void> setLanguage(String languageCode) async {
    if (!_enabled) return;
    try {
      final code = languageCode == 'system'
          ? AppLocalePolicy.resolve(
              WidgetsBinding.instance.platformDispatcher.locale,
              AppLocalePolicy.normalizeSupportedLocales(
                AppLocalizations.supportedLocales,
              ),
            ).toLanguageTag()
          : languageCode.replaceAll('_', '-');
      await _setLanguage(code);
    } catch (error, stack) {
      ygLogger('Apple widget language unavailable: $error\n$stack');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_drain());
  }

  void dispose() {
    if (!_enabled) return;
    final subscription = _subscription;
    _subscription = null;
    _needsDrain = false;
    unawaited(subscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
  }
}
