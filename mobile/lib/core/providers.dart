import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/bulletins/data/bulletin_repository.dart';
import '../features/mesh/data/mesh_coordinator.dart' as coord;
import '../features/mesh/data/wifi_direct_discovery.dart';
import '../features/requests/data/request_repository.dart';
import '../features/settings/data/moderator_settings_repository.dart';
import '../features/sync/data/api_client.dart';
import '../features/sync/data/connectivity_sync.dart';
import '../features/sync/data/outbox_repository.dart';
import '../features/sync/data/sync_service.dart';

final bulletinRepoProvider = Provider<BulletinRepository>((_) => BulletinRepository());
final requestRepoProvider = Provider<RequestRepository>((_) => RequestRepository());
final outboxRepoProvider = Provider<OutboxRepository>((_) => OutboxRepository());
final moderatorSettingsRepoProvider = Provider<ModeratorSettingsRepository>((_) => ModeratorSettingsRepository());

final apiClientProvider = Provider<ApiClient>((_) => ApiClient());

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(
      api: ref.watch(apiClientProvider),
      bulletins: ref.watch(bulletinRepoProvider),
      requests: ref.watch(requestRepoProvider),
      outbox: ref.watch(outboxRepoProvider),
    ));

/// Owns the lifecycle of the connectivity-driven sync coordinator.
/// Started once at app boot (see `main.dart`); tears down on dispose.
final connectivitySyncProvider = Provider<ConnectivitySyncCoordinator>((ref) {
  final coordinator = ConnectivitySyncCoordinator(
    connectivity: Connectivity().onConnectivityChanged,
    sync: ref.watch(syncServiceProvider),
  );
  ref.onDispose(coordinator.stop);
  return coordinator;
});

final pendingOutboxCountProvider = FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(outboxRepoProvider).countPending();
});

/// Mesh peer discovery. Started once at app boot.
final wifiDirectDiscoveryProvider = Provider<WifiDirectDiscovery>((ref) {
  final d = WifiDirectDiscovery();
  ref.onDispose(d.dispose);
  return d;
});

/// Mesh sync coordinator. Listens to discovery peer events and runs a
/// session for each one, with per-peer backoff + concurrency cap.
final meshCoordinatorProvider = Provider<coord.MeshCoordinator>((ref) {
  final discovery = ref.watch(wifiDirectDiscoveryProvider);
  // No-op factory for the default provider — actual transports are
  // wired by main.dart at app boot via `MeshCoordinator.bind(...)`. This
  // keeps the type non-nullable for downstream consumers.
  final controller = StreamController<coord.MeshPeer>();
  final sub = discovery.peers.listen((peers) {
    for (final peer in peers) {
      controller.add(coord.MeshPeer(
        deviceAddress: peer.deviceAddress,
        deviceName: peer.deviceName,
      ));
    }
  });
  final coordinator = coord.MeshCoordinator(
    peerStream: () => controller.stream,
    buildSession: (peer) async => null,
  );
  ref.onDispose(() async {
    await sub.cancel();
    await coordinator.stop();
    await controller.close();
  });
  return coordinator;
});
