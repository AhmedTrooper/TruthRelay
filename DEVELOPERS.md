# TruthRelay — DEVELOPERS.md

> **Audience: the team lead (`ahmedtrooper`).**
> Judges, mentors, and external readers should be reading `README.md` and
> `assets/report.pdf`, not this file. Keep this document private — it is
> our internal playbook for the rest of the sprint.

This file captures strategy, the actual state of the build, the things
that still need work, and concrete next moves. The public README stays
clean and pitch-shaped; everything below is the unglamorous truth that
makes a demo actually land.

---

## 1. Where we are right now

| Stack | Gate | Status |
|---|---|---|
| Mobile (Flutter) | `flutter analyze && flutter test && flutter build apk --debug` | ✅ 137 tests passing |
| Relay (Rust) | `cargo clippy -- -D warnings && cargo test` | ✅ 9 tests passing |
| Admin (Vue) | `bun run build` (= `vue-tsc -b && vite build`) | ✅ 9 tests passing |
| Triple-stack | full gate above + `bun run build` | ✅ green |
| Sprint commits | 16 (14 mesh + 1 docs + 1 web polish) | ✅ |

The system boots, signs, deduplicates, gossips, re-verifies, falls back
to hotspot, forwards through a carrier, runs a periodic background
sync, and ships an audit log. The pitch is intact and the demo path
is reproducible.

---

## 2. What to do with the remaining time

### 2.1 — Rehearse the demo, don't add more code

The biggest risk is **demo reliability**, not feature count. Rehearse
on two physical phones at least three times. Specifically:

1. **Boot sequence** — start the api, run `cargo run -- keygen`,
   paste into the web, sign one bulletin, *then* pick up the phones.
   Every minute saved on stage is a minute not fumbling with admin
   tokens.
2. **The single hard step** — Wi-Fi Direct group formation needs
   *user interaction on the Android system dialog*. Plan a 5-second
   pause in the script for that.
3. **The QUARANTINED demo** — edit `signature_b64` in one Hive box
   via `adb shell`, pull-to-refresh, and watch the badge flip. The
   judges remember this beat the longest.

### 2.2 — Strongest angles to lead with

If we have 60 seconds to make the judges remember us:

1. **Peer-hop Ed25519 re-verification.** No other Crisis-Tech team
   has this. The math is small, the visual is loud (green → amber
   badge flip).
2. **The relay is one Cargo binary.** `cargo run -- serve` and the
   relay is up. Tell them that explicitly.
3. **The canonical-JSON contract.** All three languages produce the
   exact same bytes — the same signature verifies across all three.
   That's the "professional" bar the track rewards.

### 2.3 — Demo beats that take 30 seconds but land

- Open the relay on a phone, hand it to a judge, *they* sign a
  bulletin, *they* see it appear on the dashboard.
- Open the mobile app's Sync screen, watch the count-up animation
  pulse when a new bulletin arrives.
- Toggle airplane mode → post a help request → watch the amber
  outbox badge count up → toggle Wi-Fi back → watch it drain.

### 2.4 — Questions judges *will* ask

Pre-prepare answers:

- **"What stops a hostile phone from injecting fake bulletins?"**
  The Ed25519 signature. A peer can inject unsigned bulletins (they
  store as `signatureVerified=null` and display as QUARANTINED), but
  cannot forge a moderator signature.
- **"What if the relay is compromised?"** mTLS pinning + a
  moderator-key-rotation event in the mesh protocol (post-hackathon).
  In the demo, we trust the relay is honest — that's documented.
- **"What's the SQLite row count at production scale?"** With our
  TTL+cap retention (500/kind, 72h for Blood/Missing, 14d for
  others), the relay stays under ~10k rows for a regional rollout.
- **"Why no blockchain?"** Ed25519 + canonical JSON gives us the
  *same* tamper-evidence property for a 64-byte signature instead of
  a 200-byte proof, with no consensus layer to operate.

### 2.5 — Things to *not* add

The temptation will be to add more. Resist. Specifically:

- **Don't** add a conflict-resolution UI — the judges know CRDTs are
  a research problem; show that you know which problems you didn't
  solve.
- **Don't** add USSD support in the last hour — it's a 2-day project
  on its own and it looks impressive but is fragile on stage.
- **Don't** change the canonical JSON function. The contract is
  asserted in two cross-language tests; touching it risks breaking
  a signed-elsewhere bulletin.

---

## 3. Open issues to triage

### 3.1 — Documented as deferred

These are listed honestly in `assets/report.tex` (corner cases we
deferred). They're not blockers — they're roadmap:

- **C1** Moderator key rotation (cache invalidation event).
- **C2** Help-request signing (so requests aren't trivially spoofable).
- **C3** Conflict resolution (CRDTs + tombstones).
- **C4** Sybil resistance on the mesh (rate-limit per peer).
- **C5** USSD/audio fallback (gateway proxy).
- **C6** Localisation (Bengali first).
- **C7** Per-hop E2E encryption (X25519 + ChaCha20-Poly1305).

### 3.2 — Internal QA debt

- The mobile `seen_packets` table has TTL disabled — left over from
  a hot-fix during Wi-Fi Direct bring-up. Add a 7-day retention in
  the next commit.
- The Vue `package.json` doesn't expose a `lint` script. Add one
  before pitching to anyone who runs `bun run lint` as a default.
- The `Makefile` `make test` deliberately skips `web-test`. Either
  document that more loudly or wire it in with a `--with-web` flag.

### 3.3 — Stage-time risk

- The Docker build for `web` re-runs `bun install` from scratch on
  every build, which on slow connections adds ~40s. The
  `Dockerfile` is correct but the cache is not pinned; consider a
  `bun.lockb` copy step.
- The mobile APK debug build pulls from Maven Central every time on
  a clean checkout. Pre-build once before the demo.

---

## 4. File map (what lives where)

```
truthrelay/
├── README.md                    ← judges see this. Keep it pitch-shaped.
├── DEVELOPERS.md                ← THIS FILE. Team-internal playbook.
├── LICENSE                      MIT
├── docker-compose.yml
├── Makefile
├── project.md                   hackathon brief (don't edit)
│
├── api/                         Rust relay (cargo run -- serve)
├── web/                         Vue 3 admin (bun run dev)
├── mobile/                      Flutter Android (flutter run)
│
├── docs/                        sub-200-word pitch pieces
│   ├── pitch.md
│   ├── problem.md
│   ├── solution.md
│   ├── deck.md
│   ├── demo-script.md
│   ├── disclosures.md
│   └── social.md
│
├── scripts/
│   └── demo-mesh.md             eight-step offline validation
│
└── assets/
    ├── report.tex               ← compile: tectonic report.tex
    ├── report.pdf               ← compiled artifact (judge-facing)
    └── figures/                 ← rendered tikz figures land here
```

---

## 5. How to push a change the right way

1. Pick a single concern per commit. Multi-concern commits hide
   regressions.
2. Run the full triple-stack gate before pushing:
   ```bash
   make api-test && cd mobile && flutter analyze && flutter test \
     && flutter build apk --debug && cd ../web && bun run build
   ```
3. Update `README.md` status tables and `assets/report.pdf` when a
   feature flips status. The judges *will* notice drift.
4. Re-record `scripts/demo-mesh.md` if the change touches a transport
   or the relay API. The script is the contract for future
   contributors.
5. No `Co-Authored-By` trailer in commit messages — that's a
   team-internal style choice; keep it consistent across the sprint.

---

## 6. Communication templates

### 6.1 — When a feature flips status

> Feature: *<name>*. Status: ✅. Tests: *<n> new*. Triple-stack gate: green.
> Touches: *<files>*. Demo beat: *<where it shows up>*. Updated:
> README.md status table + assets/report.pdf section *<n>*.

### 6.2 — When a feature is deferred

> Deferred: *<name>*. Reason: *<why>*. Plan to fix: *<when / how>*.
> Documented in: assets/report.tex (corner case *C<n>*).

### 6.3 — When something breaks on stage

> Mitigation: fall back to the second-best demo beat (the QUARANTINED
> demo if Wi-Fi Direct stalls, or the HOTSPOT fallback if BLE
> permission is denied). The pitch works without the live mesh; the
> live mesh just makes it stick.

---

## 7. The single-sentence test

Before adding anything, ask:

> *"Does this make a crisis-zone citizen more likely to read the right
> bulletin, or more likely to post a help request that actually gets
> answered?"*

If yes, ship it. If not, defer it.

---

_Last updated: 29 July 2026._
