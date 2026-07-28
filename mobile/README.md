# TruthRelay — Mobile (Flutter / Android)

Offline-first crisis bulletins and help requests. Built for the
**Crisis Tech** track at JulyHackathon2026 by **TernaryOps**.

## Run

```bash
# Boot the backend first (see ../api/README.md).
flutter pub get
flutter run -d <android-device-or-emulator>

# Point at a different server:
flutter run --dart-define=TRUTHRELAY_API_URL=http://192.168.1.10:8080 \
  -d <android-device>
```

On an Android emulator, `10.0.2.2` maps to your host's localhost, so the
default `http://10.0.2.2:8080` works out of the box.

## Build APK

```bash
flutter build apk --debug      # build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release    # build/app/outputs/flutter-apk/app-release.apk
```

## Architecture

Each feature owns its data layer (`data/`), model (`models/`), and view
(`views/`). Cross-cutting concerns live in `lib/core/`.

```
lib/
├── main.dart                     # bootstrap + Hive init + router
├── core/
│   ├── canonical.dart            # canonical-JSON (must match Rust + Web)
│   ├── crypto.dart               # Ed25519 sign helper
│   ├── env.dart                  # API URL (compile-time)
│   ├── providers.dart            # Riverpod providers
│   └── router.dart               # go_router
├── data/
│   └── storage/
│       └── hive_boxes.dart       # Hive box names + init
├── features/
│   ├── bulletins/{data,models}/  # BulletinRepository, Bulletin model
│   ├── requests/{data,models}/   # RequestRepository, HelpRequest model
│   ├── sync/
│   │   ├── data/{api_client,outbox_repository,sync_service}.dart
│   │   ├── models/outbox_entry.dart
│   │   └── views/sync_view.dart
│   ├── compose/views/compose_view.dart
│   ├── home/views/home_view.dart
│   ├── detail/views/detail_view.dart
│   └── settings/
│       ├── data/moderator_settings_repository.dart
│       └── views/settings_view.dart
└── widgets/status_badge.dart
```

## Offline-first flow

1. Compose a help request → saved to local Hive box + outbox table.
2. App stays usable with airplane mode; reads come from local cache.
3. When online, the **Sync** screen pushes the outbox and pulls new
   bulletins + requests from the server.
4. The relay server dedupes by `id` / `sha256` so duplicates across devices
   don't create noise.

## Canonical-JSON contract

`lib/core/canonical.dart` produces byte-identical bytes to
`api/src/crypto.rs` and `web/src/lib/canonical.ts`. If the three drift, the
server's Ed25519 verifier will reject signatures. Verified by the test
suite: `flutter test`.

## Settings

Paste your `keygen` output (plus the assigned `id` from the server) in
**Settings** to enable the mobile app to **sign** verified bulletins.
For v1, mobile users without a registered moderator key can still read and
post unsigned help requests.