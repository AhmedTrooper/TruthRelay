// Cross-language canonical-JSON test for the mobile app.
//
// Builds a payload, runs it through the SAME canonicalBulletin function used
// by the app, then compares against an expected JSON string produced by
// the canonicalizer on the Rust and web sides.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/canonical.dart';

void main() {
  test('canonical bytes match the Rust + web output', () {
    final canonical = canonicalBulletin({
      'kind': 'VerifiedUpdate',
      'title': 'Cross-language',
      'body': 'Verified by everyone.',
      'created_at': '2026-07-28T00:00:00Z',
    });
    expect(
      canonical,
      '{"body":"Verified by everyone.","created_at":"2026-07-28T00:00:00Z","kind":"VerifiedUpdate","title":"Cross-language"}',
    );
  });

  test('canonical bytes are stable across key orderings', () {
    final a = canonicalBulletin({
      'kind': 'Blood',
      'title': 'O+',
      'body': 'urgent',
      'created_at': '2026-07-28T00:00:00Z',
    });
    final b = canonicalBulletin({
      'created_at': '2026-07-28T00:00:00Z',
      'body': 'urgent',
      'title': 'O+',
      'kind': 'Blood',
    });
    expect(a, b);
  });
}