import 'package:material_ui/material_ui.dart';

/// Navigator notifications arrive before a popup's first widget frame.
class AppModalRouteObserver extends NavigatorObserver with ChangeNotifier {
  Route<dynamic>? _topRoute;

  bool get hasPopupRoute => _topRoute is PopupRoute && _topRoute!.isActive;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _topRoute = topRoute;
    notifyListeners();
  }
}
