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

**TruthRelay: verified crisis info over flaky networks, signed by humans you can name.**

Three tiers, all offline-first:
1. Flutter Android app — citizens post & read bulletins, fully usable offline.
2. Rust + Axum relay — store-and-forward with Ed25519 signature verification.
3. Vue 3 admin PWA — moderators sign bulletins in their browser.

---

## Slide 3 — Architecture

```
[ Vue 3 Admin / PWA ]   ← signs with Ed25519
        ↓ HTTPS (when online)
[ Axum (Rust) + SQLite ]  ← verifies, dedups, store-and-forward
        ↓ HTTPS (when phone is online)
[ Flutter Android App ]   ← offline-first, outbox queue, Hive cache
```

---

## Slide 4 — Offline-First Flow

1. Compose a help request → saved to local Hive + outbox table.
2. App stays usable in airplane mode.
3. Network returns → **Sync** screen drains outbox.
4. Server dedupes by `id` (UUID) and `sha256` (bulletin payload).
5. Other phones pull the new bulletin on their next sync.

---

## Slide 5 — Trust Model

| Badge | Meaning |
|---|---|
| **VERIFIED SAFE** | Ed25519 signature from a registered moderator |
| **DEBUNKED / FAKE** | Moderator-signed correction |
| **UNVERIFIED NEED** | Unsigned help request (blood, missing, supply) |

- Signatures computed over **canonical JSON** — sorted keys, no whitespace.
- Same canonicalizer in Rust, Web, and Dart — verified by tests.
- Moderator keys minted via `cargo run -- keygen`, registered once.

---

## Slide 6 — Tech Stack & Footprint

| Component | Stack | LoC | Binary |
|---|---|---|---|
| Relay | Rust + Axum + SQLite | ~600 | single static binary |
| Admin | Vue 3 + Naive UI + Vite | ~600 | PWA, 700 KB precache |
| Mobile | Flutter + Hive + go_router | ~700 | ~15 MB debug APK |

All MIT-licensed. No paid SaaS, no telemetry, no third-party auth.

---

## Slide 7 — Demo

- App offline → compose "Blood O+ needed" → entry visible locally.
- Toggle online → **Push** → server records it (`/api/v1/requests`).
- Moderator signs a "Hospital A open" bulletin in the web admin.
- Mobile **Pull** → bulletin appears with **VERIFIED SAFE** badge.
- Airplane mode again → app still serves both entries from cache.

---

## Slide 8 — Impact & Roadmap

**Now (v1):**
- Single binary relay, single moderator tier, Ed25519-signed bulletins.
- Anonymous, idempotent sync — already survives the demos above.

**Next:**
- BLE / Wi-Fi Direct device-to-device mesh (no relay hop).
- End-to-end encrypted message bodies (signatures provide authenticity, not
  confidentiality).
- WebAuthn / hardware-key moderator signing.

**Built for Bangladesh, useful everywhere the network drops.**