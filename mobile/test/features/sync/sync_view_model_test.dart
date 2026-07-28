/// Tests for [SyncViewModel] — the pure-Dart view-model that the Sync
/// screen renders. No Flutter imports; no async timing tricks.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/mesh/data/ble_discovery.dart' show DiscoveryStatus;
import 'package:mobile/features/mesh/data/mesh_coordinator.dart' show MeshPeer, MeshSyncResult;
import 'package:mobile/features/mesh/data/mesh_session.dart' show MeshSessionResult, MeshSessionState;
import 'package:mobile/features/sync/views/sync_view_model.dart';

MeshPeer _peer(String addr, {String name = 'Phone'}) =>
    MeshPeer(deviceName: '$name-$addr', deviceAddress: addr);

MeshSyncResult _result(
  String addr, {
  bool ok = true,
  int sent = 0,
  int received = 0,
  String? error,
  String name = 'Phone',
}) {
  final state = ok ? MeshSessionState.done : MeshSessionState.failed;
  return MeshSyncResult(
    peer: _peer(addr, name: name),
    outcome: MeshSessionResult(
      finalState: state,
      itemsSent: sent,
      itemsReceived: received,
      error: error,
    ),
  );
}

SyncViewModel _vm({
  List<MeshPeer> peers = const [],
  DiscoveryStatus status = DiscoveryStatus.idle,
  List<MeshSyncResult> history = const [],
}) =>
    SyncViewModel(peers: peers, status: status, history: history);

void main() {
  group('SyncViewModel.snapshot', () {
    test('returns the empty sentinel when there are no peers and no history', () {
      final snap = _vm().snapshot();
      expect(snap.peers, isEmpty);
      expect(snap.totalSessions, 0);
      expect(snap.totalFailedSessions, 0);
      expect(snap.lastSync, isNull);
      expect(snap.discoveryStatus, DiscoveryStatus.idle);
    });

    test('emits one row per discovered peer even with no history', () {
      final snap = _vm(
        peers: [_peer('aa:11'), _peer('bb:22', name: 'Pixel')],
        status: DiscoveryStatus.scanning,
      ).snapshot();
      expect(snap.peers.map((r) => r.deviceName).toList(),
          ['Phone-aa:11', 'Pixel-bb:22']);
      expect(snap.discoveryStatus, DiscoveryStatus.scanning);
    });

    test('rolls up totals and lastSync across history', () {
      final snap = _vm(
        peers: [_peer('a'), _peer('b')],
        status: DiscoveryStatus.advertisingAndScanning,
        history: [
          _result('a', ok: true, sent: 4, received: 7),
          _result('b', ok: true, sent: 2, received: 5),
          _result('a', ok: false, sent: 1, received: 0, error: 'timeout'),
        ],
      ).snapshot();
      expect(snap.totalSessions, 3);
      expect(snap.totalFailedSessions, 1);
      expect(snap.totalItemsSent, 7);
      expect(snap.totalItemsReceived, 12);
      expect(snap.lastSync, isNotNull);
    });

    test('lateralises per-peer counters to the most recent result', () {
      final snap = _vm(
        peers: [_peer('a')],
        history: [
          _result('a', ok: true, sent: 1, received: 1),
          _result('a', ok: true, sent: 5, received: 9),
        ],
      ).snapshot();
      final row = snap.peers.single;
      expect(row.lastSent, 5);
      expect(row.lastReceived, 9);
      expect(row.status, PeerSyncStatus.ok);
    });

    test('marks the most recent failure as failed', () {
      final snap = _vm(
        peers: [_peer('a')],
        history: [
          _result('a', ok: true, sent: 1, received: 1),
          _result('a', ok: false, error: 'Oops'),
        ],
      ).snapshot();
      expect(snap.peers.single.status, PeerSyncStatus.failed);
      expect(snap.totalFailedSessions, 1);
    });

    test('keeps a discovered peer row even if the history only mentions it once',
        () {
      final snap = _vm(
        peers: [_peer('a'), _peer('b')],
        history: [_result('a', ok: true, sent: 2)],
      ).snapshot();
      // Both peers stay in the snapshot — b just has no counters yet.
      expect(snap.peers.length, 2);
      final b = snap.peers.firstWhere((r) => r.deviceAddress == 'b');
      expect(b.lastSent, 0);
      expect(b.lastReceived, 0);
      expect(b.status, PeerSyncStatus.idle);
    });

    test('lastSync stays null when every session failed', () {
      final snap = _vm(
        peers: [_peer('a')],
        history: [_result('a', ok: false, error: 'boom')],
      ).snapshot();
      expect(snap.lastSync, isNull);
    });

    test('peer rows are sorted by name', () {
      final snap = _vm(
        peers: [_peer('z', name: 'Zeta'), _peer('a', name: 'Alpha')],
      ).snapshot();
      expect(snap.peers.map((r) => r.deviceName).toList(), [
        'Alpha-a',
        'Zeta-z',
      ]);
    });
  });

  group('transportLabelFor', () {
    test('maps canonical names', () {
      expect(transportLabelFor('wifi-direct'), 'Wi-Fi Direct');
      expect(transportLabelFor('hotspot'), 'Local hotspot');
      expect(transportLabelFor('ble'), 'BLE');
    });
    test('returns "Unknown" for null/empty', () {
      expect(transportLabelFor(null), 'Unknown');
      expect(transportLabelFor(''), 'Unknown');
    });
    test('passes unknown labels through verbatim', () {
      expect(transportLabelFor('peer-link'), 'peer-link');
    });
  });

  group('formatRelativeTime', () {
    test('returns "never" for null', () {
      expect(formatRelativeTime(null), 'never');
    });
    test('returns "just now" for sub-minute deltas', () {
      expect(formatRelativeTime(DateTime.now().toUtc()), 'just now');
    });
    test('formats minutes, hours, days', () {
      final now = DateTime.now().toUtc();
      expect(formatRelativeTime(now.subtract(const Duration(minutes: 3))), '3m ago');
      expect(formatRelativeTime(now.subtract(const Duration(hours: 2))), '2h ago');
      expect(formatRelativeTime(now.subtract(const Duration(days: 4))), '4d ago');
    });
  });

  group('sessionStateLabel', () {
    test('covers every MeshSessionState value', () {
      expect(sessionStateLabel(MeshSessionState.idle), 'idle');
      expect(sessionStateLabel(MeshSessionState.awaitingPeer), 'awaiting peer');
      expect(sessionStateLabel(MeshSessionState.transferring), 'transferring');
      expect(sessionStateLabel(MeshSessionState.done), 'done');
      expect(sessionStateLabel(MeshSessionState.failed), 'failed');
    });
  });
}
