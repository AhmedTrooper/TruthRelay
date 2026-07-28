/**
 * Cross-language canonical-JSON + signature test.
 *
 * Mints a keypair, builds the canonical bytes using the SAME canonicalizer
 * that the Vue app uses, signs them with Ed25519, POSTs the bulletin to the
 * running Axum server, and asserts the server accepts it (201).
 *
 * Run with: bun run scripts/canonical-test.ts
 */

import * as ed from '@noble/ed25519';
import { sha512 } from '@noble/hashes/sha2.js';

ed.hashes.sha512 = sha512;

function canonicalize(value: unknown): unknown {
  if (value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(canonicalize);
  const obj = value as Record<string, unknown>;
  const sorted: Record<string, unknown> = {};
  for (const k of Object.keys(obj).sort()) sorted[k] = canonicalize(obj[k]);
  return sorted;
}

function canonicalBulletin(payload: object): string {
  return JSON.stringify(canonicalize(payload));
}

const API = process.env.VITE_API_URL ?? 'http://localhost:8080';
const ADMIN = process.env.TRUTHRELAY_ADMIN_TOKEN ?? 'dev-token';

async function main() {
  // 1. Mint a keypair.
  const secret = ed.utils.randomSecretKey();
  const publicKey = await ed.getPublicKeyAsync(secret);

  // 2. Register the moderator.
  const reg = await fetch(`${API}/api/v1/moderators`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Admin-Token': ADMIN },
    body: JSON.stringify({
      name: 'canonical-test',
      public_key_b64: Buffer.from(publicKey).toString('base64'),
    }),
  });
  const modView = (await reg.json()) as { id: string };
  console.log('registered:', modView.id);

  // 3. Build canonical bytes + sign.
  const payload = {
    kind: 'VerifiedUpdate',
    title: 'Cross-language test',
    body: 'Signed via the web canonicalizer, verified by the Rust backend.',
    created_at: new Date().toISOString(),
  };
  const canonical = canonicalBulletin(payload);
  console.log('canonical:', canonical);

  const sig = await ed.signAsync(new TextEncoder().encode(canonical), secret);
  const sigB64 = Buffer.from(sig).toString('base64');

  // 4. POST the bulletin.
  const res = await fetch(`${API}/api/v1/bulletins`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      moderator_id: modView.id,
      payload,
      signature_b64: sigB64,
    }),
  });

  console.log('POST status:', res.status);
  if (res.status !== 201) {
    console.error('FAIL', await res.text());
    process.exit(1);
  }
  console.log('✓ Cross-language canonical + signature works');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});