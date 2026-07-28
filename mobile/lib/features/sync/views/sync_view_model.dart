/// View-model layer for the Sync screen.
///
/// Aggregates mesh peer discovery state, session history, and last-sync
/// timing into a single immutable snapshot that the Sync screen can render
/// without needing to know about the underlying transport, coordinator,
/// or Riverpod plumbing. The view-model is pure-Dart (no Flutter imports)
/// so it can be unit-tested with no widget setup.
library;

import 'dart:collection';

import 'package:flutter/foundation.dart' show immutable;

import '../../mesh/data/ble_discovery.dart' show DiscoveryStatus;
import '../../mesh/data/mesh_coordinator.dart' show MeshPeer, MeshSyncResult;
import '../../mesh/data/mesh_session.dart' show MeshSessionState;

/// One row in the Sync screen's peer table. Built from a [MeshPeer]
/// + the latest [MeshSyncResult] (if any) so the UI never has to
/// re-derive counts from raw session events.
@immutable
class PeerSyncRow {
  /// Stable per-device id used by the coordinator's backoff map.
  final String deviceAddress;

  /// Human-readable name shown in the UI ("Pixel 7", "Galaxy S22", etc.).
  final String deviceName;

  /// Transport that handled the most recent successful session, or
  /// `null` if this peer has never synced. Surfaced as "Wi-Fi Direct",
  /// "BLE", "Local hotspot" or "Unknown".
  final String? transportLabel;

  /// Items we sent to the peer on the most recent successful session.
  final int lastSent;

  /// Items we received from the peer on the most recent successful session.
  final int lastReceived;

  /// Wall-clock timestamp of the most recent session attempt (success
  /// or failure). `null` if this peer has never been attempted.
  final DateTime? lastAttempt;

  /// "active" while a session is in flight, "ok" on most recent success,
  /// "failed" on most recent failure, "idle" otherwise.
  final PeerSyncStatus status;

  const PeerSyncRow({
    required this.deviceAddress,
    required this.deviceName,
    required this.transportLabel,
    required this.lastSent,
    required this.lastReceived,
    required this.lastAttempt,
    required this.status,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerSyncRow &&
          other.deviceAddress == deviceAddress &&
          other.deviceName == deviceName &&
          other.transportLabel == transportLabel &&
          other.lastSent == lastSent &&
          other.lastReceived == lastReceived &&
          other.lastAttempt == lastAttempt &&
          other.status == status;

  @override
  int get hashCode => Object.hash(
        deviceAddress,
        deviceName,
        transportLabel,
        lastSent,
        lastReceived,
        lastAttempt,
        status,
      );
}

enum PeerSyncStatus { idle, active, ok, failed }

/// Snapshot of everything the Sync screen needs to render in one frame.
/// Built by [SyncViewModel.snapshot] from coordinator + discovery state.
@immutable
class SyncViewSnapshot {
  final List<PeerSyncRow> peers;
  final DiscoveryStatus discoveryStatus;
  final int totalItemsSent;
  final int totalItemsReceived;
  final int totalSessions;
  final int totalFailedSessions;
  final DateTime? lastSync;

  const SyncViewSnapshot({
    required this.peers,
    required this.discoveryStatus,
    required this.totalItemsSent,
    required this.totalItemsReceived,
    required this.totalSessions,
    required this.totalFailedSessions,
    required this.lastSync,
  });

  static const SyncViewSnapshot empty = SyncViewSnapshot(
    peers: <PeerSyncRow>[],
    discoveryStatus: DiscoveryStatus.idle,
    totalItemsSent: 0,
    totalItemsReceived: 0,
    totalSessions: 0,
    totalFailedSessions: 0,
    lastSync: null,
  );
}

/// Builds a [SyncViewSnapshot] from already-collected peer + status values
/// and a history list.
///
/// The view-model is intentionally pure — it does not subscribe to any
/// streams. The widget reads the latest values from the discovery layer
/// (which keeps its own internal broadcast subscription) and feeds them
/// in. Tests can construct a [SyncViewModel] directly with literal values
/// and call [snapshot] without any async timing tricks.
class SyncViewModel {
  /// Latest peer snapshot from the discovery layer. The widget refreshes
  /// this every rebuild so the view-model never goes stale.
  final List<MeshPeer> peers;

  /// Latest discovery status. Same lifecycle as [peers].
  final DiscoveryStatus status;

  /// Coordinator session history. Newer entries at the end.
  final List<MeshSyncResult> history;

  SyncViewModel({
    required this.peers,
    required this.status,
    required this.history,
  });

  /// Pure synchronous snapshot. No awaits, no streams.
  SyncViewSnapshot snapshot() => _buildSnapshot(peers, status);

  SyncViewSnapshot _buildSnapshot(
    List<MeshPeer> peers,
    DiscoveryStatus status,
  ) {
    final rows = <PeerSyncRow>[];
    final byAddress = <String, PeerSyncRow>{};

    // Seed with currently-discovered peers so we don't lose rows when
    // a peer disappears between discovery ticks.
    for (final p in peers) {
      byAddress[p.deviceAddress] = PeerSyncRow(
        deviceAddress: p.deviceAddress,
        deviceName: p.deviceName,
        transportLabel: null,
        lastSent: 0,
        lastReceived: 0,
        lastAttempt: null,
        status: PeerSyncStatus.idle,
      );
    }

    var sent = 0;
    var received = 0;
    var sessions = 0;
    var failed = 0;
    DateTime? lastSync;

    // Walk the history in chronological order so later results overwrite
    // earlier ones for the same peer.
    for (final r in history) {
      sessions++;
      if (!r.outcome.isOk) failed++;
      sent += r.outcome.itemsSent;
      received += r.outcome.itemsReceived;
      lastSync = r.outcome.isOk ? DateTime.now().toUtc() : lastSync;

      final status = r.outcome.isOk ? PeerSyncStatus.ok : PeerSyncStatus.failed;
      final existing = byAddress[r.peer.deviceAddress];
      byAddress[r.peer.deviceAddress] = PeerSyncRow(
        deviceAddress: r.peer.deviceAddress,
        deviceName: r.peer.deviceName,
        transportLabel: existing?.transportLabel ?? 'Peer link',
        lastSent: r.outcome.itemsSent,
        lastReceived: r.outcome.itemsReceived,
        lastAttempt: lastSync,
        status: status,
      );
    }

    rows.addAll(byAddress.values);
    rows.sort((a, b) => a.deviceName.compareTo(b.deviceName));

    return SyncViewSnapshot(
      peers: UnmodifiableListView(rows),
      discoveryStatus: status,
      totalItemsSent: sent,
      totalItemsReceived: received,
      totalSessions: sessions,
      totalFailedSessions: failed,
      lastSync: lastSync,
    );
  }
}

/// Transport-name helper. Pure function so the widget and the tests can
/// share the same labels without re-deriving them.
String transportLabelFor(String? transport) {
  if (transport == null || transport.isEmpty) return 'Unknown';
  switch (transport) {
    case 'wifi-direct':
    case 'WifiDirect':
      return 'Wi-Fi Direct';
    case 'ble':
    case 'Ble':
      return 'BLE';
    case 'hotspot':
    case 'Hotspot':
      return 'Local hotspot';
    case 'Peer link':
      return 'Peer link';
    default:
      return transport;
  }
}

/// Pretty-print a duration for the Sync screen ("just now", "3m ago", "2h ago").
String formatRelativeTime(DateTime? when) {
  if (when == null) return 'never';
  final delta = DateTime.now().toUtc().difference(when);
  if (delta.inSeconds < 60) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

/// Map a [MeshSessionState] to a human label. Exposed so future transport
/// rows can re-use it without re-implementing the switch.
String sessionStateLabel(MeshSessionState state) {
  switch (state) {
    case MeshSessionState.idle:
      return 'idle';
    case MeshSessionState.awaitingPeer:
      return 'awaiting peer';
    case MeshSessionState.transferring:
      return 'transferring';
    case MeshSessionState.done:
      return 'done';
    case MeshSessionState.failed:
      return 'failed';
  }
}
