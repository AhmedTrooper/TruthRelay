/// Tests for the peer-hop Ed25519 re-verification logic.
///
/// Covers [verifyBulletin] (low-level), [ModeratorPublicKeyRepository]
/// (cache behaviour), and the [BulletinRepository._verifyMany] helper
/// which is what runs every time a peer-supplied bulletin lands.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mobile/core/crypto.dart';
import 'package:mobile/data/storage/hive_boxes.dart';
import 'package:mobile/features/bulletins/data/bulletin_repository.dart';
import 'package:mobile/features/bulletins/models/bulletin.dart';
import 'package:mobile/features/sync/data/api_client.dart';
import 'package:mobile/features/sync/data/moderator_public_key_repository.dart';

final _ed25519 = Ed25519();

Future<Uint8List> _derivePublicKey(Uint8List secret) async {
  final kp = await _ed25519.newKeyPairFromSeed(secret);
  final pk = await kp.extractPublicKey();
  return Uint8List.fromList(pk.bytes);
}

void main() {
  setUpAll(() async {
    final tempDir =
        '${Directory.systemTemp.path}/truthrelay-sig-${DateTime.now().microsecondsSinceEpoch}';
    Hive.init(tempDir);
    await Future.wait([
      Hive.openBox<Map>(HiveBoxes.bulletins),
      Hive.openBox<Map>(HiveBoxes.requests),
      Hive.openBox<Map>(HiveBoxes.outbox),
    ]);
  });

  group('verifyBulletin', () {
    test('round-trips a valid signature over canonical bytes', () async {
      final secret = randomSecretKey();
      final payload = {
        'kind': 'VerifiedUpdate',
        'title': 'All clear',
        'body': 'Water station open.',
        'created_at': '2026-07-29T12:00:00Z',
      };
      final sig = await signBulletin(payload, secret);
      final pub = await _derivePublicKey(secret);
      final ok = await verifyBulletin(
        payload: payload,
        signature: sig,
        publicKey: pub,
      );
      expect(ok, isTrue);
    });

    test('rejects a tampered payload', () async {
      final secret = randomSecretKey();
      final payload = {
        'kind': 'VerifiedUpdate',
        'title': 'All clear',
        'body': 'Water station open.',
        'created_at': '2026-07-29T12:00:00Z',
      };
      final sig = await signBulletin(payload, secret);
      final pub = await _derivePublicKey(secret);
      final tampered = Map<String, dynamic>.from(payload)
        ..['title'] = 'All gone';
      final ok = await verifyBulletin(
        payload: tampered,
        signature: sig,
        publicKey: pub,
      );
      expect(ok, isFalse);
    });

    test('rejects a signature from a different key', () async {
      final secret1 = randomSecretKey();
      final payload = {
        'kind': 'Debunk',
        'title': 'Rumor',
        'body': 'No power at the clinic.',
        'created_at': '2026-07-29T12:00:00Z',
      };
      final sig1 = await signBulletin(payload, secret1);
      final pub2 = await _derivePublicKey(randomSecretKey());
      final ok = await verifyBulletin(
        payload: payload,
        signature: sig1,
        publicKey: pub2,
      );
      expect(ok, isFalse);
    });

    test('rejects malformed signature length without throwing', () async {
      final secret = randomSecretKey();
      final pub = await _derivePublicKey(secret);
      final ok = await verifyBulletin(
        payload: {
          'kind': 'VerifiedUpdate',
          'title': 't',
          'body': 'b',
          'created_at': 'x',
        },
        signature: Uint8List(32), // wrong length
        publicKey: pub,
      );
      expect(ok, isFalse);
    });

    test('rejects malformed pubkey length without throwing', () async {
      final secret = randomSecretKey();
      final sig = await signBulletin(
        {
          'kind': 'VerifiedUpdate',
          'title': 't',
          'body': 'b',
          'created_at': 'x',
        },
        secret,
      );
      final ok = await verifyBulletin(
        payload: {
          'kind': 'VerifiedUpdate',
          'title': 't',
          'body': 'b',
          'created_at': 'x',
        },
        signature: sig,
        publicKey: Uint8List(16), // wrong length
      );
      expect(ok, isFalse);
    });
  });

  group('ModeratorPublicKeyRepository', () {
    test('caches the pubkey after the first fetch', () async {
      final api = _FakeApiClient({'mod-1': 'AAAA'});
      final repo = ModeratorPublicKeyRepository(api: api);
      await repo.get('mod-1');
      await repo.get('mod-1');
      expect(api.fetchCount['mod-1'], 1); // only one network roundtrip
    });

    test('returns null and caches sentinel for unknown moderator', () async {
      final api = _FakeApiClient(<String, String>{});
      final repo = ModeratorPublicKeyRepository(api: api);
      await repo.get('mod-ghost');
      await repo.get('mod-ghost');
      expect(api.fetchCount['mod-ghost'], 1);
    });

    test('invalidate() forces the next call to re-fetch', () async {
      final api = _FakeApiClient({'mod-2': 'AAAA'});
      final repo = ModeratorPublicKeyRepository(api: api);
      await repo.get('mod-2');
      expect(api.fetchCount['mod-2'], 1);
      repo.invalidate('mod-2');
      await repo.get('mod-2');
      expect(api.fetchCount['mod-2'], 2);
    });

    test('clear() drops the whole cache', () async {
      final api = _FakeApiClient({'mod-3': 'AAAA'});
      final repo = ModeratorPublicKeyRepository(api: api);
      await repo.get('mod-3');
      repo.clear();
      await repo.get('mod-3');
      expect(api.fetchCount['mod-3'], 2);
    });
  });

  group('BulletinRepository signature verification on peer hop', () {
    test('stores signatureVerified=true when sig matches moderator pubkey',
        () async {
      final secret = randomSecretKey();
      final pub = await _derivePublicKey(secret);
      final repo = _seedRepo({'mod-good': encodeBase64(pub)});

      final payload = {
        'kind': 'VerifiedUpdate',
        'title': 't',
        'body': 'b',
        'created_at': '2026-07-29T12:00:00Z',
      };
      final sig = await signBulletin(payload, secret);
      final bulletin = _bulletin(
        id: 'b-good',
        moderatorId: 'mod-good',
        sigB64: encodeBase64(sig),
      );

      await repo.upsertMany([bulletin]);
      final stored = await repo.get('b-good');
      expect(stored, isNotNull);
      expect(stored!.signatureVerified, isTrue);
      expect(stored.isVerifiedLocally, isTrue);
    });

    test('stores signatureVerified=false when sig does not match', () async {
      final secret = randomSecretKey();
      final otherSecret = randomSecretKey();
      final pub = await _derivePublicKey(secret);
      final repo = _seedRepo({'mod-x': encodeBase64(pub)});

      final payload = {
        'kind': 'Debunk',
        'title': 't',
        'body': 'b',
        'created_at': '2026-07-29T12:00:00Z',
      };
      // Sign with a different key than the one registered.
      final sig = await signBulletin(payload, otherSecret);
      final bulletin = _bulletin(
        id: 'b-bad',
        moderatorId: 'mod-x',
        sigB64: encodeBase64(sig),
      );

      await repo.upsertMany([bulletin]);
      final stored = await repo.get('b-bad');
      expect(stored, isNotNull);
      expect(stored!.signatureVerified, isFalse);
      expect(stored.isVerifiedLocally, isFalse);
    });

    test('stores signatureVerified=false when moderator is unknown', () async {
      final repo = _seedRepo(<String, String>{});
      final secret = randomSecretKey();
      final payload = {
        'kind': 'VerifiedUpdate',
        'title': 't',
        'body': 'b',
        'created_at': '2026-07-29T12:00:00Z',
      };
      final sig = await signBulletin(payload, secret);
      final bulletin = _bulletin(
        id: 'b-unknown',
        moderatorId: 'mod-never',
        sigB64: encodeBase64(sig),
      );

      await repo.upsertMany([bulletin]);
      final stored = await repo.get('b-unknown');
      expect(stored, isNotNull);
      expect(stored!.signatureVerified, isFalse);
    });

    test('bulletins without moderator or signature keep signatureVerified=null',
        () async {
      final repo = _seedRepo(<String, String>{});
      final bulletin = _bulletin(
        id: 'b-partial',
        moderatorId: null,
        sigB64: null,
      );

      await repo.upsertMany([bulletin]);
      final stored = await repo.get('b-partial');
      expect(stored!.signatureVerified, isNull);
    });
  });
}

Bulletin _bulletin({
  required String id,
  String? moderatorId,
  String? sigB64,
}) {
  return Bulletin(
    id: id,
    kind: 'VerifiedUpdate',
    title: 't',
    body: 'b',
    sha256: null,
    status: 'Active',
    moderatorId: moderatorId,
    moderatorName: moderatorId == null ? null : 'Test Mod',
    signatureB64: sigB64,
    createdAt: '2026-07-29T12:00:00Z',
    receivedAt: '2026-07-29T12:00:00Z',
  );
}

BulletinRepository _seedRepo(Map<String, String> b64ById) {
  final api = _FakeApiClient(b64ById);
  final pubRepo = ModeratorPublicKeyRepository(api: api);
  return BulletinRepository(moderatorKeys: pubRepo);
}

class _FakeApiClient extends ApiClient {
  final Map<String, String> b64ById;
  final Map<String, int> fetchCount = {};
  _FakeApiClient(this.b64ById) : super();

  @override
  Future<String?> fetchModeratorPublicKeyB64(String moderatorId) async {
    fetchCount[moderatorId] = (fetchCount[moderatorId] ?? 0) + 1;
    return b64ById[moderatorId];
  }
}