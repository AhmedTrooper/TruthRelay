/// Periodic background sync via the `workmanager` plugin.
///
/// On Android the system schedules a 15-minute minimum periodic task that
/// runs even when the app is closed, gated by [NetworkType.connected] so it
/// only fires when the device has internet.
///
/// The actual work — pushing the outbox and pulling new bulletins — is the
/// same code path as the foreground connectivity-driven coordinator
/// (commit 3). Both call `SyncService.pushPending()` + `pull()`.
///
/// Because `Workmanager` invokes the entry point in a fresh isolate, we
/// cannot share Riverpod providers with the foreground app. The background
/// entry point rebuilds the necessary services from scratch.
library;

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'sync_service.dart';

/// Name registered with Workmanager for the periodic sync task.
const String backgroundSyncTaskName = 'truthrelay.sync.periodic';

/// Frequency for the periodic sync. Workmanager enforces a 15-minute minimum
/// on Android; the exact interval is best-effort based on system conditions.
const Duration backgroundSyncInterval = Duration(minutes: 15);

/// Initialize Workmanager and schedule the periodic sync task.
///
/// Safe to call multiple times; the plugin guards against duplicate init.
Future<void> initBackgroundSync() async {
  try {
    await Workmanager().initialize(
      callbackDispatcher,
    );
    await Workmanager().registerPeriodicTask(
      backgroundSyncTaskName,
      backgroundSyncTaskName,
      frequency: backgroundSyncInterval,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
    );
  } catch (e) {
    // Workmanager fails on platforms that don't support it (e.g. desktop
    // during tests). Swallow so the app keeps running.
    debugPrint('initBackgroundSync: $e');
  }
}

/// Cancel the periodic sync. Useful when the user opts out of background
/// sync, or for tests that need a clean slate.
Future<void> cancelBackgroundSync() async {
  try {
    await Workmanager().cancelByUniqueName(backgroundSyncTaskName);
  } catch (_) {
    // Same swallow rationale as init.
  }
}

/// The plugin requires a top-level @pragma('vm:entry-point') function as the
/// entry point. Do not rename or move without updating the Android setup.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != backgroundSyncTaskName) return true;
    // Reconstruct the sync stack inside the background isolate. Hive boxes
    // are opened here because the foreground app may not be running.
    return await runBackgroundSync();
  });
}

/// Run the actual sync work. Returns true on success so Workmanager can apply
/// its backoff policy on failure.
Future<bool> runBackgroundSync() async {
  try {
    // The foreground app may already have opened Hive boxes; doing it again
    // is a no-op (Hive.openBox returns the existing instance).
    await ensureHiveBoxesOpen();
    final service = buildSyncService();
    await service.pushPending();
    await service.pull();
    return true;
  } catch (e) {
    debugPrint('runBackgroundSync failed: $e');
    return false;
  }
}

// ---- Hooks the app's bootstrap wires up -------------------------------
//
// These are typed as `dynamic` so this file doesn't take a hard dependency
// on the foreground app's Hive bootstrap path; production code wires them
// in `main.dart`.

Future<void> Function() ensureHiveBoxesOpen = () async {
  throw UnimplementedError('ensureHiveBoxesOpen must be wired in main()');
};

SyncService Function() buildSyncService = () {
  throw UnimplementedError('buildSyncService must be wired in main()');
};
