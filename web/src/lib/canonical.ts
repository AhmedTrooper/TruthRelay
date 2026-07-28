/**
 * Canonical JSON bytes for bulletin payloads.
 *
 * MUST produce byte-identical output to:
 *   - api/src/crypto.rs canonical_bulletin_bytes()
 *   - mobile/lib/core/canonical.dart canonicalBulletin()
 *
 * Rules:
 *   - Keys are sorted alphabetically.
 *   - No trailing newline.
 *   - No whitespace between separators.
 *
 * If any of the three components drift, signature verification will fail.
 */

export interface BulletinPayload {
  kind: string;
  title: string;
  body: string;
  created_at: string;
}

function canonicalize(value: unknown): unknown {
  if (value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(canonicalize);
  const obj = value as Record<string, unknown>;
  const sorted: Record<string, unknown> = {};
  for (const k of Object.keys(obj).sort()) {
    sorted[k] = canonicalize(obj[k]);
  }
  return sorted;
}

export function canonicalBulletin(payload: BulletinPayload): string {
  return JSON.stringify(canonicalize(payload));
}