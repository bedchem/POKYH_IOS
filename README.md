<div align="center">

# POKYH — iOS

**The native SwiftUI app for students and guardians of LBS Brixen — WebUntis, reimagined.**

Stundenplan · Noten · Mensa · Abwesenheiten · Nachrichten · To-dos · Klassen-Erinnerungen — plus Home-Screen widgets and Live Activities.

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
- [Widgets & Live Activities](#widgets--live-activities)
- [Project layout](#project-layout)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

---

## Overview

POKYH for iOS is a native SwiftUI client for the **Landesberufsschule Brixen** (South Tyrol).
It talks directly to the school's [WebUntis](https://www.untis.at/) instance for timetable,
grades, messages and absences, and to the **POKYH backend** (`api.pokyh.com`) for the cafeteria
menu, to-dos and class reminders — the same backend the web app uses.

It ships with **Home-Screen widgets**, **Lock-Screen / Dynamic Island Live Activities** for the
next lesson, biometric lock, multi-account support and background refresh.

---

## Features

- 📅 **Stundenplan** — timetable with lesson details
- 📊 **Noten** — grades with subject views and averages (`GradeMath`)
- 🍽️ **Mensa** — daily menu with ratings & comments
- 🚫 **Abwesenheiten** — view (and, where permitted, report/excuse)
- ✉️ **Nachrichten** — WebUntis message center
- ✅ **To-dos** & 🔔 **Erinnerungen** — synced via the POKYH backend
- 👪 **Eltern-Accounts** — guardians log in; the child's class is resolved automatically (incl. from the child's timetable)
- 🔐 **Biometric lock** (Face ID / Touch ID) and Keychain-stored credentials
- 👥 **Multi-account** — switch between saved accounts
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
│   BackendClient ───────────►  POKYH Backend (api.pokyh.com)           │
│                                                                        │
│   Keychain (creds) · Crypto · Cache/DiskCache · Notifications          │
│   WidgetBridge ──────────────────────┐                                 │
└───────────────────────────────────────┼───────────────────────────────┘
                                        │  App Group (shared container)
┌───────────────────────────────────────▼───────────────────────────────┐
│  POKYHWidget (extension)  ·  SharedKit  ·  Live Activity + widgets      │
└────────────────────────────────────────────────────────────────────────┘
```

- **`UntisClient`** — WebUntis auth and data (timetable, grades, messages, absences). Resolves the
  effective student: for a **guardian**, it finds the child and derives their class from the
  child's **timetable** when WebUntis doesn't expose it directly.
- **`BackendClient`** — POKYH backend calls. Login is a trusted **server-to-server** call with
  `X-Server-Key` + `X-API-Key`; user requests carry a `Bearer` token.
- **`Store`** — the app's single source of truth (`@MainActor`), orchestrating login, account
  switching and data refresh.
- **`SharedKit` + App Group** — shares the data the widgets and Live Activities render.

---

## Requirements

- **Xcode** (matching the project's Swift toolchain) on macOS
- **iOS deployment target: 26.0** (see `IPHONEOS_DEPLOYMENT_TARGET`)
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

---

## Configuration & secrets

All non-secret configuration lives centrally in **`POKYH/Config.swift`** (backend URL, WebUntis
base/school, every API route). Secrets live in the **gitignored** `POKYH/Secrets.swift`:

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

> `Secrets.swift` must **never** be committed. The `serverKey` is sensitive; ship it via your build
> configuration / secret management, not in source control.

---

## How auth works

1. The user logs in with **WebUntis** credentials (`UntisClient.login`).
2. The client resolves the effective student. For a **guardian** it finds the child and, if the
   class isn't directly available, derives it from the **child's timetable** (block-school weeks are
   sampled across the year).
3. Only students and guardians get a POKYH account: `BackendClient.loginWithUntis` performs a
   server-to-server login (`X-Server-Key`), returning an access token + refresh token.
   Teacher/admin accounts get no POKYH account (`backendStatus = .notStudent`).
4. `BackendClient.me` fetches the POKYH profile (incl. `classId`) for reminders & to-dos.
5. Credentials are stored in the **Keychain**; the app can re-login silently and lock behind
   biometrics.

If a guardian still resolves to no class, the backend keeps any existing membership rather than
unenrolling — a transient resolution miss never loses the class.

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
├── Store.swift              # @MainActor app state / orchestration
├── UntisClient.swift        # WebUntis auth + data, student/guardian resolution
├── BackendClient.swift      # POKYH backend client
├── *View.swift              # SwiftUI screens (Home, Timetable, Grades, Mensa, …)
├── Notifications / Background / LiveActivityManager / WidgetBridge
├── Crypto · Security · Cache · DiskCache · JSON · DateHelpers · GradeMath
POKYHWidget/                 # widget + Live Activity extension
Shared/SharedKit.swift       # types/data shared across targets (App Group)
Secrets.example.swift        # template for POKYH/Secrets.swift
POKYH.xcodeproj
```

---

## Security

- WebUntis credentials are stored in the **Keychain**; the app gates access behind **Face ID / Touch ID**.
- `Secrets.swift` (API & server keys) is **gitignored** and must be supplied per build.
- Backend calls send `X-API-Key`; the privileged login also sends the secret `X-Server-Key`.
- Diagnostics UI is compiled in only when `Secrets.isDebug == true` — keep it `false` in production.

---

## Troubleshooting

| Symptom                                  | Likely cause / fix                                                                  |
| ---------------------------------------- | ----------------------------------------------------------------------------------- |
| `.noClass` after login                   | WebUntis returned `klasseId = 0` and the timetable fallback found no lessons. For guardians ensure the child resolves; enable `isDebug` for the class-resolution diagnostics. |
| `.notStudent`                            | Teacher/admin WebUntis account — no POKYH account is created (by design).            |
| Backend login fails                      | Check `Secrets.serverKey` == backend `SERVER_KEY` and `Secrets.apiKey` == backend `API_KEY`. |
| Widgets/Live Activity show no data       | App Group not enabled on **both** targets, or the app hasn't refreshed `SharedKit` yet. |
| Background refresh never runs            | `Config.bgRefreshId` must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist. |

---

<div align="center">

Part of the **POKYH** project · iOS (this repo) · Frontend (Next.js) · Backend (Express/Prisma)

</div>
