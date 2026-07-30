# TruthRelay — Slide Deck

> Markdown source. Convert to PDF with marp / Pandoc / Google Slides.

---

## Slide 1 — Problem

**When the network goes down, trustworthy information goes with it.**

- Cellular blackouts during the July Revolution in Bangladesh cut off
  citizens from blood requests, missing-person posts, and verified safe-route
  updates.
- "Jogajog" word-of-mouth relays worked but were unauthenticated, and panic
  traveled faster than facts.
- The Crisis Tech track rewards tools that work when normal infrastructure
  fails.

---

## Slide 2 — Solution

**TruthRelay: verified crisis info when there is no internet at all.**

Three tiers, all offline-first by mandate:
1. Flutter Android app — citizens post & read bulletins, fully usable offline.
2. Rust + Axum relay — store-and-forward with Ed25519 signature verification.
3. Vue 3 admin PWA — moderators sign bulletins in their browser.

A single laptop runs the relay, the admin, and a local-only Wi-Fi hotspot.
Phones join the hotspot, talk to the relay at `http://<laptop-ip>:8080`, and
gossip to each other over Wi-Fi Direct or BLE when out of range.

---

## Slide 3 — Architecture (100% offline deployment)

```
                  ┌─────────────────────────────────────────────┐
                  │  Laptop (no internet)                       │
                  │  ┌─────────────┐  /api/* ┌──────────────┐  │
                  │  │ Axum + SQLite│◄────────┤ nginx → Vue 3 │  │
                  │  │ 0.0.0.0:8080 │  proxy  │    PWA admin  │  │
                  │  └──────┬──────┘         └──────┬───────┘  │
                  │         │                       │          │
                  │         └───── Local-only Wi-Fi hotspot ───┘
                  │                       │
                  │            ┌──────────┴──────────┐
                  │            ▼                     ▼
                  │       Phone A              Phone B
                  │       (on hotspot)         (on hotspot)
                  │            │ Wi-Fi Direct / BLE gossip
                  │            ▼                     ▼
                  │       Phone D              Phone C
                  │       (out of AP range)    (out of AP range)
                  └─────────────────────────────────────────────┘
```

Solid arrows = HTTP to the laptop hotspot. Dashed arrows = peer gossip
(Wi-Fi Direct / BLE).

---

## Slide 4 — Offline-First Flow

A post travels through three independent triggers in parallel:

1. **Local write.** Tap "Post" → payload appended to the local Hive `outbox`
   box. No network call. The app shows the post immediately, tagged
   `UNVERIFIED NEED`.
2. **Three drain triggers — whichever fires first wins:**
   - **Direct hotspot.** Phone re-joins the laptop's hotspot → 3-second-debounced
     `connectivity_plus` callback → `SyncService.pushPending()` POSTs the
     outbox to `/api/v1/sync`.
   - **Background sync.** `workmanager` fires every 15 minutes (when
     `NetworkType.CONNECTED`) — same `pushPending() + pull()` call.
   - **Peer carry.** Phone is out of range → gossips its outbox over BLE or
     Wi-Fi Direct to peer phones. Any phone that later reaches the laptop
     POSTs the carried rows to `/api/v1/mesh/forward` with its peer-id for
     audit.
3. **Server-side dedupe.** `POST /api/v1/mesh/forward` runs the *same*
   idempotent Ed25519-verify + `sha256`-dedupe path as `/api/v1/sync`, so a
   forwarded post is never re-verified against a different rule.

---

## Slide 5 — Trust Model

| Badge | Meaning |
|---|---|
| **VERIFIED SAFE** | Ed25519 signature from a registered moderator (verified locally on every peer hop) |
| **DEBUNKED / FAKE** | Moderator-signed correction |
| **UNVERIFIED NEED** | Unsigned help request (blood, missing, supply) |

- Signatures computed over **canonical JSON** — sorted keys, no whitespace.
- Same canonicalizer in Rust, Web, and Dart — verified by tests.
- Moderator keys minted via `cargo run -- keygen`, registered via the admin
  PWA (one click).

---

## Slide 6 — Tech Stack & Footprint

| Component | Stack | Binary |
|---|---|---|
| Relay | Rust + Axum + SQLite (WAL) | 5.6 MiB single static binary |
| Admin | Vue 3 + Naive UI + Vite | nginx-served static SPA, same laptop |
| Mobile | Flutter + Hive + Riverpod | Android 5.0+, ~15 MB debug APK |

All MIT-licensed. No paid SaaS, no telemetry, no third-party auth.

---

## Slide 7 — Demo (8 steps, two physical phones)

1. Both phones join the laptop's hotspot → pull moderator bulletin via
   `/api/v1/sync`.
2. Phone A posts a help request — laptop has no internet, the relay still
   accepts it.
3. Move Phone B out of the hotspot → the two phones sync over Wi-Fi Direct;
   the bulletin and request cross the air gap.
4. Disable Wi-Fi Direct; the same scenario survives over a soft-AP
   (`startLocalOnlyHotspot`).
5. Bring the carrier phone back near the laptop → it drains the peer's
   outbox through `/api/v1/mesh/forward`; the admin UI shows the forwarded
   rows.
6. Flip a signature on the wire; the receiving phone marks the bulletin
   QUARANTINED.
7. Run a clock-injected `RetentionPolicy` on a synthetic 2000-row load;
   observe the cap and the 72h/14d TTL hold.
8. Kill the app; within 15 minutes the outbox drains via `workmanager`
   whenever the laptop's hotspot is reachable.

---

## Slide 8 — What's Next

**Now (v1, shipped):**
- Single binary relay, single moderator tier, Ed25519-signed bulletins.
- Thrice-redundant outbox drain (direct / background / peer-carry).
- Phone-to-phone gossip over Wi-Fi Direct / BLE / local-only hotspot.
- Anonymous, idempotent sync — already survives the demo above.

**Next:**
- Per-user Ed25519 keys for help requests (currently `UNVERIFIED`-tagged).
- E2E encryption on the mesh transport (X25519 + ChaCha20-Poly1305).
- `MODERATOR_PUBKEY_ROTATED` gossip invalidation for moderator key rotation.
- WebAuthn / hardware-key moderator signing.

**Built for Bangladesh, useful everywhere the network drops.**
