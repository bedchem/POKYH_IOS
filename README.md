<div align="center">

# POKYH — iOS

**The native SwiftUI app for students and guardians of LBS Brixen — WebUntis, reimagined.**

Stundenplan · Noten · Mensa · Abwesenheiten · Nachrichten · To-dos · Klassen-Erinnerungen
— with Home-Screen widgets, Live Activities, an **offline mode**, and a polished **iPad** layout.

SwiftUI · async/await · WidgetKit · ActivityKit · BackgroundTasks · App Group sharing

</div>

---

## Table of contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Configuration & secrets](#configuration--secrets)
- [How auth works](#how-auth-works)
- [Offline mode](#offline-mode)
- [Profile pictures & avatars](#profile-pictures--avatars)
- [iPad & responsive layout](#ipad--responsive-layout)
- [Widgets & Live Activities](#widgets--live-activities)
- [Project layout](#project-layout)
- [Performance](#performance)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

---

## Overview

POKYH for iOS is a native SwiftUI client for the **Landesberufsschule Brixen** (South Tyrol).
It talks directly to the school's [WebUntis](https://www.untis.at/) instance for timetable,
grades, messages and absences, and to the **POKYH backend** (`api.pokyh.com`) for the cafeteria
menu, to-dos and class reminders — the same backend the web app uses.

It ships with **Home-Screen widgets**, **Lock-Screen / Dynamic Island Live Activities** for the
next lesson, **biometric lock**, **multi-account** support, **background refresh**, a **resilient
offline mode**, and an adaptive layout that scales cleanly from iPhone to iPad.

---

## Features

- 📅 **Stundenplan** — timetable with lesson details, week/day views, infinite paging
- 📊 **Noten** — grades with subject views and averages (`GradeMath`)
- 🍽️ **Mensa** — daily menu with ratings & comments
- 🚫 **Abwesenheiten** — view (and, where permitted, report/excuse)
- ✉️ **Nachrichten** — WebUntis message center
- ✅ **To-dos** & 🔔 **Erinnerungen** — synced via the POKYH backend
- 👪 **Eltern-Accounts** — guardians log in; the child's class is resolved automatically (incl. from the child's timetable)
- 🔌 **Offline mode** — last loaded timetable/grades stay available with no connection; a banner makes it obvious
- 🖼️ **Cached profile pictures** — avatars are stored on-device (instant, offline) with a graceful initials fallback
- 🎨 **Stable avatar colors** — each user gets a random-but-persistent color on first sight
- 🔑 **POKYH-only login** — accounts without a WebUntis login can still sign in (automatic backend fallback)
- 🔐 **Biometric lock** (Face ID / Touch ID) and Keychain-stored credentials
- 👥 **Multi-account** — switch between saved accounts; tap a whole row to switch
- 📱 **iPad-ready** — content scales and centers on large displays (size-class driven)
- 🧩 **Widgets** — next lesson, today's schedule, grades, messages, overview
- 🟢 **Live Activities** — current/next lesson on the Lock Screen & Dynamic Island
- 🔄 **Background refresh** via `BGTaskScheduler`
- 📆 **ICS export** of the timetable

---

## Architecture

```
┌───────────────────────── POKYH (app target) ─────────────────────────┐
│  SwiftUI views  ·  Store (@MainActor state)                            │
│                                                                        │
│   UntisClient ─────────────►  WebUntis  (JSON-RPC + REST)              │
│   BackendClient ───────────►  POKYH Backend (api.pokyh.com)            │
│                                                                        │
│   Keychain (creds) · Crypto · Cache/DiskCache/ImageCache              │
│   Notifications · WidgetBridge ──────┐                                 │
└───────────────────────────────────────┼───────────────────────────────┘
                                        │  App Group (shared container)
┌───────────────────────────────────────▼───────────────────────────────┐
│  POKYHWidget (extension)  ·  SharedKit  ·  Live Activity + widgets      │
└────────────────────────────────────────────────────────────────────────┘
```

- **`UntisClient`** — WebUntis auth and data (timetable, grades, messages, absences). Resolves the
  effective student: for a **guardian**, it finds the child and derives their class from the
  child's **timetable** when WebUntis doesn't expose it directly. Token-less (offline) sessions
  read straight from the on-disk cache instead of hitting the network.
- **`BackendClient`** — POKYH backend calls. WebUntis-linked login is a trusted **server-to-server**
  call (`X-Server-Key` + `X-API-Key`); a direct username/password login (`/auth/login`) powers the
  POKYH-only fallback. User requests carry a `Bearer` token.
- **`Store` (`AppState`)** — the app's single source of truth (`@MainActor`), orchestrating login,
  account switching, the offline race, and data refresh.
- **`DiskCache` / `ImageCache` / `Cache`** — persistent JSON cache (offline timetable/grades),
  on-disk image cache (avatars), and in-memory TTL caches.
- **`SharedKit` + App Group** — shares the data the widgets and Live Activities render.

---

## Requirements

- **Xcode** (matching the project's Swift toolchain) on macOS
- **iOS deployment target: 26.0** (see `IPHONEOS_DEPLOYMENT_TARGET`)
- Device family **iPhone + iPad** (`TARGETED_DEVICE_FAMILY = 1,2`)
- An Apple Developer account for device builds, widgets, Live Activities & push
- A running [POKYH backend](../pokyh-backend)

---

## Getting started

```bash
# 1. Create your secrets file from the template
cp Secrets.example.swift POKYH/Secrets.swift
#    → fill in the keys (see below). POKYH/Secrets.swift is gitignored.

# 2. Open the project
open POKYH.xcodeproj
```

Then in Xcode:
1. Select your **Team** for the `POKYH` app target **and** the `POKYHWidget` extension.
2. Confirm the App Group is enabled on both targets (shared container for widgets/Live Activities).
3. Build & run on a simulator or device.

Build from the command line:

```bash
xcodebuild build -project POKYH.xcodeproj -scheme POKYH -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/dd
```

---

## Configuration & secrets

All non-secret configuration lives centrally in **`POKYH/Config.swift`** (backend URL, WebUntis
base/school, every API route — nothing is hard-coded across the codebase). Secrets live in the
**gitignored** `POKYH/Secrets.swift`:

```swift
// POKYH/Secrets.swift  (copied from Secrets.example.swift)
enum Secrets {
    static let apiKey    = "YOUR_BACKEND_API_KEY"   // = backend API_KEY  / web NEXT_PUBLIC_API_KEY
    static let serverKey = "YOUR_SERVER_KEY"        // = backend SERVER_KEY  (sensitive!)
    static let isDebug   = false                    // true → show diagnostics UI
}
```

| Key                  | Must match…                                  |
| -------------------- | -------------------------------------------- |
| `Secrets.apiKey`     | backend `API_KEY`                            |
| `Secrets.serverKey`  | backend `SERVER_KEY`                         |
| `Config.backendURL`  | the deployed backend (`https://api.pokyh.com`) |
| `Config.untisBase` / `Config.school` | the school's WebUntis instance |

> `Secrets.swift` must **never** be committed. The `serverKey` is sensitive — see [Security](#security).

---

## How auth works

1. The user logs in with **WebUntis** credentials (`UntisClient.login`).
2. The client resolves the effective student. For a **guardian** it finds the child and, if the
   class isn't directly available, derives it from the **child's timetable** (block-school weeks are
   sampled across the year).
3. Students and guardians get a POKYH account: `BackendClient.loginWithUntis` performs a
   server-to-server login (`X-Server-Key`), returning an access token + refresh token.
   Teacher/admin accounts get no POKYH account (`backendStatus = .notStudent`).
4. **POKYH-only fallback:** if WebUntis login fails (no such account), the app automatically tries a
   direct `BackendClient.login` with the same credentials. A successful backend-only session has no
   timetable/grades, so those tabs are hidden — everything else (Mensa, to-dos, reminders) works.
5. Credentials are stored in the **Keychain**; the app re-logs in silently and locks behind biometrics.

If a guardian still resolves to no class, the backend keeps any existing membership rather than
unenrolling — a transient resolution miss never loses the class.

---

## Offline mode

For **returning accounts**, login is raced against a 5-second timeout (`Store.offlineTimeout`):

- On success → normal online session; a **token-less snapshot** of the session is persisted to
  `DiskCache` (`session-<username>`) for next time. **No tokens or cookies are ever written to disk.**
- On timeout / fast network error → the app restores the cached snapshot, flips `isOffline = true`,
  and shows an **offline banner**. The real login keeps running in the background and seamlessly
  *upgrades* the session the moment it succeeds.

Token-less (offline) sessions never call WebUntis — `UntisClient` serves timetable, grades, exams,
messages and absences straight from the on-disk cache (or empty), so the app stays usable and never
bounces you to the lock screen. Each week of the timetable you view is cached, so the lessons you
loaded are available offline.

---

## Profile pictures & avatars

- **`ImageCache`** caches avatar images in-memory (`NSCache`) and on disk (App-Group `images/`,
  SHA-256 filenames). Images appear instantly and survive offline; only image bytes are stored.
- **`AvatarView`** shows a colored initials placeholder while loading and cross-fades to the photo —
  with a graceful fallback to the initials avatar if the image can't be fetched.
- **`Palette.color(for:)`** assigns each user a random color **on first sight**, persisted per
  username in `UserDefaults` (`pokyh_avatar_hues`) — stable forever after, never hard-coded.
- The signed-in user's picture appears in the profile header, the toolbar, **and** every account row
  (the entire row is tappable to switch accounts).

---

## iPad & responsive layout

The app targets iPhone **and** iPad. Layout adapts purely by **horizontal size class** (no device
model checks): in the `.regular` size class, `appBackground()`'s `ReadableContent` modifier caps
content to a comfortable width and centers it (full-bleed background), while login/lock screens use
`centeredForm()`. On iPhone (`.compact`) it's a no-op.

---

## Widgets & Live Activities

The **`POKYHWidget`** extension provides:

- `NextLessonWidget`, `TodayScheduleWidget`, `OverviewWidget`, `GradesWidget`, `MessagesWidget`
- `LessonLiveActivity` — current/next lesson on the Lock Screen & Dynamic Island

Data is shared from the app via the **App Group** container (`WidgetBridge` → `SharedKit`). Live
Activities are driven by `LiveActivityManager`; background updates use `BGTaskScheduler` with the
identifier in `Config.bgRefreshId` (must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist).

---

## Project layout

```
POKYH/                       # app target
├── POKYHApp.swift           # @main entry
├── Config.swift             # central config: URLs + all API routes
├── Secrets.swift            # gitignored secrets (from Secrets.example.swift)
├── Store.swift              # @MainActor app state / orchestration (login, offline, switching)
├── UntisClient.swift        # WebUntis auth + data, student/guardian resolution
├── BackendClient.swift      # POKYH backend client (incl. POKYH-only login)
├── *View.swift              # SwiftUI screens (Home, Timetable, Grades, Mensa, Profile, …)
├── ImageCache.swift         # on-disk + in-memory avatar cache
├── DiskCache.swift          # persistent JSON cache (offline timetable/grades/session)
├── Cache.swift              # in-memory TTL cache
├── Theme.swift              # design system, avatar colors, responsive modifiers
├── Notifications / Background / LiveActivityManager / WidgetBridge
├── Crypto · Security · JSON · DateHelpers · GradeMath
POKYHWidget/                 # widget + Live Activity extension
Shared/SharedKit.swift       # types/data shared across targets (App Group)
Secrets.example.swift        # template for POKYH/Secrets.swift
POKYH.xcodeproj
```

---

## Performance

- **Caching everywhere:** in-memory TTL caches + on-disk JSON/image caches; viewed timetable weeks
  are precached (±2 weeks) for fluid, lag-free paging.
- **Offline never blocks the UI:** the background login upgrade keeps the app responsive.
- **No main-thread stalls:** the biometry probe (an expensive first `canEvaluatePolicy`) is warmed up
  off the main thread at launch, so the first render never hangs.
- **Animations** are lightweight spring/ease transitions; loading states use shimmer skeletons and
  `ProgressView` only where a wait is real.

---

## Security

- WebUntis credentials live in the **Keychain** (AES-GCM, `AfterFirstUnlock`); access is gated behind **Face ID / Touch ID**.
- The **offline session snapshot contains no tokens or cookies** — only display data and cache keys.
- `Secrets.swift` (API & server keys) is **gitignored** and must be supplied per build.
- All traffic is **HTTPS** (no ATS exceptions). Backend calls send `X-API-Key`; the privileged
  server-to-server login also sends the secret `X-Server-Key`.
- The on-disk caches store only academic data and image bytes — never credentials — inside the
  sandboxed App-Group container.
- Diagnostics UI is compiled in only when `Secrets.isDebug == true` — keep it `false` in production.

> ⚠️ **Note on `serverKey`:** any key embedded in a shipped client can be extracted from the binary
> by a determined attacker. Because `X-Server-Key` authorizes the privileged WebUntis→backend login,
> the backend should additionally validate each request against live WebUntis (it does) and rate-limit
> `/auth/login`. Treat the client `serverKey` as a gate, not a sole secret.

---

## Troubleshooting

| Symptom                                  | Likely cause / fix                                                                  |
| ---------------------------------------- | ----------------------------------------------------------------------------------- |
| `.noClass` after login                   | WebUntis returned `klasseId = 0` and the timetable fallback found no lessons. For guardians ensure the child resolves; enable `isDebug` for the class-resolution diagnostics. |
| `.notStudent`                            | Teacher/admin WebUntis account — no POKYH account is created (by design).            |
| POKYH-only login won't proceed           | The user must exist in the backend; check `Secrets.apiKey` and that `/auth/login` returns a token. |
| Offline banner never appears             | Offline mode only applies to **returning** accounts that have a cached session (`studentId > 0`). |
| Backend login fails                      | Check `Secrets.serverKey` == backend `SERVER_KEY` and `Secrets.apiKey` == backend `API_KEY`. |
| Widgets/Live Activity show no data       | App Group not enabled on **both** targets, or the app hasn't refreshed `SharedKit` yet. |
| Background refresh never runs            | `Config.bgRefreshId` must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist. |

---

<div align="center">

Part of the **POKYH** project · iOS (this repo) · Frontend (Next.js) · Backend (Express/Prisma)

</div>
