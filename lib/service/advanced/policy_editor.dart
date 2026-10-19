import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/service/advanced/local_api/service.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/service/advanced/platform_policy.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/runtime_host.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/connect/provider_mode.dart';

/// Subpages carry the same original configuration and their own JSON draft.
/// Invalid intermediate text stays here, never in the database or runtime.
class PolicyEditorDraft {
  final ConnectionConfiguration original;
  final Map<String, dynamic> policy;

  PolicyEditorDraft(this.original, [Map<String, dynamic>? policy])
    : policy = jsonDecode(
        jsonEncode(policy ?? original.policy.toJson()),
      ) as Map<String, dynamic>;

  PolicyEditorDraft copy() => PolicyEditorDraft(original, policy);
}

class PolicyEditorService {
  final ConnectionCoordinator coordinator;
  final ConnectionPlatform platform;
  final WindowsMode windowsMode;
  final bool validateInterface;
  final Future<int?> Function() _reservedApiPort;

  PolicyEditorService({
    ConnectionCoordinator? coordinator,
    ConnectionPlatform? platform,
    WindowsMode? windowsMode,
    this.validateInterface = true,
    Future<int?> Function()? reservedApiPort,
  }) : coordinator = coordinator ?? ConnectionCoordinator.instance,
       platform = platform ?? connectionPlatform,
       windowsMode = windowsMode ?? windowsBuildMode,
       _reservedApiPort =
           reservedApiPort ?? LocalApiService.instance.reservedPort;

  bool get supportsWindowsSystemVpn =>
      platform == ConnectionPlatform.windows && windowsMode == WindowsMode.msix;

  Future<PolicyEditorDraft> load() async {
    await coordinator.initialize();
    return PolicyEditorDraft(await coordinator.configuration);
  }

  bool get requiresInterface =>
      validateInterface &&
      (platform == ConnectionPlatform.windows ||
          platform == ConnectionPlatform.linux);

  static bool emptyAndroidScope(PlatformPolicy policy) {
    final android = policy.toJson()['android'] as Map<String, dynamic>;
    return android['appScope'] == 'included' &&
        (android['includedAppPackageNames'] as List).isEmpty;
  }

  ({PlatformPolicy policy, Object runtime}) prepare(PolicyEditorDraft draft) {
    final value = draft.copy().policy;
    final apple =
        platform == ConnectionPlatform.ios ||
        platform == ConnectionPlatform.macos;
    if (supportsWindowsSystemVpn || apple) {
      final section = apple ? 'apple' : 'windows';
      value[section]['excludedCidrs'] =
          (value[section]['excludedCidrs'] as List)
              .cast<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();
    }
    final policy = PlatformPolicy.fromJson(value);
    if (requiresInterface && policy.xrayOutboundInterfaceName.trim().isEmpty) {
      throw const FormatException('Network interface is required');
    }
    Map<String, dynamic>? appleTun;
    if (supportsWindowsSystemVpn) {
      policy.toWindowsPolicy();
    } else if (apple) {
      appleTun = policy.toTun(platform).toJson();
    } else {
      policy.validateDns(platform, windowsMode: windowsMode);
    }
    return (
      policy: policy,
      runtime: _effectiveRuntime(
        policy,
        platform,
        windowsMode: windowsMode,
        appleTun: appleTun,
      ),
    );
  }

  Future<bool> save({
    required PolicyEditorDraft draft,
    required Future<bool> Function(bool disconnect) confirm,
  }) async {
    final prepared = prepare(draft);
    final policy = prepared.policy;
    await coordinator.initialize();
    await _validateLanProxy(draft, policy);
    await coordinator.refresh();
    if ((await coordinator.configuration).encode() != draft.original.encode()) {
      throw const ConnectionHostException('configurationChanged');
    }
    final changed = !sameRuntime(
      draft.original.policy,
      policy,
      platform,
      windowsMode: windowsMode,
      applyServerDialing: await _usesManagedServerDialing(
        draft.original.connection,
      ),
    );
    final disconnect =
        platform == ConnectionPlatform.android && emptyAndroidScope(policy);
    var allowed = false;
    if (changed && coordinator.state.value.phase == ConnectionPhase.connected) {
      allowed = await confirm(disconnect);
      if (!allowed) {
        return false;
      }
    }
    await coordinator.apply(
      ConnectionConfiguration(
        connection: draft.original.connection,
        policy: policy,
      ),
      affectsRuntime: changed,
      disconnect: disconnect && changed,
      expectedConfiguration: draft.original.encode(),
      allowReconnect: allowed,
    );
    return true;
  }

  Future<bool> _usesManagedServerDialing(ConnectionSettings settings) async {
    if (settings.expert ||
        await usesProviderConfiguration(
          coordinator.db,
          settings,
          runtime: coordinator.state.value.runtime,
        )) {
      return false;
    }
    if (settings.trafficMode != TrafficMode.custom) return true;
    final id = settings.customId;
    return id != null &&
        (await coordinator.db.routingProfileDao.searchRow(id))?.advanced ==
            false;
  }

  Future<void> _validateLanProxy(
    PolicyEditorDraft draft,
    PlatformPolicy policy,
  ) async {
    if (draft.original.connection.expert || !policy.lanProxyEnabled) return;
    if (await usesProviderConfiguration(
      coordinator.db,
      draft.original.connection,
      runtime: coordinator.state.value.runtime,
    )) {
      return;
    }
    if (policy.lanProxyPort == await _reservedApiPort()) {
      throw const FormatException(
        'Proxy port conflicts with the local HTTP API',
      );
    }
    final settings = draft.original.connection;
    String? data;
    if (settings.trafficMode == TrafficMode.custom &&
        settings.customId != null) {
      final row = await coordinator.db.routingProfileDao.searchRow(
        settings.customId!,
      );
      if (row?.advanced == true) data = row!.data;
    }
    if (data != null) {
      final json =
          jsonDecode(utf8.decode(base64Decode(data))) as Map<String, dynamic>;
      ConnectionCompiler.validateLanProxyInbounds(
        json['inbounds'] as List? ?? [],
        policy.lanProxyPort,
      );
    }
  }

  /// LAN sharing applies on the next App start. Inactive platform settings and
  /// inactive Android lists are also storage only.
  static bool sameRuntime(
    PlatformPolicy a,
    PlatformPolicy b,
    ConnectionPlatform platform, {
    WindowsMode? windowsMode,
    bool applyServerDialing = true,
  }) => const DeepCollectionEquality().equals(
    _effectiveRuntime(
      a,
      platform,
      windowsMode: windowsMode,
      applyServerDialing: applyServerDialing,
    ),
    _effectiveRuntime(
      b,
      platform,
      windowsMode: windowsMode,
      applyServerDialing: applyServerDialing,
    ),
  );

  static Object _effectiveRuntime(
    PlatformPolicy policy,
    ConnectionPlatform platform, {
    WindowsMode? windowsMode,
    Map<String, dynamic>? appleTun,
    bool applyServerDialing = true,
  }) {
    final json = policy.toJson();
    final result = <String, dynamic>{
      'ipv6': policy.ipv6Enabled,
      if (applyServerDialing)
        'dialing': policy.dialing.effective(ipv6: policy.ipv6Enabled).toJson(),
      'dnsIpv4Address': policy.dnsIpv4Address,
      if (policy.ipv6Enabled ||
          (platform == ConnectionPlatform.windows &&
              (windowsMode ?? windowsBuildMode) == WindowsMode.msix))
        'dnsIpv6Address': policy.dnsIpv6Address,
      'log': json['log'],
    };
    if (platform == ConnectionPlatform.android) {
      final android = json['android'] as Map<String, dynamic>;
      final scope = android['appScope'];
      final packages = switch (scope) {
        'included' => List<String>.from(android['includedAppPackageNames']),
        'excluded' => List<String>.from(android['excludedAppPackageNames']),
        _ => <String>[],
      }..sort();
      result['android'] = {'scope': scope, 'packages': packages};
    } else if (platform == ConnectionPlatform.ios ||
        platform == ConnectionPlatform.macos) {
      final tun = appleTun ?? policy.toTun(platform).toJson();
      if (tun['enableDot'] != true) tun.remove('dnsServerName');
      result['apple'] = tun;
    } else {
      result['interface'] = policy.xrayOutboundInterfaceName;
      if (platform == ConnectionPlatform.windows &&
          (windowsMode ?? windowsBuildMode) == WindowsMode.msix) {
        result['windows'] = json['windows'];
      }
    }
    return result;
  }
}
