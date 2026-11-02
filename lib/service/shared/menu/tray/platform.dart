import 'dart:async';

import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/core/tools/platform.dart';
import 'package:onexray/service/shared/menu/tray/entry.dart';
import 'package:tray_manager/tray_manager.dart' as native;
import 'package:nativeapi/nativeapi.dart' as nativeapi;

abstract interface class TrayPlatform {
  void init({
    required void Function() onClick,
    required void Function(bool) onMenuVisibility,
  });
  Future<void> setIcon(String path);
  void setMenu(
    List<TrayMenuEntry> entries,
    void Function(TrayMenuEntry) onSelect,
  );
  Future<void> openMenu();
  void dispose();
}

final class NativeTrayPlatform implements TrayPlatform {
  native.TrayIcon? _tray;
  native.ListenerId? _listener;
  native.Image? _image;
  _NativeTrayMenu? _menu;
  Completer<void>? _popup;
  void Function(bool)? _onMenuVisibility;

  @override
  void init({
    required void Function() onClick,
    required void Function(bool) onMenuVisibility,
  }) {
    final tray = native.TrayIcon.create();
    if (tray == null) throw StateError('Unable to create the tray icon');
    _tray = tray;
    _onMenuVisibility = onMenuVisibility;
    // Linux tray icons are StatusNotifierItems: the panel draws the menu from
    // the exported dbusmenu, and nativeapi's openContextMenu() always returns
    // false there. With the trigger `none` the item exports /NO_DBUSMENU, so no
    // menu ever appears. Let the panel open the menu on any click instead.
    final hostShowsMenu = AppPlatform.isLinux;
    tray.setContextMenuTrigger(
      hostShowsMenu
          ? native.ContextMenuTrigger.clicked
          : native.ContextMenuTrigger.none,
    );
    tray.iconSize = nativeapi.Size(width: 18, height: 18);
    tray.setTooltip('OneXray');
    if (AppPlatform.isMacOS) tray.setTitle('');
    _listener = tray.addListener((event) {
      if (event is! native.TrayIconClickedEvent &&
          event is! native.TrayIconRightClickedEvent) {
        return;
      }
      if (hostShowsMenu) {
        // Some hosts still call Activate/ContextMenu next to the exported menu.
        ygLogger('Tray ${event.runtimeType} ignored: the panel shows the menu');
        return;
      }
      onClick();
    });
  }

  @override
  Future<void> setIcon(String path) async {
    final image = native.ImageAsset.fromAsset(path);
    if (image == null) throw StateError('Unable to load tray icon: $path');
    final previous = _image;
    _tray!.icon = image;
    _image = image;
    previous?.dispose();
    _tray!.setVisible(true);
  }

  @override
  void setMenu(
    List<TrayMenuEntry> entries,
    void Function(TrayMenuEntry) onSelect,
  ) {
    final next = _NativeTrayMenu(entries, onSelect, (visible) {
      _onMenuVisibility?.call(visible);
      if (!visible) {
        final popup = _popup;
        _popup = null;
        popup?.complete();
      }
    });
    try {
      _tray!.setContextMenu(next.menu);
    } catch (_) {
      next.dispose();
      rethrow;
    }
    final previous = _menu;
    _menu = next;
    previous?.dispose();
  }

  @override
  Future<void> openMenu() {
    if (_popup case final pending?) return pending.future;
    final popup = Completer<void>();
    _popup = popup;
    try {
      if (!_tray!.openContextMenu()) {
        throw StateError('Unable to open the tray menu');
      }
    } catch (error, stackTrace) {
      if (identical(_popup, popup)) _popup = null;
      if (!popup.isCompleted) popup.completeError(error, stackTrace);
    }
    return popup.future;
  }

  @override
  void dispose() {
    final tray = _tray;
    if (tray == null) return;
    _onMenuVisibility = null;
    final popup = _popup;
    _popup = null;
    popup?.complete();
    if (_listener case final listener?) tray.removeListener(listener);
    tray.setContextMenu(null);
    tray.setVisible(false);
    tray.dispose();
    _tray = null;
    _listener = null;
    _menu?.dispose();
    _menu = null;
    _image?.dispose();
    _image = null;
  }
}

final class _NativeTrayMenu {
  final _menus = <native.Menu>[];
  final _items = <(native.MenuItem, native.ListenerId)>[];
  late final native.Menu menu;
  native.ListenerId? _listener;

  _NativeTrayMenu(
    List<TrayMenuEntry> entries,
    void Function(TrayMenuEntry) onSelect,
    void Function(bool) onVisibility,
  ) {
    try {
      menu = _build(entries, onSelect);
      _listener = menu.addListener((event) {
        if (event is native.MenuOpenedEvent) onVisibility(true);
        if (event is native.MenuClosedEvent) onVisibility(false);
      });
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  native.Menu _build(
    List<TrayMenuEntry> entries,
    void Function(TrayMenuEntry) onSelect,
  ) {
    final menu = native.Menu.create();
    if (menu == null) throw StateError('Unable to create the tray menu');
    _menus.add(menu);
    for (final entry in entries) {
      if (entry.isSeparator) {
        menu.addSeparator();
        continue;
      }
      final type = entry.children != null
          ? native.MenuItemType.submenu
          : entry.checked != null
          ? native.MenuItemType.checkbox
          : native.MenuItemType.normal;
      final item = native.MenuItem.createWithLabelAndType(entry.label, type);
      if (item == null) {
        throw StateError('Unable to create tray item: ${entry.label}');
      }
      final listener = item.addListener((event) {
        if (event is native.MenuItemClickedEvent && !entry.disabled) {
          onSelect(entry);
        }
      });
      _items.add((item, listener));
      item.isEnabled = !entry.disabled;
      if (entry.checked != null) {
        item.state = entry.checked!
            ? native.MenuItemState.checked
            : native.MenuItemState.unchecked;
      }
      if (entry.children case final children?) {
        item.submenu = _build(children, onSelect);
      }
      menu.addItem(item);
    }
    return menu;
  }

  void dispose() {
    if (_listener case final listener?) menu.removeListener(listener);
    _listener = null;
    for (final (item, listener) in _items) {
      item.removeListener(listener);
      item.dispose();
    }
    _items.clear();
    for (final menu in _menus.reversed) {
      menu.dispose();
    }
    _menus.clear();
  }
}
