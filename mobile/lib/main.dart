import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/logger.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'data/storage/hive_boxes.dart';
import 'features/bulletins/data/bulletin_repository.dart';
import 'features/requests/data/request_repository.dart';
import 'features/sync/data/api_client.dart';
import 'features/sync/data/background_sync.dart';
import 'features/sync/data/outbox_repository.dart';
import 'features/sync/data/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.info('🚀 Starting TruthRelay Mobile App...');
  await HiveBoxes.init();
  AppLogger.info('📦 Local Hive storage boxes initialized.');

  // Wire the background-isolate hooks so the periodic Workmanager task
  // shares the foreground app's Hive + sync plumbing.
  ensureHiveBoxesOpen = HiveBoxes.init;
  buildSyncService = () => SyncService(
        api: ApiClient(),
        bulletins: BulletinRepository(),
        requests: RequestRepository(),
        outbox: OutboxRepository(),
      );
  runApp(const ProviderScope(child: TruthRelayApp()));

  // Defer background Workmanager registration to post-frame callback
  // so startup frame rendering is smooth and unblocked.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    AppLogger.info('🔄 Registering background sync workers...');
    initBackgroundSync();
  });
}

class TruthRelayApp extends ConsumerStatefulWidget {
  const TruthRelayApp({super.key});

  @override
  ConsumerState<TruthRelayApp> createState() => _TruthRelayAppState();
}

class _TruthRelayAppState extends ConsumerState<TruthRelayApp> {
  @override
  void initState() {
    super.initState();
    // Kick off the foreground connectivity-driven sync coordinator as soon
    // as the app starts. The provider is read once to attach its lifecycle
    // hooks (Riverpod will dispose it when the widget unmounts).
    Future.microtask(() {
      ref.read(connectivitySyncProvider).start();
      // Boot the mesh coordinator so peer offers (from the hotspot
      // controller) start a session automatically.
      ref.read(meshCoordinatorFacadeProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TruthRelay',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10b981),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      routerConfig: appRouter,
    );
  }
}