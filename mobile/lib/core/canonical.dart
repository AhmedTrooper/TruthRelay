/// Canonical JSON for bulletin payloads.
///
/// MUST produce byte-identical output to:
///   - api/src/crypto.rs canonical_bulletin_bytes()
///   - web/src/lib/canonical.ts canonicalBulletin()
///
/// Rules:
///   - Keys sorted alphabetically.
///   - No trailing newline.
///   - No whitespace between separators.
library;

import 'dart:convert' show jsonEncode;

dynamic _canonicalize(dynamic v) {
  if (v is Map) {
    final sorted = <String, dynamic>{};
    final keys = v.keys.cast<String>().toList()..sort();
    for (final k in keys) {
      sorted[k] = _canonicalize(v[k]);
    }
    return sorted;
  }
  if (v is List) {
    return v.map(_canonicalize).toList();
  }
  return v;
}

String canonicalBulletin(Map<String, dynamic> payload) {
  return jsonEncode(_canonicalize(payload));
}