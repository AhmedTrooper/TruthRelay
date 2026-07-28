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

Two parallel discovery radios keep phones visible even when no group has
formed yet. Wi-Fi Direct uses `flutter_p2p_connection` to advertise host
credentials over BLE and surface them as scanned peers. A second
BLE-only channel (`ble_discovery.dart`) broadcasts a 16-byte `MeshPeerAdvertisement`
containing a `TR1` magic, a version, our 9-byte peer id, and the local
item-count modulo 65536. Battery-conscious scan windows are 5 s on / 30 s
off by default. The BLE discovery layer is transport-pure: it does not
move packet payloads — that arrives in `ble_transport.dart`.

Once two phones have discovered each other they can synchronise over a
GATT carry (`BleMeshTransport`). Each `MeshPacket` JSON envelope is broken
into 4-byte-header frames (`[len:2][seq:2][payload:N]`, ≤180 bytes per
frame by default so the channel survives both BLE 4.x and BLE 5 MTU
quirks), reassembled on the receiver with a per-message timeout, deduped
at the chunk level, and a `BleByteChannel` interface so production can
bind to `flutter_blue_plus` GATT without dragging the plugin into unit
tests. The same `MeshTransport` interface that the Wi-Fi Direct transport
implements is reused unchanged.

When neither Wi-Fi Direct nor BLE can carry the volume of traffic —
older devices, restrictive ROMs, missing permissions — one phone can act
as a **local-only access point** via Android's
`WifiManager.startLocalOnlyHotspot()`. Other phones join the AP using
`WifiConfiguration`, then run the same `MeshTransport` session as the
Wi-Fi Direct transport. The framing is intentionally trivial: each
`MeshTransport` send produces a 4-byte big-endian length prefix followed
by UTF-8 payload bytes; outbound frames are split into 16 KiB chunks so
a single large send can never deadlock the kernel's TCP send buffer on
a slow receiver. A `HotspotChannel` byte-pipe interface keeps the
framing/reassembly logic pure Dart so unit tests cover the whole stack
without touching real sockets.

When a phone has connectivity but its neighbour does not, the connected
phone becomes a **carrier**: it receives the offline phone's queued
outbox (bulletins + help requests) over a local mesh transport and
forwards them to `/api/v1/mesh/forward`. Trust is enforced server-side —
every bulletin still must carry a valid Ed25519 signature from a
registered moderator, and each help request is deduplicated by `id`.
The same idempotent insertion path that `/api/v1/sync` uses is reused,
so the relay never sees a forwarded bulletin it didn't already
verify.

**Peer-hop verification.** A bulletin that travels only over the local
mesh never reaches the relay, so the server cannot vouch for it. Before
any peer-received bulletin is written to the local Hive store, the
mobile client recomputes the canonical JSON bytes and runs an Ed25519
verify against the moderator's public key (cached after the first
fetch, refreshed on `invalidate()`). The result is stored as a
`signatureVerified` flag: `true` ⇒ show VERIFIED SAFE, `false` ⇒
quarantine, `null` ⇒ server-supplied bulletin where the relay has
already vouched. The flag is recomputed on every `upsertMany`, so a
tampered payload arriving from a hostile peer can never launder a
prior `true` through the on-disk value.

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

The dashboard gives a 30-second read on the relay: KPI tiles with
freshness deltas, a pure-SVG donut of the bulletin-kind mix, a
signed-bulletin inspector that surfaces the canonical JSON bytes, the
`sha256` hash, and the Ed25519 signature that the server will verify. A
relay-health probe card measures the round-trip to `/api/v1/stats`,
auto-refreshes every 60 s when armed, and the theme persists across
sessions so the demo runs in either light or dark mode.

**Trust model.** Cryptographic, not centralized. A bulletin is *VERIFIED SAFE*
only if a registered moderator's Ed25519 signature passes on the server.
Unverified requests still travel — they're tagged *UNVERIFIED NEED* so
readers know what they're trusting.

**Why it wins.** The system is designed for the *exact moment* the internet
goes down. No feature requires a live connection. Sync is idempotent.
Everything is MIT-licensed, the binary footprint is tiny, and a single
`cargo run -- serve` boots the relay in under three seconds.