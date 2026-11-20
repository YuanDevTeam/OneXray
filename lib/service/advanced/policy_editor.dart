import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:onexray/core/ffi/windows/mode.dart';
import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/proxy/host.dart';
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

  bool get hasChanges =>
      !const DeepCollectionEquality().equals(policy, original.policy.toJson());

  PolicyEditorDraft copy() => PolicyEditorDraft(original, policy);
}

class PolicyEditorService {
  final ConnectionCoordinator coordinator;
  final ConnectionPlatform platform;
  final WindowsMode windowsMode;
  final bool validateInterface;
  final Future<int?> Function() _reservedApiPort;
  final Future<({bool supported, String? reason})> Function()? _proxyCapability;
  final Future<bool> Function()? _supportsApnsProxyPreset;

  PolicyEditorService({
    ConnectionCoordinator? coordinator,
    ConnectionPlatform? platform,
    WindowsMode? windowsMode,
    this.validateInterface = true,
    Future<int?> Function()? reservedApiPort,
    Future<({bool supported, String? reason})> Function()? proxyCapability,
    Future<bool> Function()? supportsApnsProxyPreset,
  }) : coordinator = coordinator ?? ConnectionCoordinator.instance,
       platform = platform ?? connectionPlatform,
       windowsMode = windowsMode ?? windowsBuildMode,
       _reservedApiPort =
           reservedApiPort ?? LocalApiService.instance.reservedPort,
       // Keep the injectable named argument public while storing it privately.
       // ignore: prefer_initializing_formals
       _proxyCapability = proxyCapability,
       // ignore: prefer_initializing_formals
       _supportsApnsProxyPreset = supportsApnsProxyPreset;

  bool get supportsWindowsSystemVpn =>
      platform == ConnectionPlatform.windows && windowsMode == WindowsMode.msix;

  Future<PolicyEditorDraft> load() async {
    await coordinator.initialize();
    return PolicyEditorDraft(await coordinator.configuration);
  }

  Future<bool> apnsProxyPresetApplicable(
    ConnectionConfiguration configuration,
  ) async =>
      platform == ConnectionPlatform.ios &&
      await _usesAppManagedOrdinaryRouting(configuration.connection);

  Future<bool> _apnsProxyPresetSupported() async =>
      await (_supportsApnsProxyPreset?.call() ??
          AppHostApi().appleVpnCapabilities().then(
            (value) => value.serviceExclusions,
          ));

  bool get requiresInterface =>
      validateInterface &&
      (platform == ConnectionPlatform.windows ||
          platform == ConnectionPlatform.linux);

  bool get supportsProxy =>
      platform == ConnectionPlatform.macos ||
      platform == ConnectionPlatform.windows ||
      platform == ConnectionPlatform.linux;

  Future<({bool supported, String? reason})> proxyCapability() async {
    if (_proxyCapability != null) return _proxyCapability();
    final capability = await DesktopProxyHost().capability();
    return (supported: capability.supported, reason: capability.reason);
  }

  static bool emptyAndroidScope(PlatformPolicy policy) {
    final android = policy.toJson()['android'] as Map<String, dynamic>;
    return android['appScope'] == 'included' &&
        (android['includedAppPackageNames'] as List).isEmpty;
  }

  ({PlatformPolicy policy, Object runtime}) prepare(
    PolicyEditorDraft draft, {
    bool apnsPresetApplicable = false,
  }) {
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
    if (!policy.usesProxy(platform) &&
        requiresInterface &&
        policy.xrayOutboundInterfaceName.trim().isEmpty) {
      throw const FormatException('Network interface is required');
    }
    if (policy.usesProxy(platform)) {
      // Tunnel-only drafts stay stored without becoming proxy requirements.
    } else if (supportsWindowsSystemVpn) {
      policy.toWindowsPolicy();
    } else if (!apple) {
      policy.validateDns(platform, windowsMode: windowsMode);
    }
    return (
      policy: policy,
      runtime: _effectiveRuntime(
        policy,
        platform,
        windowsMode: windowsMode,
        apnsPresetApplicable: apnsPresetApplicable,
      ),
    );
  }

  Future<bool> save({
    required PolicyEditorDraft draft,
    required Future<bool> Function(bool disconnect) confirm,
  }) async {
    final wantsApnsPreset =
        platform == ConnectionPlatform.ios &&
        draft.policy['apple']['apnsProxyPreset'] == true;
    final basePolicy = wantsApnsPreset ? null : prepare(draft).policy;
    await coordinator.initialize();
    await coordinator.refresh();
    if ((await coordinator.configuration).encode() != draft.original.encode()) {
      throw const ConnectionHostException('configurationChanged');
    }
    final applyServerDialing = await _usesAppManagedOrdinaryRouting(
      draft.original.connection,
    );
    final apnsPresetApplicable =
        platform == ConnectionPlatform.ios &&
        applyServerDialing &&
        (coordinator.state.value.runtime?.apnsProxyPresetApplied == true ||
            (wantsApnsPreset && await _apnsProxyPresetSupported()));
    final policy =
        basePolicy ??
        prepare(draft, apnsPresetApplicable: apnsPresetApplicable).policy;
    await _validateLanProxy(draft, policy);
    if (policy.usesProxy(platform) &&
        policy.proxyPort == await _reservedApiPort()) {
      throw const FormatException(
        'Proxy port conflicts with the local HTTP API',
      );
    }
    if (policy.usesProxy(platform) &&
        policy.autoSetSystemProxy &&
        !(await proxyCapability()).supported) {
      throw const FormatException(
        'Automatic system proxy settings are unavailable',
      );
    }
    final changed = !sameRuntime(
      draft.original.policy,
      policy,
      platform,
      windowsMode: windowsMode,
      applyServerDialing: applyServerDialing,
      apnsPresetApplicable: apnsPresetApplicable,
    );
    final disconnect =
        platform == ConnectionPlatform.android && emptyAndroidScope(policy);
    var allowed = false;
    if (changed && coordinator.state.value.canDisconnect) {
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

  Future<bool> _usesAppManagedOrdinaryRouting(
    ConnectionSettings settings,
  ) async {
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
    bool apnsPresetApplicable = false,
  }) => const DeepCollectionEquality().equals(
    _effectiveRuntime(
      a,
      platform,
      windowsMode: windowsMode,
      applyServerDialing: applyServerDialing,
      apnsPresetApplicable: apnsPresetApplicable,
    ),
    _effectiveRuntime(
      b,
      platform,
      windowsMode: windowsMode,
      applyServerDialing: applyServerDialing,
      apnsPresetApplicable: apnsPresetApplicable,
    ),
  );

  static Object _effectiveRuntime(
    PlatformPolicy policy,
    ConnectionPlatform platform, {
    WindowsMode? windowsMode,
    bool applyServerDialing = true,
    bool apnsPresetApplicable = false,
  }) {
    final apnsPresetApplied =
        platform == ConnectionPlatform.ios &&
        apnsPresetApplicable &&
        policy.appleApnsProxyPreset;
    if (apnsPresetApplied) policy = policy.withApnsProxyPresetApplied();
    final json = policy.toJson();
    final runtimeDns = policy.runtimeDns(platform);
    final result = <String, dynamic>{
      if (apnsPresetApplied) 'apnsProxyPresetApplied': true,
      'ipv6': policy.ipv6Enabled,
      if (applyServerDialing)
        'dialing': policy.dialing.effective(ipv6: policy.ipv6Enabled).toJson(),
      'dnsIpv4Address': runtimeDns.ipv4Address,
      if (policy.ipv6Enabled ||
          (platform == ConnectionPlatform.windows &&
              (windowsMode ?? windowsBuildMode) == WindowsMode.msix))
        'dnsIpv6Address': runtimeDns.ipv6Address,
      'log': json['log'],
    };
    if (platform == ConnectionPlatform.macos ||
        platform == ConnectionPlatform.windows ||
        platform == ConnectionPlatform.linux) {
      result['captureMode'] = policy.captureMode.name;
      if (policy.usesProxy(platform)) {
        result['proxyPort'] = policy.proxyPort;
        result['autoSetSystemProxy'] = policy.autoSetSystemProxy;
        return result;
      }
    }
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
      final tun = policy.toTun(platform).toJson();
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
