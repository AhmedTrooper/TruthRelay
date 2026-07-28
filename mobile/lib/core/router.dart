import 'package:go_router/go_router.dart';

import '../features/compose/views/compose_view.dart';
import '../features/detail/views/detail_view.dart';
import '../features/home/views/home_view.dart';
import '../features/settings/views/settings_view.dart';
import '../features/sync/views/sync_view.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeView()),
    GoRoute(path: '/compose', builder: (_, __) => const ComposeView()),
    GoRoute(path: '/sync', builder: (_, __) => const SyncView()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsView()),
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