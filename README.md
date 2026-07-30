# TruthRelay

> **Verified crisis information over flaky networks, signed by humans you can name.**

TruthRelay is an offline-first mesh of crisis bulletins and help requests. It works
when the cellular fabric and the internet go down — exactly when trustworthy
information matters most. Inspired by *Jogajog* during the July Revolution in
Bangladesh.

Built in 72 hours by **TernaryOps** for the **Crisis Tech** track at
**JulyHackathon2026**. Repository: [AhmedTrooper/TruthRelay](https://github.com/AhmedTrooper/TruthRelay). Licensed MIT.

> 📄 **For the full deep-dive (architecture, trust model, transport layer, corner cases, and diagrams), read the [Project Report (PDF)](assets/report.pdf).**

---

## ⚡ Getting Started (Run in 30 Seconds)

### Requirements & Environment
- 🐳 **Docker & Docker Compose** (*Required*) — The API server (Rust/Axum/SQLite) and Web Dashboard (Vue 3/Vite/Nginx) run completely inside Docker containers. **No local Rust, Node, or Bun installations are needed.**
- 📱 **Android Studio & Flutter SDK** (*Optional*) — Only required if you plan to build or run the Android mobile application locally or on an emulator.

### Quick Start: Clone & Run
```bash
# 1. Clone the repository
git clone https://github.com/AhmedTrooper/TruthRelay.git
cd TruthRelay

# 2. Launch API + Web Admin
make up
```

- **Web Admin Dashboard**: [`http://localhost:5173`](http://localhost:5173)
- **API Relay Server**: [`http://localhost:8080`](http://localhost:8080)

### 🔄 Modifying Code (`make up` vs `make rebuild`)
- **`make up`**: Runs `docker compose up --build`. Automatically re-compiles modified HTML/CSS/JS or Rust source files when launching containers.
- **`make rebuild`**: Runs `docker compose build --no-cache`. Use this if you make major structural modifications or need to ensure a clean build without Docker layer caching.
- **`make up-bg`**: Runs `docker compose up -d --build` in background (detached) mode.
- **`make down`**: Stops running containers (`docker compose down`).

### 🌐 Finding Your Laptop's Local IP & Port

To connect physical Android devices or external devices to your laptop's API relay server, you need your laptop's local IP address and server port:

- **Server Port**: `8080` by default (API runs on port `8080`, Web on `5173`).

#### How to find your local IPv4 address by OS:

- **🐧 Linux (*Recommended Platform*)**:
  > *Linux is recommended because Docker runs natively without VM/virtualization overhead, providing maximum performance and seamless local network interface binding.*
  ```bash
  hostname -I | awk '{print $1}'
  # Or using iproute2:
  ip a | grep 'inet '
  ```
- **🍎 macOS**:
  ```bash
  ipconfig getifaddr en0   # Wi-Fi interface
  # Or for Ethernet:
  ipconfig getifaddr en1
  ```
- **🪟 Windows** (Command Prompt / PowerShell):
  ```cmd
  ipconfig
  # Look for "IPv4 Address" under your active Wi-Fi or Ethernet adapter (e.g., 192.168.1.5)
  ```

Once you have your IP (e.g., `192.168.1.5`), use `http://192.168.1.5:8080` as your `TRUTHRELAY_API_URL`.

### 📱 Building & Running the Android Mobile App

The Android app requires Flutter SDK and connects to the relay API via `TRUTHRELAY_API_URL`.

- **Default Target (`http://10.0.2.2:8080`)**: Pointed at host `localhost:8080` for the Android Emulator out-of-the-box.
- **Physical Device / Local Wi-Fi Mesh (`http://<YOUR_IP>:8080`)**: Pass your machine's IP address when running on physical devices or offline local hotspots.

```bash
# Option A: Run directly on connected Android device/emulator
cd mobile
flutter run --dart-define=TRUTHRELAY_API_URL=http://192.168.1.5:8080
# Or from root: make mobile-run API=http://192.168.1.5:8080

# Option B: Build standalone APK (Debug or Release)
cd mobile
flutter build apk --release --dart-define=TRUTHRELAY_API_URL=http://192.168.1.5:8080
# Output APK: mobile/build/app/outputs/flutter-apk/app-release.apk
# Or from root: make mobile-build API=http://192.168.1.5:8080
```

### 🛡️ How Moderator Registration & Bulletin Signing Works

Crisis updates in TruthRelay are cryptographically signed at the source with **Ed25519** signatures before being broadcast.

#### Step 1: Mint or Generate a Moderator Keypair
- **Option A (Web Dashboard — 1-Click Auto)**: Open `http://localhost:5173`, click **`+ Sign bulletin`** → Click **`⚡ Quick Generate & Register Keypair`**. This creates an Ed25519 keypair and registers it on the server automatically.
- **Option B (CLI)**: Run `cd api && cargo run -- keygen --name "Your Name"`. Copy the output JSON and paste it into the Web Admin under **Moderators** (`/moderators`).

#### Step 2: Server Registration (`POST /api/v1/moderators`)
- The server registers your `public_key_b64` under a generated `moderator_id` UUID using the `X-Admin-Token` header.
- The web dashboard auto-negotiates standard admin tokens (`dev-token-change-me`, `change-me`, etc.) and saves working tokens in `localStorage`.

#### Step 3: Sign & Post a Bulletin (`POST /api/v1/bulletins`)
1. In the Web Admin or Mobile App, compose your bulletin (Kind: *VerifiedUpdate* or *Debunk*, Title, Body).
2. The client constructs **byte-identical Canonical JSON** and signs it using your local `secret_key_b64`.
3. The server verifies the signature against your registered public key and broadcasts the bulletin to all connected peers!

#### Step 4: Mobile App Signing (Android)
- In the Android app, navigate to **Settings** (`/settings`) → Paste your Keypair JSON. Once saved in secure storage, bulletins composed on mobile are signed locally before being sent over Wi-Fi Direct/BLE mesh or synced to the relay.

### 🌐 How Information Spreads 100% Offline (Phone-to-Phone Mesh)

```
[ Laptop / Server ] 
        │ (Wi-Fi)
        ▼
   [ Phone A ]  ──(Walks into crisis zone)──► [ Phone B ] ──(P2P Hop)──► [ Phone C ] ──(P2P Hop)──► [ Phone D ]
   (Online Sync)                              (Offline Mesh)             (Offline Mesh)             (Offline Mesh)
```

1. **Ingestion**: Phone A connects to the laptop/relay over Wi-Fi and pulls verified bulletins.
2. **Walking Off-Grid**: Phone A walks into the blackout area where Phones B, C, and D have **no internet and no server connection**.
3. **BLE Discovery**: Phones automatically discover nearby devices via Bluetooth Low Energy (`TR1` protocol).
4. **Wi-Fi Direct Handoff**: Phones form peer-to-peer Wi-Fi Direct links (or dynamic local hotspots without routers) to exchange bulletins in milliseconds.
5. **Viral Cascade**: Information cascades phone-to-phone (A ➔ B ➔ C ➔ D) across the crisis area off-grid.
6. **Reverse Outbox**: Urgent help requests created on Phone D travel backwards (D ➔ C ➔ B ➔ A) and auto-upload to the relay as soon as Phone A reaches Wi-Fi/internet!

---

## Pitch & Documentation Materials

* [Problem Statement](docs/problem.md) — Why we built TruthRelay
* [Solution Architecture](docs/solution.md) — 400-word deep dive into the mesh and trust model
* [Demo Script](docs/demo-script.md) — Step-by-step 3-minute video guide
* [Slide Deck](docs/deck.md) — 8-slide presentation outline
* [Social Media Post](docs/social.md) — Ready-to-publish summary
* [Elevator Pitch](docs/pitch.md) — 25-word summary
* [Disclosures](docs/disclosures.md) — Open source attribution and tech stack

## What it does

- **Citizens (Android app)** compose and read blood requests, missing-person
  posts, and verified updates — fully offline, with a local Hive cache and an
  outbox that drains the moment connectivity returns.
- **Moderators (web admin / PWA)** sign bulletins with their Ed25519 key. Their
  public key lives on the relay under a moderator ID they choose the name of.
- **The relay (Axum + SQLite)** deduplicates by `sha256`, verifies every
  signature against the registered public key, and store-and-forwards so a phone
  that's been offline for hours can catch up in one round-trip.

### Can a phone post something when offline?

**Yes — and the post is guaranteed to reach the relay eventually, even if the
posting phone never sees the laptop again.** A post travels through three
independent triggers in parallel:

1. **Local write.** When the citizen taps "Post" on Phone D, the payload is
   appended to the local Hive `outbox` box. No network call is made. The app
   immediately shows the post in the local feed tagged as `UNVERIFIED NEED`.
2. **Three drain triggers** — whichever fires first wins:
   - **Direct hotspot.** The moment Phone D sees the laptop's Wi-Fi hotspot
     (3-second-debounced `connectivity_plus` callback),
     `SyncService.pushPending()` POSTs the outbox to `/api/v1/sync`. On a 200 it
     marks each row `markDone()`.
   - **Background sync.** `workmanager` runs a 15-minute periodic task gated by
     `NetworkType.CONNECTED`; same `pushPending() + pull()` call.
   - **Peer carry (the interesting one).** When Phone D is *out of range* of the
     hotspot, it gossips its outbox over BLE or Wi-Fi Direct to peer phones. Any
     phone that later reaches the laptop (Phone A in the canonical demo) calls
     `SyncService.forwardPeerOutbox(forwarderPeerId, peerOutbox)`, which POSTs
     the carried rows to `POST /api/v1/mesh/forward` with the bearer's peer-id
     for audit.
3. **Server-side dedupe.** `POST /api/v1/mesh/forward` runs the *same*
   idempotent Ed25519-verify + `sha256`-dedupe path as `/api/v1/sync`. The audit
   log records the `forwarder_peer_id` so the admin dashboard can distinguish
   "phone pushed its own outbox" from "phone carried a peer's outbox".

The offline phone does not need to mark its own outbox row done — the next time
it reaches the laptop, `pull()` returns the canonical record from the relay and
the local upsert collapses it.

## Why it matters

- Cellular fabric dies first in a crisis; trustworthy info matters most then.
- Trust without a central authority — signatures are over content, not over
  accounts.
- Offline-first on the phone; signed-at-source so a rumor can't be silently
  re-authored in transit.
- **HTTP + opportunistic local mesh** — talks to the relay over any IP link
  (Wi-Fi, satellite, fiber) and, when no internet is available, syncs over
  Wi-Fi Direct, BLE, or a local-only access point between nearby phones so a
  bulletin from one corner of the affected area can reach another corner that's
  been offline for hours.
- All three components produce **byte-identical canonical JSON** before
  signing, so signatures cross language boundaries cleanly.

### Offline mesh status

| Transport                                | Status       |
|------------------------------------------|--------------|
| Wi-Fi Direct (BLE discovery + group)     | discovery ✅ |
| Wi-Fi Direct (transport — handshake/sync)| transport ✅ |
| Mesh session state machine (hello/request/data/ack) | ✅ |
| Peer-driven coordinator (concurrency + backoff) | ✅ |
| BLE (discovery — 16-byte TR1 beacons)    | discovery ✅ |
| BLE (transport — chunked, MTU-aware)     | transport ✅ |
| Local-only hotspot (auto-fallback)       | transport ✅ |
| Relay forwarding (peer outbox via uplink) | endpoint ✅ |
| Ed25519 re-verification on every peer hop     | ✅        |
| Peer-sync UI (transport label, counters, sync now) | ✅ |
| Demo script (end-to-end offline workflow)   | ✅        |

### Web admin status

| Feature                                    | Status   |
|--------------------------------------------|----------|
| Light/dark theme toggle (persisted)        | ✅        |
| Dashboard KPIs with freshness delta        | ✅        |
| Bulletin-mix donut (pure SVG)              | ✅        |
| Signed-bulletin inspector (canonical JSON + sha256 + sig) | ✅ |
| Bulletin / Request search + kind filter    | ✅        |
| Relay health probe + latency chip          | ✅        |
| Auto-refresh every 60s (toggleable)        | ✅        |
| Peer-outbox forwarding UI (wired to commit 12) | ✅ |
| KPI count-up animation + value-change pulse | ✅ |
| Bulletin kind filter chips + signed-only toggle | ✅ |
| Mesh-forward audit log (localStorage, last 20) | ✅ |
| Vitest unit suite (theme, StatCard)        | ✅        |

## Architecture

```
   ┌──────────────────────────┐
   │  Vue 3 Admin / PWA       │   signs bulletins with Ed25519
   └──────────────┬───────────┘
                  │  HTTPS (when internet is up)
                  ▼
   ┌──────────────────────────┐
   │  Axum Relay + SQLite     │   verifies, dedups, store-and-forward
   └──────────────┬───────────┘
                  │  HTTPS (when phone is online)
                  ▼
   ┌──────────────────────────┐
   │  Flutter Android App     │   offline-first, outbox queue, Hive cache
   └────┬─────────────────────┘
        │  Wi-Fi Direct / BLE / Local-Only Hotspot
        │  (when no internet — gossip over BLE-advertised peers)
        ▼
   Neighbouring Flutter Android Apps — same mesh, same dedup
```

## Repo layout

| Folder    | Stack                                   | Purpose                              |
|-----------|------------------------------------------|--------------------------------------|
| `api/`    | Rust + Axum + SQLite + ed25519-dalek    | Relay server + `keygen` CLI          |
| `web/`    | Vue 3 + Naive UI + Vite PWA + bun       | Admin dashboard (installable PWA, dark/light, Vitest) |
| `mobile/` | Flutter (Android) + Riverpod + Hive     | Citizen-side app                     |

## Quickstart — Docker (one command)

```bash
# from repo root
docker compose up -d --build

# Web admin → http://localhost:5173
# API relay → http://localhost:8080
docker compose logs -f      # tail logs
docker compose down -v      # tear down + delete persisted SQLite
```

Override ports and the admin token via `.env` (copy `.env.example`):

```bash
TRUTHRELAY_ADMIN_TOKEN=secret \
TRUTHRELAY_WEB_PORT=8080  TRUTHRELAY_API_PORT=9000 \
docker compose up -d --build
```

Behind the scenes, the `web` container ships an nginx that reverse-proxies
`/api/*` to the `api` container on port 8080 — so the SPA only ever talks to
its own origin and you never see CORS in the browser.

## Quickstart — bare metal

```bash
# 1. Relay server (Rust)
cd api
cargo run -- keygen --name demo                 # prints {public_key_b64, secret_key_b64}
TRUTHRELAY_BIND=0.0.0.0:8080 TRUTHRELAY_DB=./truthrelay.db \
  TRUTHRELAY_ADMIN_TOKEN=demo cargo run -- serve

# 2. Admin dashboard (Vue)
cd ../web
bun install
VITE_API_URL=http://localhost:8080 bun run dev   # http://localhost:5173

# 3. Mobile app (Flutter, Android only)
cd ../mobile
flutter pub get
flutter run -d <android-device>
```

When the Android emulator can't reach `localhost`, point it at the host
machine: `flutter run --dart-define=TRUTHRELAY_API_URL=http://10.0.2.2:8080`.

## The 100% Offline Edge-Node Setup (Crisis Scenario)

This project is built so that you can run it entirely without a global internet connection. In a crisis, your laptop becomes the "edge server" and mobiles act as a viral mesh network.

Here is exactly how everything runs completely offline:

1. **Docker just needs to compile (No external DBs):** Because we use SQLite, we don't need Postgres or Redis. Docker simply downloads its basic language environment (Rust, Bun, Debian) to compile the code locally on your laptop. Once compiled, it runs 100% off-grid.
2. **Expose the local server on your laptop:** Start a local Wi-Fi hotspot on your laptop. The API **must** be exposed so phones can reach it. By setting `TRUTHRELAY_BIND=0.0.0.0:8080`, you expose the server to anyone on your local network.
3. **Find your laptop's IP and Port:** The API defaults to port `8080`. Find your IPv4 address:
   - **Linux (*Recommended*)**: `hostname -I | awk '{print $1}'` or `ip a | grep 'inet '`
   - **macOS**: `ipconfig getifaddr en0` (or `en1`)
   - **Windows**: `ipconfig` (look for `IPv4 Address`)
4. **Inject the environment variables into Flutter:** You must explicitly tell the Flutter app where your laptop's local server is located, otherwise it defaults to localhost. You inject this during the build or run step using `--dart-define`:
   ```bash
   cd mobile
   # Replace with your actual laptop IP and Port!
   flutter run -d <device> --dart-define=TRUTHRELAY_API_URL=http://192.168.1.5:8080
   ```
5. **The Viral Mesh Begins:** 2, 3, or 10 mobiles walk up to the laptop's Wi-Fi hotspot and pull the data. They then walk away deeper into the crisis zone. From there, **mobile-to-mobile sync occurs via BLE and Wi-Fi Direct**, completely independent of the laptop!

## Per-component Make targets

The repo is coordinated by a top-level `Makefile` (run `make` to list targets).

### Top-level orchestration

| Target          | Effect                                                            |
|-----------------|-------------------------------------------------------------------|
| `make up` (or `docker-up`) | `docker compose up --build` (runs in foreground, auto-rebuilds modified code) |
| `make up-bg`    | `docker compose up -d --build` (runs in background with forced rebuild) |
| `make down`     | `docker compose down`                                             |
| `make rebuild`  | `docker compose build --no-cache`                                 |
| `make logs`     | `docker compose logs -f`                                          |
| `make dev`      | Two terminals: `make dev-api` + `make dev-web`                    |
| `make dev-api`  | Run only the api (`cargo run -- serve`)                           |
| `make dev-web`  | Run only the web (Vite + HMR on 5173)                             |
| `make test`     | Run `api-test` + `mobile-test` (does **not** run `web-test`)      |
| `make build`    | Build api release + web prod + apk debug                          |
| `make clean`    | Remove build artifacts in all three subprojects                   |
| `make reset`    | Nuke local DBs + build outputs + stop containers                   |

### Per-component shortcuts

| Shortcut          | Effect                              |
|-------------------|-------------------------------------|
| `make api`        | List `api/Makefile` targets         |
| `make api-dev`    | `cd api && make dev`                |
| `make api-test`   | `cd api && make test`               |
| `make api-build`  | `cd api && make build`              |
| `make api-keygen NAME=alice` | Mint a keypair for `alice`  |
| `make web`        | List `web/Makefile` targets         |
| `make web-dev`    | `cd web && make dev`                |
| `make web-build`  | `cd web && make build`              |
| `make web-test`   | `cd web && make test` (needs API)   |
| `make mobile`     | List `mobile/Makefile` targets      |
| `make mobile-run` | `cd mobile && make run`             |
| `make mobile-build` | `cd mobile && make build`         |
| `make mobile-test` | `cd mobile && make test`           |

To run every suite end-to-end:

```bash
make api-test web-test mobile-test
```

(`make test` is intentionally web-test-free — the web canonical test needs a
running relay. Run `make api-dev` in another terminal first, or use `make up`.)

---

## API reference

Base URL when bare-metal: `http://localhost:8080`. Inside Docker the web nginx
proxies `/api/*` to the api container, so the SPA hits the same origin.

### System

| Method | Path             | Body | Returns                              |
|--------|------------------|------|--------------------------------------|
| `GET`  | `/healthz`       | —    | `200 {"status":"ok"}`                |
| `GET`  | `/api/v1/stats`  | —    | `200 {"bulletins":n,"moderators":n,"requests":n}` |

### Moderators

| Method | Path                              | Headers                | Body                                  | Returns                                  |
|--------|-----------------------------------|------------------------|---------------------------------------|------------------------------------------|
| `POST` | `/api/v1/moderators`              | `X-Admin-Token: <tok>` | `{name, public_key_b64}`              | `201 {id, name, public_key_b64, created_at}` |
| `GET`  | `/api/v1/moderators/{id}`         | —                      | —                                     | `200 {...}` / `404`                       |

`POST /api/v1/moderators` is the **only** endpoint that requires admin auth.
Everything else is open.

### Bulletins (signed)

| Method | Path                              | Body                                      | Returns                                          |
|--------|-----------------------------------|-------------------------------------------|--------------------------------------------------|
| `POST` | `/api/v1/bulletins`               | `SignedBulletin` (see below)              | `201` / `400 invalid_signature` / `409 duplicate` |
| `GET`  | `/api/v1/bulletins`               | —                                         | `200 {items, next_cursor}`                       |
| `GET`  | `/api/v1/bulletins/{id}`          | —                                         | `200 {...}` / `404`                              |

```jsonc
// POST /api/v1/bulletins
{
  "moderator_id": "<uuid>",
  "payload": {
    "kind": "Blood | Missing | VerifiedUpdate | Debunk | Supply",
    "title": "<≤120 chars>",
    "body":  "<≤4000 chars>",
    "created_at": "<RFC3339>"
  },
  "signature_b64": "<base64 64-byte Ed25519 signature>"
}
```

### Help requests (unsigned — anyone can post)

| Method | Path                              | Body                                                  | Returns                       |
|--------|-----------------------------------|-------------------------------------------------------|-------------------------------|
| `POST` | `/api/v1/requests`                | `HelpRequest`                                         | `201` / `409 duplicate (id)`  |
| `GET`  | `/api/v1/requests`                | —                                                     | `200 {items, next_cursor}`    |

```jsonc
// POST /api/v1/requests
{
  "id": "<client-uuid>",
  "kind": "Blood | Supply | Missing",
  "title": "...",
  "body":  "...",
  "location": "free text | null",
  "contact":  "free text | null",
  "created_at": "<RFC3339>"
}
```

### Sync (offline-first round-trip)

| Method | Path                                                | Body                  | Returns                                                              |
|--------|-----------------------------------------------------|-----------------------|----------------------------------------------------------------------|
| `GET`  | `/api/v1/sync?since=<rfc3339>&limit=<1..1000>`      | —                     | `200 {bulletins, requests, server_time}` (server_time = RFC3339 now) |
| `POST` | `/api/v1/sync`                                      | `{bulletins, requests}` | `200 {accepted, duplicates}`                                       |

`since` defaults to `1970-01-01T00:00:00Z` (i.e. everything). `limit` is
clamped to `[1, 1000]`. `POST /sync` is the phone's outbox drain — it accepts
any subset of bulletins and requests in one round-trip and returns counters
so the client can mark each row `done` or `failed`.

---

## Canonical-JSON contract

This is the wire-format dictator. All three implementations must produce
**byte-identical** bytes for the same payload. Rust verifies signatures
against these exact bytes; the web and mobile clients sign them.

```
canonicalBytes(payload) =
  '{"body":"...","created_at":"...","kind":"...","title":"..."}'
```

Rules: keys sorted alphabetically (recursively, including inside arrays of
objects), no whitespace, no trailing newline.

Implementations:

- **Rust** — `api/src/crypto.rs::canonical_bulletin_bytes`
- **Web** — `web/src/lib/canonical.ts::canonicalBulletin`
- **Mobile** — `mobile/lib/core/canonical.dart::canonicalBulletin`

The contract is asserted by two tests:

- `web/scripts/canonical-test.ts` — mints a key, canonicalizes + signs in
  TypeScript, POSTs to a live api, asserts HTTP 201.
- `mobile/test/canonical_sign_test.dart` — asserts a fixed byte literal
  against `canonicalBulletin(...)`.

## Signature scheme

1. `bytes = canonicalBytes(payload)` (RFC3339 `created_at` is part of the
   signed bytes — timestamps are tamper-evident).
2. `sig = ed25519.sign(secretKey, bytes)` → 64 bytes.
3. Base64-encode `sig` → `signature_b64`.
4. POST to `/api/v1/bulletins` with `{moderator_id, payload, signature_b64}`.
5. Server looks up `public_key` for `moderator_id`, recomputes canonical
   bytes, calls `ed25519.verify(pubkey, bytes, sig)`.

Failure modes the server returns:

| Condition               | HTTP | Code                |
|-------------------------|------|---------------------|
| Moderator ID not found  | 400  | `unknown_moderator` |
| Signature doesn't match | 400  | `invalid_signature` |
| `sha256` already seen   | 409  | `duplicate`         |

## Routes — web admin

`vue-router`, history mode. Five routes:

| Path           | View                              |
|----------------|-----------------------------------|
| `/`            | Dashboard (stats + recent items)  |
| `/bulletins`   | Bulletins table + new-bulletin modal |
| `/requests`    | Help requests list                |
| `/moderators`  | Paste-secret wizard (writes to localStorage) |
| `/sync`        | Push queued / pull since          |

The web client auto-attaches `X-Admin-Token` to POSTs ending in
`/moderators`, so you only have to paste the token once.

## Routes — mobile

`go_router`. Six routes:

| Path                       | View                          |
|----------------------------|-------------------------------|
| `/`                        | Home feed (bulletins + requests) |
| `/compose`                 | Compose a new bulletin or help request |
| `/sync`                    | Sync screen (push outbox + pull since) |
| `/settings`                | Moderator key + admin token   |
| `/detail/bulletin/:id`     | Single bulletin view          |
| `/detail/request/:id`      | Single help request view      |

---

## End-to-end demo walkthrough

1. `make up` (or the bare-metal trio from "Quickstart").
2. Mint a key on the api host:
   ```bash
   cd api && cargo run -- keygen --name demo
   # → JSON with public_key_b64 + secret_key_b64
   ```
3. Open the web admin → `/moderators` → paste the JSON → "Register".
   The web stores `secret_key_b64` in `localStorage`.
4. Open `/bulletins` → compose a `VerifiedUpdate` ("Hospital A is open") →
   sign + POST → 201 → appears in the table.
5. Refresh the page — the bulletin is still there (SQLite persistence).
6. On the Android emulator: open the app, compose a `Blood` help request,
   tap Save. The local Hive box + outbox get the new entry.
7. Toggle airplane mode on the emulator → re-open the app → still works.
8. Toggle Wi-Fi back on → `/sync` → "Push" → outbox drains → 200.
9. On the host: `curl http://localhost:8080/api/v1/requests` → the help
   request is present.
10. Sign a new bulletin in the web admin → mobile `/sync` → "Pull" → it
    appears in the feed.

## Status badges

Both UIs render a colored badge on every row. Real labels from
`web/src/components/StatusBadge.vue` and `mobile/lib/widgets/status_badge.dart`:

| Label              | Color    | When                                              |
|--------------------|----------|---------------------------------------------------|
| `VERIFIED`         | emerald  | Signed by a registered moderator (`verified` prop) |
| `VERIFIED UPDATE`  | sky      | `kind = VerifiedUpdate`                            |
| `DEBUNKED`         | rose     | `kind = Debunk`                                    |
| `MISSING`          | amber    | `kind = Missing`                                   |
| `BLOOD`            | rose     | `kind = Blood`                                     |
| `SUPPLY`           | violet   | `kind = Supply`                                    |
| (default)          | slate    | Anything else                                      |

The `verified` prop toggles the dot and emerald coloring regardless of kind,
so a signed `Blood` request reads as `VERIFIED · BLOOD` in the UI.

---

## Offline-first mechanics (mobile)

- **Local store** — one Hive box per feature (`bulletins`, `requests`,
  `outbox`, `settings`). Boxes are opened lazily by
  `data/storage/hive_boxes.dart` and shared across the app via Riverpod
  providers.
- **Compose** → write to the local box + enqueue an `outbox` row with
  `status='pending'`.
- **`SyncService.drain()`** reads rows where `status='pending' OR (status='failed'
  AND attempts<5)`, POSTs the batch to `/api/v1/sync`, and:
  - 2xx → mark `done`.
  - 4xx → mark `failed` (will retry up to 5 times).
  - 5xx / network → keep `pending`, exponential backoff.
- **Pull** — `GET /api/v1/sync?since=<last_server_time>&limit=200`, then merge
  by id (server wins on conflict).

## Crypto + identity model

- A **moderator** is an Ed25519 keypair. The public key is registered
  server-side under a `moderator_id` chosen by the admin token holder.
- The secret key **never leaves** the device that mints it — web stores it in
  `localStorage`, mobile stores it in `flutter_secure_storage`.
- The server is **not a CA**. It only stores the public key and trusts whoever
  the admin token holder registers. That trust boundary is documented and
  intentional.
- Trust ladder:
  1. **Server is honest** ⇒ it stores public keys faithfully and only relays
     bulletins that pass `verify(public_key, canonical_bytes, signature)`.
  2. **Signature verifies** ⇒ the bulletin was produced by the holder of the
     secret key corresponding to `moderator_id`.
  3. **Holder of the secret key is trustworthy** ⇒ the *content* is
     trustworthy. This is the moderator's job — hence the registry.

---

## Project layout

```
api/
├── src/
│   ├── cli.rs                    # clap subcommands: serve | keygen
│   ├── lib.rs                    # Router + app wiring
│   ├── crypto.rs                 # canonical_bulletin_bytes + verify_bulletin
│   ├── db.rs                     # sqlite init + migrate
│   ├── error.rs                  # ApiError → IntoResponse
│   ├── state.rs                  # AppState { db, admin_token }
│   ├── migrate.sql               # moderators, bulletins, help_requests, seen_packets
│   └── features/
│       ├── system.rs             # /healthz, /api/v1/stats
│       ├── moderators.rs         # /api/v1/moderators
│       ├── bulletins.rs          # /api/v1/bulletins (signed)
│       ├── requests.rs           # /api/v1/requests (help, unsigned)
│       └── sync.rs               # POST + GET /api/v1/sync
├── scripts/e2e.sh                # Phase-1 exit-criteria smoke test
├── Cargo.toml                    # no hardcoded versions — cargo add
├── Dockerfile                    # multi-stage Rust → debian-slim
└── Makefile

web/
├── src/
│   ├── main.ts                   # Vue + Pinia + naive-ui + router + SW
│   ├── App.vue
│   ├── router/index.ts           # 5 routes
│   ├── lib/
│   │   ├── canonical.ts          # canonicalBulletin()
│   │   ├── crypto.ts             # signBulletin() — @noble/ed25519
│   │   └── api/
│   │       ├── client.ts         # axios + X-Admin-Token injector
│   │       └── endpoints.ts
│   ├── stores/                   # Pinia: moderator, api, sync
│   ├── features/                 # feature-based, no god modules
│   │   ├── dashboard/
│   │   ├── bulletins/            # table + new-bulletin modal
│   │   ├── requests/
│   │   ├── moderators/           # paste-secret wizard
│   │   └── sync/
│   └── components/
│       └── StatusBadge.vue       # the real badge logic
├── scripts/canonical-test.ts     # cross-language signature check
├── vite.config.ts                # vite-plugin-pwa (autoUpdate)
├── package.json                  # no hardcoded versions — bun add
├── nginx.conf                    # /api → api:8080 reverse proxy
├── Dockerfile                    # bun build → nginx:alpine
└── Makefile

mobile/
├── lib/
│   ├── main.dart                 # ProviderScope + MaterialApp.router
│   ├── core/
│   │   ├── canonical.dart        # canonicalBulletin()
│   │   ├── crypto.dart           # signBulletin() — package:cryptography
│   │   ├── env.dart              # TRUTHRELAY_API_URL
│   │   ├── providers.dart        # Riverpod providers
│   │   └── router.dart           # go_router — 6 routes
│   ├── data/
│   │   ├── api/                  # Dio client + endpoint wrappers
│   │   └── storage/hive_boxes.dart
│   ├── features/                 # feature-based, no god modules
│   │   ├── home/                 # feed
│   │   ├── compose/              # bulletin + help-request forms
│   │   ├── bulletins/            # repository + view
│   │   ├── requests/             # repository + view
│   │   ├── detail/               # bulletin + request detail
│   │   ├── sync/                 # outbox + sync service
│   │   └── settings/             # moderator secret + admin token
│   └── widgets/status_badge.dart # matches web
├── test/canonical_sign_test.dart # asserts fixed byte literal
├── pubspec.yaml                  # no hardcoded versions — flutter pub add
└── Makefile
```

---

## Docker

`docker-compose.yml` runs two services on a dedicated `truthrelay-net` bridge:

| Service | Image             | Internal port | Host port (default) | Healthcheck         |
|---------|-------------------|---------------|---------------------|---------------------|
| `api`   | `truthrelay-api`  | 8080          | `${TRUTHRELAY_API_PORT:-8080}` | `curl /healthz`     |
| `web`   | `truthrelay-web`  | 80 (nginx)    | `${TRUTHRELAY_WEB_PORT:-5173}` | `wget /`            |

Named volumes `api-data` and `api-keys` persist SQLite + moderator keys
across rebuilds. `web` depends on `api` being `service_healthy` before it
boots, so the SPA never starts against a half-warm backend.

## Tests

| Suite          | What it asserts                                              | Needs server? |
|----------------|--------------------------------------------------------------|---------------|
| `make api-test`     | 12-step e2e (healthz, stats, keygen, register, sign, post, dedup, tamper, sync) | No (boots its own on 8080) |
| `make web-test`     | TS canonicalizer produces bytes that the running api accepts | Yes (`:8080`) |
| `make mobile-test`  | Dart canonicalizer produces a fixed byte literal + sign/verify round-trip | No |

Run all three: `make api-test web-test mobile-test`.

## Disclosures

Tech stack, third-party libraries, and AI tools used are documented in
[`docs/disclosures.md`](docs/disclosures.md).

---

## ⚠️ Current Limitations & Future Roadmap

> 💡 **Core Crisis Architecture Note**: Absence of internet connectivity is **NOT** a system limitation—it is the foundational design mandate of TruthRelay. The entire system is engineered for 100% off-grid deployment using self-hosted local laptop hotspots, local SQLite/Hive storage, Bluetooth Low Energy (BLE), and Wi-Fi Direct multi-hop peer-to-peer gossip.

| # | Current Limitation | Impact | Planned Future Solution |
|---|---|---|---|
| **1** | **Soft-AP Hotspot Client Limit** | Android `WifiManager` limits soft-AP hotspot connections to ~8–10 devices. | **Tree-Structured Mesh Routing**: Upgrade to hierarchical multi-hop tree routing over BLE/Wi-Fi Direct. |
| **2** | **Continuous Scanning Battery Drain** | Active BLE scanning consumes ~18–22% battery over a 12-hour session. | **Screen-Off Duty Throttling**: Throttle BLE scan duty cycles (5s scan / 60s sleep when screen is off) to drop drain <5%. |
| **3** | **Unsigned Citizen Requests** | Bulletins are signed with Ed25519; help requests are unverified needs (`UNVERIFIED NEED`). | **Per-User Ed25519 Client Signing**: Issue per-user keypairs in app storage so citizen requests carry signatures. |
| **4** | **Out-of-Band Key Rotation** | Rotating a moderator key requires clearing the local key repository. | **Mesh Key Rotation Protocol**: Broadcast `MODERATOR_PUBKEY_ROTATED` mesh packets to auto-invalidate stale pubkeys. |
| **5** | **Cleartext Peer Transfer** | P2P packets travel unencrypted between local phones. | **E2EE Mesh Encryption**: Implement X25519 key exchange + ChaCha20-Poly1305 per-hop encryption. |

## Submission pointers

| Asset               | File                                     |
|---------------------|------------------------------------------|
| 25-word pitch       | `docs/pitch.md`                          |
| 200-word problem    | `docs/problem.md`                        |
| 400-word solution   | `docs/solution.md`                       |
| Slide deck (6–10)   | `docs/deck.md`                           |
| 3-min demo script   | `docs/demo-script.md`                    |
| Facebook post       | `docs/social.md`                         |
| Tech disclosures    | `docs/disclosures.md`                    |
| Full project report | [`assets/report.pdf`](assets/report.pdf) |

## License

MIT — see [`LICENSE`](LICENSE).