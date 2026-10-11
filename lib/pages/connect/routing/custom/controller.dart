import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/connect/dialogs.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/pages/connect/routing/custom/rule_controller.dart';
import 'package:onexray/pages/shared/widgets/adaptive_dialog.dart';
import 'package:onexray/pages/shared/widgets/configuration_transfer.dart';
import 'package:onexray/service/connect/routing/custom/editor.dart';
import 'package:onexray/service/connect/routing/custom/configuration.dart';
import 'package:onexray/service/shared/failure.dart';
import 'package:onexray/service/connect/routing/custom/document.dart';
import 'package:onexray/service/connect/routing/custom/state.dart';
import 'package:onexray/service/connect/routing/options.dart';
import 'package:onexray/service/shared/share/configuration_transfer.dart';
import 'package:onexray/service/shared/xray/fragment.dart';

typedef OpenCustomRule = Future<RoutingRuleState?> Function(
  BuildContext context,
  RoutingRuleState? rule,
);

const _unchangedCustomRoutingValue = Object();

class CustomRoutingEditorState {
  final CustomRoutingEditorDraft? original;
  final List<RoutingProfileData> profiles;
  final String name;
  final List<RoutingRuleState> rules;
  final List<Object> ruleKeys;
  final Object? selectedRuleKey;
  final int entryCount;
  final RoutingDnsSettings dns;
  final RoutingSniffingSettings sniffing;
  final RoutingSelectionSettings selection;

  String get directDnsAddress => dns.directAddress;
  final bool fakeDns;
  final Map<String, dynamic>? fragmentOutbound;
  final bool processing;
  final bool transferBusy;
  final bool saving;
  final bool deleting;
  final bool inlineEditing;
  final String? error;

  CustomRoutingEditorState({
    this.original,
    Iterable<RoutingProfileData> profiles = const [],
    this.name = '',
    Iterable<RoutingRuleState> rules = const [],
    Iterable<Object> ruleKeys = const [],
    this.selectedRuleKey,
    this.entryCount = 1,
    String? directDnsAddress,
    RoutingDnsSettings? dns,
    this.sniffing = const RoutingSniffingSettings(),
    this.selection = const RoutingSelectionSettings(),
    this.fakeDns = false,
    this.fragmentOutbound,
    this.processing = true,
    this.transferBusy = false,
    this.saving = false,
    this.deleting = false,
    this.inlineEditing = false,
    this.error,
  }) : dns =
           dns ??
           (directDnsAddress == null
               ? const RoutingDnsSettings()
               : const RoutingDnsSettings().withDirectAddress(
                   directDnsAddress,
                 )),
       profiles = List.unmodifiable(profiles),
       rules = List.unmodifiable(rules),
       ruleKeys = List.unmodifiable(ruleKeys);

  bool get loaded => original != null;
  bool get busy => processing || transferBusy;
  bool get editingBlocked => busy || deleting;
  bool get fragment => fragmentOutbound != null;

  CustomRoutingEditorState copyWith({
    Object? original = _unchangedCustomRoutingValue,
    Iterable<RoutingProfileData>? profiles,
    String? name,
    Iterable<RoutingRuleState>? rules,
    Iterable<Object>? ruleKeys,
    Object? selectedRuleKey = _unchangedCustomRoutingValue,
    int? entryCount,
    String? directDnsAddress,
    RoutingDnsSettings? dns,
    RoutingSniffingSettings? sniffing,
    RoutingSelectionSettings? selection,
    bool? fakeDns,
    Map<String, dynamic>? fragmentOutbound,
    bool clearFragment = false,
    bool? processing,
    bool? transferBusy,
    bool? saving,
    bool? deleting,
    bool? inlineEditing,
    Object? error = _unchangedCustomRoutingValue,
  }) => CustomRoutingEditorState(
    original: identical(original, _unchangedCustomRoutingValue)
        ? this.original
        : original as CustomRoutingEditorDraft?,
    profiles: profiles ?? this.profiles,
    name: name ?? this.name,
    rules: rules ?? this.rules,
    ruleKeys: ruleKeys ?? this.ruleKeys,
    selectedRuleKey: identical(selectedRuleKey, _unchangedCustomRoutingValue)
        ? this.selectedRuleKey
        : selectedRuleKey,
    entryCount: entryCount ?? this.entryCount,
    dns:
        dns ??
        (directDnsAddress == null
            ? this.dns
            : this.dns.withDirectAddress(directDnsAddress)),
    sniffing: sniffing ?? this.sniffing,
    selection: selection ?? this.selection,
    fakeDns: fakeDns ?? this.fakeDns,
    fragmentOutbound: clearFragment
        ? null
        : fragmentOutbound ?? this.fragmentOutbound,
    processing: processing ?? this.processing,
    transferBusy: transferBusy ?? this.transferBusy,
    saving: saving ?? this.saving,
    deleting: deleting ?? this.deleting,
    inlineEditing: inlineEditing ?? this.inlineEditing,
    error: identical(error, _unchangedCustomRoutingValue)
        ? this.error
        : error as String?,
  );
}

class CustomRoutingEditorController
    extends PageCubit<CustomRoutingEditorState> {
  final int? profileId;
  final CustomRoutingEditorService service;
  final name = TextEditingController();
  CustomRoutingRuleController? inlineRule;
  Object? _inlineRuleKey;
  StreamSubscription<CustomRoutingRuleState>? _inlineRuleSubscription;
  late final ConfigurationTransferController transfer;
  late final StreamSubscription<ConfigurationTransferState>
  _transferSubscription;
  bool _syncingName = false;

  CustomRoutingEditorController({
    this.profileId,
    CustomRoutingEditorService? service,
  }) : service = service ?? CustomRoutingEditorService(),
       super(CustomRoutingEditorState()) {
    name.addListener(_nameChanged);
    transfer = ConfigurationTransferController(
      kind: ConfigurationKind.custom,
      readText: () => previewState?.encode() ?? '',
      readName: () => state.name,
      hasContent: () => state.rules.isNotEmpty,
      onImport: (draft) => replaceTemplate(draft.text, name: draft.name),
    );
    _transferSubscription = transfer.stream.listen(_transferChanged);
  }

  int get routeCount => state.profiles.length + (profileId == null ? 1 : 0);

  void _nameChanged() {
    if (_syncingName || state.editingBlocked) return;
    emit(state.copyWith(name: name.text));
  }

  void _setName(String value) {
    _syncingName = true;
    name.text = value;
    _syncingName = false;
  }

  void _transferChanged(ConfigurationTransferState transferState) {
    emit(state.copyWith(transferBusy: transferState.busy));
  }

  Future<void> load(BuildContext context) async {
    emit(state.copyWith(processing: true, error: null));
    try {
      final draft = await service.load(profileId);
      final rows = await service.rows;
      // Keep connection-read failures before exposing an editable draft.
      await service.coordinator.configuration;
      if (!isPageActive) return;
      final value = draft.state as RoutingProfileState;
      var valueName = value.name;
      if (profileId == null && valueName.isEmpty && context.mounted) {
        final used = rows
            .map(
              (row) => int.tryParse(
                RegExp(r'(\d+)$').firstMatch(row.name)?.group(1) ?? '',
              ),
            )
            .toSet();
        var number = 1;
        while (used.contains(number)) {
          number++;
        }
        valueName =
            '${AppLocalizations.of(context)!.prototypeCustomRouting} $number';
      }
      final keys = List<Object>.generate(value.rules.length, (_) => Object());
      final selected = keys.isEmpty ? null : keys[keys.length > 1 ? 1 : 0];
      _setName(valueName);
      emit(
        CustomRoutingEditorState(
          original: draft,
          profiles: rows,
          name: valueName,
          rules: value.rules,
          ruleKeys: keys,
          selectedRuleKey: selected,
          entryCount: value.entryCount,
          dns: value.dns,
          sniffing: value.sniffing,
          selection: value.selection,
          fakeDns: value.fakeDns,
          fragmentOutbound: value.fragmentOutbound,
          processing: false,
          transferBusy: transfer.state.busy,
          inlineEditing: state.inlineEditing,
        ),
      );
      _syncInlineRule();
    } catch (_) {
      if (context.mounted) {
        emit(
          state.copyWith(
            error: AppLocalizations.of(context)!.prototypeCannotReadCustomRoute,
          ),
        );
      }
    } finally {
      emit(state.copyWith(processing: false));
    }
  }

  String? nameError(AppLocalizations l10n) {
    final value = state.name.trim();
    if (value.isEmpty || value.runes.length > 32) {
      return l10n.prototypeRouteNameRequired;
    }
    if (state.profiles.any(
      (row) =>
          row.id != profileId &&
          row.name.trim().toLowerCase() == value.toLowerCase(),
    )) {
      return l10n.prototypeRouteNameUnique;
    }
    return null;
  }

  RoutingProfileState get profileState => RoutingProfileState(
    id: profileId,
    name: state.name.trim(),
    entryCount: state.entryCount,
    dns: state.dns,
    sniffing: state.sniffing,
    selection: state.selection,
    fakeDns: state.fakeDns,
    fragmentOutbound: state.fragmentOutbound,
    rules: state.rules,
  );

  RoutingProfileState? get previewState {
    try {
      final value = profileState;
      value.validate();
      return value;
    } on FormatException {
      return null;
    }
  }

  void _replaceProfileState(RoutingProfileState value, {String? name}) {
    final keys = List<Object>.generate(value.rules.length, (_) => Object());
    final selected = keys.isEmpty ? null : keys[keys.length > 1 ? 1 : 0];
    final nextName = name ?? state.name;
    _setName(nextName);
    emit(
      state.copyWith(
        name: nextName,
        entryCount: value.entryCount,
        dns: value.dns,
        sniffing: value.sniffing,
        selection: value.selection,
        fakeDns: value.fakeDns,
        fragmentOutbound: value.fragmentOutbound,
        clearFragment: !value.fragment,
        rules: value.rules,
        ruleKeys: keys,
        selectedRuleKey: selected,
        error: null,
      ),
    );
    _syncInlineRule();
  }

  void setInlineEditing(bool value) {
    if (state.inlineEditing == value) return;
    _flushInlineRule();
    emit(state.copyWith(inlineEditing: value));
    _syncInlineRule();
  }

  void _flushInlineRule() {
    final source = inlineRule;
    final key = _inlineRuleKey;
    final index = key == null ? -1 : state.ruleKeys.indexOf(key);
    if (source == null || index < 0) return;
    final rules = state.rules.toList();
    rules[index] = source.draftRule;
    emit(state.copyWith(rules: rules));
  }

  void _syncInlineRule({bool refresh = false}) {
    final key = state.inlineEditing ? state.selectedRuleKey : null;
    if (_inlineRuleKey == key && !refresh) return;
    final previous = inlineRule;
    final previousSubscription = _inlineRuleSubscription;
    _inlineRuleSubscription = null;
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }
    _inlineRuleKey = key;
    final index = key == null ? -1 : state.ruleKeys.indexOf(key);
    final next = index < 0
        ? null
        : CustomRoutingRuleController(rule: state.rules[index]);
    inlineRule = next;
    if (next != null) {
      _inlineRuleSubscription = next.stream.listen(
        (_) => _inlineRuleChanged(next),
      );
    }
    // Inputs from the previous rule unmount on the next frame.
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(previous.close()),
      );
    }
  }

  void _inlineRuleChanged(CustomRoutingRuleController source) {
    if (!identical(inlineRule, source)) return;
    final key = _inlineRuleKey;
    final index = key == null ? -1 : state.ruleKeys.indexOf(key);
    if (!isPageActive || state.editingBlocked || index < 0) return;
    final rules = state.rules.toList();
    rules[index] = source.draftRule;
    emit(state.copyWith(rules: rules));
  }

  /// Import tools stage their dependencies separately before calling this.
  /// Persistence remains a deliberate Save action, never activation.
  void replaceTemplate(String text, {String? name}) {
    final document = RoutingProfileDocument.parse(text);
    if (document.assets.isNotEmpty) {
      throw const CustomRoutingEditorException('assets');
    }
    final nextName =
        name ??
        (document.state.name.isEmpty ? state.name : document.state.name);
    _replaceProfileState(document.state, name: nextName);
  }

  void setEntryCount(int value) {
    if (state.editingBlocked) return;
    emit(state.copyWith(entryCount: value));
  }

  void setDirectDnsAddress(String value) {
    if (state.editingBlocked) return;
    emit(state.copyWith(directDnsAddress: value, error: null));
  }

  void setFakeDns(bool value) {
    if (state.editingBlocked) return;
    if (value && !state.sniffing.enabled) return;
    emit(state.copyWith(fakeDns: value, error: null));
  }

  void setDns(RoutingDnsSettings value) {
    if (state.editingBlocked) return;
    emit(state.copyWith(dns: value, error: null));
  }

  void setSniffing(RoutingSniffingSettings value) {
    if (state.editingBlocked) return;
    if (state.fakeDns && !value.enabled) return;
    emit(state.copyWith(sniffing: value, error: null));
  }

  void setSelection(RoutingSelectionSettings value) {
    if (state.editingBlocked) return;
    emit(state.copyWith(selection: value, error: null));
  }

  void setFragment(bool value) {
    if (state.editingBlocked) return;
    if (value == state.fragment) return;
    emit(
      state.copyWith(
        fragmentOutbound: value ? XrayFragment.defaultOutbound() : null,
        clearFragment: !value,
        error: null,
      ),
    );
  }

  Future<void> editRule(
    BuildContext context,
    OpenCustomRule open, [
    int? index,
  ]) async {
    if (!state.loaded || state.editingBlocked) return;
    _flushInlineRule();
    if (state.inlineEditing) {
      final rules = state.rules.toList();
      final keys = state.ruleKeys.toList();
      Object selected;
      if (index == null) {
        rules.add(
          RoutingRuleState(
            ruleTag: AppLocalizations.of(context)!.prototypeNewRule,
          ),
        );
        keys.add(Object());
        selected = keys.last;
      } else {
        selected = keys[index];
      }
      emit(
        state.copyWith(rules: rules, ruleKeys: keys, selectedRuleKey: selected),
      );
      _syncInlineRule();
      return;
    }
    final rule = index == null ? null : state.rules[index];
    if (index != null) {
      emit(state.copyWith(selectedRuleKey: state.ruleKeys[index]));
    }
    final edited = await open(context, rule);
    if (!isPageActive || edited == null) return;
    final rules = state.rules.toList();
    final keys = state.ruleKeys.toList();
    Object selected;
    if (index == null) {
      rules.add(edited);
      keys.add(Object());
      selected = keys.last;
    } else {
      rules[index] = edited;
      selected = keys[index];
    }
    emit(
      state.copyWith(rules: rules, ruleKeys: keys, selectedRuleKey: selected),
    );
    _syncInlineRule(refresh: true);
  }

  void deleteRule(int index) {
    if (!state.loaded || state.editingBlocked) return;
    _flushInlineRule();
    final rules = state.rules.toList();
    final keys = state.ruleKeys.toList();
    final wasSelected = state.selectedRuleKey == keys[index];
    rules.removeAt(index);
    keys.removeAt(index);
    var selected = state.selectedRuleKey;
    if (wasSelected) {
      selected = keys.isEmpty ? null : keys[index.clamp(0, keys.length - 1)];
    }
    emit(
      state.copyWith(rules: rules, ruleKeys: keys, selectedRuleKey: selected),
    );
    _syncInlineRule();
  }

  void reorder(int from, int to) {
    if (!state.loaded || state.editingBlocked) return;
    _flushInlineRule();
    final rules = state.rules.toList();
    final keys = state.ruleKeys.toList();
    rules.insert(to, rules.removeAt(from));
    keys.insert(to, keys.removeAt(from));
    emit(state.copyWith(rules: rules, ruleKeys: keys));
  }

  String ruleName(int index, AppLocalizations l10n) =>
      state.rules[index].ruleTag.isEmpty
      ? l10n.prototypeNewRule
      : state.rules[index].ruleTag;

  String ruleSummary(int index, AppLocalizations l10n) {
    final rule = state.rules[index];
    final domains = rule.domain;
    final ips = rule.ip;
    final port = rule.port;
    final network = rule.network;
    return [
      if (domains.isNotEmpty)
        domains.first.startsWith('geosite:')
            ? '${l10n.prototypeWebsiteSet} · ${domains.first.substring(8)}'
            : domains.join(', '),
      if (ips.isNotEmpty)
        ips.first.startsWith('geoip:')
            ? '${l10n.prototypeIpSet} · ${ips.first.substring(6)}'
            : 'IP · ${ips.join(', ')}',
      if (port != null) '${l10n.prototypeTargetPort} · $port',
      if (network != null)
        '${l10n.prototypeNetworkType} · ${network is List ? network.join(', ') : network}',
      if (rule.protocol.isNotEmpty)
        '${l10n.routingRuleProtocol} · ${rule.protocol.join(', ')}',
      if (rule.localOS.isNotEmpty)
        '${l10n.routingRuleLocalOS} · ${rule.localOS.join(', ')}',
    ].join(' · ');
  }

  String ruleAction(int index, AppLocalizations l10n) =>
      switch (state.rules[index].action) {
        RoutingRuleAction.direct => l10n.prototypeDirect,
        RoutingRuleAction.block => l10n.prototypeBlock,
        RoutingRuleAction.proxy => l10n.prototypeUseVpn,
      };

  void cancel(BuildContext context) {
    Navigator.of(context).pop();
  }

  Future<void> save(BuildContext context) async {
    if (state.busy || state.original == null) return;
    _flushInlineRule();
    final l10n = AppLocalizations.of(context)!;
    if (nameError(l10n) != null) return;
    emit(state.copyWith(processing: true, saving: true, error: null));
    try {
      final id = await service.save(
        CustomRoutingEditorDraft(
          original: state.original!.original,
          state: profileState,
        ),
        confirmReconnect: () => context.mounted
            ? showApplyAndReconnectDialog(context, label: state.name.trim())
            : Future.value(false),
        imported: transfer.imported,
      );
      if (id != null &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        ContextAlert.showToast(
          context,
          l10n.prototypeNameSaved(state.name.trim()),
        );
        Navigator.of(context).pop(id);
      }
    } catch (failure) {
      emit(state.copyWith(error: _failureMessage(l10n, failure)));
    } finally {
      if (!isPageActive) await transfer.close();
      emit(state.copyWith(processing: false, saving: false));
    }
  }

  Future<void> delete(BuildContext context) async {
    final row = state.original?.original;
    if (state.busy || row == null) return;
    final l10n = AppLocalizations.of(context)!;
    emit(state.copyWith(processing: true, deleting: true, error: null));
    try {
      final deleted = await service.delete(
        row,
        confirm: (selected, reconnect) async =>
            context.mounted &&
            await showAppDialog<bool>(
                  context,
                  (dialogContext) => AppDialog(
                    title: l10n.prototypeDeleteName(row.name),
                    subtitle: reconnect
                        ? l10n.prototypeDeletingRouteReconnectNotice
                        : selected
                        ? l10n.prototypeDeletedRouteSmartNotice
                        : l10n.prototypeRemoveRouteNotice,
                    body: ConnectCallout(
                      icon: LucideIcons.circleAlert,
                      text: l10n.prototypeCannotUndo,
                      warning: true,
                    ),
                    actions: [
                      ConnectDialogButton(
                        label: l10n.prototypeCancel,
                        secondary: true,
                        onPressed: () => Navigator.pop(dialogContext, false),
                      ),
                      ConnectDialogButton(
                        label: reconnect
                            ? l10n.prototypeSwitchAndReconnect
                            : selected
                            ? l10n.prototypeDeleteAndUseSmartRouting
                            : l10n.prototypeDeleteRoute,
                        destructive: true,
                        icon: LucideIcons.trash2,
                        onPressed: () => Navigator.pop(dialogContext, true),
                      ),
                    ],
                  ),
                ) ==
                true,
      );
      if (deleted &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(row.id);
      }
    } catch (failure) {
      emit(
        state.copyWith(
          error: appFailureMessage(
            l10n,
            failure,
            operation: l10n.actionResult(
              l10n.prototypeDelete,
              l10n.resultFailed,
            ),
          ),
        ),
      );
    } finally {
      emit(state.copyWith(processing: false, deleting: false));
    }
  }

  String _failureMessage(AppLocalizations l10n, Object failure) =>
      switch (failure) {
        CustomRoutingEditorException(reason: 'name') =>
          l10n.prototypeRouteNameRequired,
        CustomRoutingEditorException(reason: 'duplicate') =>
          l10n.prototypeRouteNameUnique,
        CustomRoutingEditorException(reason: 'limit') =>
          l10n.prototypeCustomRouteLimit,
        _ => appFailureMessage(l10n, failure, operation: l10n.buttonSaveFailed),
      };

  @override
  Future<void> disposePageResources() async {
    await _transferSubscription.cancel();
    await _inlineRuleSubscription?.cancel();
    await inlineRule?.close();
    if (!state.saving) await transfer.close();
    name.dispose();
  }
}
