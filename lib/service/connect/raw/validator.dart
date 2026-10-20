import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/empty.dart';
import 'package:onexray/service/settings/language/service.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/shared/xray/validation.dart';
import 'package:onexray/service/shared/share/configuration_source.dart';

final class ParsedRawConfiguration {
  final ConfigurationSource _source;
  final String name;

  const ParsedRawConfiguration._(this._source, this.name);
  String get text => _source.text;
  Map<String, dynamic> get json => _source.value as Map<String, dynamic>;
}

class XrayRawValidator {
  static ParsedRawConfiguration normalize(
    String rawText, {
    String? nameOverride,
  }) => normalizeParsed(
    ConfigurationSource.parse(rawText),
    nameOverride: nameOverride,
  );

  static ParsedRawConfiguration normalizeParsed(
    ConfigurationSource source, {
    String? nameOverride,
  }) {
    final decoded = source.value;
    final normalizedNameOverride = nameOverride?.trim();
    if (decoded is! Map<String, dynamic>) {
      throw const JsonDiagnostic(
        "Xray config root must be an object",
        path: [],
      );
    }
    final jsonMap = decoded;
    final overrideName =
        normalizedNameOverride?.isNotEmpty == true &&
        jsonMap['name'] != normalizedNameOverride;
    final json = overrideName
        ? <String, dynamic>{...jsonMap, 'name': normalizedNameOverride}
        : jsonMap;
    final name = json['name'];
    if (name is! String || !EmptyTool.checkString(name)) {
      throw JsonDiagnostic(
        appLocalizationsNoContext().validationNameRequired,
        path: const ['name'],
      );
    }

    // Saving is not runtime compilation. Keep the exact source, including all
    // expert fields and formatting, unless the caller explicitly renames it.
    return ParsedRawConfiguration._(
      overrideName ? ConfigurationSource.encoded(json) : source,
      name,
    );
  }

  static Future<ParsedRawConfiguration> validate(
    String rawText, {
    Future<String> Function(String)? testXray,
  }) async => validateParsed(normalize(rawText), testXray: testXray);

  /// The parsed draft belongs to this operation, not a reusable validation cache.
  static Future<ParsedRawConfiguration> validateParsed(
    ParsedRawConfiguration parsed, {
    Future<String> Function(String)? testXray,
  }) => GeoDataService().withFiles(() async {
    final res = await (testXray ?? AppHostApi().testXray)(
      XrayValidation.full(parsed.json),
    );
    if (res.isNotEmpty) {
      throw AppFailure(
        FailureCategory.configuration,
        'xrayValidation',
        cause: res,
      );
    }

    return parsed;
  });
}
