/// Mesh-local inventory: "what bulletins and help-requests do I currently
/// hold, in a form the peer protocol can advertise?".
///
/// Wraps the existing repositories behind a single read interface and
/// combines them into the bloom-filter + count + newest-timestamp tuple the
/// [MeshHello] / [MeshInventory] envelopes carry.
///
/// This file is the bridge between the per-feature repositories and the
/// transport-agnostic mesh session: it knows how to produce an inventory
/// and how to consume inbound [MeshData] payloads (delegating to the right
/// repository based on `itemKind`).
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../bulletins/data/bulletin_repository.dart';
import '../../bulletins/models/bulletin.dart';
import '../../requests/data/request_repository.dart';
import '../../requests/models/help_request.dart';
import '../../sync/data/bloom_filter.dart';

/// A single item the mesh cares about: an id (sha256 for bulletins, UUID for
/// requests), its kind, and the canonical JSON bytes we publish.
@immutable
class MeshItem {
  /// 'bulletin' or 'request'. String-keyed to match the wire format used by
  /// `MeshData.itemKind` in `models/mesh_packet.dart`.
  final String kind;

  /// For bulletins this is the content sha256. For requests this is the
  /// client-generated UUID.
  final String id;

  /// Canonical JSON bytes — exactly what the wire protocol carries.
  final Uint8List payload;

  /// When we received (or locally generated) this item. UTC.
  final DateTime receivedAt;

  const MeshItem({
    required this.kind,
    required this.id,
    required this.payload,
    required this.receivedAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeshItem &&
          other.kind == kind &&
          other.id == id &&
          _bytesEqual(other.payload, payload) &&
          other.receivedAt == receivedAt;

  @override
  int get hashCode => Object.hash(kind, id, _bytesHash(payload), receivedAt);

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _bytesHash(Uint8List b) {
    var h = 0;
    for (final byte in b) {
      h = (h * 31 + byte) & 0x7fffffff;
    }
    return h;
  }
}

/// Snapshot of "what I have" at a point in time. Built by
/// [MeshLocalInventorySource.snapshot] and consumed by the mesh session.
@immutable
class MeshLocalInventory {
  /// Bloom filter over every item id (sha256 for bulletins, UUID for
  /// requests) we currently hold. Used by the peer to ask only for ids it
  /// probably doesn't already have.
  final BloomFilter bloom;

  /// Total count of items the bloom filter covers. Cheap integrity check
  /// for the peer — a wildly-wrong count means the bloom is stale.
  final int itemCount;

  /// When the most-recent item was received (UTC). Lets a peer decide if
  /// it has anything newer to send before opening a heavy transfer.
  final DateTime newestReceivedAt;

  const MeshLocalInventory({
    required this.bloom,
    required this.itemCount,
    required this.newestReceivedAt,
  });

  /// Returns the subset of [requestedIds] that the bloom filter says we
  /// probably don't have. The peer should send only those. Bloom is
  /// probabilistic; the receiving side still verifies by [id] / [sha256]
  /// before storing.
  List<String> missingIds(Iterable<String> requestedIds) {
    final out = <String>[];
    for (final id in requestedIds) {
      if (!bloom.mightContainString(id)) out.add(id);
    }
    return out;
  }
}

/// Read interface over the two feature repositories plus a sha256 helper.
/// Pure Dart so the mesh session can be unit-tested without Hive.
abstract class MeshLocalInventorySource {
  /// Returns the canonical bytes for a single item, or `null` if not held.
  Future<Uint8List?> payloadFor(String id);

  /// Persists a peer-received item. Returns `true` if it was new (and
  /// therefore stored), `false` if we already had it.
  Future<bool> applyInbound(MeshItem item);

  /// Builds a snapshot of the current state.
  Future<MeshLocalInventory> snapshot();

  /// Snapshot of every id (bulletin sha256 + request UUID) we currently
  /// hold. Used by the coordinator to pre-fill the [MeshSession.localIds]
  /// so the session can advertise and serve without re-enumerating.
  Future<List<String>> currentIds();
}

/// Production source: reads from the real repositories.
class RepositoryInventorySource implements MeshLocalInventorySource {
  RepositoryInventorySource({
    required this.bulletins,
    required this.requests,
    Sha256? sha256,
  }) : _sha256 = sha256 ?? Sha256();

  /// Visible for testing. Production code should obtain an instance via
  /// `RepositoryInventorySource(bulletins: …, requests: …)`.
  final BulletinRepository bulletins;
  final RequestRepository requests;
  final Sha256 _sha256;

  @override
  Future<Uint8List?> payloadFor(String id) async {
    final bs = await bulletins.list(limit: 10000);
    for (final b in bs) {
      if (b.sha256 == id) return _encode(b.toJson());
    }
    final rs = await requests.list(limit: 10000);
    for (final r in rs) {
      if (r.id == id) return _encode(r.toJson());
    }
    return null;
  }

  @override
  Future<bool> applyInbound(MeshItem item) async {
    switch (item.kind) {
      case 'bulletin':
        final json = jsonDecode(utf8.decode(item.payload)) as Map<String, dynamic>;
        final b = Bulletin.fromJson(json);
        final sha = b.sha256 ?? b.id;
        final existing = await bulletins.list(limit: 10000);
        if (existing.any((x) => (x.sha256 ?? x.id) == sha)) return false;
        await bulletins.upsertMany([b]);
        return true;
      case 'request':
        final json = jsonDecode(utf8.decode(item.payload)) as Map<String, dynamic>;
        final r = HelpRequest.fromJson(json);
        final existing = await requests.list(limit: 10000);
        if (existing.any((x) => x.id == r.id)) return false;
        await requests.upsertMany([r]);
        return true;
      default:
        throw ArgumentError.value(item.kind, 'item.kind', 'unknown mesh item kind');
    }
  }

  @override
  Future<List<String>> currentIds() async {
    final bs = await bulletins.list(limit: 10000);
    final rs = await requests.list(limit: 10000);
    return <String>[
      for (final b in bs) b.sha256 ?? b.id,
      for (final r in rs) r.id,
    ];
  }

  @override
  Future<MeshLocalInventory> snapshot() async {
    final bs = await bulletins.list(limit: 10000);
    final rs = await requests.list(limit: 10000);
    final ids = <String>[
      for (final b in bs) b.sha256 ?? b.id,
      for (final r in rs) r.id,
    ];
    final bloom = BloomFilter();
    for (final id in ids) {
      final digest = await _sha256.hash(utf8.encode(id));
      bloom.add(Uint8List.fromList(digest.bytes));
    }
    DateTime newest = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final b in bs) {
      final t = _parseUtc(b.receivedAt);
      if (t.isAfter(newest)) newest = t;
    }
    for (final r in rs) {
      final t = _parseUtc(r.receivedAt);
      if (t.isAfter(newest)) newest = t;
    }
    return MeshLocalInventory(
      bloom: bloom,
      itemCount: ids.length,
      newestReceivedAt: newest,
    );
  }

  static Uint8List _encode(Map<String, dynamic> json) =>
      Uint8List.fromList(utf8.encode(jsonEncode(json)));

  static DateTime _parseUtc(String iso) {
    final t = DateTime.tryParse(iso);
    return (t ?? DateTime.fromMillisecondsSinceEpoch(0)).toUtc();
  }
}

/// In-memory source for unit tests.
class InMemoryInventorySource implements MeshLocalInventorySource {
  final Map<String, MeshItem> _items = {};

  void seed(Iterable<MeshItem> items) {
    for (final i in items) {
      _items[i.id] = i;
    }
  }

  int get size => _items.length;

  MeshItem? item(String id) => _items[id];

  @override
  Future<Uint8List?> payloadFor(String id) async => _items[id]?.payload;

  @override
  Future<bool> applyInbound(MeshItem item) async {
    if (_items.containsKey(item.id)) return false;
    _items[item.id] = item;
    return true;
  }

  @override
  Future<List<String>> currentIds() async => _items.keys.toList(growable: false);

  @override
  Future<MeshLocalInventory> snapshot() async {
    final ids = _items.keys.toList(growable: false);
    final bloom = BloomFilter();
    for (final id in ids) {
      bloom.addString(id);
    }
    DateTime newest = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final i in _items.values) {
      if (i.receivedAt.isAfter(newest)) newest = i.receivedAt;
    }
    return MeshLocalInventory(
      bloom: bloom,
      itemCount: ids.length,
      newestReceivedAt: newest,
    );
  }
}