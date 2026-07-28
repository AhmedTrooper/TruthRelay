# Solution (400 words)

TruthRelay is a **three-tier offline-first crisis-information system**.
It runs on Android phones, in a web browser, and on a tiny Rust server
— and it is built to *degrade gracefully* the moment the network drops.

**Architecture.**

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  Vue 3 Admin PWA │    │ Axum (Rust) +    │    │ Flutter Android  │
│  Naive UI        │◄──►│ SQLite (WAL)     │◄──►│ Hive + outbox    │
│  Ed25519 signer  │    │ store-and-forward│    │ go_router        │
└──────────────────┘    └──────────────────┘    └─────┬────────────┘
                                                     │
                                          Wi-Fi Direct (BLE discovery)
                                          BLE small-payload
                                          Local-only hotspot
                                                     │
                                             neighbouring phones
                                          (same dedup, same sig checks)
```

The **Flutter mobile app** is the citizen-side interface. Every screen reads
from a local Hive cache, so the app is fully usable with airplane mode on.
Every write is appended to an **outbox** table that drains opportunistically
when any connectivity appears — local Wi-Fi, mobile data, even an Axum
hotspot opened on a laptop. Each outbox row carries a client-generated UUID,
so the relay can dedupe across phones without coordination.

The mesh layer adds **gossip-style peer sync** for the case when *no* uplink
is available. Phones advertise themselves over BLE; nearby phones form a
Wi-Fi Direct group, swap bloom-filter inventories plus a compact id list
(via a `MeshHello` envelope), exchange the bulletins each side is missing
as signed JSON `MeshData` envelopes, and ack each one with `MeshAck`.
A 32-byte packet id per envelope, persisted in a tiny `mesh_seen` Hive
box, deduplicates retransmits across the gossip. A peer-driven
`MeshCoordinator` watches for newly-discovered peers and spawns a
dedicated `MeshSession` per peer with a configurable concurrency cap and
5-minute per-peer backoff, so the same neighbour can't trigger a tight
loop of re-syncs. Every bulletin is re-verified against the moderator's
registered public key on every hop — VERIFIED status is computed locally,
never trusted from a peer's word.

The **Axum relay** is a single Rust binary with a SQLite WAL database.
It exposes three primitives: `POST /api/v1/bulletins`, `POST /api/v1/requests`,
and `POST /api/v1/sync` for bulk push/pull. Bulletins carry an Ed25519
signature; the relay re-verifies the signature against the moderator's
registered public key before persisting. Duplicate content is rejected by
`sha256` (bulletins) or `id` (requests).

The **Vue admin PWA** lets trusted moderators sign bulletins with the
keypair minted by the relay's `keygen` CLI. The same canonical-JSON function
that the relay uses for verification runs in the browser, so the signature
is computed over the exact bytes the server will hash. Verified bulletins
flow back into the mobile feed on the next sync.

**Trust model.** Cryptographic, not centralized. A bulletin is *VERIFIED SAFE*
only if a registered moderator's Ed25519 signature passes on the server.
Unverified requests still travel — they're tagged *UNVERIFIED NEED* so
readers know what they're trusting.

**Why it wins.** The system is designed for the *exact moment* the internet
goes down. No feature requires a live connection. Sync is idempotent.
Everything is MIT-licensed, the binary footprint is tiny, and a single
`cargo run -- serve` boots the relay in under three seconds.