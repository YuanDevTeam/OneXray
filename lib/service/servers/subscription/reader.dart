import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/shared/share/xray_share_reader.dart';
import 'package:onexray/service/shared/xray/validation.dart';
import 'package:onexray/service/shared/xray/remnawave.dart';

final class SubscriptionConfigurationResult {
  final List<CoreConfigCompanion> rows;
  final SubscriptionMode mode;
  final bool convertedToOrdinary;

  SubscriptionConfigurationResult({
    required Iterable<CoreConfigCompanion> rows,
    required this.mode,
    this.convertedToOrdinary = false,
  }) : rows = List.unmodifiable(rows);

  int get count => rows.where((row) => row.type.value == activeType).length;

  String get activeType => mode == SubscriptionMode.providerManaged
      ? CoreConfigType.Remnawave.name
      : CoreConfigType.outbound.name;
}

/// A subscription's plaintext is classified before any single-node projection.
class SubscriptionConfigurationReader {
  final Future<String> Function(String, {String? ageSecretKey}) _decode;
  final Future<List<CoreConfigCompanion>> Function(String) _nodes;
  final Future<String> Function(String) _validate;
  final Future<void> Function(Future<void> Function()) _withFiles;

  SubscriptionConfigurationReader({
    Future<String> Function(String, {String? ageSecretKey})? decode,
    Future<List<CoreConfigCompanion>> Function(String)? readNodes,
    Future<String> Function(String)? validate,
    Future<void> Function(Future<void> Function())? withFiles,
  }) : _decode = decode ?? AppHostApi().decodeSubscriptionText,
       _nodes = readNodes ?? ((text) => XrayShareReader().parseShareText(text)),
       _validate = validate ?? AppHostApi().testXray,
       _withFiles =
           withFiles ?? ((action) => GeoDataService().withFiles(action));

  Future<SubscriptionConfigurationResult> read(
    String text,
    SubscriptionInput input, {
    SubscriptionFormatConfirmation? confirmOrdinary,
  }) async {
    final plaintext = await _decode(
      text,
      ageSecretKey: input.normalizedAgeSecretKey,
    );
    Object? value;
    try {
      value = JsonTool.decoder.convert(plaintext);
    } on FormatException {
      if (input.panel == SubscriptionPanel.remnawave) {
        if (confirmOrdinary == null) {
          throw const RemnawaveResponseFormatException();
        }
        if (!await confirmOrdinary(input.name)) {
          throw const AppFailure(FailureCategory.conflict, 'cancelled');
        }
        return _readOrdinary(plaintext, convertedToOrdinary: true);
      }
      final start = plaintext.trimLeft();
      if (start.startsWith('{') || start.startsWith('[')) rethrow;
    }
    final complete =
        input.panel == SubscriptionPanel.remnawave ||
        value is List ||
        (value is Map<String, dynamic> &&
            value.keys.any((key) => key != 'outbounds'));
    if (!complete) {
      if (input.mode == SubscriptionMode.providerManaged) {
        throw const FormatException(
          'The subscription must contain complete Xray JSON configurations',
        );
      }
      return _readOrdinary(plaintext);
    }

    final values = value is List ? value : [value];
    if (values.isEmpty) {
      throw const FormatException(
        'The subscription must contain Xray configuration objects',
      );
    }
    final rows = <CoreConfigCompanion>[];
    FormatException? firstFailure;
    await _withFiles(() async {
      for (final (index, config) in values.indexed) {
        if (config is! Map<String, dynamic>) {
          firstFailure ??= const FormatException(
            'The subscription must contain Xray configuration objects',
          );
          continue;
        }
        final String validation;
        final List<CoreConfigCompanion> configRows;
        try {
          validation = XrayValidation.full(RemnawaveAdapter.adapt(config));
          configRows = _configurationRows(config, '${input.name} ${index + 1}');
        } on FormatException catch (error) {
          firstFailure ??= error;
          continue;
        } on TypeError {
          firstFailure ??= const FormatException(
            'The subscription contains an invalid Xray configuration structure',
          );
          continue;
        }
        // A native channel failure aborts the refresh; only a completed Core
        // validation can reject an individual configuration.
        final error = await _validate(validation);
        if (error.isNotEmpty) {
          firstFailure ??= FormatException(error);
          continue;
        }
        rows.addAll(configRows);
      }
    });
    final result = SubscriptionConfigurationResult(
      rows: rows,
      mode: input.mode ?? SubscriptionMode.providerManaged,
    );
    if (result.count == 0) {
      if (rows.isEmpty && firstFailure != null) throw firstFailure!;
      throw const FormatException(
        'The selected mode contains no usable configurations',
      );
    }
    return result;
  }

  List<CoreConfigCompanion> _configurationRows(
    Map<String, dynamic> config,
    String fallbackName,
  ) {
    final name =
        [config['remarks'], config['name']]
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .firstOrNull ??
        fallbackName;
    final rows = [
      CoreConfigCompanion.insert(
        name: name,
        type: CoreConfigType.Remnawave.name,
        tags: '',
        data: Value(base64Encode(utf8.encode(jsonEncode(config)))),
        delay: PingDelayConstants.unknown,
        subId: DBConstants.defaultId,
      ),
    ];
    final outbounds = config['outbounds'] as List? ?? const [];
    for (final outbound in outbounds.cast<Map<String, dynamic>>()) {
      if (const [
            'freedom',
            'blackhole',
            'dns',
            'loopback',
          ].contains(outbound['protocol']) ||
          outboundDialerProxy(outbound)?.isNotEmpty == true ||
          outboundProxyTag(outbound)?.isNotEmpty == true) {
        continue;
      }
      rows.add(outboundCompanion(outbound));
    }
    return rows;
  }

  Future<SubscriptionConfigurationResult> _readOrdinary(
    String plaintext, {
    bool convertedToOrdinary = false,
  }) async {
    final rows = await _nodes(plaintext);
    if (rows.isEmpty) {
      throw const FormatException('The subscription contains no usable nodes');
    }
    return SubscriptionConfigurationResult(
      rows: rows,
      mode: SubscriptionMode.appManaged,
      convertedToOrdinary: convertedToOrdinary,
    );
  }
}
