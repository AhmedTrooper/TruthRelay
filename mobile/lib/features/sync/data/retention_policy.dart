/// Local retention policy for mesh-cached bulletins and help requests.
///
/// Two rules are applied together:
///   1. Time-to-live by `kind`:
///        - Blood / Missing  -> 72 hours
///        - Everything else  -> 14 days
///   2. Hard cap per `kind`: at most [_maxPerKind] records retained.
///
/// The policy is pure (no I/O) and clock-injectable so it can be unit-tested
/// deterministically. Callers (the per-feature repositories) invoke
/// [prune] on every upsert and pass in the candidates + a clock.

import '../../bulletins/models/bulletin.dart' as b;
import '../../requests/models/help_request.dart' as r;

class RetentionPolicy {
  /// Hard upper bound on records kept per `kind`.
  static const int maxPerKind = 500;

  /// TTL for urgent life-safety posts. Short by design: stale blood requests
  /// and missing-person reports are actively harmful in a crisis.
  static const Duration urgentTtl = Duration(hours: 72);

  /// TTL for everything else (verified updates, debunk notices, supply requests).
  static const Duration defaultTtl = Duration(days: 14);

  final DateTime Function() _now;

  RetentionPolicy({DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  /// Returns true if a record of [kind] created at [createdAt] is still fresh
  /// at the current clock.
  bool isFresh(String kind, DateTime createdAt) {
    final ttl = _ttlFor(kind);
    final now = _now().toUtc();
    final created = createdAt.toUtc();
    return now.difference(created) <= ttl;
  }

  Duration ttlFor(String kind) => _ttlFor(kind);

  Duration _ttlFor(String kind) {
    switch (kind) {
      case 'Blood':
      case 'Missing':
        return urgentTtl;
      default:
        return defaultTtl;
    }
  }

  /// Filter + cap a list of bulletins. Input order is `receivedAt DESC` (newest
  /// first). Output preserves that ordering. Items failing the TTL or
  /// exceeding the per-kind cap are dropped.
  List<b.Bulletin> pruneBulletins(List<b.Bulletin> rows) {
    return _prune(rows, (row) => row.kind, (row) => DateTime.parse(row.createdAt));
  }

  /// Same as [pruneBulletins] but for help requests.
  List<r.HelpRequest> pruneRequests(List<r.HelpRequest> rows) {
    return _prune(rows, (row) => row.kind, (row) => DateTime.parse(row.createdAt));
  }

  List<T> _prune<T>(
    List<T> rows,
    String Function(T) kindOf,
    DateTime Function(T) createdAtOf,
  ) {
    // Bucket by kind, keep fresh items only, then cap.
    final buckets = <String, List<T>>{};
    for (final row in rows) {
      if (!isFresh(kindOf(row), createdAtOf(row))) continue;
      buckets.putIfAbsent(kindOf(row), () => <T>[]).add(row);
    }
    // Input is already newest-first; sub-lists preserve order, just trim.
    final out = <T>[];
    for (final list in buckets.values) {
      final take = list.length > maxPerKind ? list.take(maxPerKind).toList() : list;
      out.addAll(take);
    }
    return out;
  }
}
