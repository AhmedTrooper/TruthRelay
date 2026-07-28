/// Coordinates automatic server sync triggered by connectivity changes.
///
/// Subscribes to a stream of connectivity states (typically
/// `Connectivity().onConnectivityChanged`), debounces rapid flips, and on
/// each transition into an "online" state kicks off the existing
/// [SyncService.pushPending] then [SyncService.pull].
///
/// This file owns no transport — it only orchestrates. The injected
/// [stream] and [onOnline] callback make the coordinator fully unit-testable
/// without requiring a real device or plugin platform channel.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'sync_service.dart';

/// Signature of the side-effect that runs when the coordinator transitions
/// into an online state. Defaults to "drain outbox + pull newest from server".
typedef OnlineHandler = Future<void> Function(SyncService sync);

class ConnectivitySyncCoordinator {
  final Stream<List<ConnectivityResult>> _connectivity;
  final SyncService _sync;
  final OnlineHandler _onOnline;
  final Duration _debounce;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _debounceTimer;
  bool _busy = false;
  bool _online = false;

  // ignore_for_file: prefer_initializing_formals

ConnectivitySyncCoordinator({
    required Stream<List<ConnectivityResult>> connectivity,
    required SyncService sync,
    Duration debounce = const Duration(seconds: 3),
    OnlineHandler? onOnline,
  })  : _connectivity = connectivity,
        _sync = sync,
        _debounce = debounce,
        _onOnline = onOnline ?? _defaultOnOnline;

  static Future<void> _defaultOnOnline(SyncService s) async {
    await s.pushPending();
    await s.pull();
  }

  /// Begin listening for connectivity transitions.
  void start() {
    if (_sub != null) return;
    _sub = _connectivity.listen(_onConnectivity);
  }

  /// Stop listening. Safe to call multiple times.
  Future<void> stop() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _sub?.cancel();
    _sub = null;
  }

  void _onConnectivity(List<ConnectivityResult> snapshot) {
    final isOnline = !_isOffline(snapshot);
    if (isOnline == _online) return; // no edge; ignore duplicates
    _online = isOnline;
    if (!isOnline) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _kick);
  }

  Future<void> _kick() async {
    if (_busy) return; // a sync is already running
    _busy = true;
    try {
      await _onOnline(_sync);
    } catch (_) {
      // Swallow here; downstream errors are surfaced by SyncService via the
      // outbox (rows marked failed, retried up to 5 times).
    } finally {
      _busy = false;
    }
  }

  static bool _isOffline(List<ConnectivityResult> snapshot) {
    if (snapshot.isEmpty) return true;
    return snapshot.length == 1 && snapshot.first == ConnectivityResult.none;
  }

  /// Exposed for tests.
  bool get isBusy => _busy;
  bool get isOnline => _online;
}
