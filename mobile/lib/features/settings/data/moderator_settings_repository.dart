import 'package:hive_flutter/hive_flutter.dart';

import '../../../data/storage/hive_boxes.dart';

class StoredModerator {
  final String id;
  final String name;
  final String publicKeyB64;
  final String secretKeyB64;
  final String createdAt;

  const StoredModerator({
    required this.id,
    required this.name,
    required this.publicKeyB64,
    required this.secretKeyB64,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'public_key_b64': publicKeyB64,
        'secret_key_b64': secretKeyB64,
        'created_at': createdAt,
      };

  factory StoredModerator.fromJson(Map<String, dynamic> m) => StoredModerator(
        id: m['id'] as String,
        name: m['name'] as String,
        publicKeyB64: m['public_key_b64'] as String,
        secretKeyB64: m['secret_key_b64'] as String,
        createdAt: m['created_at'] as String,
      );
}

class ModeratorSettingsRepository {
  static const _key = 'moderator';
  Box<Map> get _box => Hive.box<Map>(HiveBoxes.settings);

  StoredModerator? load() {
    final raw = _box.get(_key);
    if (raw == null) return null;
    return StoredModerator.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> save(StoredModerator m) => _box.put(_key, m.toJson());

  Future<void> clear() => _box.delete(_key);
}