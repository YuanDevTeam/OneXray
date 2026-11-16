import 'dart:convert';
import 'dart:io';

import 'package:onexray/core/errors/failure.dart';

import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/advanced/xray/geodata/service.dart';
import 'package:onexray/service/launch/storage_preparation.dart';
import 'package:onexray/service/connect/routing/custom/geodata_suggestions.dart';
import 'package:onexray/service/advanced/tunnel/interface.dart';

enum SetupStep { welcome, configuration, complete }

class SetupFailure extends AppFailure {
  final String component;
  const SetupFailure(this.component, {super.cause})
    : super(
        component == 'privacy'
            ? FailureCategory.permission
            : component == 'region' || component == 'interface'
            ? FailureCategory.input
            : FailureCategory.storage,
        component,
      );
}

/// Setup saves initial preferences. Permissions and connection readiness belong
/// to normal startup and connection actions, not this flow.
class SetupService {
  final AppDatabase? _database;
  final Future<void> Function()? _prepareLocal;
  final Future<void> Function(ConnectionConfiguration)? _saveConfiguration;
  final Future<List<String>> Function()? _readRegionCodes;
  final PreferencesKey _preferences = PreferencesKey();
  final ConnectionPlatform platform;

  SetupService({
    this._database,
    this._prepareLocal,
    this._saveConfiguration,
    this._readRegionCodes,
    ConnectionPlatform? platform,
  }) : platform = platform ?? connectionPlatform;

  AppDatabase get _db => _database ?? AppDatabase();
  bool get supportsProxy =>
      platform == ConnectionPlatform.macos ||
      platform == ConnectionPlatform.windows ||
      platform == ConnectionPlatform.linux;
  bool get requiresInterface =>
      platform == ConnectionPlatform.windows ||
      platform == ConnectionPlatform.linux;

  Future<SetupStep> currentStep() async {
    if (!await _preferences.readPrivacyAccepted()) return SetupStep.welcome;
    if (!await _preferences.readFirstRun()) return SetupStep.complete;
    return SetupStep.configuration;
  }

  Future<void> acceptPrivacy() async {
    await _preferences.savePrivacyAccepted(true);
  }

  Future<void> prepareLocal() async {
    if (!await _preferences.readPrivacyAccepted()) {
      throw const SetupFailure('privacy');
    }
    final prepare = _prepareLocal;
    if (prepare != null) return prepare();
    final databaseWasMissing = await StoragePreparation.ensureReady();
    await GeoDataService().ensureInstalled(
      resetOrphanedFiles: databaseWasMissing,
    );
  }

  Future<ConnectionConfiguration> configuration() async =>
      ConnectionConfiguration.fromJson(
        jsonDecode((await _db.connectionConfigDao.read()).configurationJson)
            as Map<String, dynamic>,
      );

  Future<void> _save(ConnectionConfiguration value) async {
    final save = _saveConfiguration;
    if (save != null) return save(value);
    await _db.connectionConfigDao.commit(configurationJson: value.encode());
  }

  Future<void> finish({
    required String interfaceName,
    List<String>? regions,
    CaptureMode? captureMode,
  }) async {
    await prepareLocal();
    final previous = await configuration();
    final mode = supportsProxy
        ? captureMode ?? previous.policy.captureMode
        : CaptureMode.tun;
    final needsInterface = requiresInterface && mode != CaptureMode.proxy;
    if (needsInterface &&
        !(await interfaces()).any((item) => item.name == interfaceName)) {
      throw const SetupFailure('interface');
    }
    if (regions != null) {
      final available = await regionCodes();
      if (regions.length > 1 || !regions.every(available.contains)) {
        throw const SetupFailure(
          'region',
          cause: 'Select one region from the installed routing data.',
        );
      }
    }
    final policy = previous.policy.toJson();
    if (supportsProxy) policy['captureMode'] = mode.name;
    if (needsInterface) policy['xrayOutboundInterfaceName'] = interfaceName;
    final connection = previous.connection.toJson();
    if (regions != null) {
      connection['smart'] = {
        ...previous.connection.smart.toJson(),
        'directRegions': regions,
      };
    }
    await _save(
      ConnectionConfiguration(
        connection: ConnectionSettings.fromJson(connection),
        policy: PlatformPolicy.fromJson(policy),
      ),
    );
    // Mark complete only after both choices have been committed successfully.
    await _preferences.saveFirstRun(false);
  }

  Future<List<String>> regionCodes() async {
    final read = _readRegionCodes;
    if (read != null) return read();
    final catalog = await (await RoutingGeodataIndex.load()).regionCatalog();
    return catalog.regionCodes;
  }

  /// A Setup region lookup only. Do not persist the IP or response,
  /// send app identifiers, or use the VPN's proxy/metrics endpoint.
  Future<String?> suggestRegion() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.getUrl(
        Uri.https('ip-check-perf.radar.cloudflare.com', '/'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 5))) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) return null;
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      final code = decoded is Map ? decoded['country'] : null;
      return code is String ? code.toUpperCase() : null;
    } on Exception {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<OutboundInterfaceOption>> interfaces() async {
    if (!requiresInterface) return const [];
    return queryXrayOutboundInterfaces();
  }
}
