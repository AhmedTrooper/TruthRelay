import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../features/bulletins/data/bulletin_repository.dart';
import '../features/mesh/data/ble_discovery.dart' as ble;
import '../features/mesh/data/local_hotspot_backend.dart';
import '../features/mesh/data/local_hotspot_transport.dart' as ht;
import '../features/mesh/data/mesh_coordinator.dart' as coord;
import '../features/mesh/data/mesh_local_inventory.dart';
import '../features/sync/data/seen_packets_local.dart';
import '../features/requests/data/request_repository.dart';
import '../features/settings/data/moderator_settings_repository.dart';
import '../features/sync/data/api_client.dart';
import '../features/sync/data/connectivity_sync.dart';
import '../features/sync/data/moderator_public_key_repository.dart';
import '../features/sync/data/outbox_repository.dart';
import '../features/sync/data/sync_service.dart';

final moderatorPublicKeyRepoProvider =
    Provider<ModeratorPublicKeyRepository>((_) => ModeratorPublicKeyRepository());

final bulletinRepoProvider = Provider<BulletinRepository>((ref) {
  return BulletinRepository(moderatorKeys: ref.watch(moderatorPublicKeyRepoProvider));
});
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

final bleDiscoveryProvider = Provider<ble.BleDiscovery>((ref) {
  final d = ble.BleDiscovery();
  ref.onDispose(d.dispose);
  return d;
});

final hotspotBackendProvider = Provider<LocalHotspotBackend>((ref) {
  final b = LocalHotspotBackend();
  ref.onDispose(b.dispose);
  return b;
});

enum HotspotRole { idle, host, joiner }

@immutable
class HotspotSessionState {
  final HotspotRole role;
  final String? ssid;
  final String? passphrase;
  final String? gatewayIp;
  final String? lastError;
  final int peersConnected;
  const HotspotSessionState({
    required this.role,
    this.ssid,
    this.passphrase,
    this.gatewayIp,
    this.lastError,
    this.peersConnected = 0,
  });
  static const idle = HotspotSessionState(role: HotspotRole.idle);
  HotspotSessionState copyWith({
    HotspotRole? role,
    String? ssid,
    String? passphrase,
    String? gatewayIp,
    String? lastError,
    int? peersConnected,
  }) =>
      HotspotSessionState(
        role: role ?? this.role,
        ssid: ssid ?? this.ssid,
        passphrase: passphrase ?? this.passphrase,
        gatewayIp: gatewayIp ?? this.gatewayIp,
        lastError: lastError ?? this.lastError,
        peersConnected: peersConnected ?? this.peersConnected,
      );
}

/// Stable per-device id advertised in MeshHeader.peerId. Independent of
/// hotspot role so the coordinator can resolve it without a cycle.
final localPeerIdProvider = Provider<String>((_) {
  return const Uuid().v4().substring(0, 8);
});

/// Registry that pairs an inbound peer id (from the host accept loop)
/// with the HotspotChannel the session will stream over. Populated by the
/// HotspotSessionController; consumed by buildSession.
class HotspotChannelRegistry {
  final Map<String, ht.HotspotChannel> _channels = {};
  void put(String id, ht.HotspotChannel c) => _channels[id] = c;
  ht.HotspotChannel? take(String id) => _channels.remove(id);
  ht.HotspotChannel? peek(String id) => _channels[id];
  int get length => _channels.length;
}

final hotspotChannelRegistryProvider =
    Provider<HotspotChannelRegistry>((_) => HotspotChannelRegistry());

/// Mesh coordinator. Listens on a private peer stream; the
/// HotspotSessionController pushes discovered peers into it.
class _CoordinatorHolder {
  final coord.MeshCoordinator coordinator;
  final StreamController<coord.MeshPeer> peerFeed;
  _CoordinatorHolder(this.coordinator, this.peerFeed);
}

final meshCoordinatorProvider = Provider<_CoordinatorHolder>((ref) {
  final bulletins = ref.watch(bulletinRepoProvider);
  final requests = ref.watch(requestRepoProvider);
  final registry = ref.watch(hotspotChannelRegistryProvider);
  final seen = InMemorySeenPackets();
  final peerFeed = StreamController<coord.MeshPeer>.broadcast();

  coord.SessionFactory buildSession = (peer) async {
    final ch = registry.take(peer.deviceAddress) ?? registry.peek('hotspot');
    if (ch == null) return null;
    final source = RepositoryInventorySource(
      bulletins: bulletins,
      requests: requests,
    );
    final localIds = await source.currentIds();
    final transport = ht.LocalHotspotHostTransport(
      peer: ht.HotspotPeer(peerId: peer.deviceAddress, channel: ch),
    );
    return coord.SessionRequest(
      peer: peer,
      transport: transport,
      localPeerId: ref.read(localPeerIdProvider),
      source: source,
      seen: seen,
      localIds: localIds,
    );
  };

  final coordinator = coord.MeshCoordinator(
    peerStream: () => peerFeed.stream,
    buildSession: buildSession,
  );

  ref.onDispose(() async {
    await coordinator.stop();
    await peerFeed.close();
  });
  return _CoordinatorHolder(coordinator, peerFeed);
});

class HotspotSessionController extends StateNotifier<HotspotSessionState> {
  final LocalHotspotBackend _backend;
  final _CoordinatorHolder _coordinator;
  final HotspotChannelRegistry _registry;
  StreamSubscription? _peersSub;

  HotspotSessionController(
    this._backend,
    this._coordinator,
    this._registry,
  ) : super(HotspotSessionState.idle);

  Future<void> startHost() async {
    try {
      final creds = await _backend.startHost(port: 8765);
      state = HotspotSessionState(
        role: HotspotRole.host,
        ssid: creds.ssid,
        passphrase: creds.passphrase,
        gatewayIp: '192.168.43.1',
      );
      _peersSub?.cancel();
      _peersSub = _backend.hostPeers.listen((hp) {
        _registry.put(hp.peerId, hp.channel);
        state = state.copyWith(peersConnected: _registry.length);
        _coordinator.peerFeed.add(coord.MeshPeer(
          deviceAddress: hp.peerId,
          deviceName: 'hotspot-guest',
        ));
      });
    } catch (e) {
      state = HotspotSessionState(role: HotspotRole.idle, lastError: e.toString());
    }
  }

  Future<void> stopHost() async {
    await _peersSub?.cancel();
    _peersSub = null;
    await _backend.stopHost();
    state = HotspotSessionState.idle;
  }

  Future<void> join(String ssid, String passphrase) async {
    try {
      final channel = await _backend.joinHotspot(
        ssid: ssid,
        passphrase: passphrase,
      );
      state = HotspotSessionState(
        role: HotspotRole.joiner,
        ssid: ssid,
        peersConnected: 1,
      );
      _registry.put('hotspot', channel);
      _coordinator.peerFeed.add(coord.MeshPeer(
        deviceAddress: 'hotspot',
        deviceName: 'hotspot-host',
      ));
    } catch (e) {
      state = HotspotSessionState(role: HotspotRole.idle, lastError: e.toString());
    }
  }

  Future<void> leave() async {
    await _backend.leaveHotspot();
    state = HotspotSessionState.idle;
  }
}

final hotspotSessionProvider =
    StateNotifierProvider<HotspotSessionController, HotspotSessionState>(
        (ref) {
  final backend = ref.watch(hotspotBackendProvider);
  final holder = ref.watch(meshCoordinatorProvider);
  final registry = ref.watch(hotspotChannelRegistryProvider);
  return HotspotSessionController(backend, holder, registry);
});

/// Public coordinator facade. Most consumers should read this instead of
/// the holder.
final meshCoordinatorFacadeProvider = Provider<coord.MeshCoordinator>(
    (ref) => ref.watch(meshCoordinatorProvider).coordinator);