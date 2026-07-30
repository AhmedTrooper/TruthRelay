# TruthRelay — Demo Video Script (3 minutes max)

> Two physical Android phones, one laptop. **No internet involved** — the
> laptop runs the Axum relay, the Vue admin (via nginx), and a local-only
> Wi-Fi hotspot.

## Shot list

### 0:00 — 0:30 — Problem (15s)

- Black screen, white text: *"July 2024. Dhaka. The internet goes down."*
- Cut to: phone screen showing failed network, then a panic message
  *"Hospital A is out of blood!"* re-circulating.

Voiceover: *"When the cellular fabric fails, so does trustworthy information.
TruthRelay is built for the moment the network drops — and works anyway."*

### 0:30 — 1:30 — Offline Compose (60s)

- Open the Flutter app on an Android emulator (Phone A).
- **Airplane mode ON.** Status bar shows the icon.
- Tap **Post** → choose kind **Blood** → fill title "O+ needed" → Save.
- The request appears in the local feed immediately, tagged `UNVERIFIED NEED`.
- Open the desktop terminal: `curl http://127.0.0.1:8080/api/v1/requests`
  shows the request is **NOT** on the server yet (because the phone is offline).

Voiceover: *"With airplane mode on, the app is fully usable. The request is
saved locally — no internet required."*

### 1:30 — 2:15 — Peer Carry over the Mesh (45s)

- Pick up Phone B and walk it out of the laptop's hotspot range.
- Tap **Sync** on Phone B → it discovers Phone A via BLE → they form a
  Wi-Fi Direct group → Phone A's outbox (and bulletin cache) crosses the
  air gap to Phone B.
- Phone A's outbox row is now also stored on Phone B's local outbox.

Voiceover: *"Phone A is connected to the laptop's hotspot. Phone B is not.
They sync over a local mesh transport — Wi-Fi Direct if group formation
works, BLE otherwise. Phone B now carries Phone A's pending post in its
own outbox queue."*

### 2:15 — 2:45 — Carrier Uploads to the Relay (30s)

- Bring Phone B back near the laptop → it rejoins the hotspot.
- The 3-second-debounced `connectivity_plus` callback fires
  `SyncService.pushPending()`.
- Phone B POSTs its outbox (including Phone A's carried row) to the relay
  via `POST /api/v1/mesh/forward`, with Phone B's peer-id stamped on the
  payload for audit.
- `curl http://127.0.0.1:8080/api/v1/requests` now shows the request — even
  though the *posting* phone (Phone A) never reached the laptop.

Voiceover: *"When Phone B rejoins the laptop, it drains its outbox — including
the post it carried from Phone A — straight into the relay. The server
dedupes by UUID and verifies any signatures, so duplicates across phones
don't create noise."*

### 2:45 — 3:00 — Moderator Signs (15s)

- Switch to the **Vue admin dashboard** in the browser.
- Tap **`+ Sign bulletin`** at the top of **Mission Control (Dashboard)**.
- Kind: **VerifiedUpdate**, title: *"Hospital A is open and accepting blood donors"* → **Sign & post**.
- The bulletin appears in the **Bulletins** list with the moderator's name.

Voiceover: *"Moderators sign bulletins with Ed25519. The server re-verifies
the signature against the registered public key before persisting."*

### 3:00 — 3:15 — Pull & Display (15s) — *(or trim the previous step)*

- Back to Phone A: **Sync** → **Pull**.
- The verified bulletin appears in the **Bulletins** tab with a
  **VERIFIED SAFE** badge.
- End card: *"TruthRelay. Verified crisis info, no internet required."*
  + GitHub link + `#JulyHackathon2026`.

---

## Recording setup

1. **Screen capture**: OBS or `adb shell screenrecord` for the emulator.
2. **Web browser**: any Chrome / Firefox on the host machine.
3. **Backend**: `make up` (boots the local Docker crisis mesh instantly —
   Axum on `0.0.0.0:8080`, nginx serving the admin SPA, local-only hotspot).
4. **Mobile**: Get your laptop's local IP (e.g., `192.168.1.5`), then
   ```
   flutter run \
     --dart-define=TRUTHRELAY_API_URL=http://192.168.1.5:8080 \
     -d emulator-5554
   ```
5. **Lights, microphone**: 1 minute of setup, 2 takes, pick the best.

## Editing notes

- The whole thing must fit in 3 minutes — trim the "Pull & Display" step if
  you run long, since the peer-carry narrative is the headline.
- Add captions for the moderator keygen flow (the JSON paste is hard to read
  on screen at 1080p).
- The "Phone B leaves hotspot range" frame is the centrepiece — hold it for
  a full second so the audience notices the outbox row crossing the air gap.
- End with a 2-second hold of the GitHub link.