/// Pluggable backend interface for [WifiDirectDiscovery].
///
/// Splitting the interface out of `wifi_direct_discovery.dart` keeps the
/// discovery wrapper small and lets tests substitute a deterministic fake
/// without ever touching the platform channel. The default constructor of
/// `WifiDirectDiscovery` wires up [_P2pClientBackend] (the production
/// implementation backed by `flutter_p2p_connection` v3).
library;

import 'dart:async';

import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

/// Abstract surface area of the Wi-Fi Direct client used for discovery.
abstract class MeshDiscoveryBackend {
  Future<void> initialize();
  Future<bool> askP2pPermissions();
  Future<bool> checkP2pPermissions();
  Future<bool> checkLocationEnabled();
  Future<bool> checkWifiEnabled();

  /// Begin a BLE peer scan. Returns the active subscription so callers can
  /// cancel it without going through the backend.
  Future<StreamSubscription<List<BleDiscoveredDevice>>> startScan(
    void Function(List<BleDiscoveredDevice>) onData, {
    Function? onError,
    Duration timeout,
  });

  Future<void> stopScan();
  Future<void> dispose();
}

/// Production backend — wraps [FlutterP2pClient].
class P2pClientBackend implements MeshDiscoveryBackend {
  final FlutterP2pClient _client;
  P2pClientBackend({FlutterP2pClient? client})
      : _client = client ?? FlutterP2pClient();

  @override
  Future<void> initialize() => _client.initialize();

  @override
  Future<bool> askP2pPermissions() => _client.askP2pPermissions();

  @override
  Future<bool> checkP2pPermissions() => _client.checkP2pPermissions();

  @override
  Future<bool> checkLocationEnabled() => _client.checkLocationEnabled();

  @override
  Future<bool> checkWifiEnabled() => _client.checkWifiEnabled();

  @override
  Future<StreamSubscription<List<BleDiscoveredDevice>>> startScan(
    void Function(List<BleDiscoveredDevice>) onData, {
    Function? onError,
    Duration timeout = const Duration(seconds: 15),
  }) =>
      _client.startScan(onData, onError: onError, timeout: timeout);

  @override
  Future<void> stopScan() => _client.stopScan();

  @override
  Future<void> dispose() => _client.dispose();
}
