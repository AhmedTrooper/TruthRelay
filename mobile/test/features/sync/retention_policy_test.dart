/// Unit tests for the local retention policy used by the offline-first
/// mesh cache. Deterministic via an injected clock.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/bulletins/models/bulletin.dart';
import 'package:mobile/features/requests/models/help_request.dart';
import 'package:mobile/features/sync/data/retention_policy.dart';

void main() {
  group('RetentionPolicy.ttlFor', () {
    final p = RetentionPolicy();
    test('Blood and Missing get the 72h urgent TTL', () {
      expect(p.ttlFor('Blood'), const Duration(hours: 72));
      expect(p.ttlFor('Missing'), const Duration(hours: 72));
    });

    test('Other kinds get the 14-day default TTL', () {
      expect(p.ttlFor('Supply'), const Duration(days: 14));
      expect(p.ttlFor('VerifiedUpdate'), const Duration(days: 14));
      expect(p.ttlFor('Debunk'), const Duration(days: 14));
    });
  });

  group('RetentionPolicy.pruneBulletins', () {
    Bulletin make(String id, String kind, DateTime createdAt) => Bulletin(
          id: id,
          kind: kind,
          title: id,
          body: 'b',
          status: 'Active',
          createdAt: createdAt.toUtc().toIso8601String(),
          receivedAt: createdAt.toUtc().toIso8601String(),
        );

    test('drops Blood records older than 72h', () {
      final now = DateTime.utc(2026, 7, 28, 12, 0, 0);
      final p = RetentionPolicy(clock: () => now);
      final rows = <Bulletin>[
        make('1', 'Blood', now.subtract(const Duration(hours: 71, minutes: 59))),
        make('2', 'Blood', now.subtract(const Duration(hours: 72, minutes: 1))),
      ];
      final kept = p.pruneBulletins(rows);
      expect(kept.map((b) => b.id).toList(), ['1']);
    });

    test('keeps VerifiedUpdate records up to 14 days old', () {
      final now = DateTime.utc(2026, 7, 28, 12, 0, 0);
      final p = RetentionPolicy(clock: () => now);
      final rows = <Bulletin>[
        make('a', 'VerifiedUpdate', now.subtract(const Duration(days: 13))),
        make('b', 'VerifiedUpdate', now.subtract(const Duration(days: 14, hours: 1))),
      ];
      final kept = p.pruneBulletins(rows);
      expect(kept.map((b) => b.id).toList(), ['a']);
    });

    test('caps each kind at maxPerKind, newest first', () {
      final now = DateTime.utc(2026, 7, 28, 12, 0, 0);
      final p = RetentionPolicy(clock: () => now);
      // Provide maxPerKind + 50 Blood rows, newest first.
      final rows = <Bulletin>[];
      for (var i = 0; i < RetentionPolicy.maxPerKind + 50; i++) {
        rows.add(make('b$i', 'Blood', now.subtract(Duration(minutes: i))));
      }
      final kept = p.pruneBulletins(rows);
      expect(kept.length, RetentionPolicy.maxPerKind);
      expect(kept.first.id, 'b0');
      expect(kept.last.id, 'b${RetentionPolicy.maxPerKind - 1}');
    });

    test('preserves caller-supplied ordering (newest first) within a kind', () {
      final now = DateTime.utc(2026, 7, 28, 12, 0, 0);
      final p = RetentionPolicy(clock: () => now);
      // Caller is responsible for sorting newest-first; policy preserves order.
      final rows = <Bulletin>[
        make('new', 'Supply', now.subtract(const Duration(hours: 1))),
        make('mid', 'Supply', now.subtract(const Duration(days: 2))),
        make('old', 'Supply', now.subtract(const Duration(days: 5))),
      ];
      final kept = p.pruneBulletins(rows);
      expect(kept.map((b) => b.id).toList(), ['new', 'mid', 'old']);
    });
  });

  group('RetentionPolicy.pruneRequests', () {
    HelpRequest make(String id, String kind, DateTime createdAt) => HelpRequest(
          id: id,
          kind: kind,
          title: id,
          body: 'b',
          status: 'Active',
          createdAt: createdAt.toUtc().toIso8601String(),
          receivedAt: createdAt.toUtc().toIso8601String(),
        );

    test('Missing is treated as urgent (72h TTL)', () {
      final now = DateTime.utc(2026, 7, 28, 12, 0, 0);
      final p = RetentionPolicy(clock: () => now);
      final rows = <HelpRequest>[
        make('1', 'Missing', now.subtract(const Duration(hours: 73))),
        make('2', 'Missing', now.subtract(const Duration(hours: 71))),
      ];
      final kept = p.pruneRequests(rows);
      expect(kept.map((r) => r.id).toList(), ['2']);
    });

    test('Supply uses default 14-day TTL', () {
      final now = DateTime.utc(2026, 7, 28, 12, 0, 0);
      final p = RetentionPolicy(clock: () => now);
      final rows = <HelpRequest>[
        make('1', 'Supply', now.subtract(const Duration(days: 10))),
        make('2', 'Supply', now.subtract(const Duration(days: 20))),
      ];
      final kept = p.pruneRequests(rows);
      expect(kept.map((r) => r.id).toList(), ['1']);
    });
  });
}
