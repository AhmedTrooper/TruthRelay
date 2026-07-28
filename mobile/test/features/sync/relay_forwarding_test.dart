/// Unit tests for the relay-forwarding path on the mobile side.
///
/// We exercise `SyncService.forwardPeerOutbox` against a stub
/// `ApiClient` that records what was POSTed and returns canned
/// responses. The Hive boxes are still opened in `setUpAll` because
/// `SyncService.forTest()` instantiates real `OutboxRepository` /
/// `BulletinRepository` / `RequestRepository` just to satisfy the
/// field types — but `forwardPeerOutbox` only touches the `api`
/// instance, so the Hive state is irrelevant.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mobile/data/storage/hive_boxes.dart';
import 'package:mobile/features/sync/data/api_client.dart';
import 'package:mobile/features/sync/data/sync_service.dart';

class _RecordingApi extends ApiClient {
  final List<Map<String, dynamic>> posts = [];
  final Map<String, dynamic> response;

  _RecordingApi(this.response) : super();

  @override
  Future<Map<String, dynamic>> meshForward({
    required String forwarderPeerId,
    required List<Map<String, dynamic>> bulletins,
    required List<Map<String, dynamic>> requests,
  }) async {
    posts.add({
      'forwarder_peer_id': forwarderPeerId,
      'bulletins': bulletins,
      'requests': requests,
    });
    return response;
  }
}

class _NoIoSyncService extends SyncService {
  _NoIoSyncService(ApiClient api) : super.forTest() {
    // Replace the stubbed api with our recording instance.
    _api = api;
  }

  late ApiClient _api;

  @override
  ApiClient get api => _api;
}

void main() {
  setUpAll(() async {
    final tempDir =
        '${Directory.systemTemp.path}/truthrelay-relay-fwd-${DateTime.now().microsecondsSinceEpoch}';
    Hive.init(tempDir);
    await Future.wait([
      Hive.openBox<Map>(HiveBoxes.bulletins),
      Hive.openBox<Map>(HiveBoxes.requests),
      Hive.openBox<Map>(HiveBoxes.outbox),
    ]);
  });

  test('forwardPeerOutbox posts to /mesh/forward with peer-supplied items',
      () async {
    final api = _RecordingApi({
      'accepted': 2,
      'duplicates': 0,
      'rejected': 0,
      'forwarder_peer_id': 'peer-b',
      'server_time': '2026-07-29T12:00:00Z',
    });
    final svc = _NoIoSyncService(api);

    final peerOutbox = [
      '{"kind":"bulletin","sha256":"abc","title":"t","body":"b"}',
      '{"kind":"request","id":"r-1","title":"rt","body":"rb"}',
    ];
    final result = await svc.forwardPeerOutbox(
      forwarderPeerId: 'peer-b',
      peerOutbox: peerOutbox,
    );

    expect(api.posts, hasLength(1));
    final posted = api.posts.single;
    expect(posted['forwarder_peer_id'], 'peer-b');
    expect(posted['bulletins'], hasLength(1));
    expect(posted['requests'], hasLength(1));
    expect((posted['bulletins'] as List).first['sha256'], 'abc');
    expect((posted['requests'] as List).first['id'], 'r-1');

    expect(result['accepted'], 2);
    expect(result['duplicates'], 0);
    expect(result['rejected'], 0);
  });

  test('forwardPeerOutbox ignores malformed entries without throwing',
      () async {
    final api = _RecordingApi({
      'accepted': 1,
      'duplicates': 0,
      'rejected': 0,
      'forwarder_peer_id': 'peer-c',
      'server_time': '2026-07-29T12:00:00Z',
    });
    final svc = _NoIoSyncService(api);

    final peerOutbox = [
      '{not-json',
      '{"kind":"bulletin","sha256":"good"}',
      '',
    ];
    final result = await svc.forwardPeerOutbox(
      forwarderPeerId: 'peer-c',
      peerOutbox: peerOutbox,
    );

    final posted = api.posts.single;
    expect(posted['bulletins'], hasLength(1));
    expect(posted['requests'], isEmpty);
    expect(result['accepted'], 1);
  });

  test('forwardPeerOutbox surfaces rejected counts to the caller', () async {
    final api = _RecordingApi({
      'accepted': 1,
      'duplicates': 0,
      'rejected': 3,
      'forwarder_peer_id': 'peer-d',
      'server_time': '2026-07-29T12:00:00Z',
    });
    final svc = _NoIoSyncService(api);

    final result = await svc.forwardPeerOutbox(
      forwarderPeerId: 'peer-d',
      peerOutbox: [
        '{"kind":"bulletin","sha256":"good"}',
        '{"kind":"bulletin","sha256":"bad-1"}',
        '{"kind":"bulletin","sha256":"bad-2"}',
        '{"kind":"bulletin","sha256":"bad-3"}',
      ],
    );

    expect(result['accepted'], 1);
    expect(result['rejected'], 3);
    expect(api.posts.single['bulletins'], hasLength(4));
  });

  test('forwardPeerOutbox with empty input posts empty arrays', () async {
    final api = _RecordingApi({
      'accepted': 0,
      'duplicates': 0,
      'rejected': 0,
      'forwarder_peer_id': 'peer-e',
      'server_time': '2026-07-29T12:00:00Z',
    });
    final svc = _NoIoSyncService(api);

    final result = await svc.forwardPeerOutbox(
      forwarderPeerId: 'peer-e',
      peerOutbox: const [],
    );

    expect(api.posts.single['bulletins'], isEmpty);
    expect(api.posts.single['requests'], isEmpty);
    expect(result['accepted'], 0);
  });
}