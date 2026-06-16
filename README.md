<div align="center">

# POKYH — iOS

**Native SwiftUI-Schulapp für die Landesberufsschule Brixen (Südtirol)**

Stundenplan · Noten (mit Notenrechner) · Mensa · Abwesenheiten · Nachrichten · Todos · Erinnerungen · Klassenbuch
· Home-Screen-Widget · Live Activity · Kalender-Export · Offline-Modus

</div>

> Nativer Port des [pokyh-frontend](https://github.com/bedchem/pokyh-frontend) (Next.js).
> Gleiche Funktionen & Aufbau — eigenes, natives Apple-Design.
> Nicht offiziell mit der LBS Brixen oder WebUntis verbunden.

---

## Inhalt

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Architektur](#architektur)
- [Targets & Datenfluss](#targets--datenfluss)
- [Projektstruktur](#projektstruktur)
- [Lokale Entwicklung](#lokale-entwicklung)
- [Widget-Target reproduzieren](#widget-target-reproduzieren)
- [Konfiguration](#konfiguration)
- [Sicherheit & Datenschutz](#sicherheit--datenschutz)
- [Performance](#performance)
- [Bekannte Einschränkungen](#bekannte-einschränkungen)
- [API-Referenz (WebUntis)](#api-referenz-webuntis)
- [Lizenz](#lizenz)

---

## Features

| Bereich | Beschreibung |
|---------|--------------|
| **Home** | Persönliche Begrüßung, heutiger Unterricht, tägliches Mensa-Gericht, zuletzt eingetragene Noten, Schnellzugriffe |
| **Stundenplan** | Wochenraster **und** Tagesansicht mit Uhrzeiten, Prüfungen, Vertretungen, Entfällen, Ferien-/Wochenend-Tagen; **`.ics`-Export** (Woche & Prüfungen) |
| **Noten** | Fachübersicht, **gewichteter Gesamtschnitt** (über alle Einzelnoten), „Zuletzt eingetragen", **Notenrechner**, **Zielnote-Rechner**, Verlaufs-Diagramm |
| **Mensa** | Speiseplan ab dem aktuellen Tag, Bilder, Nährwerte, Allergene, **Sterne-Bewertung** & **Kommentare** |
| **Abwesenheiten** | Fehlstunden mit Jahresübersicht & Status (entschuldigt / offen) |
| **Nachrichten** | WebUntis MessageCenter: Posteingang, Gesendet, Entwürfe, Anhänge |
| **Todos** | Persönliche Aufgabenliste mit Fälligkeitsdaten |
| **Erinnerungen** | Klassenweite Erinnerungen mit Kommentaren; abgelaufene werden ausgeblendet |
| **Klassenbuch / Klasse** | Klassenbuch-Einträge, Klassencode & Mitglieder |

### Plattform-Integration

| Feature | Beschreibung |
|---------|--------------|
| **Home-Screen-Widgets** | **5 Widgets** (lesen geteilte Snapshots aus der App-Group, springen automatisch weiter): <br>• **Nächste Stunde** (S/M) — laufende/kommende Stunde, Raum, Lehrkraft, Live-Countdown <br>• **Heutiger Plan** (M/L) — alle verbleibenden Stunden des Tages als Liste <br>• **Noten** (S/M) — Gesamtschnitt + zuletzt eingetragene Noten <br>• **Nachrichten** (S/M) — ungelesene + neueste Betreffzeilen <br>• **Überblick** (M/L, *kombiniert*) — nächste Stunde + Schnitt + ungelesene Nachrichten |
| **Lock-Screen-Widgets** | „Nächste Stunde" als **Inline / Rectangular / Circular** und „Noten" als **Circular-Gauge** + Rectangular — minimalistisch, vibrant-tauglich. |
| **Live Activity** | Laufende/nächste Stunde auf Sperrbildschirm **und Dynamic Island** mit Countdown (bis Start in der Pause, bis Ende während der Stunde). |
| **Offline-Modus** | Letzter erfolgreich geladener Stundenplan & Noten werden persistiert. Bei Netzwerkfehler (nicht bei Auth-Fehler) wird automatisch der Offline-Stand angezeigt. |
| **Kalender-Export** | Stundenplan-Woche und kommende Prüfungen als RFC-5545 `.ics` über das System-Share-Sheet. |

### Konten, Theme & Benachrichtigungen

- **Mehrbenutzer** mit konfigurierbarem **Standard-Konto** (setzen **und entfernen**), pro Konto: **Aktualisieren** (Re-Login → Klasse/Name) und **Umbenennen** (lokaler Spitzname, jederzeit auf Standard zurücksetzbar). Widgets & Live Activity zeigen die Daten des **Standard-Kontos**.
- **Cache & Daten löschen** (Einstellungen): entfernt alle Konten, Anmeldedaten (Keychain), den Offline-Stundenplan/Noten-Cache, geteilte Widget-Snapshots und App-Einstellungen vom Gerät. Der Offline-Cache ist **pro Schüler** (studentId) isoliert — verschiedene Konten teilen offline nie denselben Plan.
- **Face ID / Touch ID** als Entsperr-Gate; Kontowechsel wird biometrisch bestätigt.
- **Hell / Dunkel / System** mit **weichem Crossfade** beim Umschalten.
- **Lokale Benachrichtigungen**: Erinnerungen (geplant), neue Nachrichten, **neue Noten** und **Stundenausfälle** — über das App-interne Sync-System (eigener Throttle für die teureren Abrufe).

---

## Tech Stack

| Was | Womit |
|-----|-------|
| UI | **SwiftUI** (iOS 26, Liquid Glass) |
| Sprache | **Swift 5** |
| Nebenläufigkeit | Swift Concurrency (`async/await`, MainActor-Isolation) |
| Widget / Live Activity | **WidgetKit** + **ActivityKit** (eigene App-Extension) |
| Datenteilung App ⇄ Widget | **App Group** (`group.dev.plattnericus.POKYH`) + JSON-Snapshot |
| WebUntis-Daten | WebUntis-interne API, direkt nativ (JSON-RPC + Bearer-Token) |
| App-Daten | [POKYH Backend](https://github.com/bedchem/pokyh-backend) (Node.js, JWT) |
| Sicherheit | Keychain + **AES-GCM-256 (CryptoKit)**, `LocalAuthentication` (Face ID), HTTPS-only |
| Caching | In-Memory (`TTLCache`, `URLCache`) + **persistenter Disk-Cache** (Offline) |
| Benachrichtigungen | `UserNotifications` (lokal geplant) |

---

## Architektur

```
SwiftUI Views ──▶ UntisClient ───▶ WebUntis API (lbs-brixen.webuntis.com)
                │   (authenticate · Bearer-Token · timetable/grades/absences/messages)
                │      └─ Erfolg → TTLCache + DiskCache   ┐
                │      └─ Netzfehler → DiskCache-Fallback ┘  (Offline)
                │
                └▶ BackendClient ─▶ POKYH Backend (api.pokyh.com)
                    (Todos · Erinnerungen · Klasse · Mensa · Ratings · Kommentare)

AppState (ObservableObject)   →  Phasen: lock · login · authed
CredentialStore + Keychain    →  Mehrbenutzer · Standard-Konto · Spitzname · Face ID
NotificationManager           →  Erinnerungen · Nachrichten · neue Noten · Ausfälle
WidgetBridge ──▶ SharedStore ──▶ App Group ──▶ WidgetKit-Timeline (Home-Screen-Widget)
LiveActivityManager ──────────▶ ActivityKit ──▶ Live Activity (Sperrbildschirm/Island)
```

- **Schüler- und Elternkonten:** Schülerkonten nutzen ihre eigenen Daten. Bei
  Erziehungsberechtigten ist `getStudents` gesperrt — das Kind wird aus den
  WebUntis-App-Daten (`user.students[0].id`) aufgelöst.
- **Kein Hardcoding in den Views:** URLs/Keys liegen zentral in `POKYH/Config.swift`;
  Marken-Farben als *eine* Quelle in `Shared/SharedKit.swift` (`Brand`).
- **Geteilter Code, eine Quelle:** `Shared/SharedKit.swift` wird in **App und Widget**
  kompiliert → das Live-Activity-Datenmodell ist garantiert identisch.
- **Nebenläufigkeit:** Sicherheitskritische, threadübergreifende Typen (JSON-Parsing,
  Biometrie, Benachrichtigungen) sind bewusst `nonisolated`, um Actor-Laufzeitabbrüche
  auf echter Hardware zu vermeiden.

---

## Targets & Datenfluss

| Target | Produkt | Zweck |
|--------|---------|-------|
| **POKYH** | `.app` | Hauptanwendung |
| **POKYHWidgetExtension** | `.appex` | Home-Screen-Widget + Live-Activity-UI |

**So fließen die Daten zum Widget/zur Live Activity (ohne Netzwerkzugriff im Widget):**

1. Die App lädt den Stundenplan der aktuellen Woche.
2. `WidgetBridge.publish(_:)` schreibt einen kompakten `TimetableSnapshot`
   (max. 12 kommende Stunden) als JSON in den **App-Group-Container** und ruft
   `WidgetCenter.reloadAllTimelines()`.
3. `LiveActivityManager.refresh(from:)` startet/aktualisiert/beendet die Live Activity
   anhand der heutigen Stunden.
4. Das Widget liest den Snapshot über `SharedStore.readSnapshot()` — schnell,
   energiesparend, offline-fähig.

> Das Widget enthält **keine** Zugangsdaten und macht **keine** Netzwerk-Calls —
> es rendert ausschließlich den von der App bereitgestellten Snapshot.

---

## Projektstruktur

```
POKYH_IOS/
├── POKYH/                       # Haupt-App (synchronisierter Xcode-Ordner)
│   ├── Config.swift             # zentrale Konfiguration (siehe .env.example)
│   ├── Models.swift             # Datenmodelle (Codable für Offline-Cache)
│   ├── UntisClient.swift        # WebUntis-Networking + Offline-Fallback
│   ├── BackendClient.swift      # POKYH-Backend
│   ├── Security.swift           # Keychain · AES-GCM · Face ID · Mehrbenutzer
│   ├── Notifications.swift      # lokale Benachrichtigungen (inkl. Noten/Ausfälle)
│   ├── Store.swift              # AppState (Phasen · Theme · Login · Konten)
│   ├── DiskCache.swift          # persistenter JSON-Cache (Offline)
│   ├── WidgetBridge.swift       # schreibt Snapshot + Widget-Reload
│   ├── LiveActivityManager.swift# ActivityKit-Steuerung
│   ├── ICSExport.swift          # RFC-5545-Kalender-Export + Share-Sheet
│   ├── GradeMath.swift          # Notenrechner-Mathematik
│   └── *View.swift              # Screens (Home, Timetable, Grades, Mensa …)
├── Shared/
│   └── SharedKit.swift          # App Group · Snapshot · SharedStore · Brand ·
│                                #   LessonActivityAttributes  (App + Widget)
├── POKYHWidget/
│   ├── POKYHWidgetBundle.swift  # @main WidgetBundle (registriert alle Widgets)
│   ├── NextLessonWidget.swift   # Widget „Nächste Stunde" + TimelineProvider
│   ├── TodayScheduleWidget.swift# Widget „Heutiger Plan"
│   ├── GradesWidget.swift       # Widget „Noten"
│   ├── MessagesWidget.swift     # Widget „Nachrichten"
│   ├── OverviewWidget.swift     # kombiniertes Widget „Überblick"
│   ├── LessonLiveActivity.swift # Live-Activity-UI (Lock Screen + Dynamic Island)
│   ├── Info.plist               # NSExtensionPointIdentifier = widgetkit-extension
│   └── POKYHWidget.entitlements # App Group
├── POKYH.entitlements           # App Group (Haupt-App)
├── Info.plist                   # App: BGTask · NSSupportsLiveActivities
└── scripts/
    └── add_widget_target.rb     # legt das Widget-Target reproduzierbar an
```

---

## Lokale Entwicklung

**Voraussetzungen:** Xcode 26+, iOS-26-Simulator oder Gerät.

```bash
# Projekt öffnen
open POKYH.xcodeproj

# Bauen & starten (⌘R), oder per CLI:
xcodebuild -project POKYH.xcodeproj -scheme POKYH \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Der `POKYH`-Scheme baut die App **inklusive** der eingebetteten Widget-Extension.
Für ein echtes Gerät in Xcode unter *Signing & Capabilities* das eigene Team wählen;
die **App Group** (`group.dev.plattnericus.POKYH`) muss für beide Targets aktiviert sein.

---

## Widget-Target reproduzieren

Das Xcode-Projekt nutzt einen *synchronisierten* Ordner (`PBXFileSystemSynchronizedRootGroup`).
Das Widget-Target ist deshalb **reproduzierbar per Skript** angelegt — kein manuelles
Klicken in Xcode, keine fragile `project.pbxproj`-Handarbeit:

```bash
# benötigt das xcodeproj-Gem (gem install xcodeproj)
ruby scripts/add_widget_target.rb      # Target + App Group + Embedding anlegen
ruby scripts/sync_widget_sources.rb    # alle POKYHWidget/*.swift ins Target aufnehmen
```

`add_widget_target.rb` ist idempotent (bricht ab, wenn das Target existiert) und richtet
ein: Extension-Target, geteilte Quelle für App **und** Widget, Build-Settings, App-Group-
Entitlements für beide Targets sowie das Einbetten der Extension in die App.
`sync_widget_sources.rb` nimmt neu hinzugefügte Widget-Dateien ins Compile-Target auf.

---

## Konfiguration

Alle konfigurierbaren Werte sind in [`.env.example`](.env.example) dokumentiert und
liegen zentral in `POKYH/Config.swift` — nichts ist über die Views verstreut.

| Schlüssel | Zweck |
|-----------|-------|
| `BACKEND_URL` | POKYH-Backend-URL (HTTPS) |
| `API_KEY` | Backend-API-Key (öffentlich, wie im Web-Frontend) |
| `SERVER_KEY` | Server-zu-Server-Key (siehe Sicherheit) |
| `WEBUNTIS_BASE_URL` | WebUntis-Instanz-URL |
| `WEBUNTIS_SCHOOL` | Schulkürzel (`lbs-brixen`) |

Die App-Group-ID (`group.dev.plattnericus.POKYH`) ist als einzige Konstante in
`Shared/SharedKit.swift` (`AppGroup.id`) definiert und in beiden Entitlements gespiegelt.

---

## Sicherheit & Datenschutz

**Passwort-Speicherung — zwei Verschlüsselungsebenen** (`POKYH/Security.swift`):

1. **App-Ebene:** Das WebUntis-Passwort wird mit **AES-GCM (256-bit, CryptoKit)**
   verschlüsselt. Der Master-Key liegt selbst im **Keychain**
   (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), ist gerätegebunden und
   verlässt das Gerät nie.
2. **System-Ebene:** Key und Chiffrat liegen im iOS-Keychain, der sie
   hardwaregestützt erneut verschlüsselt und **nicht** in iCloud/Backups synchronisiert.

- Der Zugriff ist zusätzlich **app-seitig durch Face ID / Touch ID gegated**
  (`Biometric.authenticate` vor jedem Lesen). Bewusst **keine** `SecAccessControl`-
  Biometrie am Keychain-Item selbst — das erzwingt einen Geräte-Passcode, ist
  kontext-/reuse-abhängig und brach den Kontowechsel.
- Ein WebUntis-Passwort muss zum Re-Login im Klartext vorliegen und kann daher nicht
  als Einweg-Hash gespeichert werden; die Ver-/Entschlüsselung läuft hinter dem
  Biometrie-Gate.
- `hasPassword`-Prüfungen (UI-Render) nutzen einen nicht-sensiblen Marker
  (`kSecUseAuthenticationUIFail`) und lösen **keine** Biometrie aus.
- **HTTPS-only** (WebUntis + Backend), keine Klartextverbindungen, keine Secret-Logs.
- **Offline-Cache & Widget-Snapshot** enthalten ausschließlich fachliche Daten
  (Stundenplan/Noten) — **niemals** Zugangsdaten. Der App-Group-Container ist
  sandboxed und folgt dem System-Datenschutz; das Widget liest nur, schreibt nie.
- **Auto-Sperre:** nach längerer Inaktivität im Hintergrund wird die Sitzung beendet.
- **App-Store-Privacy-Manifest** (`POKYH/PrivacyInfo.xcprivacy`): kein Tracking,
  keine Dritt-SDK-Datenerhebung.

> ⚠️ Der `SERVER_KEY` wird für den Server-zu-Server-Login nach dem WebUntis-Login
> benötigt und liegt im Client. Für maximale Produktionssicherheit sollte das Backend
> einen dedizierten Mobile-Auth-Endpoint bereitstellen (WebUntis-Login → Backend-Token),
> dann entfällt der Key im Client.

---

## Performance

- **Mehrstufiges Caching:** `TTLCache` (In-Memory) für schnelle Wiederholzugriffe,
  `DiskCache` für Offline-Persistenz, `URLCache` für Mensa-Bilder.
- **Stundenplan-Prefetch:** ein 5-Wochen-Fenster wird im Hintergrund vorgeladen →
  flüssiges, ruckelfreies Blättern ohne Spinner.
- **Throttling der Benachrichtigungs-Syncs:** Nachrichten/Erinnerungen max. alle 60 s,
  die teureren Noten-/Stundenplan-Checks separat alle 30 min.
- **Schlanker Widget-Snapshot:** maximal 12 kommende Stunden; das Widget rechnet/lädt
  nicht selbst, sondern rendert nur.
- **Geteilte DateFormatter** statt teurer Neu-Allokation in Render-Hot-Paths.

---

## Bekannte Einschränkungen

- **Mensa-Daten** stammen aus der Backend-API; liegen für heute keine Gerichte vor,
  bleibt die Mensa leer (kein Rückfall auf alte Tage).
- **Benachrichtigungen** für neue Noten/Nachrichten/Ausfälle sind **lokal** (Polling
  beim App-Nutzen / Background-App-Refresh). Echtzeit-**Remote-Push** würde
  serverseitiges APNs (+ Apple-Developer-Push-Konfiguration) erfordern.
- **Live Activity** erscheint nur, wenn der Nutzer Live Activities aktiviert hat und
  für den aktuellen Tag Stunden vorliegen.

---

## API-Referenz (WebUntis)

Alle genutzten WebUntis-Endpunkte — zentral in `POKYH/Config.swift` (`Config.Routes`)
gebündelt, Basis `https://lbs-brixen.webuntis.com/WebUntis`:

| Methode / Pfad | Zweck |
|----------------|-------|
| `POST /jsonrpc.do?school=lbs-brixen` · `authenticate` | Login → `personId`, `klasseId`, `personType`, `JSESSIONID` |
| `POST /jsonrpc.do` · `getKlassen` | Klassennamen auflösen |
| `POST /jsonrpc.do` · `getStudents` | Zugängliche Schüler (Eltern-Auflösung) |
| `POST /jsonrpc.do` · `getCurrentSchoolyear` | Aktuelles Schuljahr |
| `POST /jsonrpc.do` · `getSchoolyears` | Alle Schuljahre (Jahres-Filter) |
| `GET /api/token/new` | Bearer-Token für REST-Endpunkte |
| `GET /api/rest/view/v1/timetable/entries` | Stundenplan (Woche/Tag, Prüfungen) |
| `GET /api/classreg/grade/grading/list` | Fächer mit Benotung |
| `GET /api/classreg/grade/grading/lesson` | Noten je Fach/Lesson |
| `GET /api/classreg/absences/students` | Abwesenheiten (paginiert) |
| `GET /api/classreg/classregevents` | Klassenbuch-Einträge |
| `GET /api/rest/view/v1/messages` *(+ `/sent`, `/drafts`, `/{id}`)* | Nachrichten |
| `POST /api/rest/view/v1/messages/{id}/markasread` | Als gelesen markieren |
| `GET /api/rest/view/v1/app/data` *(+ Fallbacks)* | App-Daten (Eltern→Kind-Auflösung) |

**POKYH-Backend** (`https://api.pokyh.com`): `POST /auth/login`, `POST /auth/register`,
`GET /auth/me`, `GET /dishes`, `…/dish-ratings`, `…/dish-comments`, `/users/{u}/todos`,
`/classes/mine`, `/classes/{id}/reminders` (+ Kommentare).

---

## Lizenz

MIT — kostenlos nutzbar, keine Garantie. Nicht offiziell mit der LBS Brixen oder
WebUntis verbunden.
