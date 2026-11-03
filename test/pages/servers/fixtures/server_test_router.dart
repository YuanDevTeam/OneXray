import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/servers/controller.dart';
import 'package:onexray/pages/servers/details.dart';
import 'package:onexray/pages/servers/page.dart';
import 'package:onexray/pages/servers/view.dart';

/// Uses the production branch paths and typed extras without startup services.
GoRouter serverTestRouter({
  required WidgetBuilder home,
  List<GoRoute> extraRoutes = const [],
}) => GoRouter(
  initialLocation: '/servers',
  routes: [
    GoRoute(
      path: '/servers',
      builder: (context, _) => home(context),
      routes: [
        GoRoute(
          path: 'server-resource',
          builder: (_, state) =>
              ServerResourcePage(params: state.extra! as ServerResourceParams),
        ),
        GoRoute(
          path: 'source-details',
          builder: (_, state) =>
              ServerSourcePage(params: state.extra! as ServerSourceParams),
        ),
        GoRoute(
          path: 'server-group',
          builder: (_, state) =>
              ServerGroupPage(params: state.extra! as ServerGroupParams),
        ),
        GoRoute(
          path: 'server-manual-groups',
          builder: (_, state) => ServerManualGroupsPage(
            controller: state.extra! as ServersController,
          ),
        ),
        ...extraRoutes,
      ],
    ),
  ],
);
