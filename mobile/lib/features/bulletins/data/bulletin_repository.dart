import 'package:hive_flutter/hive_flutter.dart';

import '../../../data/storage/hive_boxes.dart';
import '../models/bulletin.dart';

class BulletinRepository {
  Box<Map> get _box => Hive.box<Map>(HiveBoxes.bulletins);

  Future<void> upsertMany(List<Bulletin> rows) async {
    if (rows.isEmpty) return;
    final entries = {for (final r in rows) r.id: r.toJson()};
    await _box.putAll(entries);
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