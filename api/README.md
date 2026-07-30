# TruthRelay — Relay API (Rust + Axum)

The middle tier: receives signed bulletins from moderators, deduplicates them,
exposes bulk sync for offline-first clients (mobile + web), and mints
moderator Ed25519 keypairs.

## Run

```bash
# 1. Start the API Relay Server
cargo run -- serve
# Default bind: 0.0.0.0:8080
# Default admin token: "change-me" (overridden by TRUTHRELAY_ADMIN_TOKEN)
```

## Mint & Register a Moderator Keypair

```bash
# 1. Mint an Ed25519 keypair
cargo run -- keygen --name "your-name"
```

Output (copy the JSON into Web Admin or Mobile App):

```json
{
  "name": "your-name",
  "public_key_b64": "...",
  "secret_key_b64": "...",
  "created_at": "...",
  "note": "..."
}
```

### Register the Moderator with the Relay
```bash
curl -X POST http://localhost:8080/api/v1/moderators \
  -H "Content-Type: application/json" \
  -H "X-Admin-Token: change-me" \
  -d '{"name":"your-name","public_key_b64":"<from keygen>"}'
```
*Note: The Web Dashboard auto-negotiates admin tokens automatically.*

## API

| Method | Path | Notes |
|--------|------|-------|
| GET    | /healthz | liveness |
| GET    | /api/v1/stats | row counts |
| POST   | /api/v1/moderators | register (admin) |
| GET    | /api/v1/moderators/{id} | fetch pubkey |
| POST   | /api/v1/bulletins | submit signed bulletin |
| GET    | /api/v1/bulletins | list recent |
| GET    | /api/v1/bulletins/{id} | get one |
| POST   | /api/v1/requests | submit a help request |
| GET    | /api/v1/requests | list recent |
| POST   | /api/v1/sync | bulk push from offline client |
| GET    | /api/v1/sync?since=<rfc3339>&limit=<n> | bulk pull |

See `docs/` in the repo root for the full schema.

## End-to-end test

```bash
# In one terminal
cargo run -- serve

# In another terminal
make test          # or: bash scripts/e2e.sh
```

The e2e script mints a key, registers, signs a bulletin (via `cryptography`
Python lib), POSTs it, asserts a 409 on duplicate, flips a bit in the signature
and asserts a 400, and round-trips through `/api/v1/sync`.

## Project layout

```
api/src/
├── main.rs              # clap dispatch (keygen | serve)
├── lib.rs               # run(), keygen(), build_router()
├── cli.rs               # clap structs
├── crypto.rs            # canonical JSON + Ed25519 verify
├── db.rs                # runs migrate.sql at startup
├── state.rs             # AppState { db, admin_token }
├── error.rs             # ApiError → IntoResponse
├── migrate.sql          # SQLite schema
└── features/            # feature-based modules
    ├── bulletins.rs     # POST/GET bulletins, signature verify, dedup
    ├── requests.rs      # POST/GET help requests
    ├── moderators.rs    # POST/GET moderator pubkeys
    ├── sync.rs          # POST/GET bulk sync
    └── system.rs        # /healthz, /api/v1/stats
```