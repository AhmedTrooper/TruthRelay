import 'package:hive_flutter/hive_flutter.dart';

import '../../../data/storage/hive_boxes.dart';
import '../models/outbox_entry.dart';

class OutboxRepository {
  Box<Map> get _box => Hive.box<Map>(HiveBoxes.outbox);
  int _nextId = 1;

  OutboxRepository() {
    final existing = _box.values.cast<Map>().toList();
    if (existing.isNotEmpty) {
      _nextId = existing.map((m) => m['local_id'] as int).reduce((a, b) => a > b ? a : b) + 1;
    }
  }

  Future<int> enqueue({required OutboxKind kind, required String payload}) async {
    final id = _nextId++;
    final entry = OutboxEntry(
      localId: id,
      kind: kind,
      payload: payload,
      status: 'pending',
      attempts: 0,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    await _box.put(id, entry.toJson());
    return id;
  }

  Future<List<OutboxEntry>> pending() async {
    final all = _box.values.cast<Map>().toList();
    return all
        .map((m) => OutboxEntry.fromJson(Map<String, dynamic>.from(m)))
        .where((e) => e.status == 'pending' || (e.status == 'failed' && e.attempts < 5))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<int> countPending() async {
    return (await pending()).length;
  }

  Future<void> markDone(int localId) async {
    final raw = _box.get(localId);
    if (raw == null) return;
    final m = Map<String, dynamic>.from(raw);
    m['status'] = 'done';
    await _box.put(localId, m);
  }

  Future<void> markFailed(int localId, String error) async {
    final raw = _box.get(localId);
    if (raw == null) return;
    final m = Map<String, dynamic>.from(raw);
    m['status'] = 'failed';
    m['attempts'] = (m['attempts'] as int) + 1;
    m['last_error'] = error;
    await _box.put(localId, m);
  }

  Future<void> clear() => _box.clear();
}