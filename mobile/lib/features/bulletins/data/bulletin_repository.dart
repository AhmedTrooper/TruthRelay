import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/crypto.dart';
import '../../../data/storage/hive_boxes.dart';
import '../../sync/data/moderator_public_key_repository.dart';
import '../../sync/data/retention_policy.dart';
import '../models/bulletin.dart';

class BulletinRepository {
  Box<Map> get _box => Hive.box<Map>(HiveBoxes.bulletins);
  final RetentionPolicy _policy = RetentionPolicy();

  /// Optional moderator-pubkey cache used to re-verify peer-supplied
  /// bulletins on every hop. When `null`, signature verification is a
  /// no-op (the bulletins are still stored, just with
  /// `signatureVerified: null`).
  ModeratorPublicKeyRepository? moderatorKeys;

  BulletinRepository({this.moderatorKeys});

  /// Re-runs the Ed25519 check on every supplied bulletin. Returns a
  /// new list of bulletins annotated with [Bulletin.signatureVerified].
  /// If the moderator pubkey is not cached and no repository is wired
  /// in, the result is the input list unchanged with verification
  /// left as `null`.
  Future<List<Bulletin>> _verifyMany(List<Bulletin> rows) async {
    if (moderatorKeys == null) return rows;
    final out = <Bulletin>[];
    for (final b in rows) {
      if (b.signatureB64 == null ||
          b.moderatorId == null ||
          b.signatureB64!.isEmpty ||
          b.moderatorId!.isEmpty) {
        // Nothing to verify — keep the row, mark as unverified.
        out.add(b.copyWith(resetSignatureVerified: true));
        continue;
      }
      final pubkey = await moderatorKeys!.get(b.moderatorId!);
      if (pubkey == null) {
        out.add(b.copyWith(signatureVerified: false));
        continue;
      }
      final payload = {
        'kind': b.kind,
        'title': b.title,
        'body': b.body,
        'created_at': b.createdAt,
      };
      final ok = await verifyBulletin(
        payload: payload,
        signature: decodeBase64(b.signatureB64!),
        publicKey: pubkey,
      );
      out.add(b.copyWith(signatureVerified: ok));
    }
    return out;
  }

  Future<void> upsertMany(List<Bulletin> rows) async {
    if (rows.isEmpty) return;
    final verified = await _verifyMany(rows);
    // Merge incoming rows with existing rows, then prune by retention policy.
    final merged = <String, Bulletin>{
      for (final r in verified) r.id: r,
    };
    for (final raw in _box.values) {
      final m = Map<String, dynamic>.from(raw);
      merged.putIfAbsent(m['id'] as String, () => Bulletin.fromJson(m));
    }
    final all = merged.values.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final kept = _policy.pruneBulletins(all);
    final keptIds = {for (final b in kept) b.id};
    final toDrop = merged.keys.where((id) => !keptIds.contains(id)).toList();
    final toPut = <String, Map>{
      for (final b in kept.where((b) => verified.any((r) => r.id == b.id)))
        b.id: b.toJson(),
    };
    if (toDrop.isNotEmpty) {
      await _box.deleteAll(toDrop);
    }
    if (toPut.isNotEmpty) {
      await _box.putAll(toPut);
    }
  }

  Future<List<Bulletin>> list({int limit = 200}) async {
    final all = _box.values.map((m) => Bulletin.fromJson(Map<String, dynamic>.from(m))).toList();
    all.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return all.take(limit).toList();
  }

  Future<Bulletin?> get(String id) async {
    final raw = _box.get(id);
    if (raw == null) return null;
    return Bulletin.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> clear() => _box.clear();
}
