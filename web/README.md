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

## Build

```bash
bun run build
bun run preview
```

The build output is a PWA: installable from the browser's address bar, registers a service worker, and works offline for cached pages.

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