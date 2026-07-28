import 'package:hive_flutter/hive_flutter.dart';

import '../../../data/storage/hive_boxes.dart';
import '../models/help_request.dart';

class RequestRepository {
  Box<Map> get _box => Hive.box<Map>(HiveBoxes.requests);

  Future<void> upsertMany(List<HelpRequest> rows) async {
    if (rows.isEmpty) return;
    final entries = {for (final r in rows) r.id: r.toJson()};
    await _box.putAll(entries);
  }

  Future<void> insert(HelpRequest r) async {
    await _box.put(r.id, r.toJson());
  }

  Future<List<HelpRequest>> list({int limit = 200}) async {
    final all = _box.values.map((m) => HelpRequest.fromJson(Map<String, dynamic>.from(m))).toList();
    all.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return all.take(limit).toList();
  }

  Future<void> clear() => _box.clear();
}