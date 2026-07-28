/// Local-only hotspot transport for the offline mesh.
///
/// When Wi-Fi Direct group formation is not available (older devices,
/// restrictive ROMs, missing permissions, no user interaction), one phone
/// can become a *local-only access point* via Android's
/// `WifiManager.startLocalOnlyHotspot()` (API 26+). Other phones join the
/// AP using `WifiConfiguration`, then run the same [MeshTransport] session
/// we already use for Wi-Fi Direct.
///
/// This file defines the transport-agnostic [MeshTransport] bindings and a
/// `LocalHotspotHostBackend` interface so unit tests don't need an Android
/// emulator. Production wiring goes through the `truthrelay.local_hotspot`
/// `MethodChannel` exposed by `MainActivity.kt` (follow-up commit).
///
/// Lifecycle (host side):
///   1. `ensurePermissions()` — confirm location + Wi-Fi + the right
///      runtime permissions are granted.
///   2. `startHost()` — request the OS to open the AP; the backend returns
///      the [HotspotCredentials] (SSID + PSK + band).
///   3. `acceptPeer(...)` for each joiner; transport forwards the
///      configured [MeshTransport] stream between host and joiner.
///   4. `stopHost()` to tear down.
///
/// Lifecycle (joiner side):
///   1. `join(...)` — connect to the AP using [HotspotCredentials].
///   2. Open a TCP socket on a fixed port and start streaming the
///      [MeshTransport] bytes.
///   3. `leave()` to disconnect.
///
/// The framing is intentionally trivial: each [MeshTransport] send produces
/// a length-prefixed UTF-8 frame. The receiver reassembles and hands whole
/// JSON envelopes to the [MeshSession].
///
/// Outbound frames are also split into 16 KiB chunks before being pushed
/// onto the underlying [HotspotChannel] so a single large send can never
/// deadlock the kernel's TCP send buffer on a slow receiver.
///
/// The actual byte-pipe beneath the transport is abstracted behind the
/// [HotspotChannel] interface so unit tests can drive the whole
/// length-prefix framing and reassembly with in-memory
/// `StreamController<Uint8List>` pairs instead of touching real sockets.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

import 'mesh_session.dart';

/// Per-write chunk size when sending to the channel. Sized to stay well
/// inside the default Linux loopback send buffer (≈ 64 KiB) and the typical
/// Android Wi-Fi driver MTU after TCP overhead, leaving headroom for the
/// OS to acknowledge each piece without back-pressuring our send loop.
const int _kHotspotSendChunkBytes = 16 * 1024;

/// Soft cap on the total message size we'll accept. Anything larger is
/// rejected with [HotspotException].
const int _kHotspotMaxMessageBytes = 256 * 1024;

/// Raw byte channel beneath the framing layer. Production wraps a real
/// `dart:io` [Socket] over the local-only hotspot; tests substitute an
/// in-memory `StreamController<Uint8List>` pair.
///
/// The contract is intentionally minimal: caller pushes framed UTF-8
/// bytes via [sendBytes] (one logical call per chunk — the channel does
/// not coalesce) and reads raw inbound bytes from [incomingBytes]. The
/// channel is responsible for the underlying transport lifecycle.
abstract class HotspotChannel {
  /// Push a single chunk of bytes to the remote peer. Blocks until the
  /// underlying write completes.
  Future<void> sendBytes(Uint8List bytes);

  /// Stream of inbound byte chunks as they arrive.
  Stream<Uint8List> get incomingBytes;

  /// Tear down the underlying connection. Idempotent.
  Future<void> close();
}

/// SSID + passphrase + band returned by the OS when the local-only hotspot
/// comes up. Plain text because Android's API gives us plaintext (we never
/// rely on `WifiConfiguration.preSharedKey` being encrypted on disk).
@immutable
class HotspotCredentials {
  final String ssid;
  final String passphrase;
  final int port;
  final int band; // 0 = 2.4GHz, 1 = 5GHz, 2 = 6GHz — matches Android's constants
  final DateTime issuedAt;

  const HotspotCredentials({
    required this.ssid,
    required this.passphrase,
    required this.port,
    required this.band,
    required this.issuedAt,
  });

  Map<String, dynamic> toJson() => {
        'ssid': ssid,
        'passphrase': passphrase,
        'port': port,
        'band': band,
        'issued_at': issuedAt.toUtc().toIso8601String(),
      };

  factory HotspotCredentials.fromJson(Map<String, dynamic> m) =>
      HotspotCredentials(
        ssid: m['ssid'] as String,
        passphrase: m['passphrase'] as String,
        port: (m['port'] as num).toInt(),
        band: (m['band'] as num).toInt(),
        issuedAt: DateTime.parse(m['issued_at'] as String),
      );
}

/// Errors surfaced by the hotspot backend. Production code maps Android
/// exceptions into one of these so the rest of the app only sees this
/// narrow set.
class HotspotException implements Exception {
  final String message;
  final String? code;
  const HotspotException(this.message, {this.code});
  @override
  String toString() => 'HotspotException(${code ?? 'unspecified'}): $message';
}

/// Backend interface. Production wires to the Android MethodChannel; tests
/// substitute an in-memory implementation so the whole transport can be
/// driven from pure Dart.
abstract class LocalHotspotHostBackend {
  /// Returns true if the runtime permissions and OS pre-conditions are
  /// met. False means the caller should defer the start and prompt the
  /// user.
  Future<bool> ensurePermissions();

  /// Opens a local-only hotspot. Returns the credentials when the AP is
  /// up. May throw [HotspotException] if the OS refuses.
  Future<HotspotCredentials> startHost({required int port});

  /// Tears the hotspot down. Idempotent.
  Future<void> stopHost();

  /// Streams peer connection events. Each [HotspotPeer] carries the
  /// [HotspotChannel] the host will use to exchange mesh packets.
  Stream<HotspotPeer> get peerEvents;
}

/// An inbound connection once a peer has joined the AP. The host uses
/// [LocalHotspotHostTransport] to run a [MeshSession] over [channel].
class HotspotPeer {
  final String peerId;
  final HotspotChannel channel;
  HotspotPeer({required this.peerId, required this.channel});

  @override
  String toString() => 'HotspotPeer(id=$peerId)';
}

/// Joiner-side backend. Distinct from [LocalHotspotHostBackend] because the
/// flows are different: the joiner doesn't open an AP, it connects to one.
abstract class LocalHotspotJoinerBackend {
  Future<bool> ensurePermissions();

  /// Connects to the AP described by [credentials] and opens a TCP
  /// session on `credentials.port`. Returns the open [HotspotChannel] on
  /// success.
  Future<HotspotChannel> join(HotspotCredentials credentials);

  /// Disconnects and removes the temporary Wi-Fi configuration so the
  /// phone reverts to its previous network.
  Future<void> leave();
}

/// Host-side transport: pulls peers from [LocalHotspotHostBackend.peerEvents]
/// and runs a separate [MeshTransport] session per peer. Single-consumer.
class LocalHotspotHostTransport implements MeshTransport {
  final HotspotPeer peer;
  final StreamController<String> _incoming =
      StreamController<String>.broadcast();
  final _sendLock = _AsyncLock();
  StreamSubscription<Uint8List>? _sub;
  bool _closed = false;
  final _FrameParser _parser = _FrameParser();

  LocalHotspotHostTransport({required this.peer}) {
    _sub = peer.channel.incomingBytes.listen(
      (bytes) {
        for (final frame in _parser.push(bytes)) {
          if (!_incoming.isClosed) _incoming.add(frame);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!_incoming.isClosed) {
          _incoming.addError(HotspotException('channel: $e'));
        }
      },
      onDone: () async {
        if (!_incoming.isClosed) await _incoming.close();
      },
      cancelOnError: false,
    );
  }

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> send(String packetJson) async {
    if (_closed) return;
    final body = Uint8List.fromList(utf8.encode(packetJson));
    final header = Uint8List(4);
    // big-endian length
    header[0] = (body.length >> 24) & 0xff;
    header[1] = (body.length >> 16) & 0xff;
    header[2] = (body.length >> 8) & 0xff;
    header[3] = body.length & 0xff;
    await _sendLock.run(() async {
      await peer.channel.sendBytes(header);
      var offset = 0;
      while (offset < body.length) {
        final take = (body.length - offset) < _kHotspotSendChunkBytes
            ? body.length - offset
            : _kHotspotSendChunkBytes;
        await peer.channel.sendBytes(
          Uint8List.sublistView(body, offset, offset + take),
        );
        offset += take;
      }
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    try {
      await peer.channel.close();
    } catch (_) {/* ignore */}
    if (!_incoming.isClosed) await _incoming.close();
  }
}

/// Joiner-side transport. Wraps a [HotspotChannel] opened by
/// [LocalHotspotJoinerBackend.join].
class LocalHotspotJoinerTransport implements MeshTransport {
  final HotspotChannel channel;
  final StreamController<String> _incoming =
      StreamController<String>.broadcast();
  final _sendLock = _AsyncLock();
  StreamSubscription<Uint8List>? _sub;
  bool _closed = false;
  final _FrameParser _parser = _FrameParser();

  LocalHotspotJoinerTransport({required this.channel}) {
    _sub = channel.incomingBytes.listen(
      (bytes) {
        for (final frame in _parser.push(bytes)) {
          if (!_incoming.isClosed) _incoming.add(frame);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!_incoming.isClosed) {
          _incoming.addError(HotspotException('channel: $e'));
        }
      },
      onDone: () async {
        if (!_incoming.isClosed) await _incoming.close();
      },
      cancelOnError: false,
    );
  }

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> send(String packetJson) async {
    if (_closed) return;
    final body = Uint8List.fromList(utf8.encode(packetJson));
    final header = Uint8List(4);
    header[0] = (body.length >> 24) & 0xff;
    header[1] = (body.length >> 16) & 0xff;
    header[2] = (body.length >> 8) & 0xff;
    header[3] = body.length & 0xff;
    await _sendLock.run(() async {
      await channel.sendBytes(header);
      var offset = 0;
      while (offset < body.length) {
        final take = (body.length - offset) < _kHotspotSendChunkBytes
            ? body.length - offset
            : _kHotspotSendChunkBytes;
        await channel.sendBytes(
          Uint8List.sublistView(body, offset, offset + take),
        );
        offset += take;
      }
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    try {
      await channel.close();
    } catch (_) {/* ignore */}
    if (!_incoming.isClosed) await _incoming.close();
  }
}

/// Streaming length-prefix frame parser. A 4-byte big-endian length
/// followed by exactly that many UTF-8 payload bytes. Returns one frame
/// per call when a complete frame is available, otherwise nothing.
///
/// Multiple frames may arrive in a single chunk; [push] walks them
/// sequentially and yields each one as it's complete. If the buffered
/// length is implausibly large we drop the buffer so a malformed peer
/// can't pin memory forever.
class _FrameParser {
  Uint8List? _pending;
  int _pendingOffset = 0;
  int _pendingNeeded = -1;

  Iterable<String> push(Uint8List chunk) sync* {
    var srcOffset = 0;
    final src = chunk;
    while (srcOffset < src.length) {
      if (_pendingNeeded < 0) {
        // Need more bytes to fill the 4-byte length header.
        if (_pending == null) {
          _pending = Uint8List(4);
          _pendingOffset = 0;
        }
        final take = (4 - _pendingOffset) < (src.length - srcOffset)
            ? 4 - _pendingOffset
            : src.length - srcOffset;
        _pending!.setRange(_pendingOffset, _pendingOffset + take,
            src.sublist(srcOffset, srcOffset + take));
        _pendingOffset += take;
        srcOffset += take;
        if (_pendingOffset < 4) return;
        _pendingNeeded =
            (_pending![0] << 24) | (_pending![1] << 16) | (_pending![2] << 8) | _pending![3];
        if (_pendingNeeded <= 0 || _pendingNeeded > _kHotspotMaxMessageBytes) {
          // Malformed length — drop buffer and skip this frame.
          _pending = null;
          _pendingOffset = 0;
          _pendingNeeded = -1;
          continue;
        }
        _pending = Uint8List(_pendingNeeded);
        _pendingOffset = 0;
      }
      // We know we need _pendingNeeded bytes of payload.
      final remaining = _pendingNeeded - _pendingOffset;
      final avail = src.length - srcOffset;
      final take = remaining < avail ? remaining : avail;
      _pending!.setRange(
          _pendingOffset, _pendingOffset + take, src.sublist(srcOffset, srcOffset + take));
      _pendingOffset += take;
      srcOffset += take;
      if (_pendingOffset < _pendingNeeded) return;
      // Frame complete — emit and reset.
      final out = utf8.decode(_pending!);
      _pending = null;
      _pendingOffset = 0;
      _pendingNeeded = -1;
      yield out;
    }
  }

  void reset() {
    _pending = null;
    _pendingOffset = 0;
    _pendingNeeded = -1;
  }
}

/// Tiny async mutex so concurrent sends don't interleave on the same channel.
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

/// Test/in-memory paired channel. One half's [sendBytes] writes into the
/// other half's [incomingBytes]. The peer id is a label for assertions.
class _PairedHotspotChannel implements HotspotChannel {
  final String label;
  final StreamController<Uint8List> _outbound;
  final StreamController<Uint8List> _remoteInbound;
  bool _closed = false;

  _PairedHotspotChannel(
    this.label,
    this._outbound,
    this._remoteInbound,
  );

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    if (_closed) return;
    if (!_remoteInbound.isClosed) _remoteInbound.add(bytes);
  }

  @override
  Stream<Uint8List> get incomingBytes => _outbound.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Close both pipes. We intentionally do *not* await `done` because
    // teardown happens after the caller has dropped all subscriptions
    // and would otherwise deadlock waiting for a `done` future with no
    // listener.
    if (!_outbound.isClosed) {
      unawaited(_outbound.close());
    }
    if (!_remoteInbound.isClosed) {
      unawaited(_remoteInbound.close());
    }
  }
}

/// In-memory backend pair used by unit tests. Returns paired host +
/// joiner backends with a fresh [HotspotCredentials]. Real implementations
/// bind to the OS; this one uses pure Dart streams so tests run on the
/// host VM with no Android runtime.
class InMemoryHotspotPair {
  final LocalHotspotHostBackend host;
  final LocalHotspotJoinerBackend joiner;
  final HotspotCredentials credentials;

  InMemoryHotspotPair._({
    required this.host,
    required this.joiner,
    required this.credentials,
  });

  /// Spins up a host + joiner pair. Returns once the host backend is
  /// ready to accept peers.
  static Future<InMemoryHotspotPair> pair({int port = 0}) async {
    final creds = HotspotCredentials(
      ssid: 'TruthRelay-Test',
      passphrase: 'unit-test',
      port: port,
      band: 0,
      issuedAt: DateTime.now().toUtc(),
    );
    final peerEvents = StreamController<HotspotPeer>.broadcast();
    final hostBackend = _InMemoryHostBackend(
      creds: creds,
      peerEvents: peerEvents,
    );
    final joinerBackend = _InMemoryJoinerBackend(hostBackend);
    return InMemoryHotspotPair._(
      host: hostBackend,
      joiner: joinerBackend,
      credentials: creds,
    );
  }
}

class _InMemoryHostBackend implements LocalHotspotHostBackend {
  final HotspotCredentials creds;
  final StreamController<HotspotPeer> _peerEvents;
  bool _permissionsOk = true;
  int _peerCounter = 0;

  _InMemoryHostBackend({
    required this.creds,
    required this._peerEvents,
  });

  @override
  Future<bool> ensurePermissions() async => _permissionsOk;

  @override
  Future<HotspotCredentials> startHost({required int port}) async => creds;

  @override
  Future<void> stopHost() async {
    await _peerEvents.close();
  }

  /// Pushes a fresh peer connected to [remoteChannel] (the joiner's
  /// outbound side) onto the host's peer stream.
  void deliverPeer(HotspotChannel remoteChannel) {
    if (_peerEvents.isClosed) return;
    _peerEvents.add(HotspotPeer(
      peerId: 'unit-peer-${++_peerCounter}',
      channel: remoteChannel,
    ));
  }

  @override
  Stream<HotspotPeer> get peerEvents => _peerEvents.stream;

  // Test seam — set to false to simulate denial.
  set permissions(bool v) => _permissionsOk = v;
}

class _InMemoryJoinerBackend implements LocalHotspotJoinerBackend {
  final _InMemoryHostBackend _host;
  bool _permissionsOk = true;

  _InMemoryJoinerBackend(this._host);

  @override
  Future<bool> ensurePermissions() async => _permissionsOk;

  @override
  Future<HotspotChannel> join(HotspotCredentials credentials) async {
    // Two paired StreamControllers: one for joiner→host bytes, one for
    // host→joiner bytes. The host side of the channel is given to the
    // host via [deliverPeer]; the joiner side is returned here.
    final joinerToHost = StreamController<Uint8List>();
    final hostToJoiner = StreamController<Uint8List>();
    final joinerChannel = _PairedHotspotChannel(
      'joiner',
      hostToJoiner,
      joinerToHost,
    );
    final hostChannel = _PairedHotspotChannel(
      'host',
      joinerToHost,
      hostToJoiner,
    );
    _host.deliverPeer(hostChannel);
    return joinerChannel;
  }

  @override
  Future<void> leave() async {
    // No persistent state — closing the channel is the caller's job.
  }

  set permissions(bool v) => _permissionsOk = v;
}