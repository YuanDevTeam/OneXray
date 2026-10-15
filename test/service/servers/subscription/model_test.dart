import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/validator.dart';

void main() {
  test('new source keeps mode unspecified and HWID copies retain policy', () {
    const automatic = SubscriptionInput(
      name: 'Plain',
      url: 'https://example.com/sub',
    );
    expect(automatic.panel, SubscriptionPanel.generic);
    expect(automatic.mode, isNull);
    expect(automatic.withHwid('device').mode, isNull);

    const explicit = SubscriptionInput(
      name: 'Full',
      url: 'https://example.com/full',
      panel: SubscriptionPanel.remnawave,
      mode: SubscriptionMode.providerManaged,
      ageSecretKey: 'private',
      agePublicKey: 'public',
    );
    final copied = explicit.withHwid('device');
    expect(copied.panel, SubscriptionPanel.remnawave);
    expect(copied.mode, SubscriptionMode.providerManaged);
    expect(copied.ageSecretKey, explicit.ageSecretKey);
    expect(copied.agePublicKey, explicit.agePublicKey);
    expect(copied.hwid, 'device');
  });

  test('configuration and source enum wire values remain distinct', () {
    expect(CoreConfigType.fromString('Remnawave'), CoreConfigType.Remnawave);
    expect(CoreConfigType.fromString('full'), isNull);
    expect(CoreConfigType.fromString('remnawave'), isNull);
    expect(
      SubscriptionPanel.fromString('remnawave'),
      SubscriptionPanel.remnawave,
    );
    expect(
      SubscriptionMode.fromString('providerManaged'),
      SubscriptionMode.providerManaged,
    );
    expect(SubscriptionPanel.fromString('unknown'), isNull);
    expect(SubscriptionMode.fromString('automatic'), isNull);
  });

  group('SubscriptionUrl.normalize', () {
    test('removes whitespace and URL fragment', () {
      expect(
        SubscriptionUrl.normalize(
          ' https://example.com/sub?token=123#Subscription Name ',
        ),
        'https://example.com/sub?token=123',
      );
    });

    test('preserves encoded fragment characters', () {
      expect(
        SubscriptionUrl.normalize(
          'https://example.com/sub?value=encoded%23value',
        ),
        'https://example.com/sub?value=encoded%23value',
      );
    });
  });

  group('SubscriptionInput age key pair', () {
    test('normalizes empty keys to no encryption context', () {
      const input = SubscriptionInput(
        name: 'Plain',
        url: 'https://example.com/sub',
        ageSecretKey: '   ',
        agePublicKey: '   ',
      );

      expect(input.normalizedAgeSecretKey, isNull);
      expect(input.normalizedAgePublicKey, isNull);
      expect(input.normalizedAgeContext, isNull);
      expect(input.hasIncompleteAgeKeyPair, isFalse);
    });

    test('trims and keeps a configured key pair together', () {
      const input = SubscriptionInput(
        name: 'Encrypted',
        url: 'https://example.com/sub',
        ageSecretKey: '  AGE-SECRET-KEY-1TEST  ',
        agePublicKey: '  age1test  ',
      );

      expect(input.normalizedAgeSecretKey, 'AGE-SECRET-KEY-1TEST');
      expect(input.normalizedAgePublicKey, 'age1test');
      expect(input.normalizedAgeContext?.secretKey, 'AGE-SECRET-KEY-1TEST');
      expect(input.normalizedAgeContext?.publicKey, 'age1test');
      expect(input.hasIncompleteAgeKeyPair, isFalse);
    });

    test('rejects a partial key pair', () {
      const input = SubscriptionInput(
        name: 'Encrypted',
        url: 'https://example.com/sub',
        ageSecretKey: 'AGE-SECRET-KEY-1TEST',
      );

      expect(input.hasIncompleteAgeKeyPair, isTrue);
      expect(input.normalizedAgeContext, isNull);
    });
  });

  test(
    'optional subscription UA is normalized and rejects invalid header text',
    () {
      for (final value in [null, '', '  ']) {
        final input = SubscriptionInput(
          name: 'Provider',
          url: 'https://example.com/sub',
          userAgent: value,
        );
        expect(input.normalizedUserAgent, isNull);
        expect(SubscriptionValidator.validate(input), isNull);
      }
      const input = SubscriptionInput(
        name: 'Provider',
        url: 'https://example.com/sub',
        userAgent: '  Example/1.0 (compatible)  ',
      );
      expect(
        input.withHwid('device').normalizedUserAgent,
        'Example/1.0 (compatible)',
      );
      expect(SubscriptionValidator.validate(input), isNull);
      for (final value in [
        'Example/1.0\r\nX-Test: value',
        'Example/\u0000',
        '示例',
      ]) {
        expect(
          SubscriptionValidator.validate(
            SubscriptionInput(
              name: 'Provider',
              url: 'https://example.com/sub',
              userAgent: value,
            ),
          ),
          SubscriptionUpdateResult.userAgentInvalid,
        );
      }
    },
  );
}
