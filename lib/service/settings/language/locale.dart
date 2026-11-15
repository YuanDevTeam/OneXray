import 'package:material_ui/material_ui.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';

abstract final class AppLocalePolicy {
  // gen-l10n still emits the SDK's legacy Material/Cupertino delegates.
  static const localizationsDelegates = [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ];

  static const english = Locale("en");

  static const simplifiedChinese = Locale.fromSubtags(
    languageCode: "zh",
    scriptCode: "Hans",
  );

  static const traditionalChinese = Locale.fromSubtags(
    languageCode: "zh",
    scriptCode: "Hant",
  );

  static List<Locale> normalizeSupportedLocales(
    Iterable<Locale> supportedLocales,
  ) {
    return supportedLocales
        .map((locale) {
          if (locale.languageCode != "zh") {
            return locale;
          }
          if (locale.scriptCode == "Hant") {
            return traditionalChinese;
          }
          return simplifiedChinese;
        })
        .toList(growable: false);
  }

  static Locale resolve(Locale? locale, Iterable<Locale> supportedLocales) {
    final locales = supportedLocales.toList(growable: false);
    if (locale == null) {
      return english;
    }

    final exactLocale = _findExact(locale, locales);
    if (exactLocale != null) {
      return exactLocale;
    }

    if (locale.languageCode == "zh") {
      final useTraditional =
          locale.scriptCode == "Hant" ||
          locale.countryCode == "TW" ||
          locale.countryCode == "HK" ||
          locale.countryCode == "MO";
      return useTraditional ? traditionalChinese : simplifiedChinese;
    }

    for (final supportedLocale in locales) {
      if (supportedLocale.languageCode == locale.languageCode &&
          supportedLocale.scriptCode == locale.scriptCode) {
        return supportedLocale;
      }
    }
    for (final supportedLocale in locales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return supportedLocale;
      }
    }
    return english;
  }

  static Locale? _findExact(Locale locale, Iterable<Locale> locales) {
    for (final supportedLocale in locales) {
      if (supportedLocale.languageCode == locale.languageCode &&
          supportedLocale.scriptCode == locale.scriptCode &&
          supportedLocale.countryCode == locale.countryCode) {
        return supportedLocale;
      }
    }
    return null;
  }
}
