import 'dart:convert';

import 'package:flutter/foundation.dart';

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

  /// Test-only factory: constructs a SyncService with stubbed dependencies
  /// that throw on any real call. Tests should subclass [SyncService] and
  /// override only the methods they need.
  ///
  /// The stub instances do NOT touch Hive at construction time. They are
  /// constructed via a factory function so tests can pass in their own
  /// already-opened repos when needed.
  @visibleForTesting
  SyncService.forTest()
      : api = _NullApi(),
        bulletins = _NoIoBulletins(),
        requests = _NoIoRequests(),
        outbox = _NoIoOutbox();

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

// ---- Null-typed test doubles --------------------------------------------
//
// These satisfy the SyncService constructor's required types without doing
// anything. They are only reachable via `SyncService.forTest()` and exist so
// tests can pass `SyncService.forTest()` and override individual methods.

class _NullApi extends ApiClient {
  _NullApi() : super();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('SyncService.forTest() ApiClient stub called: ${invocation.memberName}');
}

class _NoIoBulletins extends BulletinRepository {
  _NoIoBulletins() : super();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('SyncService.forTest() BulletinRepository stub called: ${invocation.memberName}');
}

class _NoIoRequests extends RequestRepository {
  _NoIoRequests() : super();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('SyncService.forTest() RequestRepository stub called: ${invocation.memberName}');
}

class _NoIoOutbox extends OutboxRepository {
  _NoIoOutbox() : super();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('SyncService.forTest() OutboxRepository stub called: ${invocation.memberName}');
}