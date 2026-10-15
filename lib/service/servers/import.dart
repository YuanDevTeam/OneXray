import 'dart:convert';
import 'dart:io';

import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/service/shared/db/config_writer.dart';
import 'package:onexray/service/connect/raw/editor.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/advanced/xray/geodata/model.dart';
import 'package:onexray/service/advanced/xray/geodata/validator.dart';
import 'package:onexray/service/shared/ping/service.dart';
import 'package:onexray/service/shared/xray/validation.dart';
import 'package:onexray/service/shared/share/app_link_model.dart';
import 'package:onexray/service/shared/share/app_link_parser.dart';
import 'package:onexray/service/shared/share/service.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/shared/share/configuration_source.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/shared/in_flight_operations.dart';
import 'package:onexray/service/shared/share/xray_share_reader.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/connect/raw/db.dart';
import 'package:onexray/service/connect/raw/validator.dart';
import 'package:path/path.dart' as p;

class ServerImportResult {
  final int count;
  final int? subscriptionId;
  final int rawCount;
  final int customCount;
  final int geoDataCount;
  final int subscriptionCount;
  final List<OneXrayGeoDataLink> failedGeoData;
  int get writeFailureCount => failedGeoData.length;
  const ServerImportResult({
    required this.count,
    this.subscriptionId,
    this.rawCount = 0,
    this.customCount = 0,
    this.geoDataCount = 0,
    this.subscriptionCount = 0,
    this.failedGeoData = const [],
  });
}

class ServerImportPreview {
  final List<CoreConfigCompanion> rows;
  final List<ParsedRawConfiguration> raw;
  final List<OneXrayGeoDataLink> geoData;
  final List<ConfigurationContent> customRoutes;
  final List<GeoDataInput> assets;
  final GeoDataImport? _dependencies;
  ServerImportPreview(
    Iterable<CoreConfigCompanion> rows, {
    Iterable<ParsedRawConfiguration> raw = const [],
    Iterable<OneXrayGeoDataLink> geoData = const [],
    Iterable<ConfigurationContent> customRoutes = const [],
    this._dependencies,
    Iterable<GeoDataInput> assets = const [],
  }) : rows = List.unmodifiable(rows),
       raw = List.unmodifiable(raw),
       geoData = List.unmodifiable(geoData),
       customRoutes = List.unmodifiable(customRoutes),
       assets = List.unmodifiable(assets);
  int get count => rows.length;
  int get rawCount => raw.length;
  bool get hasItems =>
      rows.isNotEmpty ||
      raw.isNotEmpty ||
      geoData.isNotEmpty ||
      customRoutes.isNotEmpty;
  Future<void> dispose() async => _dependencies?.dispose();
}

class ServerImportDetection {
  final List<OneXraySubscriptionLink> subscriptions;
  final List<_ImportLine> _local;
  ServerImportDetection._(
    Iterable<OneXraySubscriptionLink> subscriptions,
    Iterable<_ImportLine> local,
  ) : subscriptions = List.unmodifiable(subscriptions),
      _local = List.unmodifiable(local);
  String get localText => _local.map((line) => line.text).join('\n');
}

final class _ImportLine {
  final String text;
  final Uri? uri;
  final OneXrayAppLink? link;
  const _ImportLine._(this.text, this.uri, this.link);

  factory _ImportLine.parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null) {
      return _ImportLine._(text, uri, null);
    }
    final link = OneXrayAppLinkParser.parse(uri);
    return _ImportLine._(
      text,
      uri,
      link ??
          (NetClient.isHttpsDownloadUri(uri)
              ? OneXraySubscriptionLink(
                  name: uri.fragment,
                  url: SubscriptionUrl.normalize(uri.toString()),
                )
              : null),
    );
  }
}

class ServerSubscriptionImport {
  final String name;
  final SubscriptionInsertResult result;
  const ServerSubscriptionImport(this.name, this.result);
}

/// Prepares content without writes; [commit] imports it after user-initiated input.
class ServerImportService {
  // Pages create import instances; clear-data pauses their shared import work.
  static final _imports = InFlightOperations();

  static Future<void> pauseForDataClear() => _imports.pause();

  static void resumeAfterDataClear() => _imports.resume();

  final AppDatabase? _database;
  final ConfigurationTransferService _transfer;
  final Future<List<CoreConfigCompanion>> Function(String) _parse;
  final Future<String> Function(String) _validate;
  final Future<ConfigWriteResult> Function(List<CoreConfigCompanion>) _write;
  final void Function(List<int>) _schedule;
  final Future<SubscriptionInsertResult> Function(OneXraySubscriptionLink)
  _subscribe;
  final Future<bool> Function(OneXrayGeoDataLink) _validateGeoData;
  final Future<bool> Function(OneXrayGeoDataLink) _writeGeoData;

  ServerImportService({
    AppDatabase? database,
    ConfigurationTransferService? transfer,
    Future<List<CoreConfigCompanion>> Function(String)? parse,
    Future<String> Function(String)? validate,
    Future<ConfigWriteResult> Function(List<CoreConfigCompanion>)? write,
    void Function(List<int>)? schedule,
    Future<SubscriptionInsertResult> Function(OneXraySubscriptionLink)?
    subscribe,
    Future<bool> Function(OneXrayGeoDataLink)? validateGeoData,
    Future<bool> Function(OneXrayGeoDataLink)? writeGeoData,
  }) : _database = database,
       _transfer = transfer ?? ConfigurationTransferService(),
       _parse = parse ?? XrayShareReader().parseShareText,
       _validate = validate ?? AppHostApi().testXray,
       _write =
           write ??
           ((rows) => ConfigWriter.writeRowsInTransaction(
             database ?? AppDatabase(),
             rows,
             null,
           )),
       _schedule = schedule ?? PingService().schedulePingConfigIds,
       _subscribe = subscribe ?? _importSubscription,
       _validateGeoData =
           validateGeoData ??
           ((link) async =>
               (await GeoDataValidator.validate(link.name, link.url)).item1),
       _writeGeoData =
           writeGeoData ??
           ((link) async {
             await GeoDataService().add(
               GeoDataInput(
                 fileName: link.name,
                 type: link.type,
                 url: link.url,
               ),
             );
             return true;
           });

  static void _checkSize(String text) {
    if (text.trim().isEmpty || utf8.encode(text).length > 16 * 1024 * 1024) {
      throw const FormatException('Invalid import size');
    }
  }

  /// Classify before any writes. JSON/base64 stay intact for the native parser.
  ServerImportDetection detect(String text) {
    _checkSize(text);
    final subscriptions = <OneXraySubscriptionLink>[];
    final local = <_ImportLine>[];
    for (final line in _inputLines(text)) {
      final link = line.link;
      if (link is OneXraySubscriptionLink) {
        subscriptions.add(link);
      } else {
        local.add(line);
      }
    }
    return ServerImportDetection._(subscriptions, local);
  }

  static List<_ImportLine> _inputLines(String text) =>
      text.trimLeft().startsWith('{')
      ? [_ImportLine._(text, null, null)]
      : text.split('\n').map(_ImportLine.parse).toList();

  Future<List<ServerSubscriptionImport>> importSubscriptions(
    List<OneXraySubscriptionLink> links,
  ) => _imports.track(() async {
    final results = <ServerSubscriptionImport>[];
    for (final link in links) {
      if (_imports.isPaused) break;
      final name = link.name.trim().isEmpty
          ? Uri.parse(link.url).host
          : link.name.trim();
      try {
        results.add(ServerSubscriptionImport(name, await _subscribe(link)));
      } catch (error) {
        results.add(
          ServerSubscriptionImport(
            name,
            SubscriptionInsertResult(
              status: SubscriptionUpdateResult.writeFailed,
              error: error,
            ),
          ),
        );
      }
    }
    return List.unmodifiable(results);
  });

  static Future<SubscriptionInsertResult> _importSubscription(
    OneXraySubscriptionLink link,
  ) async {
    if (!NetClient.isHttpsDownloadUri(Uri.parse(link.url))) {
      return const SubscriptionInsertResult(
        status: SubscriptionUpdateResult.invalidContent,
      );
    }
    final service = SubscriptionService();
    for (final row in await AppDatabase().subscriptionDao.allRows) {
      if (row.url != link.url) continue;
      final result = await service.refreshSubscriptionResult(row);
      return SubscriptionInsertResult(
        status: result.status,
        subId: row.id,
        count: result.count,
        error: result.error,
      );
    }
    String? secretKey;
    String? publicKey;
    if (link.ageKeyType != null) {
      final pair = await AppHostApi().generateAgeKeyPair(
        keyType: link.ageKeyType!,
      );
      secretKey = pair.secretKey;
      publicKey = pair.publicKey;
      if (secretKey?.isNotEmpty != true || publicKey?.isNotEmpty != true) {
        return const SubscriptionInsertResult(
          status: SubscriptionUpdateResult.invalidAgeSecretKey,
        );
      }
    }
    final name = link.name.trim().isEmpty
        ? Uri.parse(link.url).host
        : link.name.trim();
    return service.insertSubscription(
      SubscriptionInput(
        name: name,
        url: link.url,
        userAgent: link.userAgent,
        ageSecretKey: secretKey,
        agePublicKey: publicKey,
        panel: link.panel,
        mode: link.mode,
      ),
    );
  }

  Future<ServerImportPreview> preview(
    String text, {
    bool manual = false,
  }) async {
    _checkSize(text);
    return _preview(
      ServerImportDetection._([], _inputLines(text)),
      manual: manual,
    );
  }

  Future<ServerImportPreview> previewDetected(
    ServerImportDetection detection,
  ) => _preview(detection);

  Future<ServerImportPreview> _preview(
    ServerImportDetection detection, {
    bool manual = false,
  }) async {
    final text = detection.localText;
    _checkSize(text);
    if (!manual) {
      if (text.trimLeft().startsWith('{')) {
        final source = ConfigurationSource.parse(text);
        final json = source.value;
        if (json is Map<String, dynamic>) {
          final outbounds = json['outbounds'];
          final custom =
              outbounds is List &&
              outbounds.any(
                (item) =>
                    item == null ||
                    (item is Map && (item.isEmpty || item['tag'] == '')),
              );
          final raw = json.keys.any(
            const {'inbounds', 'routing', 'dns', 'fakedns'}.contains,
          );
          if (custom || raw) {
            final content = ConfigurationTransferService.readSource(
              source,
              custom ? ConfigurationKind.custom : ConfigurationKind.raw,
            );
            return _configurationPreview([], [content], []);
          }
        }
        return ServerImportPreview(await _parse(text));
      }
      final rows = <CoreConfigCompanion>[];
      final geoData = <OneXrayGeoDataLink>[];
      final other = <String>[];
      final configurations = <ConfigurationContent>[];
      final parsedLines = detection._local;
      final usedGeoData = <OneXrayGeoDataLink>{};
      for (final item in parsedLines) {
        final uri = item.uri;
        final link = item.link;
        if (link == null) {
          if (uri?.scheme.toLowerCase() == OneXrayAppLinkParser.scheme) {
            continue;
          }
          other.add(item.text);
          continue;
        }
        try {
          if (link is OneXrayConfigLink &&
              link.type == OneXrayConfigLinkType.outbound) {
            final outbound = decodeSingleOutbound(
              link.xrayJson,
              nameAlias: link.name.isEmpty ? null : link.name,
            );
            final error = await _validate(XrayValidation.nodes([outbound]));
            if (error.isNotEmpty) {
              throw AppFailure(
                FailureCategory.configuration,
                'xrayValidation',
                cause: error,
              );
            }
            rows.add(outboundCompanion(outbound));
          } else if (link is OneXrayConfigLink &&
              link.type != OneXrayConfigLinkType.outbound) {
            final kind = ConfigurationKind.values.singleWhere(
              (kind) => kind.linkType == link.type,
            );
            final source = ConfigurationSource.parse(link.xrayJson);
            final dependencies = <OneXrayGeoDataLink>[];
            if (kind == ConfigurationKind.raw) {
              final references = geoDataReferences(
                source.value as Map<String, dynamic>,
              );
              for (final data
                  in parsedLines
                      .map((item) => item.link)
                      .whereType<OneXrayGeoDataLink>()) {
                if (references.containsKey(data.name) ||
                    references.containsKey('${data.name}.dat')) {
                  usedGeoData.add(data);
                  dependencies.add(data);
                }
              }
            }
            configurations.add(
              ConfigurationTransferService.readSource(
                source,
                kind,
                nameOverride: link.name.isEmpty ? null : link.name,
                linked: dependencies,
              ),
            );
          } else if (link is OneXrayGeoDataLink) {
            geoData.add(link);
          } else {
            throw const FormatException('Unsupported local asset');
          }
        } catch (_) {
          // Skip invalid links without discarding the remaining input.
        }
      }
      if (other.any((line) => line.trim().isNotEmpty)) {
        try {
          rows.addAll(await _parse(other.join('\n')));
        } catch (_) {
          // Other valid App links in this input may still be imported.
        }
      }
      geoData.removeWhere(
        (link) => usedGeoData.any(
          (used) =>
              used.name == link.name &&
              used.type == link.type &&
              used.url == link.url,
        ),
      );
      final standalone = <OneXrayGeoDataLink>[];
      for (final link in geoData) {
        if (!_safeGeoDataName(link.name) ||
            !NetClient.isHttpsDownloadUri(Uri.parse(link.url)) ||
            !await _validateGeoData(link) ||
            standalone.any((item) => item.name == link.name)) {
          continue;
        }
        standalone.add(link);
      }
      return _configurationPreview(rows, configurations, standalone);
    }
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> ||
        json['outbounds'] is! List ||
        (json['outbounds'] as List).isEmpty) {
      throw const JsonDiagnostic(
        'A non-empty outbounds array is required',
        path: ['outbounds'],
      );
    }
    final error = await _validate(
      XrayValidation.nodes(json['outbounds'] as List),
    );
    if (error.isNotEmpty) {
      throw AppFailure(
        FailureCategory.configuration,
        'xrayValidation',
        cause: error,
      );
    }
    return ServerImportPreview([
      for (final outbound in json['outbounds'] as List)
        outboundCompanion(outbound as Map<String, dynamic>),
    ]);
  }

  Future<ServerImportPreview> _configurationPreview(
    List<CoreConfigCompanion> rows,
    List<ConfigurationContent> contents,
    List<OneXrayGeoDataLink> standalone,
  ) async {
    final custom = contents
        .where((item) => item.kind != ConfigurationKind.raw)
        .toList();
    if (custom.length > 3 || contents.any((item) => item.name.trim().isEmpty)) {
      throw const FormatException('Invalid configuration name or count');
    }
    final assets = [for (final content in contents) ...content.assets];
    final draft = await _transfer.prepareAssets(assets);
    try {
      if (draft == null) {
        for (final route in custom) {
          await CustomRoutingService.validate(
            route.routing!,
            testXray: _validate,
          );
        }
      }
      final raw = <ParsedRawConfiguration>[];
      for (final content in contents.where(
        (item) => item.kind == ConfigurationKind.raw,
      )) {
        final name = content.name.trim();
        if (name.runes.length > 32) throw const RawEditorException('name');
        final parsed = XrayRawValidator.normalizeParsed(
          content.source,
          nameOverride: name,
        );
        if (draft == null) {
          await XrayRawValidator.validateParsed(parsed, testXray: _validate);
        }
        raw.add(parsed);
      }
      return ServerImportPreview(
        rows,
        raw: raw,
        customRoutes: custom,
        dependencies: draft,
        assets: assets,
        geoData: standalone,
      );
    } catch (_) {
      await draft?.dispose();
      rethrow;
    }
  }

  Future<ServerImportResult> commit(ServerImportPreview preview) =>
      _imports.track(() async {
        if (!preview.hasItems) {
          throw const FormatException('No usable servers');
        }
        return _commitPreview(preview);
      });

  Future<ServerImportResult> _commitPreview(ServerImportPreview preview) async {
    late final db = _database ?? AppDatabase();
    Future<ConfigWriteResult?> save(
      Future<void> Function() writeMetadata,
    ) async {
      if (preview._dependencies != null) {
        for (final route in preview.customRoutes) {
          await CustomRoutingService.validate(
            route.routing!,
            testXray: _validate,
          );
        }
        for (final raw in preview.raw) {
          await XrayRawValidator.validateParsed(raw, testXray: _validate);
        }
      }
      Future<ConfigWriteResult?> write() async {
        await writeMetadata();
        final rows = [
          ...preview.rows,
          for (final raw in preview.raw)
            XrayRawDb.configCompanion(raw.name.trim(), raw.text),
        ];
        final result = rows.isEmpty ? null : await _write(rows);
        if (result != null &&
            (result.count != rows.length || result.ids.length != rows.length)) {
          throw StateError('Incomplete asset write');
        }
        for (final custom in preview.customRoutes) {
          await CustomRoutingService(db)
              .save(custom.routing!.copyWith(name: custom.name));
        }
        return result;
      }

      return preview._dependencies != null || preview.customRoutes.isNotEmpty
          ? db.transaction(write)
          : write();
    }

    final result = preview._dependencies != null
        ? await preview._dependencies.save(save)
        : preview.customRoutes.isNotEmpty
        ? await GeoDataService().withFiles(() => save(() async {}))
        : await save(() async {});
    if (result != null && !_imports.isPaused) {
      _schedule(result.ids.take(preview.rows.length).toList());
    }
    var geoDataCount = 0;
    final failures = <OneXrayGeoDataLink>[];
    for (final link in preview.geoData) {
      if (_imports.isPaused) {
        failures.add(link);
        continue;
      }
      try {
        if (await _writeGeoData(link)) {
          geoDataCount++;
        } else {
          failures.add(link);
        }
      } catch (_) {
        failures.add(link);
      }
    }
    return ServerImportResult(
      count: preview.count,
      rawCount: preview.rawCount,
      customCount: preview.customRoutes.length,
      geoDataCount: geoDataCount,
      failedGeoData: List.unmodifiable(failures),
    );
  }

  static bool _safeGeoDataName(String name) =>
      name.isNotEmpty &&
      !name.endsWith('.') &&
      !name.endsWith(' ') &&
      !RegExp(r'[/\\:*?"<>|\x00-\x1f]').hasMatch(name) &&
      !RegExp(
        r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
        caseSensitive: false,
      ).hasMatch(name);

  static Future<String?> pickTextFile({bool jsonOnly = false}) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: jsonOnly
          ? ['json', 'txt']
          : ['json', 'txt', 'png', 'jpg', 'jpeg', 'webp'],
    );
    if (file == null) {
      return null;
    }
    if (file.path == null) {
      throw const FormatException('Cannot read selected file');
    }
    final input = File(file.path!);
    if (await input.length() > 16 * 1024 * 1024) {
      throw const FormatException('Invalid import size');
    }
    if ([
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
    ].contains(p.extension(file.path!).toLowerCase())) {
      final text = await ShareService().readImageFile(file.path!);
      if (text == null || text.trim().isEmpty) {
        throw const FormatException('No QR code recognized');
      }
      _checkSize(text);
      return text;
    }
    return input.readAsString();
  }

  static Future<String?> pickQrImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return null;
    if (await File(image.path).length() > 16 * 1024 * 1024) {
      throw const FormatException('Invalid import size');
    }
    final text = await ShareService().readImageFile(image.path);
    if (text == null) throw const FormatException('No QR code recognized');
    _checkSize(text);
    return text;
  }

  static Future<String?> readClipboard() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}
