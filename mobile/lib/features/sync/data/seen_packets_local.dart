/// Anti-loop deduplication store for the mesh gossip protocol.
///
/// Every mesh packet carries a 32-byte [packetId]. The store remembers which
/// `(packetId, peerAddress)` pairs we've already processed so we can drop a
/// retransmit without re-applying it to local state.
///
/// Rows are stored in a tiny Hive box (`mesh_seen`) so the dedup survives
/// app restarts. The store is also exposed for unit tests via an in-memory
/// implementation.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

/// Hex-encoded `(packetIdHex)@peerAddr` key. We don't store the raw bytes
/// to keep Hive's keys short and avoid JSON-encoding the Uint8List.
String _k(Uint8List packetId, String peerAddr) =>
    '${_hex(packetId)}@$peerAddr';

String _hex(Uint8List b) {
  final chars = List<String>.filled(b.length * 2, '0');
  const hex = '0123456789abcdef';
  for (var i = 0; i < b.length; i++) {
    final v = b[i];
    chars[i * 2] = hex[v >> 4];
    chars[i * 2 + 1] = hex[v & 0x0f];
  }
  return chars.join();
}

/// Abstract surface so unit tests can use a pure-Dart in-memory store while
/// production uses the Hive-backed one.
abstract class SeenPacketsStore {
  /// Returns true iff `(packetId, peerAddr)` has not been seen before AND
  /// was successfully recorded. Callers MUST treat a `false` return as
  /// "drop this packet, we already saw it".
  Future<bool> recordIfNew(Uint8List packetId, String peerAddr);

  /// Best-effort cleanup of entries older than [maxAge]. Returns how many
  /// rows were removed. Called periodically so the box doesn't grow forever.
  Future<int> prune({Duration maxAge = const Duration(days: 14)});

  /// Test/dev: drop everything.
  Future<void> clear();
}

class InMemorySeenPackets implements SeenPacketsStore {
  final Map<String, DateTime> _rows = {};

  @override
  Future<bool> recordIfNew(Uint8List packetId, String peerAddr) async {
    final k = _k(packetId, peerAddr);
    if (_rows.containsKey(k)) return false;
    _rows[k] = DateTime.now().toUtc();
    return true;
  }

  @override
  Future<int> prune({Duration maxAge = const Duration(days: 14)}) async {
    final cutoff = DateTime.now().toUtc().subtract(maxAge);
    final stale = _rows.entries.where((e) => e.value.isBefore(cutoff)).toList();
    for (final e in stale) {
      _rows.remove(e.key);
    }
    return stale.length;
  }

  @override
  Future<void> clear() async => _rows.clear();
}

/// Hive-backed store. Box key: `mesh_seen` (opened by [HiveBoxes.init]).
class HiveSeenPackets implements SeenPacketsStore {
  Box<Map> get _box => Hive.box<Map>('mesh_seen');

  @override
  Future<bool> recordIfNew(Uint8List packetId, String peerAddr) async {
    final key = _k(packetId, peerAddr);
    if (_box.containsKey(key)) return false;
    await _box.put(key, {
      'first_seen': DateTime.now().toUtc().toIso8601String(),
    });
    return true;
  }

  @override
  Future<int> prune({Duration maxAge = const Duration(days: 14)}) async {
    final cutoff = DateTime.now().toUtc().subtract(maxAge);
    final stale = <dynamic>[];
    for (final k in _box.keys) {
      final raw = _box.get(k);
      if (raw == null) continue;
      final m = Map<String, dynamic>.from(raw);
      final firstSeen = DateTime.tryParse(m['first_seen'] as String? ?? '');
      if (firstSeen != null && firstSeen.isBefore(cutoff)) {
        stale.add(k);
      }
    }
    if (stale.isNotEmpty) {
      await _box.deleteAll(stale);
    }
    return stale.length;
  }

  @override
  Future<void> clear() => _box.clear();
}