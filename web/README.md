# TruthRelay — Web Admin Dashboard

Vue 3 + Naive UI + Vite + PWA. Used by moderators to sign bulletins, track incoming help requests, and trigger sync.

## Configure

Create a `.env` file (or pass at build time):

```bash
VITE_API_URL=http://localhost:8080
```

## Develop

```bash
bun install
bun run dev
```

Vite serves at `http://localhost:5173`.

## Key Features & Easy Workflow

1. **⚡ 1-Click Moderator Keygen & Server Registration**:
   - Click **`+ Sign bulletin`** anywhere in the Web Admin → Click **`⚡ Quick Generate & Register Keypair`**.
   - Generates an Ed25519 keypair and registers it with the relay automatically.
2. **🟢 Live Relay Health Probing**:
   - Header status badge automatically probes `http://localhost:8080/healthz` every 15 seconds, displaying live latency (e.g. `14ms`) and connection alerts with 1-click **Retry**.
3. **🛡️ Ed25519 Source Signing**:
   - Bulletins are signed in browser memory using **Canonical JSON** bytes before sending to `POST /api/v1/bulletins`.

## Build (PWA)

```bash
bun run build
bun run preview
```

The build output is an offline PWA: installable from the browser's address bar and registers a service worker.

## Project layout

```
src/
├── main.ts              # app bootstrap + router + pinia + naive-ui + SW
├── App.vue              # global layout + dark theme
├── router/              # 5 routes
├── stores/              # pinia stores (moderator identity, cached state)
├── lib/                 # canonical JSON, Ed25519 signer, typed API
├── views/               # Dashboard, Bulletins, Requests, Moderators, Sync
└── components/          # StatusBadge, PublicKeyCard, PendingOutbox
```

## Canonical-JSON contract

`src/lib/canonical.ts` sorts the keys of the bulletin payload alphabetically and stringifies it. The result **must be byte-identical** to what the Rust backend (`api/src/crypto.rs`) and the Flutter app (`mobile/lib/core/canonical.dart`) produce, otherwise signatures will fail verification.