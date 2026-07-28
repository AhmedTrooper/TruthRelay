/// Unit tests for the peer-driven mesh coordinator.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/mesh/data/mesh_coordinator.dart';
import 'package:mobile/features/mesh/data/mesh_local_inventory.dart';
import 'package:mobile/features/mesh/data/mesh_session.dart';
import 'package:mobile/features/sync/data/seen_packets_local.dart';

/// In-memory transport pair so the coordinator can spin up real sessions.
class _BufferedTransport implements MeshTransport {
  final StreamController<String> _ctrl = StreamController<String>.broadcast();
  final List<String> _pending = <String>[];
  bool _hasListener = false;
  bool _closed = false;
  final void Function(String)? _forward;
  final Future<void> Function()? _closePeer;

  _BufferedTransport._(this._forward, this._closePeer);

  static (MeshTransport, MeshTransport) pair() {
    late _BufferedTransport a;
    late _BufferedTransport b;
    a = _BufferedTransport._(
      (s) => b._deliver(s),
      () async {
        if (!a._closed) {
          a._closed = true;
          await a._ctrl.close();
        }
      },
    );
    b = _BufferedTransport._(
      (s) => a._deliver(s),
      () async {
        if (!b._closed) {
          b._closed = true;
          await b._ctrl.close();
        }
      },
    );
    return (a, b);
  }

  void _deliver(String s) {
    if (_closed) return;
    _pending.add(s);
    _drain();
  }

  void _drain() {
    if (!_hasListener) return;
    while (_pending.isNotEmpty) {
      final next = _pending.removeAt(0);
      if (!_closed) _ctrl.add(next);
    }
  }

  @override
  Future<void> send(String packetJson) async {
    if (_closed) return;
    _forward?.call(packetJson);
  }

  @override
  Stream<String> get incoming {
    if (!_hasListener) {
      _hasListener = true;
      _drain();
    }
    return _ctrl.stream;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await _closePeer?.call();
  }
}

MeshItem _item(String id, {String kind = 'request', DateTime? at}) => MeshItem(
      kind: kind,
      id: id,
      payload: Uint8List.fromList(utf8.encode('{"id":"$id"}')),
      receivedAt: at ?? DateTime.utc(2025, 1, 1),
    );

MeshCoordinator _buildCoordinator({
  required StreamController<MeshPeer> peerCtl,
  required Map<String, InMemoryInventorySource> sourcesByPeer,
  required InMemorySeenPackets seen,
  required String localPeerId,
  int maxConcurrent = 1,
  Duration peerBackoff = const Duration(minutes: 5),
  Duration sessionTimeout = const Duration(seconds: 5),
}) {
  return MeshCoordinator(
    config: MeshCoordinatorConfig(
      maxConcurrent: maxConcurrent,
      peerBackoff: peerBackoff,
      sessionTimeout: sessionTimeout,
    ),
    peerStream: () => peerCtl.stream,
    buildSession: (MeshPeer peer) async {
      final src = sourcesByPeer.putIfAbsent(
        peer.deviceAddress,
        () => InMemoryInventorySource(),
      );
      final pair = _BufferedTransport.pair();
      // Provide a peer-side responder so the initiator's session can
      // actually exchange data.
      final responder = MeshSession(
        config: MeshSessionConfig(
          localPeerId: peer.deviceAddress,
          timeout: sessionTimeout,
        ),
        role: MeshSessionRole.responder,
        transport: pair.$2,
        source: InMemoryInventorySource(),
        localIds: const [],
        seenPacket: (Uint8List _) async => true,
      );
      unawaited(responder.run());
      final ids = await src.currentIds();
      return SessionRequest(
        peer: peer,
        transport: pair.$1,
        localPeerId: localPeerId,
        source: src,
        seen: seen,
        localIds: ids,
      );
    },
  );
}

void main() {
  test('offers a peer → drives a session → records result', () async {
    final peerCtl = StreamController<MeshPeer>.broadcast();
    final sources = <String, InMemoryInventorySource>{};
    final seen = InMemorySeenPackets();
    final coordinator = _buildCoordinator(
      peerCtl: peerCtl,
      sourcesByPeer: sources,
      seen: seen,
      localPeerId: 'me',
    );

    final src = InMemoryInventorySource();
    src.seed([_item('item-1')]);
    sources['addr-1'] = src;

    await coordinator.start();
    final results = <MeshSyncResult>[];
    final sub = coordinator.results.listen(results.add);

    coordinator.offerPeer(const MeshPeer(deviceAddress: 'addr-1', deviceName: 'p1'));

    // Wait until the coordinator has flushed the result.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();
    await coordinator.stop();
    await peerCtl.close();

    expect(results, hasLength(1));
    expect(results.first.peer.deviceAddress, 'addr-1');
    expect(results.first.outcome.isOk, isTrue);
  });

  test('second offer for the same peer within backoff is ignored', () async {
    final peerCtl = StreamController<MeshPeer>.broadcast();
    final sources = <String, InMemoryInventorySource>{};
    final seen = InMemorySeenPackets();
    final coordinator = _buildCoordinator(
      peerCtl: peerCtl,
      sourcesByPeer: sources,
      seen: seen,
      localPeerId: 'me',
      // Tiny backoff so the test doesn't take forever; we still expect the
      // second offer inside the cooldown to be dropped.
      peerBackoff: const Duration(seconds: 30),
    );
    await coordinator.start();
    coordinator.offerPeer(const MeshPeer(deviceAddress: 'a', deviceName: 'a'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(coordinator.history.length, 1);
    coordinator.offerPeer(const MeshPeer(deviceAddress: 'a', deviceName: 'a'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(coordinator.history.length, 1,
        reason: 'second offer inside cooldown should be dropped');
    await coordinator.stop();
    await peerCtl.close();
  });

  test('maxConcurrent caps in-flight peer sessions', () async {
    final peerCtl = StreamController<MeshPeer>.broadcast();
    final sources = <String, InMemoryInventorySource>{};
    final seen = InMemorySeenPackets();
    final coordinator = _buildCoordinator(
      peerCtl: peerCtl,
      sourcesByPeer: sources,
      seen: seen,
      localPeerId: 'me',
      maxConcurrent: 2,
    );
    await coordinator.start();
    coordinator.offerPeer(const MeshPeer(deviceAddress: 'a', deviceName: 'a'));
    coordinator.offerPeer(const MeshPeer(deviceAddress: 'b', deviceName: 'b'));
    coordinator.offerPeer(const MeshPeer(deviceAddress: 'c', deviceName: 'c'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(coordinator.history.length, lessThanOrEqualTo(2));
    await coordinator.stop();
    await peerCtl.close();
  });

  test('forceResync clears cooldown so the same peer can fire again',
      () async {
    final peerCtl = StreamController<MeshPeer>.broadcast();
    final sources = <String, InMemoryInventorySource>{};
    final seen = InMemorySeenPackets();
    final coordinator = _buildCoordinator(
      peerCtl: peerCtl,
      sourcesByPeer: sources,
      seen: seen,
      localPeerId: 'me',
      peerBackoff: const Duration(seconds: 30),
    );
    await coordinator.start();
    coordinator.offerPeer(const MeshPeer(deviceAddress: 'a', deviceName: 'a'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(coordinator.history.length, 1);
    coordinator.forceResync('a');
    coordinator.offerPeer(const MeshPeer(deviceAddress: 'a', deviceName: 'a'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(coordinator.history.length, 2);
    await coordinator.stop();
    await peerCtl.close();
  });

  test('stop() is idempotent', () async {
    final peerCtl = StreamController<MeshPeer>.broadcast();
    final sources = <String, InMemoryInventorySource>{};
    final seen = InMemorySeenPackets();
    final coordinator = _buildCoordinator(
      peerCtl: peerCtl,
      sourcesByPeer: sources,
      seen: seen,
      localPeerId: 'me',
    );
    await coordinator.start();
    await coordinator.stop();
    await coordinator.stop(); // should not throw
  });
}