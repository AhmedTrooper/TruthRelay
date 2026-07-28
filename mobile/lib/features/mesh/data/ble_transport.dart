/// BLE small-payload transport for the offline mesh.
///
/// BLE 4.x caps ATT writes at 20 bytes per packet and BLE 5 raises it to
/// 244 bytes. Either way, mesh JSON envelopes dwarf the MTU, so we carry
/// each `MeshPacket` as a stream of framed chunks:
///
///     +---------+---------+---------------------------+
///     | len (2) | seq (2) | payload (≤ MTU − 4 bytes) |
///     +---------+---------+---------------------------+
///
/// * `len` is the total expected payload length (big-endian, unsigned 16).
/// * `seq` is the 0-based chunk index (big-endian, unsigned 16).
/// * `payload` is a slice of UTF-8 bytes of the JSON envelope.
///
/// `len == 0` and `seq == 0xFFFF` denote a keep-alive ping — never produced
/// by the chunker, so receivers can ignore it for forward-compat.
///
/// Reassembly guards:
///   * Per-message timeout ([BleMeshTransportConfig.reassemblyTimeout])
///     drops partial frames so a flaky peer can't pin a buffer forever.
///   * `len` > 256 KiB is rejected to match [meshMaxPayloadBytes] for the
///     underlying [MeshTransport] payload limit.
///
/// The transport is split into `BleMeshTransport` (implements
/// [MeshTransport], handles framing + reassembly) and `BleByteChannel`
/// (an abstract byte-pipe so production binds to `flutter_blue_plus` GATT
/// while tests use an in-memory pair).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

import 'mesh_session.dart';

/// Raw byte channel beneath the framing layer. Production uses a `flutter_blue_plus`
/// GATT pair; tests substitute a pair of `StreamController<Uint8List>` channels.
abstract class BleByteChannel {
  /// Push a single framed chunk to the remote peer. The transport blocks
  /// until the underlying write completes (or throws).
  Future<void> sendChunk(Uint8List bytes);

  /// Stream of incoming framed chunks. The channel implementation owns
  /// pairing and lifecycle; this stream is hot until [close] is called.
  Stream<Uint8List> get incomingChunks;

  /// Tear down the underlying GATT connection.
  Future<void> close();
}

@immutable
class BleMeshTransportConfig {
  /// Maximum bytes per frame. Defaults to 180 so it fits both BLE 4.x
  /// (MTU 23, overhead 7 → payload 20 — too tight) and BLE 5 L2CAP with a
  /// conservative headroom. The transport accounts for the 4-byte header.
  final int chunkSize;

  /// Cap on how long a partial message may sit reassembling before we
  /// discard it. Defaults to 8 seconds.
  final Duration reassemblyTimeout;

  /// Soft cap on the total message size we'll accept. Anything larger is
  /// rejected with [BleTransportException]. Defaults to `meshMaxPayloadBytes`.
  final int maxMessageBytes;

  const BleMeshTransportConfig({
    this.chunkSize = 180,
    this.reassemblyTimeout = const Duration(seconds: 8),
    this.maxMessageBytes = 256 * 1024,
  });
}

class BleTransportException implements Exception {
  final String message;
  const BleTransportException(this.message);
  @override
  String toString() => 'BleTransportException: $message';
}

/// State for a single reassembly in flight.
class _PendingMessage {
  final int totalLen;
  final DateTime startedAt;
  final int chunkSize;
  final List<Uint8List?> chunks;
  int receivedChunks = 0;

  _PendingMessage({
    required this.totalLen,
    required this.startedAt,
    required this.chunkSize,
  }) : chunks = List<Uint8List?>.filled(
          BleChunker.frameCount(totalLen, chunkSize),
          null,
          growable: false,
        );

  bool get isComplete {
    for (final c in chunks) {
      if (c == null) return false;
    }
    return true;
  }

  Uint8List assemble() {
    final out = Uint8List(totalLen);
    var offset = 0;
    for (final c in chunks) {
      if (c == null) {
        throw const BleTransportException('null chunk during assemble');
      }
      out.setRange(offset, offset + c.length, c);
      offset += c.length;
    }
    return out;
  }
}

/// Helper that emits framed chunks given a UTF-8 encoded byte payload.
class BleChunker {
  static const int headerSize = 4; // 2 (len) + 2 (seq)

  /// Payload size per frame, excluding the 4-byte header.
  static int effectivePayload(int chunkSize) {
    final p = chunkSize - headerSize;
    return p > 0 ? p : 1;
  }

  /// Total number of frames required for a payload of [payloadLen] bytes.
  /// Returns at least 1 (an empty payload still emits a single `len=0` frame).
  static int frameCount(int payloadLen, int chunkSize) {
    if (payloadLen == 0) return 1;
    final per = effectivePayload(chunkSize);
    return (payloadLen + per - 1) ~/ per;
  }

  /// Encode [payload] into a sequence of framed chunks. Each frame is exactly
  /// [chunkSize] bytes long except the last, which may be shorter.
  static List<Uint8List> encode(Uint8List payload, int chunkSize) {
    if (payload.length > 0xFFFF) {
      throw BleTransportException(
          'payload ${payload.length} exceeds 16-bit length field');
    }
    final frames = <Uint8List>[];
    final per = effectivePayload(chunkSize);
    final total = payload.length;
    var written = 0;
    var seq = 0;
    while (written < total) {
      final take = (total - written) < per ? (total - written) : per;
      final frame = Uint8List(headerSize + take);
      // big-endian length
      frame[0] = (total >> 8) & 0xff;
      frame[1] = total & 0xff;
      // big-endian sequence
      frame[2] = (seq >> 8) & 0xff;
      frame[3] = seq & 0xff;
      frame.setRange(headerSize, headerSize + take, payload, written);
      frames.add(frame);
      written += take;
      seq += 1;
    }
    if (frames.isEmpty) {
      // Empty payload — single zero-len frame so the receiver can drop it.
      final frame = Uint8List(headerSize);
      frame[0] = 0;
      frame[1] = 0;
      frame[2] = 0;
      frame[3] = 0;
      frames.add(frame);
    }
    return frames;
  }

  /// Parse [frame] and return either `(totalLength, seq, payload)` for a
  /// regular chunk or `null` if the frame is reserved (e.g. keep-alive).
  static ({int total, int seq, Uint8List payload})? parse(Uint8List frame) {
    if (frame.length < headerSize) return null;
    final total = (frame[0] << 8) | frame[1];
    final seq = (frame[2] << 8) | frame[3];
    if (total == 0 && seq == 0xFFFF) return null; // keep-alive
    return (
      total: total,
      seq: seq,
      payload: Uint8List.sublistView(frame, headerSize),
    );
  }
}

/// Implements [MeshTransport] over a [BleByteChannel] with chunking +
/// reassembly + timeout. Idempotent close. Thread-safe w.r.t. the stream
/// lifecycle — single consumer by design.
class BleMeshTransport implements MeshTransport {
  final BleByteChannel channel;
  final BleMeshTransportConfig config;
  final StreamController<String> _incoming =
      StreamController<String>.broadcast();
  final _sendLock = _AsyncLock();

  StreamSubscription<Uint8List>? _sub;
  _PendingMessage? _pending;
  bool _closed = false;

  BleMeshTransport({
    required this.channel,
    BleMeshTransportConfig? config,
  }) : config = config ?? const BleMeshTransportConfig() {
    _sub = channel.incomingChunks.listen(
      _onFrame,
      onError: (Object e, StackTrace st) =>
          _incoming.addError(BleTransportException('channel: $e')),
      onDone: () async {
        await dispose();
      },
      cancelOnError: false,
    );
  }

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> send(String packetJson) async {
    if (_closed) return;
    final bytes = Uint8List.fromList(utf8.encode(packetJson));
    if (bytes.length > config.maxMessageBytes) {
      throw BleTransportException(
          'message ${bytes.length} > max ${config.maxMessageBytes}');
    }
    final frames = BleChunker.encode(bytes, config.chunkSize);
    await _sendLock.run(() async {
      for (final f in frames) {
        await channel.sendChunk(f);
      }
    });
  }

  @override
  Future<void> close() => dispose();

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    _sub = null;
    _pending = null;
    try {
      await channel.close();
    } catch (_) {/* ignore */}
    if (!_incoming.isClosed) await _incoming.close();
  }

  void _onFrame(Uint8List frame) {
    if (_closed) return;
    final parsed = BleChunker.parse(frame);
    if (parsed == null) return; // keep-alive
    final total = parsed.total;
    final seq = parsed.seq;
    final payload = parsed.payload;

    if (total > config.maxMessageBytes) {
      _incoming.addError(BleTransportException(
          'incoming $total > max ${config.maxMessageBytes}'));
      _pending = null;
      return;
    }

    final now = DateTime.now().toUtc();
    if (_pending == null || _pending!.totalLen != total) {
      _pending = _PendingMessage(
        totalLen: total,
        startedAt: now,
        chunkSize: config.chunkSize,
      );
    } else if (now.difference(_pending!.startedAt) > config.reassemblyTimeout) {
      // Stale buffer — drop and start fresh.
      _pending = _PendingMessage(
        totalLen: total,
        startedAt: now,
        chunkSize: config.chunkSize,
      );
    }

    final pending = _pending!;
    final expectedSeqs = pending.chunks.length;
    if (seq >= expectedSeqs) {
      _incoming.addError(BleTransportException(
          'seq $seq out of range (expected < $expectedSeqs)'));
      pending.chunks[seq] = payload;
      // Already wrote out of range — pretend to complete and reassemble what
      // we have, then continue with a fresh slot for the next valid frame.
      if (pending.isComplete) {
        final msg = utf8.decode(pending.assemble());
        _incoming.add(msg);
        _pending = null;
      }
      return;
    }
    if (pending.chunks[seq] != null) {
      // duplicate chunk — ignore
      return;
    }
    pending.chunks[seq] = payload;
    pending.receivedChunks += 1;
    if (pending.isComplete) {
      final msg = utf8.decode(pending.assemble());
      _incoming.add(msg);
      _pending = null;
    }
  }
}

/// Tiny mutex so [BleMeshTransport.send] frames chunks in order.
class _AsyncLock {
  Future<void> _last = Future.value();
  Future<T> run<T>(Future<T> Function() body) {
    final completer = Completer<T>();
    final previous = _last;
    _last = completer.future.then((_) => null, onError: (_) => null);
    previous.whenComplete(() async {
      try {
        completer.complete(await body());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

/// Helper used in tests: an in-memory pair of [BleByteChannel]s.
class InMemoryBleByteChannelPair {
  final BleByteChannel a;
  final BleByteChannel b;

  InMemoryBleByteChannelPair._(this.a, this.b);

  factory InMemoryBleByteChannelPair.pair() {
    final ctlAtoB = StreamController<Uint8List>();
    final ctlBtoA = StreamController<Uint8List>();
    bool aClosed = false;
    bool bClosed = false;

    final a = _BufferedBleByteChannel(
      controller: ctlBtoA,
      incoming: ctlAtoB.stream,
      onClose: () async {
        if (!aClosed) {
          aClosed = true;
          await ctlAtoB.close();
        }
      },
      isClosed: () => aClosed,
      onRemoteClose: () async {
        if (!bClosed) {
          bClosed = true;
          await ctlBtoA.close();
        }
      },
    );
    final b = _BufferedBleByteChannel(
      controller: ctlAtoB,
      incoming: ctlBtoA.stream,
      onClose: () async {
        if (!bClosed) {
          bClosed = true;
          await ctlBtoA.close();
        }
      },
      isClosed: () => bClosed,
      onRemoteClose: () async {
        if (!aClosed) {
          aClosed = true;
          await ctlBtoA.close();
        }
      },
    );
    return InMemoryBleByteChannelPair._(a, b);
  }
}

class _BufferedBleByteChannel implements BleByteChannel {
  final StreamController<Uint8List> controller;
  final Stream<Uint8List> incoming;
  final Future<void> Function() onClose;
  final bool Function() isClosed;
  final Future<void> Function() onRemoteClose;

  _BufferedBleByteChannel({
    required this.controller,
    required this.incoming,
    required this.onClose,
    required this.isClosed,
    required this.onRemoteClose,
  });

  @override
  Future<void> sendChunk(Uint8List bytes) async {
    if (isClosed()) return;
    if (controller.isClosed) return;
    controller.add(bytes);
  }

  @override
  Stream<Uint8List> get incomingChunks => incoming;

  @override
  Future<void> close() async {
    await onClose();
  }
}
