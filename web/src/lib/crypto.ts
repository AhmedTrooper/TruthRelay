/**
 * Ed25519 signing helpers for the web admin.
 *
 * Uses @noble/ed25519 (pure-JS, audited) and @noble/hashes for the SHA-512
 * backend required by the library.
 */

import * as ed from '@noble/ed25519';
// @noble/hashes exports under both names; some bundlers strip the .js extension.
import { sha512 } from '@noble/hashes/sha2.js';
import { canonicalBulletin, type BulletinPayload } from './canonical';

// Wire up the SHA-512 backend once. @noble/ed25519 needs it for hash-to-curve.
ed.hashes.sha512 = sha512;

export function decodeBase64(b64: string): Uint8Array {
  const binary = atob(b64);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export function encodeBase64(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

export async function signBulletin(
  payload: BulletinPayload,
  secretKeyBytes: Uint8Array,
): Promise<string> {
  const msg = new TextEncoder().encode(canonicalBulletin(payload));
  const sig = await ed.signAsync(msg, secretKeyBytes);
  return encodeBase64(sig);
}