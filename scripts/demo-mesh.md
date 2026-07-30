# TruthRelay — Phone-to-Phone Mesh Demo

A repeatable validation script for the offline workflow. Run this end-to-end
on a single desk with two physical Android phones (or an emulator pair) to
prove that the system survives an internet outage.

> This demo also runs against a single phone + the relay. Steps marked
> **two-phone** require the second device.

---

## Pre-flight

```bash
# Terminal 1: relay
cd api && cargo run --release

# Terminal 2: web admin
cd web && bun install && bun run dev

# Terminal 3 + 4: phones (override endpoint if needed)
cd mobile && flutter run --dart-define=TRUTHRELAY_API_URL=http://<host-ip>:8080
```

Register a moderator via the web admin (`/admin/moderators`) and publish
**one VerifiedUpdate** through the dashboard so we have something to gossip.

---

## 1. Hotspot baseline

| Phone | Expected                                                                 |
|-------|--------------------------------------------------------------------------|
| A     | Sync screen shows the moderator bulletin after `Pull`.                   |
| B     | Sync screen shows the moderator bulletin after `Pull`.                   |

Pass criteria: both Home tabs show a green `VERIFIED` badge.

---

## 2. Compose one help request while offline

1. Phone A → toggle Wi-Fi off (airplane mode for the demo).
2. Phone A → tap **Post** → choose **Request**, type "Need water", submit.
3. Phone A → Home sync icon shows the amber badge with `1` (pending outbox).
4. Phone A → open Sync → status reads "Pushed 0 items".

Expected: `pendingOutboxCountProvider` increments to 1.
Rejected failure mode: status shows `Pushed 1 items`.

---

## 3. **Two-phone** Wi-Fi Direct handoff

1. Phone A: Post another help request ("Generator running"). Outbox = 2.
2. Phone B: same app, but the relay is unreachable for B (turn off WAN too).
3. Both phones should be on the same Wi-Fi (a router, not the modem — the
   mesh layer will try BLE first if Wi-Fi Direct fails).
4. Open the Sync screen on Phone B — peer rows show Phone A within ~10 s
   of BLE discovery warming up, and the transport chip reads "Peer link".
5. Tap **Sync now** on Phone B. Expected: session row flips to `ok`,
   counters read `↑0 ↓2` (B received A's outbox).
6. Open Sync on Phone A: outbox row should be `↑0 ↓N` once A's session
   completes (A also relays whatever of B's inventory it does not have).

Pass criteria: 2+ records cross the air gap with no internet at any point.

---

## 4. **Two-phone** Local-only hotspot fallback

This is the path when Wi-Fi Direct cannot form (OEM ROM quirks, busy
spectrum, etc).

1. Force Wi-Fi Direct to fail: enable **only** BLE on both phones
   (Settings → Location → Wi-Fi Direct "off").
2. Phone A starts a local-only hotspot (`LocalHotspotHostTransport` will
   invoke `WifiManager.startLocalOnlyHotspot` if the device exposes it).
3. Phone B's BLE scan picks up the SSID advertisement in the same
   TR1 mesh service, then `WifiManager.connect(...)` joins the soft-AP.
4. The same mesh protocol as step 3 runs over the soft-AP.

Pass criteria: peer rows still flip to `ok` and the transport label in the
sync screen reads "Local hotspot" instead of "Peer link".

---

## 5. **Two-phone** Relay forwarding

The carriers phase. Phone B has the bulletin but cannot reach the laptop;
Phone A is in the laptop's hotspot but has no useful outbox of its own.

1. Phone A: connected to the laptop's hotspot. Phone B: out of hotspot range.
2. Phone B composes 3 help requests while out of range.
3. Walk Phone A into BLE range of Phone B.
4. Phone A's Sync screen should show Phone B within 10 s.
5. Tap **Sync now** on Phone A. The session flips to `ok` and the
   request counter reads `↑0 ↓3`.
6. Phone A's `ConnectivitySyncCoordinator` (already wired to the laptop's
   hotspot) drains the outbox within 3 s of any state change, so the
   3 carried requests POST to `/api/v1/sync` straight away.
7. Web admin → `/admin/requests` should now show all 3 of Phone B's
   requests.

Pass criteria: 3 forwarded requests visible in the relay's admin UI
without Phone B ever touching the laptop. (Subsequent runs that have
Phone B directly re-join the hotspot would skip steps 3–6 entirely and
upload straight to the relay — A is not privileged.)

---

## 6. Replay / tamper rejection

The signature gate from commit 13 must hold on every peer hop.

1. On Phone B, pull a system shell (`adb shell`).
2. Edit one bulletin's `signature_b64` and `title` in the local Hive box:

   ```bash
   adb shell run-as com.truthrelay.debug \
     find /data/data/com.truthrelay.debug -name '*.hive' \
     -exec grep -l VERIFIED {} \;
   ```

3. Cycle the Sync screen on Phone B; the affected bulletin now shows
   the amber `QUARANTINED` chip, not the green `VERIFIED SAFE` chip.
4. Repeat the same on Phone A after a peer session: the bulletin is
   re-verified against the cached moderator pubkey. A tampered copy
   arriving from a hostile peer never launders to green.

Pass criteria: the tampered bulletin never shows the green badge.

---

## 7. TTL + per-kind pruning

1. Compose `Blood` and `Missing` help requests; mark them as resolved
   after 73 hours (synthetic clock — adjust `DateTime.now()` in
   `MobileLocalInventory.nowProvider` for the test).
2. Compose `Supply` bulletins repeatedly until the cap is exceeded.
3. Open Sync, tap `Pull`. The repository's `_prune` hook should evict
   the oldest beyond the cap (500 / kind) and anything past the TTL
   (72 h for Blood/Missing, 14 d for everything else).

Pass criteria: the on-disk row count never exceeds the cap, and resolved
records vanish past the TTL.

---

## 8. Background sync without an open app

1. Kill the app on Phone A.
2. `workmanager` registers both the one-time initial task and the 15-min
   periodic task (`background_sync_test.dart` exercises both).
3. Periodically (within 15 min), the outbox drains to the relay without
   the user opening the app.

Pass criteria: the relay admin shows records uploaded from Phone A while
the app process was dead.

---

## Validation gates for every commit

```bash
# Rust
cd api && cargo fmt --check && cargo clippy -- -D warnings && cargo test

# Flutter
cd mobile && flutter analyze && flutter test && flutter build apk --debug

# Vue
cd web && bun run lint && bun run build && vue-tsc --noEmit
```

All three must pass on every commit.
