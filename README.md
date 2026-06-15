<div align="center">

# POKYH — iOS

**Native SwiftUI-Schulapp für die Landesberufsschule Brixen (Südtirol)**

Stundenplan · Noten (mit Notenrechner) · Mensa · Abwesenheiten · Nachrichten · Todos · Erinnerungen · Klassenbuch

</div>

> Nativer Port des [pokyh-frontend](https://github.com/bedchem/pokyh-frontend) (Next.js).
> Gleiche Funktionen & Aufbau — eigenes, natives Apple-Design.
> Nicht offiziell mit der LBS Brixen oder WebUntis verbunden.

---

## Inhalt

- [Features](#features)
- [Screenshots](#screenshots)
- [Tech Stack](#tech-stack)
- [Architektur](#architektur)
- [Projektstruktur](#projektstruktur)
- [Lokale Entwicklung](#lokale-entwicklung)
- [Konfiguration](#konfiguration)
- [Sicherheit & Datenschutz](#sicherheit--datenschutz)
- [Bekannte Einschränkungen](#bekannte-einschränkungen)
- [API-Referenz (WebUntis)](#api-referenz-webuntis)
- [Lizenz](#lizenz)

---

## Features

| Bereich | Beschreibung |
|---------|--------------|
| **Home** | Persönliche Begrüßung, heutiger Unterricht, tägliches Mensa-Gericht, zuletzt eingetragene Noten, Schnellzugriffe |
| **Stundenplan** | Wochenraster **und** Tagesansicht mit Uhrzeiten, Prüfungen, Vertretungen, Entfällen, Ferien-/Wochenend-Tagen |
| **Noten** | Fachübersicht, Gesamtschnitt, „Zuletzt eingetragen", **Notenrechner** (eigene Noten simulieren), **Zielnote-Rechner**, Verlaufs-Diagramm mit Durchschnittslinie |
| **Mensa** | Speiseplan ab dem aktuellen Tag, Bilder, Nährwerte, Allergene, **Sterne-Bewertung** & **Kommentare** |
| **Abwesenheiten** | Fehlstunden mit Jahresübersicht & Status (entschuldigt / offen) |
| **Nachrichten** | WebUntis MessageCenter: Posteingang, Gesendet, Entwürfe, Anhänge |
| **Todos** | Persönliche Aufgabenliste mit Fälligkeitsdaten |
| **Erinnerungen** | Klassenweite Erinnerungen mit Kommentaren; abgelaufene werden ausgeblendet |
| **Klassenbuch** | Klassenbuch-Einträge |
| **Klasse** | Klassencode & Mitglieder |

**Plus:** Face ID / Touch ID Login, **Mehrbenutzer** mit konfigurierbarem Standard-Konto, Hell-/Dunkel-/System-Theme, Liquid-Glass-Elemente, lokale Push-Benachrichtigungen (Erinnerungen & neue Nachrichten), weiche Animationen, Skeleton-Ladebildschirme.

---

## Tech Stack

| Was | Womit |
|-----|-------|
| UI | **SwiftUI** (iOS 26, Liquid Glass) |
| Sprache | **Swift 5** |
| Nebenläufigkeit | Swift Concurrency (`async/await`, MainActor-Isolation) |
| WebUntis-Daten | WebUntis-interne API, direkt nativ (JSON-RPC + Bearer-Token) |
| App-Daten | [POKYH Backend](https://github.com/bedchem/pokyh-backend) (Node.js, JWT) |
| Sicherheit | Keychain (Passwörter), `LocalAuthentication` (Face ID), HTTPS-only |
| Caching | In-Memory (`URLCache` für Bilder, Dish-Cache mit TTL) |
| Benachrichtigungen | `UserNotifications` (lokal geplant) |

---

## Architektur

```
SwiftUI Views ──▶ UntisClient ───▶ WebUntis API (lbs-brixen.webuntis.com)
                │   (authenticate · Bearer-Token · timetable/grades/absences/messages)
                │
                └▶ BackendClient ─▶ POKYH Backend (api.pokyh.com)
                    (Todos · Erinnerungen · Klasse · Mensa · Ratings · Kommentare)

AppState (ObservableObject)   →  Phasen: lock · login · authed
CredentialStore + Keychain    →  Mehrbenutzer · Standard-Konto · Face ID
NotificationManager           →  lokale Erinnerungs-/Nachrichten-Benachrichtigungen
```

- **Schüler- und Elternkonten:** Schülerkonten nutzen die eigenen Daten. Bei
  Erziehungsberechtigten ist `getStudents` gesperrt — das Kind wird aus den
  WebUntis-App-Daten (`user.students[0].id`) aufgelöst, alle Abfragen laufen dann
  auf das Kind.
- **Kein Hardcoding in den Views:** URLs/Keys liegen zentral in `POKYH/Config.swift`.
- **Nebenläufigkeit:** Sicherheitskritische, threadübergreifende Typen (JSON-Parsing,
  Biometrie, Benachrichtigungen) sind bewusst `nonisolated`, um Actor-Laufzeitabbrüche
  auf echter Hardware zu vermeiden.

---

## Projektstruktur

```
POKYH/
├── Config.swift              # zentrale Konfiguration (siehe .env.example)
├── Models.swift              # Datenmodelle
├── JSON.swift                # leichter dynamischer JSON-Zugriff (nonisolated)
├── Theme.swift               # Design-Tokens, Farben, Animationen
├── UntisClient.swift         # WebUntis-Networking + Parsing
├── BackendClient.swift       # POKYH-Backend (+ Dish-Cache)
├── Security.swift            # Keychain · Face ID · Mehrbenutzer
├── Notifications.swift       # lokale Benachrichtigungen
├── Store.swift               # AppState (Phasen · Theme · Login · Tabs)
├── GradeMath.swift           # Notenrechner-Mathematik
├── *View.swift               # Screens (Home, Timetable, Grades, Mensa …)
└── Assets.xcassets           # App-Icon + Logo
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
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Für ein echtes Gerät: in Xcode unter *Signing & Capabilities* das eigene Team
wählen; die App nutzt nur Standard-Capabilities (Keychain, Face ID).

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

---

## Sicherheit & Datenschutz

- Passwörter liegen ausschließlich im **Keychain** mit **biometrischer
  Zugriffskontrolle**:
  `SecAccessControl(.userPresence)` + `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
  Das Passwort ist nur nach erfolgreicher Face-ID-/Touch-ID-/Code-Prüfung
  entschlüsselbar, gerätegebunden und **nicht** in iCloud/Backups synchronisiert —
  auch bei physischem Gerätezugriff nicht auslesbar.
- Der bereits authentifizierte `LAContext` wird für den Keychain-Lesezugriff
  wiederverwendet → **eine** Face-ID-Abfrage statt zwei. `hasPassword`-Prüfungen
  (UI-Render) nutzen einen nicht-sensiblen Marker und lösen **keine** Biometrie aus.
- Ein WebUntis-Passwort muss zum Re-Login im Klartext vorliegen und kann daher nicht
  als Einweg-Hash gespeichert werden; stattdessen übernimmt das System die
  Ver-/Entschlüsselung hinter dem Biometrie-Gate.
- **Face ID / Touch ID** als Entsperr-Gate; Kontowechsel wird biometrisch bestätigt.
- **HTTPS-only** (WebUntis + Backend), keine Klartextverbindungen, keine Secret-Logs.
- Standard-Konto & zuletzt aktives Konto in `UserDefaults` (keine Geheimnisse).
- `NSFaceIDUsageDescription` ist gesetzt; Mitteilungs-Berechtigung wird nach dem
  ersten Login abgefragt.
- **App-Store-Privacy-Manifest** (`POKYH/PrivacyInfo.xcprivacy`): kein Tracking,
  keine Dritt-SDK-Datenerhebung, Required-Reason-API `UserDefaults` (CA92.1) begründet.

> ⚠️ Der `SERVER_KEY` wird für den Server-zu-Server-Login nach dem WebUntis-Login
> benötigt und liegt im Client. Für maximale Produktionssicherheit sollte das
> Backend einen dedizierten Mobile-Auth-Endpoint bereitstellen, der einen
> WebUntis-Login gegen einen Backend-Token tauscht (dann entfällt der Key im Client).

---

## Bekannte Einschränkungen

- **Mensa-Daten** stammen aus der Backend-API; liegen für heute keine Gerichte vor,
  bleibt die Mensa leer (kein Rückfall auf alte Tage).
- **Push bei geschlossener App** funktioniert für Erinnerungen (lokal geplant);
  Echtzeit-Push für neue Nachrichten bräuchte serverseitiges APNs.

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
| `GET /api/rest/view/v1/messages` | Nachrichten – Posteingang |
| `GET /api/rest/view/v1/messages/sent` | Nachrichten – Gesendet |
| `GET /api/rest/view/v1/messages/drafts` | Nachrichten – Entwürfe |
| `GET /api/rest/view/v1/messages/{id}` | Nachrichtendetail + Anhänge |
| `POST /api/rest/view/v1/messages/{id}/markasread` | Als gelesen markieren |
| `GET /api/rest/view/v1/app/data` *(+ Fallbacks)* | App-Daten (Eltern→Kind-Auflösung) |

App-Daten-Fallback-Pfade: `/api/app/data`, `/api/rest/view/v1/users/me/data`,
`/api/rest/view/v2/app/data`.

**POKYH-Backend** (`https://api.pokyh.com`): `POST /auth/login`, `POST /auth/register`,
`GET /auth/me`, `GET /dishes`, `…/dish-ratings`, `…/dish-comments`, `/users/{u}/todos`,
`/classes/mine`, `/classes/{id}/reminders` (+ Kommentare).

---

## Lizenz

MIT — kostenlos nutzbar, keine Garantie. Nicht offiziell mit der LBS Brixen oder
WebUntis verbunden.
