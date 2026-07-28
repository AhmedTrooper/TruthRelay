/// Hive bootstrap. Opens every box the app uses. Each feature owns its
/// own box key; this module only handles initialization order.

import 'package:hive_flutter/hive_flutter.dart';

class HiveBoxes {
  HiveBoxes._();

  static const bulletins = 'bulletins';
  static const requests = 'requests';
  static const outbox = 'outbox';
  static const settings = 'settings';
  static const lastSync = 'last_sync';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox(bulletins),
      Hive.openBox(requests),
      Hive.openBox(outbox),
      Hive.openBox(settings),
      Hive.openBox(lastSync),
    ]);
  }
}