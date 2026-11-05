import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/connect/failure.dart';
import 'package:onexray/service/connect/resolver.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/shared/failure.dart';

void main() {
  for (final locale in [
    const Locale('en'),
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    const Locale('ru'),
    const Locale('fa'),
  ]) {
    final l = lookupAppLocalizations(locale);
    test(
      'native operation titles stay consistent across entry points in $locale',
      () {
        for (final (code, title) in [
          ('startFailed', l.prototypeConnectionFailed),
          ('stopFailed', l.actionResult(l.prototypeDisconnect, l.resultFailed)),
          ('startTimeout', '${l.prototypeConnect} · ${l.prototypeTimeout}'),
          ('stopTimeout', '${l.prototypeDisconnect} · ${l.prototypeTimeout}'),
        ]) {
          final error = ConnectionHostException(code, cause: 'Native detail');
          expect(connectionFailureMessage(l, issue: code), title);
          expect(
            connectionFailureMessage(l, error: error),
            '$title\nNative detail',
          );
          expect(appFailureMessage(l, error), '$title\nNative detail');
          expect(
            appFailureMessage(
              l,
              AppFailure(FailureCategory.runtime, 'saveFailed', cause: error),
              operation: l.buttonSaveFailed,
            ),
            '$title\nNative detail',
          );
        }
      },
    );

    test('connection failures reuse approved copy in $locale', () {
      expect(
        connectionFailureMessage(
          l,
          error: const ConnectionResolutionException(
            ConnectionResolutionFailure.selectionUnavailable,
          ),
        ),
        '${l.prototypeNoAvailableEntries} · ${l.prototypeAddServers}',
      );
      expect(
        connectionFailureMessage(
          l,
          error: const ConnectionResolutionException(
            ConnectionResolutionFailure.insufficientCandidates,
            requiredCount: 3,
            availableCount: 2,
          ),
        ),
        '${l.prototypeNotEnoughServers} (2/3)',
      );
      expect(
        connectionFailureMessage(
          l,
          error: const ConnectionResolutionException(
            ConnectionResolutionFailure.selfReference,
          ),
        ),
        l.prototypeFinalExitEntryConflict,
      );
      expect(
        connectionFailureMessage(
          l,
          error: const ConnectionResolutionException(
            ConnectionResolutionFailure.invalidSettings,
          ),
        ),
        l.prototypeChooseNamedRoute,
      );
    });
  }

  test(
    'permission failures distinguish local network and system extension',
    () {
      final l = lookupAppLocalizations(const Locale('en'));
      for (final (kind, message) in [
        (
          PlatformPermissionKind.androidLocalNetwork,
          l.prototypeAllowLocalNetworkHint,
        ),
        (
          PlatformPermissionKind.macosSystemExtension,
          l.prototypeSystemApprovalRequired,
        ),
        (PlatformPermissionKind.appleVpn, l.prototypeVpnPermissionRequired),
      ]) {
        final permission = PlatformPermissionResult(
          kind: kind,
          state: PlatformPermissionState.denied,
        );
        expect(
          connectionFailureMessage(
            l,
            error: ConnectionHostException(
              'permissionRequired',
              permission: permission,
            ),
          ),
          message,
        );
      }
    },
  );

  test(
    'unknown failures retain a reason without guessing a network failure',
    () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(
        connectionFailureMessage(
          l,
          error: const FormatException('Invalid config'),
        ),
        '${l.resultFailed}\nInvalid config',
      );
      expect(
        connectionFailureMessage(
          l,
          error: const ConnectionHostException('nativeStatusFailed'),
        ),
        l.prototypeTemporarilyUnavailable,
      );
    },
  );
}
