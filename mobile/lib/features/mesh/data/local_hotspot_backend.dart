/// Production Dart backend for the local-only hotspot transport.
///
/// Bridges the Dart-side [LocalHotspotHostBackend] / [LocalHotspotJoinerBackend]
/// interfaces to a Kotlin MethodChannel exposed by `MainActivity.kt`. Owns a
/// single `EventChannel("truthrelay.local_hotspot.events")` for status events
/// and a single `EventChannel("truthrelay.local_hotspot.bytes")` whose listener
/// argument `connection_id` selects which connection's bytes are flowing.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'local_hotspot_transport.dart';

/// One inbound TCP connection as a [HotspotChannel]. Writes go directly over
/// the underlying socket (we never plug native sockets into Dart; the Kotlin
/// side handles I/O and streams bytes to us through EventChannel).
class NativeHotspotChannel implements HotspotChannel {
  final String connectionId;
  final void Function(Uint8List) _sendBytes;
  final void Function() _close;

  NativeHotspotChannel({
    required this.connectionId,
    required void Function(Uint8List) sendBytesSink,
    required void Function() closeSink,
  })  : _sendBytes = sendBytesSink,
        _close = closeSink;

  /// Stream of inbound bytes from the peer. The platform EventChannel drives
  /// this sink through [LocalHotspotBackend.attachPeerSink].
  final StreamController<Uint8List> _inbound =
      StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get incomingBytes => _inbound.stream;

  void push(Uint8List bytes) {
    if (!_inbound.isClosed) _inbound.add(bytes);
  }

  void remoteClosed() {
    if (!_inbound.isClosed) _inbound.close();
  }

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    _sendBytes(bytes);
  }

  @override
  Future<void> close() async {
    _close();
    if (!_inbound.isClosed) await _inbound.close();
  }
}

class LocalHotspotBackend {
  static const _methodChannel =
      MethodChannel('truthrelay.local_hotspot');
  static const _eventChannel =
      EventChannel('truthrelay.local_hotspot.events');
  static const _bytesChannel =
      EventChannel('truthrelay.local_hotspot.bytes');

  /// Active host-side listener: when peers join the AP, the Kotlin side
  /// emits `host_peer_connected` with a `connection_id`. We spin up a
  /// [NativeHotspotChannel] per id and push it onto this stream.
  final StreamController<HotspotPeer> _hostPeers =
      StreamController<HotspotPeer>.broadcast();

  /// Active joiner-side channel (at most one in this build).
  NativeHotspotChannel? _activeJoinerChannel;

  /// Back-channel: Kotlin -> Dart, per-connection bytes.
  final Map<String, NativeHotspotChannel> _channels = {};
  StreamSubscription? _eventsSub;

  Stream<HotspotPeer> get hostPeers => _hostPeers.stream;

  /// Sends raw bytes for [connectionId]. The Kotlin side tracks which socket
  /// is associated with which id and forwards the bytes.
  void _sendBytes(String connectionId, Uint8List bytes) {
    _methodChannel.invokeMethod<void>('sendBytes', {
      'connection_id': connectionId,
      'bytes': bytes,
    });
  }

  void _closeConnection(String connectionId) {
    _methodChannel.invokeMethod<void>('closeConnection', {
      'connection_id': connectionId,
    });
  }

  Future<void> ensurePermissions() async {
    final ok = await _methodChannel.invokeMethod<bool>('isHotspotSupported');
    if (ok != true) {
      throw HotspotException('Local-only hotspot not supported on this device');
    }
  }

  Future<bool> isSupported() async {
    return await _methodChannel.invokeMethod<bool>('isHotspotSupported') ??
        false;
  }

  /// Start the hotspot + TCP listener.
  Future<HotspotCredentials> startHost({int port = 8765}) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'startHost',
      {'port': port},
    );
    if (result == null) {
      throw HotspotException('startHost returned null');
    }
    _subscribeEvents();
    return HotspotCredentials(
      ssid: result['ssid'] as String,
      passphrase: result['passphrase'] as String,
      port: (result['port'] as num).toInt(),
      band: (result['band'] as num?)?.toInt() ?? 0,
      issuedAt: DateTime.parse(result['issued_at'] as String),
    );
  }

  Future<void> stopHost() async {
    await _methodChannel.invokeMethod<void>('stopHost');
  }

  /// Connect to an existing hotspot. Returns the open [HotspotChannel].
  Future<HotspotChannel> joinHotspot({
    required String ssid,
    required String passphrase,
    int port = 8765,
  }) async {
    _subscribeEvents();
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'joinHotspot',
      {
        'ssid': ssid,
        'passphrase': passphrase,
        'port': port,
      },
    );
    if (result == null) {
      throw HotspotException('joinHotbox returned null');
    }
    final connId = result['connection_id'] as String;
    final channel = NativeHotspotChannel(
      connectionId: connId,
      sendBytesSink: (bytes) => _sendBytes(connId, bytes),
      closeSink: () => _closeConnection(connId),
    );
    _channels[connId] = channel;
    _activeJoinerChannel = channel;

    // Tell the EventChannel which connection_id we want next.
    _bytesChannel
        .receiveBroadcastStream({'connection_id': connId})
        .listen(
      (event) {
        if (event is List<int>) {
          channel.push(Uint8List.fromList(event));
        } else if (event is Map && event['type'] == 'done') {
          channel.remoteClosed();
        }
      },
      onError: (Object _) => channel.remoteClosed(),
      onDone: () => channel.remoteClosed(),
    );
    return channel;
  }

  Future<void> leaveHotspot() async {
    final c = _activeJoinerChannel;
    if (c != null) {
      await c.close();
      _channels.remove('joiner')?.close();
      _activeJoinerChannel = null;
    }
    await _methodChannel.invokeMethod<void>('leaveHotspot');
  }

  void _subscribeEvents() {
    if (_eventsSub != null) return;
    _eventsSub = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final type = event['type'] as String?;
      switch (type) {
        case 'host_peer_connected':
          final connId = event['connection_id'] as String? ?? '';
          final peerAddr = event['peer_addr'] as String? ?? '';
          final ch = NativeHotspotChannel(
            connectionId: connId,
            sendBytesSink: (bytes) => _sendBytes(connId, bytes),
            closeSink: () => _closeConnection(connId),
          );
          _channels[connId] = ch;
          _bytesChannel
              .receiveBroadcastStream({'connection_id': connId})
              .listen(
            (msg) {
              if (msg is List<int>) {
                ch.push(Uint8List.fromList(msg));
              }
            },
            onError: (Object _) => ch.remoteClosed(),
            onDone: () => ch.remoteClosed(),
          );
          _hostPeers.add(HotspotPeer(peerId: peerAddr, channel: ch));
          break;
        case 'peer_disconnected':
          final connId = event['connection_id'] as String?;
          if (connId != null) {
            _channels.remove(connId)?.close();
          }
          break;
      }
    });
  }

  Future<void> dispose() async {
    await _eventsSub?.cancel();
    _eventsSub = null;
    for (final c in _channels.values) {
      await c.close();
    }
    _channels.clear();
    await _hostPeers.close();
  }
}

/// Wraps [LocalHotspotBackend] to implement the [LocalHotspotHostBackend]
/// interface from `local_hotspot_transport.dart`.
class HotspotHostBackendAdapter implements LocalHotspotHostBackend {
  final LocalHotspotBackend _backend;
  HotspotHostBackendAdapter(this._backend);

  @override
  Future<bool> ensurePermissions() async {
    try {
      await _backend.ensurePermissions();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<HotspotCredentials> startHost({required int port}) async {
    return _backend.startHost(port: port);
  }

  @override
  Future<void> stopHost() async {
    await _backend.stopHost();
  }

  @override
  Stream<HotspotPeer> get peerEvents => _backend.hostPeers;
}

/// Wraps [LocalHotspotBackend] to implement the [LocalHotspotJoinerBackend]
/// interface.
class HotspotJoinerBackendAdapter implements LocalHotspotJoinerBackend {
  final LocalHotspotBackend _backend;
  final String _ssid;
  final String _passphrase;
  final int _port;

  HotspotJoinerBackendAdapter(this._backend, {
    required String ssid,
    required String passphrase,
    int port = 8765,
  })  : _ssid = ssid,
        _passphrase = passphrase,
        _port = port;

  @override
  Future<bool> ensurePermissions() async {
    try {
      await _backend.ensurePermissions();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<HotspotChannel> join(HotspotCredentials credentials) async {
    return _backend.joinHotspot(
      ssid: credentials.ssid.isNotEmpty ? credentials.ssid : _ssid,
      passphrase: credentials.passphrase.isNotEmpty
          ? credentials.passphrase
          : _passphrase,
      port: credentials.port != 0 ? credentials.port : _port,
    );
  }

  @override
  Future<void> leave() async {
    await _backend.leaveHotspot();
  }
}
