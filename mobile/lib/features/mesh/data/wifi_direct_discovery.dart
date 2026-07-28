/// Wi-Fi Direct peer discovery for the offline mesh.
///
/// Wraps `flutter_p2p_connection` (v3 client API) to expose:
///   * a permission gate (location + Wi-Fi + Bluetooth)
///   * start/stop BLE peer discovery lifecycle
///   * a [Stream] of currently-discovered peers via Riverpod
///
/// Discovery in this package is BLE-based: hosts advertise their Wi-Fi Direct
/// hotspot credentials over a BLE service; clients scan for those
/// advertisements. We don't open sockets or sync any data here — that happens
/// in commit 7 (the Wi-Fi Direct transport).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/mesh_discovery_backend.dart';

/// Snapshot of one Wi-Fi Direct peer visible to the device.
///
/// On the client side this corresponds to a [BleDiscoveredDevice] — a host
/// that is currently broadcasting its hotspot credentials. [isGroupOwner] is
/// always `true` for now because only hosts advertise (clients discover them).
@immutable
class MeshPeer {
  final String deviceName;
  final String deviceAddress;
  final bool isGroupOwner;

  const MeshPeer({
    required this.deviceName,
    required this.deviceAddress,
    required this.isGroupOwner,
  });

  factory MeshPeer.fromBleDevice(BleDiscoveredDevice d) => MeshPeer(
        deviceName: d.deviceName,
        deviceAddress: d.deviceAddress,
        // Hosts advertise, clients discover — so any discovered peer is a
        // group owner from the client's perspective.
        isGroupOwner: true,
      );

  @override
  String toString() =>
      'MeshPeer(name=$deviceName, addr=$deviceAddress, go=$isGroupOwner)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeshPeer &&
          other.deviceName == deviceName &&
          other.deviceAddress == deviceAddress &&
          other.isGroupOwner == isGroupOwner;

  @override
  int get hashCode => Object.hash(deviceName, deviceAddress, isGroupOwner);
}

/// Status of the discovery lifecycle.
///
/// BLE-only peers add `advertising` / `advertisingAndScanning` (a phone can
/// either accept advertisements, broadcast its own, or both). They still
/// coexist with the Wi-Fi Direct scanner's `idle` / `scanning` / `error` /
/// `denied` states — the BLE layer just emits the larger variant.
enum DiscoveryStatus {
  idle,
  scanning,
  advertising,
  advertisingAndScanning,
  error,
  denied,
}

class WifiDirectDiscovery {
  final MeshDiscoveryBackend _backend;

  StreamSubscription<List<BleDiscoveredDevice>>? _sub;
  final _peers = StreamController<List<MeshPeer>>.broadcast();
  final _status = StreamController<DiscoveryStatus>.broadcast();
  DiscoveryStatus _last = DiscoveryStatus.idle;

  /// Pass [backend] to inject a deterministic test double. In production
  /// we use [P2pClientBackend] over the real `flutter_p2p_connection` plugin.
  WifiDirectDiscovery({MeshDiscoveryBackend? backend})
      : _backend = backend ?? P2pClientBackend();

  /// Currently visible peers. Updated by [start].
  Stream<List<MeshPeer>> get peers => _peers.stream;

  /// Lifecycle events for UI (e.g. "Scanning…", "Permission denied").
  Stream<DiscoveryStatus> get status => _status.stream;

  DiscoveryStatus get currentStatus => _last;

  /// One-time permission + Wi-Fi checks. Returns true iff everything is
  /// ready for [start].
  Future<bool> ensurePermissions() async {
    try {
      final granted = await _backend.askP2pPermissions();
      final locEnabled = await _backend.checkLocationEnabled();
      final wifiEnabled = await _backend.checkWifiEnabled();
      final ok = granted && locEnabled && wifiEnabled;
      if (!ok) {
        _emitStatus(DiscoveryStatus.denied);
      }
      return ok;
    } catch (e) {
      debugPrint('WifiDirectDiscovery.ensurePermissions: $e');
      _emitStatus(DiscoveryStatus.error);
      return false;
    }
  }

  /// Begin discovery. Idempotent — calling twice is a no-op.
  Future<void> start() async {
    if (_sub != null) return;
    if (!await ensurePermissions()) return;

    _emitStatus(DiscoveryStatus.scanning);
    try {
      await _backend.initialize();
      _sub = await _backend.startScan(
        (list) => _peers.add(list.map(MeshPeer.fromBleDevice).toList()),
        onError: (e) {
          debugPrint('WifiDirectDiscovery scan error: $e');
          _emitStatus(DiscoveryStatus.error);
        },
      );
    } catch (e) {
      debugPrint('WifiDirectDiscovery.start: $e');
      _emitStatus(DiscoveryStatus.error);
    }
  }

  /// Stop discovery and tear down the peer stream. Safe to call multiple
  /// times.
  Future<void> stop() async {
    try {
      await _backend.stopScan();
    } catch (_) {
      // best-effort
    }
    await _sub?.cancel();
    _sub = null;
    _emitStatus(DiscoveryStatus.idle);
  }

  void _emitStatus(DiscoveryStatus s) {
    _last = s;
    _status.add(s);
  }

  Future<void> dispose() async {
    await stop();
    await _peers.close();
    await _status.close();
    await _backend.dispose();
  }
}

/// Riverpod entry points. `wifiDirectDiscoveryProvider` owns one
/// `WifiDirectDiscovery` instance per app session; `meshPeersStreamProvider`
/// is the broadcast stream the rest of the mesh subscribes to.
final wifiDirectDiscoveryProvider = Provider<WifiDirectDiscovery>((ref) {
  final d = WifiDirectDiscovery();
  ref.onDispose(d.dispose);
  return d;
});

final meshPeersStreamProvider = StreamProvider<List<MeshPeer>>((ref) {
  final d = ref.watch(wifiDirectDiscoveryProvider);
  // Start the discovery on first subscription; consumer UI does not need to
  // call .start() explicitly.
  unawaited(d.start());
  ref.onDispose(d.stop);
  return d.peers;
});

final meshDiscoveryStatusProvider = StreamProvider<DiscoveryStatus>((ref) {
  final d = ref.watch(wifiDirectDiscoveryProvider);
  return d.status;
});