import 'dart:convert';

import 'package:onexray/core/errors/failure.dart';
import 'package:onexray/core/errors/json_diagnostic.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/json_document.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/connect/raw/validator.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/connect/routing/custom/service.dart';
import 'package:onexray/service/connect/routing/region_catalog.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/shared/xray/validation.dart';

typedef LocalApiResourceScope = Future<Map<String, dynamic>> Function(
  Future<Map<String, dynamic>> Function() action,
);

/// Read-only adapters over the same document and compiler boundaries as the UI.
/// No selection, database writes, downloads, port allocation or VPN operations.
final class LocalApiConfiguration {
  final Future<String> Function(String) _testXray;
  final LocalApiResourceScope _withResources;

  LocalApiConfiguration({
    Future<String> Function(String)? testXray,
    LocalApiResourceScope? withResources,
  }) : _testXray = testXray ?? AppHostApi().testXray,
       _withResources = withResources ?? GeoDataService().withFiles;

  Future<Map<String, dynamic>> validate(Map<String, dynamic> request) =>
      _execute(request, compile: false);

  Future<Map<String, dynamic>> compile(Map<String, dynamic> request) =>
      _execute(request, compile: true);

  Future<Map<String, dynamic>> _execute(
    Map<String, dynamic> request, {
    required bool compile,
  }) async {
    JsonDocument? source;
    late final _Configuration input;
    try {
      if (!compile &&
          (request.containsKey('outbounds') ||
              request.containsKey('options'))) {
        throw const FormatException(
          'validate checks the document only; outbounds and options are '
          'accepted only by compile',
        );
      }
      final text = _required<String>(request, 'text');
      source = JsonDocument(text);
      if (source.syntaxError case final error?) throw error;
      input = _Configuration.parse(request, text);
    } catch (error) {
      return _failure(error, 'input', source: source);
    }
    try {
      return await _withResources(() async {
        if (compile) {
          try {
            final output = _compile(input, request);
            return _result(
              'passed',
              'compile',
              compiledConfig: output,
              limitations: const [
                'Compilation is a preview only. The configuration was not '
                    'validated by the kernel, saved or started.',
                'Paths refer to the running App; ports and network interface '
                    'availability were not checked.',
              ],
            );
          } catch (error) {
            // Compiler errors describe a generated copy or request options,
            // not positions in the submitted JSON document.
            return _failure(error, 'compile');
          }
        }
        late final String projected;
        try {
          projected = input.validationJson();
        } catch (error) {
          return _failure(error, 'compile');
        }
        final limitations = [
          'Kernel validation constructs and closes an Xray instance; it does '
              'not start VPN, check permissions, bind ports or test connectivity.',
          'App-managed runtime fields are projected for validation; this is '
              'not a sandbox and process-level side effects remain possible.',
          'Only installed local resources are used. Dependencies are not '
              'downloaded and App database limits are not checked.',
          if (input.routing != null)
            'Entry slots use local freedom placeholders. Actual proxy nodes '
                'and their combined runtime configuration were not validated.',
        ];
        try {
          final error = await _testXray(projected);
          return _result(
            error.isEmpty ? 'passed' : 'failed',
            'kernel',
            validationConfig: projected,
            diagnostics: [
              if (error.isNotEmpty)
                {'code': 'kernelRejected', 'message': error},
            ],
            limitations: limitations,
          );
        } catch (error) {
          return _result(
            'notRun',
            'kernel',
            validationConfig: projected,
            diagnostics: [
              {
                'code': 'validationUnavailable',
                'message': failureDetails(error),
              },
            ],
            limitations: limitations,
          );
        }
      });
    } catch (error) {
      return _result(
        'notRun',
        'compile',
        diagnostics: [
          {'code': 'resourcesUnavailable', 'message': failureDetails(error)},
        ],
      );
    }
  }

  String _compile(_Configuration input, Map<String, dynamic> request) {
    final options = _runtimeOptions(
      _required<Map<String, dynamic>>(request, 'options'),
      includeLanProxy: input.raw == null,
    );
    final routing = input.routing;
    final supplied = request['outbounds'];
    final nodes = <Map<String, dynamic>>[];
    if (routing != null) {
      if (supplied is! List || supplied.length != routing.entryCount) {
        throw FormatException(
          'Provide exactly ${routing.entryCount} explicit outbounds for this template',
        );
      }
      for (final node in supplied) {
        if (node is! Map<String, dynamic> || node.isEmpty) {
          throw const FormatException(
            'Entry outbounds must be non-empty objects',
          );
        }
        nodes.add(copyOutboundMap(node));
      }
    } else {
      if (supplied != null) {
        throw const FormatException(
          'outbounds is only accepted for routing templates',
        );
      }
      if (input.outbound case final outbound?) nodes.add(outbound);
    }
    return ConnectionCompiler.compile(
      settings: ConnectionSettings(
        expert: input.raw != null,
        trafficMode: routing == null ? TrafficMode.allVpn : TrafficMode.custom,
      ),
      entries: [
        for (final (index, node) in nodes.indexed)
          ResolvedServer(id: index + 1, sourceId: 0, outbound: node),
      ],
      raw: input.raw,
      custom: routing,
      regions: const RegionCatalog.empty(),
      options: options,
    ).xrayJson;
  }
}

final class _Configuration {
  final Map<String, dynamic>? outbound;
  final Map<String, dynamic>? raw;
  final RoutingConfiguration? routing;
  const _Configuration({this.outbound, this.raw, this.routing});

  factory _Configuration.parse(Map<String, dynamic> request, String text) {
    final kind = _required<String>(request, 'kind');
    final name = _optional<String>(request, 'name');
    switch (kind) {
      case 'outbound':
        final value = jsonDecode(text);
        if (value is! Map<String, dynamic>) {
          throw const JsonDiagnostic(
            'An outbound object is required',
            path: [],
          );
        }
        return _Configuration(
          outbound: copyOutboundMap(value, nameAlias: name),
        );
      case 'routing':
        return _Configuration(
          routing: ConfigurationTransferService.read(
            text,
            ConfigurationKind.custom,
            nameOverride: name,
          ).routing!,
        );
      case 'advanced-routing':
        return _Configuration(
          routing: ConfigurationTransferService.read(
            text,
            ConfigurationKind.customAdvanced,
            nameOverride: name,
          ).routing!,
        );
      case 'raw':
        return _Configuration(
          raw: XrayRawValidator.normalize(text, nameOverride: name).json,
        );
      default:
        throw const FormatException(
          'kind must be outbound, routing, advanced-routing or raw',
        );
    }
  }

  String validationJson() {
    if (routing case final state?) {
      return CustomRoutingService.validationJson(state);
    }
    if (raw case final config?) return XrayValidation.full(config);
    return XrayValidation.nodes([outbound!]);
  }
}

RuntimeOptions _runtimeOptions(
  Map<String, dynamic> values, {
  required bool includeLanProxy,
}) {
  final platformName = _required<String>(values, 'platform');
  final platform = ConnectionPlatform.values.firstWhere(
    (value) => value.name == platformName,
    orElse: () => throw const FormatException('Unsupported target platform'),
  );
  final modeName = platform == ConnectionPlatform.windows
      ? _required<String>(values, 'windowsMode')
      : _optional<String>(values, 'windowsMode') ?? 'exe';
  final mode = WindowsMode.values.firstWhere(
    (value) => value.name == modeName,
    orElse: () =>
        throw const FormatException('windowsMode must be exe or msix'),
  );
  final directory = _required<String>(values, 'sessionDirectory');
  if (directory.trim().isEmpty) {
    throw const FormatException('sessionDirectory must not be empty');
  }
  final metrics = _required<int>(values, 'metricsPort');
  final socks = _required<int>(values, 'socksPort');
  if (metrics < 1 || metrics > 65535 || socks < 1 || socks > 65535) {
    throw const FormatException('Preview ports must be within 1–65535');
  }
  return RuntimeOptions(
    platform: platform,
    windowsMode: mode,
    sessionDirectory: directory,
    metricsPort: metrics,
    socksPort: socks,
    lanProxyEnabled:
        includeLanProxy &&
        (_optional<bool>(values, 'lanProxyEnabled') ?? false),
    lanProxyPort: includeLanProxy
        ? _optional<int>(values, 'lanProxyPort') ?? 11024
        : 11024,
    ipv6: _required<bool>(values, 'ipv6'),
    interfaceName: _optional<String>(values, 'interfaceName') ?? '',
    tunDnsIpv4Address:
        _optional<String>(values, 'tunDnsIpv4Address') ?? '8.8.8.8',
    tunDnsIpv6Address:
        _optional<String>(values, 'tunDnsIpv6Address') ??
        '2001:4860:4860::8888',
    logEnabled: _optional<bool>(values, 'logEnabled') ?? false,
    logFilesSupported: _optional<bool>(values, 'logFilesSupported') ?? true,
    logLevel: _optional<String>(values, 'logLevel') ?? 'warning',
    dnsLog: _optional<bool>(values, 'dnsLog') ?? true,
    maskAddress: _optional<String>(values, 'maskAddress') ?? '',
  );
}

T _required<T>(Map<String, dynamic> values, String key) {
  final value = values[key];
  if (value is! T) throw FormatException('$key is required and must be $T');
  return value;
}

T? _optional<T>(Map<String, dynamic> values, String key) {
  final value = values[key];
  if (value == null) return null;
  if (value is! T) throw FormatException('$key must be $T');
  return value;
}

Map<String, dynamic> _failure(
  Object error,
  String stage, {
  JsonDocument? source,
}) {
  final diagnostic = JsonDiagnostic.fromError(error);
  final range = diagnostic == null
      ? null
      : source?.rangeForDiagnostic(diagnostic);
  final position = range == null ? null : source?.positionAt(range.start);
  final expected = error is FormatException;
  return _result(
    expected ? 'failed' : 'notRun',
    stage,
    diagnostics: [
      {
        'code': expected ? 'invalidConfiguration' : 'operationUnavailable',
        'message': diagnostic?.message ?? failureDetails(error),
        if (diagnostic?.path != null) 'path': diagnostic!.path,
        if (range != null) 'offset': range.start,
        if (position != null) ...{
          'line': position.line + 1,
          'column': position.column + 1,
        },
      },
    ],
  );
}

Map<String, dynamic> _result(
  String status,
  String stage, {
  List<Map<String, dynamic>> diagnostics = const [],
  String? validationConfig,
  String? compiledConfig,
  List<String> limitations = const [],
}) => {
  'apiVersion': 1,
  'status': status,
  'stage': stage,
  'diagnostics': diagnostics,
  'validationConfig': ?validationConfig,
  'compiledConfig': ?compiledConfig,
  if (limitations.isNotEmpty) 'limitations': limitations,
};
