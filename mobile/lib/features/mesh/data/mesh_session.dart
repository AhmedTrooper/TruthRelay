/// Transport-independent mesh sync state machine.
///
/// Half-duplex gossip protocol. One side is the **initiator** (sends the
/// first `MeshHello`); the other is the **responder**. The flow is:
///
/// 1. Initiator → `MeshHello` (carries our inventory bloom + count + newest).
/// 2. Responder receives `MeshHello`, computes "give me what they have that
///    I don't", sends `MeshRequest`.
/// 3. Initiator receives `MeshRequest`, sends one `MeshData` per requested id.
/// 4. Initiator → `MeshAck` for each `MeshData` it successfully applied.
/// 5. Both sides terminate when the initiator has sent every requested
///    `MeshData` + ack and the responder has received the corresponding acks.
///
/// Termination signal: if the initiator has nothing to ask for, it sends
/// `MeshRequest` with empty `wantIds` as a "bye" terminator so the responder
/// can tear down cleanly.
///
/// The session is intentionally transport-agnostic: the same state machine
/// drives Wi-Fi Direct, BLE, and hotspot transports.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

import '../models/mesh_packet.dart';
import '../../sync/data/bloom_filter.dart';
import 'mesh_local_inventory.dart';

/// Transport-agnostic sink/source. Concrete implementations live in
/// `wifi_direct_transport.dart`, `ble_transport.dart`, etc.
abstract class MeshTransport {
  /// Sends exactly one JSON-encoded packet to the peer.
  Future<void> send(String packetJson);

  /// Stream of JSON-encoded packets received from the peer. Completes when
  /// the underlying transport closes.
  Stream<String> get incoming;

  /// Closes the transport cleanly.
  Future<void> close();
}

@immutable
class MeshSessionConfig {
  /// Stable per-device peer id, advertised in [MeshHeader.peerId].
  final String localPeerId;

  /// Cap on items per outgoing `MeshData` envelope.
  final int maxItemsPerChunk;

  /// Hard upper bound on the whole session.
  final Duration timeout;

  const MeshSessionConfig({
    required this.localPeerId,
    this.maxItemsPerChunk = 16,
    this.timeout = const Duration(seconds: 60),
  });
}

enum MeshSessionRole { initiator, responder }

enum MeshSessionState {
  idle,
  /// Initiator: hello sent, waiting for the peer's request. Responder: hello
  /// received, request sent, waiting for the peer's data.
  awaitingPeer,

  /// Initiator: request received, sending data. Responder: data being
  /// received, acking.
  transferring,

  done,
  failed,
}

@immutable
class MeshSessionResult {
  final MeshSessionState finalState;
  final int itemsSent;
  final int itemsReceived;
  final String? error;

  const MeshSessionResult({
    required this.finalState,
    required this.itemsSent,
    required this.itemsReceived,
    this.error,
  });

  bool get isOk => finalState == MeshSessionState.done && error == null;
}

/// Live session. One instance per peer connection.
class MeshSession {
  final MeshSessionConfig config;
  final MeshSessionRole role;
  final MeshTransport transport;
  final MeshLocalInventorySource source;
  final Future<bool> Function(Uint8List packetId) seenPacket;

  /// Pre-computed list of "ids the local side is willing to publish". For
  /// the initiator this drives the bloom in the hello; for the responder
  /// this is used to look up payloads for the requested ids.
  final List<String> localIds;

  MeshSessionState _state = MeshSessionState.idle;
  int _sent = 0;
  int _received = 0;
  int _expectedAcks = 0;
  int _gotAcks = 0;

  MeshSession({
    required this.config,
    required this.role,
    required this.transport,
    required this.source,
    required this.localIds,
    required this.seenPacket,
  });

  MeshSessionState get state => _state;

  /// Runs the session to completion. Returns a [MeshSessionResult]. Never
  /// throws — protocol errors become [MeshSessionState.failed] with a
  /// human-readable message.
  Future<MeshSessionResult> run() async {
    final completer = Completer<MeshSessionResult>();
    late StreamSubscription<String> sub;
    Timer? timer;

    sub = transport.incoming.listen(
      (raw) => _onIncoming(raw, completer),
      onError: (Object e, StackTrace st) =>
          _fail('transport error: $e', completer),
      onDone: () {
        if (_state != MeshSessionState.done) {
          _fail('transport closed early in $_state', completer);
        } else {
          _complete(completer);
        }
      },
      cancelOnError: true,
    );

    if (config.timeout > Duration.zero) {
      timer = Timer(config.timeout, () {
        _fail('timeout after ${config.timeout}', completer);
      });
    }

    try {
      if (role == MeshSessionRole.initiator) {
        await _sendHello();
      }
      _state = MeshSessionState.awaitingPeer;
    } catch (e) {
      _fail('start failed: $e', completer);
    }

    final result = await completer.future;
    timer?.cancel();
    await sub.cancel();
    await transport.close();
    return result;
  }

  Future<void> _sendHello() async {
    final snap = await source.snapshot();
    final ids = localIds.length > 1024
        ? localIds.sublist(0, 1024)
        : List<String>.from(localIds);
    final hello = MeshHello(
      header: MeshHeader(
        version: meshProtocolVersion,
        packetId: await newPacketId(),
        peerId: config.localPeerId,
      ),
      bloom: snap.bloom.toBytes(),
      itemCount: snap.itemCount,
      newestReceivedAt: snap.newestReceivedAt,
      ids: ids,
    );
    await transport.send(hello.encode());
  }

  Future<void> _onIncoming(
    String raw,
    Completer<MeshSessionResult> completer,
  ) async {
    try {
      final packet = decodeMeshPacket(raw);
      final deduped = await seenPacket(packet.header.packetId);
      if (!deduped) return;

      if (packet is MeshHello) {
        await _onHello(packet, completer);
      } else if (packet is MeshInventory) {
        await _onInventory(packet, completer);
      } else if (packet is MeshRequest) {
        await _onRequest(packet, completer);
      } else if (packet is MeshData) {
        await _onData(packet, completer);
      } else if (packet is MeshAck) {
        await _onAck(packet, completer);
      } else {
        _fail('unknown packet', completer);
      }
    } catch (e) {
      _fail('decode/handle failed: $e', completer);
    }
  }

  /// Responder: receive the initiator's hello (which carries the initiator's
  /// bloom + count + ids + newest). Compute "give me what they have that I
  /// don't" and send a single `MeshRequest`. Bloom is a sanity check — the
  /// id list is authoritative.
  Future<void> _onHello(
    MeshHello hello,
    Completer<MeshSessionResult> completer,
  ) async {
    if (role != MeshSessionRole.responder) {
      _fail('unexpected hello as initiator', completer);
      return;
    }
    final have = localIds.toSet();
    final peerBloom = BloomFilter.fromBytes(hello.bloom);
    final want = <String>[];
    for (final id in hello.ids) {
      // Sanity: drop anything the bloom says we don't have to ask for,
      // and anything we already hold.
      if (have.contains(id)) continue;
      if (!peerBloom.mightContainString(id)) continue;
      want.add(id);
      if (want.length >= 1024) break;
    }
    _expectedAcks = want.length;
    final req = MeshRequest(
      header: MeshHeader(
        version: meshProtocolVersion,
        packetId: await newPacketId(),
        peerId: config.localPeerId,
      ),
      wantIds: [for (final id in want) Uint8List.fromList(id.codeUnits)],
    );
    await transport.send(req.encode());
    _state = MeshSessionState.transferring;
  }

  /// Legacy message we no longer expect to receive, since the wire protocol
  /// was reshaped to use `MeshHello` directly. Kept so we fail with a clear
  /// error if a future change reintroduces it.
  Future<void> _onInventory(
    MeshInventory inv,
    Completer<MeshSessionResult> completer,
  ) async {
    _fail('inventory packets are no longer part of the wire protocol', completer);
  }

  /// Initiator: receive the responder's request, send each requested id as
  /// a `MeshData` envelope. Empty `wantIds` = peer has nothing to ask for,
  /// so we're done immediately.
  Future<void> _onRequest(
    MeshRequest req,
    Completer<MeshSessionResult> completer,
  ) async {
    if (role != MeshSessionRole.initiator) {
      _fail('unexpected request as responder', completer);
      return;
    }
    if (req.wantIds.isEmpty) {
      _state = MeshSessionState.done;
      _complete(completer);
      return;
    }
    final want = [for (final id in req.wantIds) String.fromCharCodes(id)];
    _expectedAcks = want.length;
    for (var i = 0; i < want.length; i += config.maxItemsPerChunk) {
      final end = (i + config.maxItemsPerChunk) < want.length
          ? i + config.maxItemsPerChunk
          : want.length;
      final chunk = want.sublist(i, end);
      for (final id in chunk) {
        await _sendDataFor(id, completer);
      }
    }
    // Wait for responder's acks via _onAck before tearing down.
  }

  Future<void> _sendDataFor(String id, Completer<MeshSessionResult> completer) async {
    final payload = await source.payloadFor(id);
    if (payload == null) {
      // Peer asked for something we don't have — skip silently.
      return;
    }
    final kind = _kindOf(id);
    final data = MeshData(
      header: MeshHeader(
        version: meshProtocolVersion,
        packetId: await newPacketId(),
        peerId: config.localPeerId,
      ),
      itemKind: kind,
      jsonPayload: String.fromCharCodes(payload),
    );
    await transport.send(data.encode());
    _sent++;
  }

  /// Responder: receive a `MeshData` envelope, persist the item, send a
  /// `MeshAck`. When all expected data packets have been acked, terminate.
  Future<void> _onData(
    MeshData data,
    Completer<MeshSessionResult> completer,
  ) async {
    if (role != MeshSessionRole.responder) {
      _fail('unexpected data as initiator', completer);
      return;
    }
    final id = _deriveId(data.itemKind, data.jsonPayload);
    final payload = Uint8List.fromList(data.jsonPayload.codeUnits);
    final item = MeshItem(
      kind: data.itemKind,
      id: id,
      payload: payload,
      receivedAt: DateTime.now().toUtc(),
    );
    final isNew = await source.applyInbound(item);
    if (isNew) _received++;
    final ack = MeshAck(
      header: MeshHeader(
        version: meshProtocolVersion,
        packetId: await newPacketId(),
        peerId: config.localPeerId,
      ),
      ackPacketId: data.header.packetId,
    );
    await transport.send(ack.encode());
    _gotAcks++;
    if (_gotAcks >= _expectedAcks) {
      _state = MeshSessionState.done;
      _complete(completer);
    }
  }

  /// Initiator: receive the responder's `MeshAck` for one of our `MeshData`
  /// packets. When every send has been acked, terminate.
  Future<void> _onAck(
    MeshAck ack,
    Completer<MeshSessionResult> completer,
  ) async {
    if (role != MeshSessionRole.initiator) {
      return; // responder ignores acks — they're metadata for the initiator.
    }
    _gotAcks++;
    if (_gotAcks >= _expectedAcks) {
      _state = MeshSessionState.done;
      _complete(completer);
    }
  }

  /// Heuristic for `itemKind` when the id alone doesn't disambiguate. UUIDs
  /// (help-requests) contain '-'; 64-char sha256 hex (bulletins) don't.
  String _kindOf(String id) {
    return id.contains('-') ? 'request' : 'bulletin';
  }

  /// Best-effort id re-derivation from the JSON payload. The peer requested
  /// by id; here we re-parse the JSON so the inventory store has a stable key.
  String _deriveId(String kind, String json) {
    final m = _extractJson(json);
    if (kind == 'bulletin') {
      return m['sha256'] as String? ?? m['id'] as String? ?? '';
    }
    return m['id'] as String? ?? '';
  }

  static final RegExp _kvRegex =
      RegExp(r'"(sha256|id)"\s*:\s*"([^"]+)"');
  Map<String, dynamic> _extractJson(String json) {
    final match = _kvRegex.firstMatch(json);
    if (match == null) return const <String, dynamic>{};
    return <String, dynamic>{match.group(1)!: match.group(2)!};
  }

  void _fail(String message, Completer<MeshSessionResult> completer) {
    if (completer.isCompleted) return;
    _state = MeshSessionState.failed;
    completer.complete(MeshSessionResult(
      finalState: _state,
      itemsSent: _sent,
      itemsReceived: _received,
      error: message,
    ));
  }

  void _complete(Completer<MeshSessionResult> completer) {
    if (completer.isCompleted) return;
    completer.complete(MeshSessionResult(
      finalState: _state,
      itemsSent: _sent,
      itemsReceived: _received,
    ));
  }
}