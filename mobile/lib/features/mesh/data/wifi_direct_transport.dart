/// Wi-Fi Direct transport binding for the mesh session.
///
/// Wraps `FlutterP2pHost` (group owner) or `FlutterP2pClient` (joiner) from
/// the `flutter_p2p_connection` plugin and exposes the
/// transport-agnostic [MeshTransport] interface used by [MeshSession].
///
/// Lifecycle (host side):
///   1. `FlutterP2pHost.initialize()` — one-time native setup.
///   2. `host.createGroup()` — form the Wi-Fi Direct group.
///   3. Wait for the first client to join.
///   4. Create [WifiDirectHostTransport].
///   5. Run a [MeshSession] with the transport.
///
/// Lifecycle (client side):
///   1. `FlutterP2pClient.initialize()`.
///   2. `client.startScan()` — discover a host (BLE advertisements).
///   3. `client.connectWithDevice(...)` — connect via hotspot credentials.
///   4. Create [WifiDirectClientTransport] when the transport layer reports
///      `isConnected`.
///   5. Run a [MeshSession] with the transport.
///
/// Per-connection lifecycle:
///   * `send(json)` — push one mesh packet to the peer.
///   * `close()`    — tear down the socket.
///
/// The transport is intentionally small: it doesn't own scan/discovery
/// (that's done by `WifiDirectDiscovery` from commit 6) and doesn't run the
/// mesh session (that's [MeshSession] from this commit). It only moves
/// UTF-8 JSON strings between the two phones.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

import 'mesh_session.dart';

@immutable
class WifiDirectHostConfig {
  /// Displayed peer id of the host (advertised in [MeshHeader.peerId]).
  final String localPeerId;

  /// Plugin instance. Inject a fake in tests.
  final FlutterP2pHost host;

  const WifiDirectHostConfig({
    required this.localPeerId,
    required this.host,
  });
}

@immutable
class WifiDirectClientConfig {
  /// Displayed peer id of the client.
  final String localPeerId;

  final FlutterP2pClient client;

  const WifiDirectClientConfig({
    required this.localPeerId,
    required this.client,
  });
}

/// Wi-Fi Direct group owner's transport. `peerId` is the client id once it
/// joins the group; the host addresses every send by that id.
class WifiDirectHostTransport implements MeshTransport {
  final WifiDirectHostConfig config;
  final String peerId;
  final StreamController<String> _incoming =
      StreamController<String>.broadcast();
  late final StreamSubscription<String> _sub;
  bool _closed = false;

  WifiDirectHostTransport({
    required this.config,
    required this.peerId,
  }) {
    _sub = config.host.streamReceivedTexts().listen(_incoming.add);
  }

  @override
  Future<void> send(String packetJson) async {
    if (_closed) return;
    await config.host.sendTextToClient(packetJson, peerId);
  }

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    try {
      await config.host.removeGroup();
    } catch (_) {/* ignore — group may already be gone */}
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}

/// Wi-Fi Direct joiner's transport. `peerId` is the host's id (or empty to
/// use `broadcastText` if no specific id is needed).
class WifiDirectClientTransport implements MeshTransport {
  final WifiDirectClientConfig config;
  final String peerId;
  final StreamController<String> _incoming =
      StreamController<String>.broadcast();
  late final StreamSubscription<String> _sub;
  bool _closed = false;

  WifiDirectClientTransport({
    required this.config,
    required this.peerId,
  }) {
    _sub = config.client.streamReceivedTexts().listen(_incoming.add);
  }

  @override
  Future<void> send(String packetJson) async {
    if (_closed) return;
    await config.client.sendTextToClient(packetJson, peerId);
  }

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    try {
      await config.client.disconnect();
    } catch (_) {/* ignore */}
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}