/// Moderator public-key cache for peer-received bulletin verification.
///
/// The cache is populated lazily: the first time we see a bulletin
/// referencing [moderatorId] we ask the server for the pubkey, decode
/// the base64, and remember it. Subsequent calls reuse the cache.
///
/// A "miss" returns `null` so callers can distinguish "we don't know
/// yet" from "we know and it's verified". The cache is best-effort —
/// a moderator that exists when we first sync may have been re-keyed
/// later, in which case the next sync refreshes the entry.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../../core/crypto.dart';
import 'api_client.dart';

class ModeratorPublicKeyRepository {
  final ApiClient _api;
  final Map<String, Uint8List?> _cache = {};

  ModeratorPublicKeyRepository({ApiClient? api})
      : _api = api ?? ApiClient();

  /// Fetches and caches the public key for [moderatorId]. Returns the
  /// raw 32-byte Ed25519 pubkey, or `null` if the moderator is
  /// unknown / the network failed / the cached entry is the explicit
  /// "not found" sentinel.
  Future<Uint8List?> get(String moderatorId) async {
    if (_cache.containsKey(moderatorId)) {
      return _cache[moderatorId];
    }
    final b64 = await _api.fetchModeratorPublicKeyB64(moderatorId);
    if (b64 == null) {
      _cache[moderatorId] = null;
      return null;
    }
    try {
      final bytes = decodeBase64(b64);
      _cache[moderatorId] = bytes;
      return bytes;
    } catch (_) {
      _cache[moderatorId] = null;
      return null;
    }
  }

  /// Drops a single entry from the cache so the next call re-fetches.
  /// Used when a sig-verify fails — the cached pubkey may be stale or
  /// the moderator may have rotated keys since the cache was warmed.
  void invalidate(String moderatorId) {
    _cache.remove(moderatorId);
  }

  /// Drops everything. Tests use this to isolate cases.
  void clear() => _cache.clear();
}