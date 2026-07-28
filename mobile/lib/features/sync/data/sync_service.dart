import 'dart:convert';

import '../../bulletins/data/bulletin_repository.dart';
import '../../bulletins/models/bulletin.dart';
import '../../requests/data/request_repository.dart';
import '../../requests/models/help_request.dart';
import '../models/outbox_entry.dart';
import 'api_client.dart';
import 'outbox_repository.dart';

class SyncService {
  final ApiClient api;
  final BulletinRepository bulletins;
  final RequestRepository requests;
  final OutboxRepository outbox;

  SyncService({
    required this.api,
    required this.bulletins,
    required this.requests,
    required this.outbox,
  });

  Future<int> pull() async {
    final data = await api.pullSync();
    final bs = (data['bulletins'] as List? ?? []).cast<Map<String, dynamic>>();
    final rs = (data['requests'] as List? ?? []).cast<Map<String, dynamic>>();
    await bulletins.upsertMany(bs.map(Bulletin.fromJson).toList());
    await requests.upsertMany(rs.map(HelpRequest.fromJson).toList());
    return bs.length + rs.length;
  }

  Future<int> pushPending() async {
    final pending = await outbox.pending();
    if (pending.isEmpty) return 0;

    final bs = <Map<String, dynamic>>[];
    final rs = <Map<String, dynamic>>[];
    for (final row in pending) {
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      if (row.kind == OutboxKind.bulletin) {
        bs.add(payload);
      } else if (row.kind == OutboxKind.request) {
        rs.add(payload);
      }
    }

    try {
      final result = await api.pushSync(bulletins: bs, requests: rs);
      final accepted = (result['accepted'] as int?) ?? 0;
      for (final row in pending) {
        await outbox.markDone(row.localId);
      }
      return accepted;
    } catch (e) {
      for (final row in pending) {
        await outbox.markFailed(row.localId, e.toString());
      }
      rethrow;
    }
  }
}