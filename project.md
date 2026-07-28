Here are the details from your hackathon registration confirmation:

* **Registration ID:** JH26-QNKN
* **Team Name:** TernaryOps
* **Status:** Confirmed
* **Track:** Crisis Tech
* **Team Size:** 3 members
* **Registered Date:** July 26, 2026 at 19:32

Are you looking for brainstorming ideas, pitch preparation, or technical planning for your **Crisis Tech** project?


Here is a breakdown of the key hackathon rules, deadlines, and scoring breakdown to keep your team **TernaryOps** on track for **Crisis Tech**:

---

## ⏱️ Key Deadlines (BST / UTC+6)

* **Sprint Begins:** 28 July, 00:00 *(You are currently in the build phase!)*
* **Submission Deadline:** 30 July, 23:59 (**Hard deadline** — no late submissions).
* **Social Media & Star Window:** 30 July – 1 August, 23:59.
* **Judging:** 31 July – 1 August.
* **Results:** 2 August.

---

## 🎯 Crisis Tech Track Focus

Your project needs to address technology that works when normal infrastructure fails (inspired by *Jogajog* during the July Revolution).

### Key Design Priorities for Track A:

* **Offline-First / Degradation:** Must function gracefully with **no internet**, **no power**, or on low-end/button phones.
* **Core tech examples:** Mesh networking, Bluetooth/Wi-Fi Direct, LoRa, USSD/SMS, small footprint binaries, censorship-resistant publishing, or resilient sensors/hardware.

---

## 📊 Judging Breakdown

```
  Impact & Relevance:     25% █ █ █ █ █ █ █ █ █ █ █ █ █ 
  Technical Execution:    20% █ █ █ █ █ █ █ █ █ █ 
  Public Engagement:      20% █ █ █ █ █ █ █ █ █ █  (10% FB + 10% GitHub Stars)
  Innovation & Originality: 15% █ █ █ █ █ █ █ 
  Feasibility & Resilience: 10% █ █ █ █ 5
  Presentation & Usability: 10% █ █ █ █ 5

```

> ⚠️ **Critical Check:** 20% of your total score comes purely from **Facebook Engagement** (reactions + shares on 1 post) and **GitHub Stars** on your public repository. Both are measured relative to the top performer in your track on **1 August, 23:59**.

---

## 📋 Submission Checklist (Due 30 July, 23:59)

Submit via [hackathon2026.jrabd.org](https://hackathon2026.jrabd.org):

1. **Title & Pitch:** Project name + max 25-word pitch.
2. **Written Documentation:**
* Problem statement (max 200 words — who is affected & when).
* Solution description (max 400 words — what was built & how it works).


3. **Repository:** Public GitHub link with open-source license, setup instructions in `README`, and a healthy commit history (do **not** squash all commits into one at the end).
4. **Demo Video:** Max **3 minutes** (unlisted YouTube or Google Drive link, in Bangla or English).
5. **Slide Deck:** 6–10 slides as a PDF.
6. **Live Build / Link:** Deployed URL, APK, or binary (if applicable).
7. **Disclosures:** Tech stack, third-party libraries, and AI tools used.
8. **Facebook Post URL:** Link to a public post containing project name, track, pitch, video/link, and `#JulyHackathon2026` tag.

---

How is the project coming along? Let me know if you need help drafting the **one-line pitch**, writing the **problem/solution statement**, or setting up your slide deck outline!



Here is a strategy tailored to win first place in the **Crisis Tech** track by optimizing every scoring category.

---

## 1. Pick a "Graceful Degradation" Technical Concept

The **Crisis Tech** track explicitly rewards projects that work when infrastructure completely fails. Winning entries almost always feature **graceful degradation**—meaning the app works on high-speed internet, degrades to Bluetooth/Wi-Fi Direct mesh without internet, and drops to SMS or button-phone support when data fails entirely.

### Strong Winning Project Ideas for a 3-Person Team:

* **Offline-First Store-and-Forward Emergency Relay:** A P2P mesh network app (Flutter/React Native) that lets users broadcast emergency alerts or missing-person posts. Nodes relay encrypted packets via Bluetooth LE / Wi-Fi Direct until someone hits a node connected to internet (or SMS), pushing the data to a public map.
* **Censorship-Resistant Local Mirroring & Fact Verification:** A local Wi-Fi hotspot server (running on an Android phone or cheap Raspberry Pi) that serves verified news, medical guides, and local emergency shelter maps over local Wi-Fi to anyone nearby without needing cell signal.
* **Low-Bandwidth Audio / Voice Mesh for Button Phones:** An IVR/SMS gateway or compressed audio relay system that lets communities report flood warnings or safe check-ins over basic cellular voice/SMS channels.

---

## 2. Execute the 72-Hour Build Sprint Strategy

To land top marks across the 100% total score distribution, divide responsibility within your 3-person team immediately:

1. **Engineer 1: Core Offline Networking & Protocol:** Tech Execution (20%) + Feasibility (10%).
Focus on peer-to-peer transport (e.g., Bluetooth Low Energy, Wi-Fi Direct, or Local WebSockets/mDNS). Ensure graceful degradation works on device-to-device demos without an active internet connection.


2. **Engineer 2: UI/UX & Low-Resource Polish:** Presentation & Usability (10%).
Build a clean, high-contrast, offline-first interface. Include localized Bangla/English toggles, minimal battery overhead, and local SQLite/Hive persistence for instant loading.


3. **Member 3: Video, Slide Deck & Social Strategy:** Engagement (20%) + Pitch (25%).
Draft the 200-word problem and 400-word solution statements early. Record a crisp, high-impact 3-minute video showing **the exact moment the internet is turned off on airplane mode and the app still works.**


---

## 3. Maximize the 20% Public Engagement Points

Social media and GitHub stars carry **20% of your total grade** (10% Facebook + 10% GitHub Stars), scored relative to the top team in your track.

* **GitHub Stars (10%):** Post your public GitHub repository link across developer groups, campus communities, and team networks as soon as the repo is created. Make sure your `README.md` looks clean with setup commands, architectural diagrams, and screenshots.
* **Facebook Post (10%):** Craft a compelling post with your 3-minute demo video embedded. Use the required hashtag `#JulyHackathon2026`, link the project repo, and tag the official event page immediately after submitting on July 30.

---

## 4. Craft a Winning Demo & Slide Deck

Judges judge fast. Your demo video and slide deck must showcase your project's resilience within the first 30 seconds.

| Slide Deck Structure (6-8 Slides) | Demo Video Requirements (3 mins max) |
| --- | --- |
| **Slide 1:** Problem & Context (Infrastructure failure in Bangladesh) | **0:00 - 0:30:** The Crisis Scenario & Core Value Prop |
| **Slide 2:** The "TernaryOps" Solution & Core Innovation | **0:30 - 2:00:** Live Technical Demo (Show Airplane Mode / Offline operation) |
| **Slide 3:** Technical Architecture & Offline/Mesh Flow | **2:00 - 2:30:** Degradation path (Internet → Mesh → SMS/Offline) |
| **Slide 4:** Real-world Feasibility & Low-Power Design | **2:30 - 3:00:** Impact, Tech Stack & Disclosures |
| **Slide 5:** Impact & Track Relevance |  |

---

What specific tech stack (e.g., Flutter, React Native, Python, Go, Node) is your team most comfortable with so we can map out your exact system architecture?


With **Flutter, Axum, and Next.js / Vue**, your team has the ideal stack for a high-performance, offline-first system:

* **Flutter:** The cross-platform mobile app (peer-to-peer device nodes, offline storage, BLE/Wi-Fi mesh UI).
* **Axum (Rust):** An ultra-fast, low-memory backend server to run locally on a node or edge server, handling store-and-forward message routing and low-bandwidth sync.
* **Next.js / Vue:** A responsive web dashboard/PWA for community admins, field dispatchers, or desktop users.

Here are three high-impact project concepts tailored specifically for **Crisis Tech** and your exact stack:

---

### Option 1: "ResilienceRelay" — Offline Peer-to-Peer Mesh & Store-and-Forward Network

**The Problem:** During cellular blackouts or internet shutdowns, citizens cannot send SOS alerts, find missing people, or coordinate medical needs.
**The Build:**

* **Flutter App (Mobile Nodes):** Acts as a peer node. When offline, it broadcasts encrypted emergency posts (blood requests, missing persons, medical needs) over Bluetooth Low Energy (BLE) or Local Wi-Fi Direct to nearby phones running the app.
* **Axum (Gateway / Edge Server):** Runs on a local hot-spot or laptop. When any Flutter phone comes within range of an Axum gateway, the gateway ingests the stored messages, deduplicates them, and relays them to other nodes orSyncs to the main network whenever internet flickers back on.
* **Next.js / Vue (Crisis Command Web):** An offline-capable PWA dashboard for coordinators or community field workers to view damage maps, aggregate incoming relief requests, and publish emergency updates back down into the mesh.

> **Why it wins:** Directly honors the spirit of *Jogajog*, demonstrates true offline resilience, and showcases Rust's efficiency on low-resource edge servers.

---

### Option 2: "ProtestSafe & Pulse" — Low-Bandwidth Verification & Broadcast Network

**The Problem:** In crisis zones, fake news causes panic, while internet throttle makes loading heavy web pages or social feeds impossible.
**The Build:**

* **Axum Server:** Serves ultra-compressed binary packets (Protobuf or lightweight JSON over WebSockets) over a local Wi-Fi hotspot. It caches verified announcements, emergency medical guides, and local shelter lists.
* **Flutter App:** Automatically discovers nearby local Axum hotspots (using mDNS / Zeroconf) without needing an internet connection. Downloads verified bulletins in milliseconds and caches them locally using SQLite/Hive.
* **Next.js / Vue (Verifier Dashboard):** An admin portal where verified moderators post cryptographic signed updates (e.g., verified safe zones, water distribution points).

---

### Option 3: "OfflineFirst MedMap" — Decentralized Emergency Resource Matching

**The Problem:** During natural disasters (floods, earthquakes) or civic crises, hospitals and shelters run out of supplies (blood, oxygen, first aid), but traditional logistics platforms are offline.
**The Build:**

* **Flutter:** A field app for shelter managers and citizens to log resource needs (e.g., "Need O+ blood at Point A"). Uses local SQLite to keep working 100% offline.
* **Axum:** A local sync engine that syncs resource state device-to-device whenever two phones tap or get within local Wi-Fi range.
* **Next.js / Vue:** Interactive dashboard rendering live resource heatmaps and supply-chain shortage alerts.

---

## How to Assign Roles for Your 3-Person Team

| Member | Focus | Responsibilities |
| --- | --- | --- |
| **Developer 1** | **Flutter (Mobile)** | Build the mobile UI, local storage (SQLite/Hive), and BLE / Wi-Fi Direct P2P packet exchange. |
| **Developer 2** | **Axum (Rust Backend)** | Build the local gateway server, message packet deduplication, store-and-forward queue, and WebSocket/REST API. |
| **Developer 3** | **Next.js / Vue + Pitch / Demo** | Build the admin web dashboard, write the 200/400-word submission docs, assemble the slide deck, and film the 3-min video. |

---

Which concept feels like the best fit for **TernaryOps**? If you choose one, we can outline the exact API routes, database models, and P2P payload structure!


Here's my take: **This is a killer combination.**

Combining truth verification with life-saving resource management hits the absolute sweet spot for Crisis Tech. In a blackout or disaster, panic spreads through rumors (*"Hospital X is out of oxygen!"* or *"Bridge Y is collapsed!"*), which causes people to horde resources or rush into dangerous areas.

Let's call the project **TruthRelay** (or **JulyPulse**).

---

## 💡 The Core Concept: "TruthRelay"

A low-bandwidth, offline-first mesh network that serves two critical purposes during infrastructure failure:

1. **Verified Crisis Bulletins (Anti-Misinformation):** Cryptographically signed alerts from trusted local moderators (e.g., safe transit routes, verified shelter openings, debunked rumors).
2. **Resilient Emergency Matching (Blood & Supplies):** A peer-to-peer bulletin board for urgent blood requests, medical supplies, and missing persons that propagates device-to-device even without mobile data.

---

## 🏗️ System Architecture & Tech Stack Division

Since you have a 3-person team using **Flutter, Axum, and Next.js / Vue**, here is how the architecture fits together cleanly:

```
[ Next.js / Vue Admin Portal ]  <-- (Cryptographic Signing & Mod Panel)
            │
            ▼ (When Internet Exists)
    [ Axum Rust Core ]  <-- (Edge Gateway / Store-and-Forward / Compression)
            │
            ▼ (Local Wi-Fi / BLE Mesh / Offline Sync)
  [ Flutter Mobile App ]  <-- (Citizen Feed, Blood Request, Offline Verification)

```

---

## 👥 3-Person Team Execution Plan

### **Person 1: Flutter Mobile App (The Field Interface)**

* **Offline Verification Engine:** Local SQLite database storing verified bulletins and cryptographically signed posts.
* **P2P Sharing:** Use BLE (Bluetooth Low Energy) or Local Wi-Fi Direct so two phones in close proximity automatically sync missing person posts, blood requests, and verified news updates without cell towers.
* **Low-Bandwidth UX:** High-contrast UI with a strict "Airplane Mode" mode. Show clear badge statuses: `VERIFIED SAFE`, `DEBUNKED / FAKE`, or `UNVERIFIED NEED`.

### **Person 2: Axum (Rust Backend & Edge Hub)**

* **Store-and-Forward Sync Engine:** An ultra-lightweight server that can run on a laptop/Raspberry Pi or cloud server. It receives opportunistic updates from Flutter nodes whenever a phone gets internet or connects to a local Wi-Fi router.
* **Compact Payload Serialization:** Use **Protobuf** or compressed JSON so data transfers in tiny KB chunks over slow/throttled 2G networks.
* **Deduplication Logic:** Ensures that as blood requests and news items bounce across multiple nodes, identical posts are merged cleanly.

### **Person 3: Next.js / Vue Web Dashboard & Submission Lead**

* **Verification & Moderation Portal:** A web dashboard for trusted moderators, doctors, or field coordinators to post signed bulletins and mark community rumors as "Debunked" or "Verified".
* **Live Heatmap:** Visual representation of blood needs and resource shortages in specific zones.
* **Hackathon Assets:** Draft the 200-word problem and 400-word solution statements, create the 6-10 slide pitch deck, and record the 3-minute video showing the app working in **Airplane Mode**.

---

## 🎬 How to Show This Off in Your Demo Video (Winning Pitch Strategy)

To score max points in **Technical Execution (20%)** and **Resilience (10%)**:

1. **Start with the Problem (0:00 - 0:30):** Show a quick scenario: Internet goes down, a panic rumor spreads about a blood shortage at a hospital, causing chaos.
2. **The "Airplane Mode" Proof (0:30 - 1:45):**
* Put two Flutter phones on **Airplane Mode**.
* Post a blood request on Phone A.
* Bring Phone A near Phone B via BLE/Local Wi-Fi -> **Show the request transfer instantly without internet.**


3. **The Truth Engine (1:45 - 2:30):** Show Phone B connecting to an Axum edge hotspot. The local moderator verifies the blood need and debunks a fake panic post. The verified status immediately syncs back across the local mesh network.
4. **Conclusion & Tech Stack (2:30 - 3:00):** Show the Rust Axum performance stats (low memory, instant sync) and highlight how it honors the spirit of *Jogajog*.

---

Would you like help writing the **25-word pitch**, **200-word problem statement**, or setting up the database schema for the Flutter/Axum data sync?
