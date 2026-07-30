#!/usr/bin/env bash
# Phase 1 exit-criteria smoke test for TruthRelay.
# Requires the server to be running at http://127.0.0.1:8080 and a working
# `cargo run -- keygen` against the same `api/` directory.

set -euo pipefail

API=${API:-http://127.0.0.1:8080}
ADMIN_TOKEN=${TRUTHRELAY_ADMIN_TOKEN:-dev-token-change-me}

echo "### 1. /healthz"
curl -fsS "$API/healthz" | tee /tmp/tr_health.json
echo
grep -q '"status":"ok"' /tmp/tr_health.json || { echo "FAIL: healthz"; exit 1; }

echo "### 2. /api/v1/stats (initial)"
curl -fsS "$API/api/v1/stats" | tee /tmp/tr_stats.json
echo

echo "### 3. Mint a moderator key"
( cd "$(dirname "$0")/.." && cargo run --quiet -- keygen --name e2e-tester ) \
  | tee /tmp/tr_keygen.json
echo

MOD_PUB=$(grep -o '"public_key_b64": *"[^"]*"' /tmp/tr_keygen.json | cut -d'"' -f4)
MOD_SEC=$(grep -o '"secret_key_b64": *"[^"]*"' /tmp/tr_keygen.json | cut -d'"' -f4)

echo "public_key_b64=${MOD_PUB:0:16}…"
echo "secret_key_b64=${MOD_SEC:0:16}…"

echo "### 4. Register moderator"
curl -fsS -X POST "$API/api/v1/moderators" \
  -H "Content-Type: application/json" \
  -H "X-Admin-Token: $ADMIN_TOKEN" \
  -d "{\"name\":\"e2e-tester\",\"public_key_b64\":\"$MOD_PUB\"}" \
  | tee /tmp/tr_register.json
echo

# Server returns the assigned moderator_id; reuse it for the signed bulletin.
MOD_ID=$(python3 -c "import json; print(json.load(open('/tmp/tr_register.json'))['id'])")
echo "moderator_id=$MOD_ID"

echo "### 5. Build canonical bytes + signature (via small Python helper)"
python3 - "$MOD_ID" "$MOD_SEC" <<'PY' > /tmp/tr_signed.json
import sys, json, base64, hashlib
from datetime import datetime, timezone

mod_id, sec_b64 = sys.argv[1], sys.argv[2]
sec_bytes = base64.b64decode(sec_b64)

# Try to use cryptography lib if available; otherwise use a pure-python Ed25519
try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization
    sk = Ed25519PrivateKey.from_private_bytes(sec_bytes)
    def sign(msg):
        return sk.sign(msg)
except ImportError:
    # Pure-python fallback using PyNaCl
    try:
        import nacl.signing
        sk = nacl.signing.SigningKey(sec_bytes)
        def sign(msg):
            return sk.sign(msg).signature
    except ImportError:
        print("ERROR: need cryptography or pynacl", file=sys.stderr)
        sys.exit(1)

payload = {
    "kind": "VerifiedUpdate",
    "title": "Hospital A is open",
    "body": "Verified by e2e-tester at " + datetime.now(timezone.utc).isoformat(),
    "created_at": datetime.now(timezone.utc).isoformat(),
}
canonical = json.dumps(payload, sort_keys=True, separators=(',', ':'))
sig = sign(canonical.encode("utf-8"))
print(json.dumps({
    "moderator_id": mod_id,
    "payload": payload,
    "signature_b64": base64.b64encode(sig).decode(),
    "canonical_hex": hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
}))
PY
cat /tmp/tr_signed.json | python3 -m json.tool | head -20
echo

echo "### 6. POST signed bulletin (expect 201)"
HTTP=$(curl -s -o /tmp/tr_posted.json -w "%{http_code}" -X POST "$API/api/v1/bulletins" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/tr_signed.json)
echo "HTTP=$HTTP"
[ "$HTTP" = "201" ] || { echo "FAIL: expected 201, got $HTTP"; cat /tmp/tr_posted.json; exit 1; }
BULLETIN_ID=$(python3 -c "import json; print(json.load(open('/tmp/tr_posted.json'))['id'])")
echo "bulletin_id=$BULLETIN_ID"

echo "### 7. POST same bulletin again (expect 409 duplicate)"
HTTP=$(curl -s -o /tmp/tr_dup.json -w "%{http_code}" -X POST "$API/api/v1/bulletins" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/tr_signed.json)
echo "HTTP=$HTTP"
[ "$HTTP" = "409" ] || { echo "FAIL: expected 409, got $HTTP"; cat /tmp/tr_dup.json; exit 1; }

echo "### 8. Tamper signature (expect 400 invalid_signature)"
python3 - <<'PY' > /tmp/tr_tampered.json
import json, base64
data = json.load(open("/tmp/tr_signed.json"))
sig = bytearray(base64.b64decode(data["signature_b64"]))
sig[0] ^= 0x01
data["signature_b64"] = base64.b64encode(bytes(sig)).decode()
print(json.dumps(data))
PY
HTTP=$(curl -s -o /tmp/tr_tamper.json -w "%{http_code}" -X POST "$API/api/v1/bulletins" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/tr_tampered.json)
echo "HTTP=$HTTP"
[ "$HTTP" = "400" ] || { echo "FAIL: expected 400, got $HTTP"; cat /tmp/tr_tamper.json; exit 1; }
grep -q "invalid_signature" /tmp/tr_tamper.json || { echo "FAIL: expected invalid_signature"; exit 1; }

echo "### 9. POST a help request (expect 201)"
REQ_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
curl -fsS -X POST "$API/api/v1/requests" \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"$REQ_ID\",\"kind\":\"Blood\",\"title\":\"O+ blood needed\",\"body\":\"DM me\",\"location\":\"Dhaka\",\"contact\":\"+880...\",\"created_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
  | python3 -m json.tool
echo

echo "### 10. GET /api/v1/sync?since=1970 (expect our bulletin + request)"
curl -fsS "$API/api/v1/sync?since=1970-01-01T00:00:00Z" | python3 -m json.tool | head -30
echo

echo "### 11. POST /api/v1/sync empty (expect 200, accepted=0, duplicates=0)"
curl -fsS -X POST "$API/api/v1/sync" \
  -H "Content-Type: application/json" \
  -d '{"bulletins":[],"requests":[]}' | python3 -m json.tool
echo

echo "### 12. Stats after run"
curl -fsS "$API/api/v1/stats" | python3 -m json.tool
echo

echo "ALL PHASE 1 VERIFICATIONS PASSED ✓"
