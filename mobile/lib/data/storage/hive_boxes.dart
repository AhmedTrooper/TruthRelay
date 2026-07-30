/// Hive bootstrap. Opens every box the app uses. Each feature owns its
/// own box key; this module only handles initialization order.
library;

import 'package:hive_flutter/hive_flutter.dart';

class HiveBoxes {
  HiveBoxes._();

  static const bulletins = 'bulletins';
  static const requests = 'requests';
  static const outbox = 'outbox';
  static const settings = 'settings';
  static const lastSync = 'last_sync';
  static const meshSeen = 'mesh_seen';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait([
      if (!Hive.isBoxOpen(bulletins)) Hive.openBox<Map>(bulletins),
      if (!Hive.isBoxOpen(requests)) Hive.openBox<Map>(requests),
      if (!Hive.isBoxOpen(outbox)) Hive.openBox<Map>(outbox),
      if (!Hive.isBoxOpen(settings)) Hive.openBox<Map>(settings),
      if (!Hive.isBoxOpen(lastSync)) Hive.openBox<Map>(lastSync),
      if (!Hive.isBoxOpen(meshSeen)) Hive.openBox<Map>(meshSeen),
    ]);
  }
}