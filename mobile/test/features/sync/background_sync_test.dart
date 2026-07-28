/// Unit tests for the background sync glue around the Workmanager plugin.
///
/// We test the parts we can isolate:
///   - Hook installation: `ensureHiveBoxesOpen` and `buildSyncService` can be
///     overridden by `main.dart` and are used inside `runBackgroundSync`.
///   - `runBackgroundSync` returns `true` on success and `false` on
///     failure (so Workmanager's backoff policy can apply).
///
/// We do NOT call Workmanager itself here — the plugin uses platform
/// channels that are unavailable in pure-Dart unit tests. The integration
/// is covered by manual + instrumented tests on a real device.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mobile/data/storage/hive_boxes.dart';
import 'package:mobile/features/sync/data/background_sync.dart';
import 'package:mobile/features/sync/data/sync_service.dart';

class _StubSyncService extends SyncService {
  int pushCalls = 0;
  int pullCalls = 0;
  bool throwOnPush;

  _StubSyncService({this.throwOnPush = false}) : super.forTest();

  @override
  Future<int> pushPending() async {
    pushCalls++;
    if (throwOnPush) throw StateError('push failed');
    return 0;
  }

  @override
  Future<int> pull() async {
    pullCalls++;
    return 0;
  }
}

void main() {
  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/truthrelay-bg-test-${DateTime.now().microsecondsSinceEpoch}');
    await Future.wait([
      Hive.openBox<Map>(HiveBoxes.bulletins),
      Hive.openBox<Map>(HiveBoxes.requests),
      Hive.openBox<Map>(HiveBoxes.outbox),
      Hive.openBox<Map>(HiveBoxes.settings),
      Hive.openBox<Map>(HiveBoxes.lastSync),
    ]);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    // Reset hooks after each test so they don't leak between cases.
    await Hive.box<Map>(HiveBoxes.bulletins).clear();
    await Hive.box<Map>(HiveBoxes.requests).clear();
    await Hive.box<Map>(HiveBoxes.outbox).clear();
    await Hive.box<Map>(HiveBoxes.settings).clear();
  });

  test('runBackgroundSync returns true on success', () async {
    final stub = _StubSyncService();
    ensureHiveBoxesOpen = () async {};
    buildSyncService = () => stub;
    addTearDown(() {
      ensureHiveBoxesOpen = () async => throw UnimplementedError();
      buildSyncService = () => throw UnimplementedError();
    });

    final ok = await runBackgroundSync();
    expect(ok, isTrue);
    expect(stub.pushCalls, 1);
    expect(stub.pullCalls, 1);
  });

  test('runBackgroundSync returns false when pushPending throws', () async {
    final stub = _StubSyncService(throwOnPush: true);
    ensureHiveBoxesOpen = () async {};
    buildSyncService = () => stub;
    addTearDown(() {
      ensureHiveBoxesOpen = () async => throw UnimplementedError();
      buildSyncService = () => throw UnimplementedError();
    });

    final ok = await runBackgroundSync();
    expect(ok, isFalse);
    expect(stub.pushCalls, 1);
    // pull() should NOT have been called since push threw.
    expect(stub.pullCalls, 0);
  });

  test('initBackgroundSync swallows plugin errors (desktop/test fallback)', () async {
    // On a non-supported platform, the plugin throws. We just want to ensure
    // the wrapper does not propagate.
    await initBackgroundSync();
    // No assertion needed beyond "did not throw".
  });

  test('backgroundSyncTaskName is a stable constant used by main + tests', () {
    expect(backgroundSyncTaskName, 'truthrelay.sync.periodic');
    expect(backgroundSyncInterval.inMinutes, greaterThanOrEqualTo(15));
  });
}
