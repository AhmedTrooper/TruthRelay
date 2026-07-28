/// Ed25519 signing using the `cryptography` package.
/// Compatible with the Rust backend's verifier.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'canonical.dart';

final _ed25519 = Ed25519();
final _rng = Random.secure();

Future<Uint8List> signBulletin(Map<String, dynamic> payload, Uint8List secretKey) async {
  final canonical = canonicalBulletin(payload);
  final message = Uint8List.fromList(utf8.encode(canonical));
  final keyPair = await _ed25519.newKeyPairFromSeed(secretKey);
  final signature = await _ed25519.sign(message, keyPair: keyPair);
  return Uint8List.fromList(signature.bytes);
}

/// Verifies an Ed25519 signature over the canonical bytes of [payload]
/// against [publicKey]. Returns `true` only if every byte matches; any
/// mismatch (tampered payload, wrong pubkey, malformed signature) yields
/// `false`. Never throws — a verification failure is data, not an
/// exception.
Future<bool> verifyBulletin({
  required Map<String, dynamic> payload,
  required Uint8List signature,
  required Uint8List publicKey,
}) async {
  if (publicKey.length != 32) return false;
  if (signature.length != 64) return false;
  try {
    final canonical = canonicalBulletin(payload);
    final message = Uint8List.fromList(utf8.encode(canonical));
    final key = SimplePublicKey(publicKey, type: KeyPairType.ed25519);
    final sigObj = Signature(signature, publicKey: key);
    return await _ed25519.verify(message, signature: sigObj);
  } catch (_) {
    return false;
  }
}

Uint8List decodeBase64(String b64) {
  return base64Decode(b64);
}

String encodeBase64(Uint8List bytes) => base64Encode(bytes);

Uint8List randomSecretKey() {
  return Uint8List.fromList(List<int>.generate(32, (_) => _rng.nextInt(256)));
}