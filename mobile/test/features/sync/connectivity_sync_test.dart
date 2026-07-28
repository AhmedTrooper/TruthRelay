/// Unit tests for the connectivity-driven server sync coordinator.

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mobile/data/storage/hive_boxes.dart';
import 'package:mobile/features/sync/data/connectivity_sync.dart';
import 'package:mobile/features/sync/data/sync_service.dart';

class _FakeSyncService extends SyncService {
  int pushCalls = 0;
  int pullCalls = 0;
  Duration delay;

  _FakeSyncService({this.delay = Duration.zero}) : super.forTest();

  @override
  Future<int> pushPending() async {
    pushCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return 0;
  }

  @override
  Future<int> pull() async {
    pullCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return 0;
  }
}

void main() {
  // SyncService.forTest() instantiates real Hive-backed repositories just to
  // satisfy the field types. Opening the boxes is the simplest way to avoid
  // "Box not found" errors without mocking the world.
  //
  // The temporary dir ensures we get a fresh Hive state every test run, which
  // sidesteps any "box already open with wrong type" issues from a previous
  // failed test run.
  setUpAll(() async {
    final tempDir = '${Directory.systemTemp.path}/truthrelay-test-${DateTime.now().microsecondsSinceEpoch}';
    Hive.init(tempDir);
    await Future.wait([
      Hive.openBox<Map>(HiveBoxes.bulletins),
      Hive.openBox<Map>(HiveBoxes.requests),
      Hive.openBox<Map>(HiveBoxes.outbox),
      Hive.openBox<Map>(HiveBoxes.settings),
      Hive.openBox<Map>(HiveBoxes.lastSync),
    ]);
  });

  setUp(() async {
    await Hive.box<Map>(HiveBoxes.bulletins).clear();
    await Hive.box<Map>(HiveBoxes.requests).clear();
    await Hive.box<Map>(HiveBoxes.outbox).clear();
    await Hive.box<Map>(HiveBoxes.settings).clear();
  });

  test('offline → online transition triggers one push + one pull', () async {
    final ctl = StreamController<List<ConnectivityResult>>.broadcast();
    final sync = _FakeSyncService();
    final coord = ConnectivitySyncCoordinator(
      connectivity: ctl.stream,
      sync: sync,
      debounce: const Duration(milliseconds: 10),
    );

    coord.start();
    await Future<void>.delayed(Duration.zero); // let subscription attach

    // Start offline, then go online.
    ctl.add([ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    ctl.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(sync.pushCalls, 1);
    expect(sync.pullCalls, 1);

    await coord.stop();
    await ctl.close();
  });

  test('rapid offline/online flips are debounced', () async {
    final ctl = StreamController<List<ConnectivityResult>>.broadcast();
    final sync = _FakeSyncService();
    final coord = ConnectivitySyncCoordinator(
      connectivity: ctl.stream,
      sync: sync,
      debounce: const Duration(milliseconds: 50),
    );

    coord.start();
    await Future<void>.delayed(Duration.zero);

    ctl.add([ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    // Three rapid online pings; debouncer should coalesce to one.
    ctl.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    ctl.add([ConnectivityResult.mobile]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    ctl.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(sync.pushCalls, 1);
    expect(sync.pullCalls, 1);

    await coord.stop();
    await ctl.close();
  });

  test('duplicate "online" snapshot is ignored', () async {
    final ctl = StreamController<List<ConnectivityResult>>.broadcast();
    final sync = _FakeSyncService();
    final coord = ConnectivitySyncCoordinator(
      connectivity: ctl.stream,
      sync: sync,
      debounce: const Duration(milliseconds: 10),
    );

    coord.start();
    await Future<void>.delayed(Duration.zero);

    ctl.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    ctl.add([ConnectivityResult.wifi]); // already online
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(sync.pushCalls, 1);
    expect(sync.pullCalls, 1);

    await coord.stop();
    await ctl.close();
  });

  test('in-flight sync is not re-entered (concurrency guard)', () async {
    final ctl = StreamController<List<ConnectivityResult>>.broadcast();
    final sync = _FakeSyncService(delay: const Duration(milliseconds: 80));
    final coord = ConnectivitySyncCoordinator(
      connectivity: ctl.stream,
      sync: sync,
      debounce: const Duration(milliseconds: 5),
    );

    coord.start();
    await Future<void>.delayed(Duration.zero);

    ctl.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // While the first sync is still running, send another online event.
    ctl.add([ConnectivityResult.mobile]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Give everything time to settle.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // The second event happened while _busy=true, so it must NOT have started
    // a parallel push/pull. Total calls should still be exactly one each.
    expect(sync.pushCalls, 1);
    expect(sync.pullCalls, 1);

    await coord.stop();
    await ctl.close();
  });

  test('downstream errors do not crash the coordinator', () async {
    final ctl = StreamController<List<ConnectivityResult>>.broadcast();
    final sync = _FakeSyncService();
    Future<void> boom(SyncService _) async => throw StateError('boom');
    final coord = ConnectivitySyncCoordinator(
      connectivity: ctl.stream,
      sync: sync,
      debounce: const Duration(milliseconds: 5),
      onOnline: boom,
    );

    coord.start();
    await Future<void>.delayed(Duration.zero);

    ctl.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Coordinator should not re-throw; subsequent events still work.
    expect(coord.isOnline, isTrue);

    await coord.stop();
    await ctl.close();
  });
}
