import 'package:hive_flutter/hive_flutter.dart';

import '../../../data/storage/hive_boxes.dart';
import '../../sync/data/retention_policy.dart';
import '../models/bulletin.dart';

class BulletinRepository {
  Box<Map> get _box => Hive.box<Map>(HiveBoxes.bulletins);
  final RetentionPolicy _policy = RetentionPolicy();

  Future<void> upsertMany(List<Bulletin> rows) async {
    if (rows.isEmpty) return;
    // Merge incoming rows with existing rows, then prune by retention policy.
    final merged = <String, Bulletin>{
      for (final r in rows) r.id: r,
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
      for (final b in kept.where((b) => rows.any((r) => r.id == b.id)))
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
