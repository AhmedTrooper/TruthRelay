# TruthRelay — Demo Video Script (3 minutes max)

## Shot list

### 0:00 — 0:30 — Problem (15s)

- Black screen, white text: *"July 2024. Dhaka. The internet goes down."*
- Cut to: phone screen showing failed network, then a panic message
  *"Hospital A is out of blood!"* re-circulating.

Voiceover: *"When the cellular fabric fails, so does trustworthy information.
TruthRelay is built for the moment the network drops — and works anyway."*

### 0:30 — 1:30 — Offline Compose (60s)

- Open the Flutter app on an Android emulator.
- **Airplane mode ON.** Status bar shows the icon.
- Tap **Post** → choose kind **Blood** → fill title "O+ needed" → Save.
- The request appears in the local feed immediately.
- Open the desktop terminal: `curl http://127.0.0.1:8080/api/v1/requests`
  shows the request is **NOT** on the server yet (because the phone is offline).

Voiceover: *"With airplane mode on, the app is fully usable. The request is
saved locally — no internet required."*

### 1:30 — 2:15 — Sync (45s)

- Connect the emulator to the **local laptop Wi-Fi hotspot**.
- Tap the sync icon → Sync screen → **Push**.
- `curl http://127.0.0.1:8080/api/v1/requests` now shows the request.

Voiceover: *"When connected to a local edge node, the local outbox drains. The relay
dedupes by UUID so duplicates across phones don't create noise."*

### 2:15 — 2:45 — Moderator Signs (30s)

- Switch to the **Vue admin dashboard** in the browser.
- Tap **`+ Sign bulletin`** at the top of **Mission Control (Dashboard)**.
- Tap **`⚡ Quick Generate & Register Keypair`** inside the modal (or paste keygen JSON under **Moderators**).
- Kind: **VerifiedUpdate**, title: *"Hospital A is open and accepting blood donors"* → **Sign & post**.
- The bulletin appears in the **Bulletins** list with the moderator's name.

Voiceover: *"Moderators sign bulletins with Ed25519. The server re-verifies
the signature against the registered public key before persisting."*

### 2:45 — 3:00 — Pull & Display (15s)

- Back to the mobile app: **Sync** → **Pull**.
- The verified bulletin appears in the **Bulletins** tab with a
  **VERIFIED SAFE** badge.
- End card: *"TruthRelay. Verified crisis info over flaky networks."*
  + GitHub link + `#JulyHackathon2026`.

---

## Recording setup

1. **Screen capture**: OBS or `adb shell screenrecord` for the emulator.
2. **Web browser**: any Chrome / Firefox on the host machine.
3. **Backend**: `make up` (boots the local Docker crisis mesh instantly).
4. **Mobile**: Get your laptop's local IP (e.g., `192.168.1.5`), then run `flutter run --dart-define=API_URL=http://192.168.1.5:8080 -d emulator-5554`.
5. **Lights, microphone**: 1 minute of setup, 2 takes, pick the best.

## Editing notes

- The whole thing must fit in 3 minutes.
- Add captions for the moderator keygen flow (the JSON paste is hard to read
  on screen at 1080p).
- The "Airplane mode toggle" frame is the centrepiece — leave it on screen
  for a full second so the audience notices.
- End with a 2-second hold of the GitHub link.