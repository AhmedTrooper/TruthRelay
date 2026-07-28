import 'package:go_router/go_router.dart';

import '../features/compose/views/compose_view.dart';
import '../features/detail/views/detail_view.dart';
import '../features/home/views/home_view.dart';
import '../features/settings/views/settings_view.dart';
import '../features/sync/views/sync_view.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeView()),
    GoRoute(path: '/compose', builder: (_, _) => const ComposeView()),
    GoRoute(path: '/sync', builder: (_, _) => const SyncView()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsView()),
    GoRoute(
      path: '/detail/bulletin/:id',
      builder: (_, state) => DetailView(kind: DetailKind.bulletin, id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/detail/request/:id',
      builder: (_, state) => DetailView(kind: DetailKind.request, id: state.pathParameters['id']!),
    ),
  ],
);