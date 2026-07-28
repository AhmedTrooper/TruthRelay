/// Integration smoke test: build canonical bytes, sign with Ed25519,
/// produce a base64 signature, and assert the resulting bytes are non-empty.
/// (End-to-end Rust verification is exercised by the bash e2e script that
///  talks to the running Axum server.)
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/canonical.dart';
import 'package:mobile/core/crypto.dart';

void main() {
  test('mobile canonical-bytes are accepted by the Rust verifier shape', () {
    final payload = {
      'kind': 'VerifiedUpdate',
      'title': 'Mobile test',
      'body': 'Signed from a real Dart canonicalizer.',
      'created_at': '2026-07-28T00:00:00Z',
    };
    final canonical = canonicalBulletin(payload);
    // This is byte-identical to the output of the Rust and Web canonicalizers.
    expect(
      canonical,
      '{"body":"Signed from a real Dart canonicalizer.","created_at":"2026-07-28T00:00:00Z","kind":"VerifiedUpdate","title":"Mobile test"}',
    );

    // And it's deterministic across key orderings.
    final reordered = canonicalBulletin({
      'created_at': '2026-07-28T00:00:00Z',
      'title': 'Mobile test',
      'kind': 'VerifiedUpdate',
      'body': 'Signed from a real Dart canonicalizer.',
    });
    expect(canonical, reordered);
  });

  test('Dart Ed25519 sign produces a non-empty 64-byte signature', () async {
    final secret = randomSecretKey();
    final sig = await signBulletin({
      'kind': 'Blood',
      'title': 'Quick',
      'body': 'urgent',
      'created_at': '2026-07-28T00:00:00Z',
    }, Uint8List.fromList(secret));
    expect(sig.length, 64);
    expect(encodeBase64(sig).length, greaterThan(0));
  });

  test('canonical survives roundtrip through jsonEncode/decode', () {
    final p = {'kind': 'VerifiedUpdate', 'title': 'a', 'body': 'b', 'created_at': '2026-01-01T00:00:00Z'};
    final c = canonicalBulletin(p);
    expect(jsonDecode(c), isA<Map<String, dynamic>>());
  });
}