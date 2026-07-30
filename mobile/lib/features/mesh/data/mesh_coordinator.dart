/// Peer-driven mesh sync coordinator.
///
/// Watches a peer-discovery stream and launches a mesh sync session for each
/// newly-discovered peer. Per-peer concurrency is capped (default 1), and
/// each successful or failed session triggers a cooldown before the same
/// peer can fire again.
///
/// The coordinator is transport-agnostic: it only knows about peer
/// identities (`MeshPeer`) and how to spin up a [MeshSession] for one. The
/// concrete Wi-Fi Direct / BLE / hotspot bindings inject their own
/// transport factories via [SessionFactory] so the coordinator itself stays
/// pure-Dart and unit-testable.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

import '../../../core/logger.dart';
import '../../sync/data/seen_packets_local.dart';
import 'mesh_local_inventory.dart';
import 'mesh_session.dart';

@immutable
class MeshPeer {
  /// Stable per-device id used as `MeshHeader.peerId`.
  final String deviceAddress;
  final String deviceName;

  const MeshPeer({required this.deviceAddress, required this.deviceName});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeshPeer &&
          other.deviceAddress == deviceAddress &&
          other.deviceName == deviceName;

  @override
  int get hashCode => Object.hash(deviceAddress, deviceName);

  @override
  String toString() => 'MeshPeer($deviceName@$deviceAddress)';
}

/// Records the result of a single sync session for tests + diagnostics.
@immutable
class MeshSyncResult {
  final MeshPeer peer;
  final MeshSessionResult outcome;
  const MeshSyncResult({required this.peer, required this.outcome});
}

/// Inputs the coordinator needs to spin up one session for one peer. Each
/// transport plugin (Wi-Fi Direct, BLE, hotspot) supplies its own factory.
@immutable
class SessionRequest {
  final MeshPeer peer;
  final MeshTransport transport;
  final String localPeerId;
  final MeshLocalInventorySource source;
  final SeenPacketsStore seen;
  final List<String> localIds;

  const SessionRequest({
    required this.peer,
    required this.transport,
    required this.localPeerId,
    required this.source,
    required this.seen,
    required this.localIds,
  });
}

/// Strategy hook — given a [MeshPeer], produce the transport + source +
/// dedup-store triple that the session will use. The default implementation
/// just calls the provided closures; transport plugins can subclass or wrap.
typedef SessionFactory = Future<SessionRequest?> Function(MeshPeer peer);

/// Configuration knobs for the coordinator.
@immutable
class MeshCoordinatorConfig {
  /// Max concurrent sessions in flight.
  final int maxConcurrent;

  /// After a session ends (any outcome), wait this long before the same
  /// peer can fire again.
  final Duration peerBackoff;

  /// Per-session timeout. Forwarded to [MeshSessionConfig.timeout].
  final Duration sessionTimeout;

  const MeshCoordinatorConfig({
    this.maxConcurrent = 1,
    this.peerBackoff = const Duration(minutes: 5),
    this.sessionTimeout = const Duration(seconds: 60),
  });
}

/// State machine for one peer.
enum _PeerSyncState { idle, inFlight, coolingDown }

class _PeerRecord {
  _PeerRecord(this.state);
  _PeerSyncState state;
  DateTime? lastAttempt;
}

/// Coordinates mesh sessions across all known peers. Pure Dart + Riverpod-
/// friendly (just `add()` and `close()` — no plugin imports).
class MeshCoordinator {
  final MeshCoordinatorConfig config;
  final SessionFactory buildSession;

  /// Stream of peer updates. The coordinator subscribes at start, restarts
  /// the subscription on resumption.
  final Stream<MeshPeer> Function() peerStream;

  final Map<String, _PeerRecord> _records = <String, _PeerRecord>{};
  final List<MeshSyncResult> _history = <MeshSyncResult>[];

  StreamSubscription<MeshPeer>? _sub;
  StreamController<MeshSyncResult>? _results;
  bool _stopped = false;

  MeshCoordinator({
    required this.peerStream,
    required this.buildSession,
    this.config = const MeshCoordinatorConfig(),
  });

  /// Live stream of session results. Useful for the Sync screen UI.
  Stream<MeshSyncResult> get results {
    _results ??= StreamController<MeshSyncResult>.broadcast();
    return _results!.stream;
  }

  List<MeshSyncResult> get history => UnmodifiableListView(_history);

  /// Begin watching the peer stream. Idempotent.
  Future<void> start() async {
    if (_stopped || _sub != null) return;
    _results ??= StreamController<MeshSyncResult>.broadcast();
    _sub = peerStream().listen(_onPeer);
  }

  /// Stop watching and cancel any in-flight sessions. Idempotent.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _sub?.cancel();
    _sub = null;
    await _results?.close();
  }

  /// Inject a peer discovered out-of-band (e.g. for tests). The same
  /// dedup, cooldown, and concurrency rules apply as for stream events.
  void offerPeer(MeshPeer peer) => _onPeer(peer);

  void _onPeer(MeshPeer peer) {
    final key = peer.deviceAddress;
    final now = DateTime.now().toUtc();
    final rec = _records.putIfAbsent(key, () => _PeerRecord(_PeerSyncState.idle));

    if (rec.state == _PeerSyncState.inFlight) return;
    if (rec.state == _PeerSyncState.coolingDown) {
      final since = rec.lastAttempt;
      if (since == null || now.difference(since) < config.peerBackoff) return;
      rec.state = _PeerSyncState.idle;
    }
    if (_inFlight >= config.maxConcurrent) return;

    AppLogger.info('📡 Discovered P2P Mesh Peer: ${peer.deviceName} (${peer.deviceAddress})');
    rec.state = _PeerSyncState.inFlight;
    rec.lastAttempt = now;
    unawaited(_runSession(peer, rec));
  }

  int _inFlight = 0;
  int get activeCount => _inFlight;

  Future<void> _runSession(MeshPeer peer, _PeerRecord rec) async {
    _inFlight++;
    AppLogger.info('🤝 Initiating P2P session with ${peer.deviceName}...');
    MeshSessionResult outcome;
    try {
      final req = await buildSession(peer);
      if (req == null) {
        outcome = const MeshSessionResult(
          finalState: MeshSessionState.failed,
          itemsSent: 0,
          itemsReceived: 0,
          error: 'factory returned no session request',
        );
      } else {
        outcome = await _runSessionInner(req);
        AppLogger.info('✅ P2P session complete with ${peer.deviceName}: Sent ${outcome.itemsSent}, Received ${outcome.itemsReceived}');
      }
    } catch (e, st) {
      AppLogger.error('❌ P2P session failed with ${peer.deviceName}', e, st);
      outcome = MeshSessionResult(
        finalState: MeshSessionState.failed,
        itemsSent: 0,
        itemsReceived: 0,
        error: 'coordinator caught: $e',
      );
    } finally {
      _inFlight--;
      rec.state = _PeerSyncState.coolingDown;
      rec.lastAttempt = DateTime.now().toUtc();
    }
    final r = MeshSyncResult(peer: peer, outcome: outcome);
    _history.add(r);
    _results?.add(r);
  }

  Future<MeshSessionResult> _runSessionInner(SessionRequest req) async {
    final session = MeshSession(
      config: MeshSessionConfig(
        localPeerId: req.localPeerId,
        timeout: config.sessionTimeout,
      ),
      // The initiator always advertises what we have; peer asks for missing.
      role: MeshSessionRole.initiator,
      transport: req.transport,
      source: req.source,
      localIds: req.localIds,
      seenPacket: (Uint8List pid) => req.seen.recordIfNew(pid, req.peer.deviceAddress),
    );
    return session.run();
  }

  /// Reset the cooldown for [peerAddress]. Useful after a manual "Sync
  /// now" tap on the Sync screen.
  void forceResync(String peerAddress) {
    final rec = _records[peerAddress];
    if (rec != null) rec.state = _PeerSyncState.idle;
  }

  /// Test seam: number of peers ever seen.
  int get knownPeerCount => _records.length;
}