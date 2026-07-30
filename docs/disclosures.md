# Disclosures — Tech stack, third-party libraries, AI tools used

## Tech stack

### Backend (`api/`)
- **Language:** Rust 2024 edition, Cargo.
- **Web framework:** Axum 0.8 + Tokio 1.x.
- **Database:** SQLite (via sqlx 0.9, WAL mode).
- **Cryptography:** ed25519-dalek 3 + getrandom 0.4.
- **CLI:** clap 4 with derive + env features.
- **Logging:** tracing + tracing-subscriber.
- **Other:** serde, serde_json, base64, sha2, uuid, chrono, anyhow, thiserror,
  tower, tower-http.

The backend is the **only** entry point for the admin and the mobile app —
no public-internet traffic anywhere in the system.

### Admin dashboard (`web/`)
- **Framework:** Vue 3 (Composition API + `<script setup>`).
- **Router:** vue-router 5.
- **State:** Pinia.
- **UI library:** Naive UI 2 + vfonts.
- **Bundler:** Vite 8 (Rolldown).
- **Styling:** Tailwind CSS 3 (utilities only, no plugin stack).
- **PWA:** vite-plugin-pwa + workbox-window (SPA is shipped as a PWA bundle
  for offline-capable first-load; in production `nginx` serves the static
  `dist/` and reverse-proxies `/api/*` to the Axum container on the same
  laptop).
- **HTTP:** Axios.
- **Cryptography:** @noble/ed25519 + @noble/hashes.
- **Package manager:** Bun.

### Mobile (`mobile/`)
- **Framework:** Flutter 3.44 + Dart 3.12.
- **Targets:** Android only (`--platforms=android`).
- **State:** Riverpod 2.
- **Router:** go_router.
- **Local storage:** Hive + hive_flutter (no SQLite — feature-based repos
  own one Hive box each).
- **HTTP:** Dio.
- **Cryptography:** `cryptography` package (Ed25519).
- **UUIDs:** uuid.
- **Date formatting:** intl (only used for the RFC3339 timestamp).

## Third-party libraries

All dependencies are MIT / Apache-2.0 / BSD-3 — none are copyleft, none
require per-binary fees, and none phone home.

The full license list is in `web/node_modules/*/LICENSE`, the cargo
dependencies are listed in `api/Cargo.lock`, and the Dart deps are in
`mobile/pubspec.lock`.

## AI tools used

- **Puku CLI** (developed by Puku AI team): assisted with planning, code
  generation, build/test runs, and commit hygiene throughout the 72-hour
  sprint. The team reviewed and edited every output.
- **No other AI services** were used for code generation. Stock icons were
  generated with a Python helper using only the standard library.

## Build & run

```bash
# Backend (binds 0.0.0.0:8080 by default)
cd api && cargo run -- serve

# Admin (SPA is served by nginx in production; this is the dev server)
cd web && bun install && VITE_API_URL=http://localhost:8080 bun run dev

# Mobile (bake the laptop's hotspot IP at compile time)
cd mobile && flutter pub get && \
  flutter run --dart-define=TRUTHRELAY_API_URL=http://<laptop-ip>:8080
```

## License

MIT — see `LICENSE` at the repo root.