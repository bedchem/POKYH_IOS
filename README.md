# POKYH for iPhone, iPad and Apple Watch

POKYH is a school app for students on WebUntis. It puts everything from WebUntis in one place
(timetable, grades, absences, messages) and adds what WebUntis does not have: the Mensa menu,
to-dos, class reminders and an overview of your own activity. POKYH exists as a website
([pokyh.com](https://pokyh.com)), an Android app and this iOS app. All three use the same
account and look and work the same way.

This repository is the native app for iPhone, iPad and Apple Watch, written in Swift and SwiftUI.

## What the app does

- **Timetable:** substitutions, cancellations and room changes at a glance, week or day.
- **Grades:** averages, trends and what you still need, per subject.
- **Absences:** report and excuse them, and see how many hours you can still miss.
- **Messages:** read WebUntis messages and write to teachers.
- **Mensa:** the menu of the day, with ratings and comments.
- **To-dos and class reminders:** shared with your class.
- **Notifications:** new messages, due to-dos and reminders as push notifications, new grades
  and cancelled lessons on top. Tapping one opens it in the app.
- **Widgets and Live Activity:** the next lesson, today's schedule, grades and messages on the
  Home Screen and Lock Screen, the current lesson in the Dynamic Island.
- **Apple Watch:** today's lessons, grades, the Mensa and your to-dos, with complications.
  Works with the iPhone nearby and on its own.
- **Offline:** the app keeps working with the last loaded data and shows how old it is.
- **Accounts and sign-in:** any WebUntis school, several accounts, Face ID, two-factor codes,
  and signing in on a computer by scanning a QR code.
- **Languages:** German, Italian and English.

## Requirements

iOS and iPadOS 26 or newer, watchOS 26 or newer.

## Building

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make setup    # copies the config templates and generates POKYH.xcodeproj
make open     # opens it in Xcode: pick the POKYH scheme and an iPhone simulator, then Run
make run      # or build and launch on the iPhone simulator from the terminal
```

`make setup` creates `Config/Secrets.xcconfig` (the POKYH API keys) and `Config/Local.xcconfig`
(your team id). Both stay on your machine. Debug builds run without keys and Xcode shows a
warning; a release build stops until they're there. Everything else that differs between
builds (backend address, bundle ids, app group) lives in `Config/Base.xcconfig`.

Other targets: `make build-ipad`, `make build-watch`, `make test`, `make clean`.

The shared code is a local Swift package, `Packages/PokyhKit`, with `PokyhCore` (models, clients,
storage, texts) and `PokyhDesign` (colors, type, components). Its tests run on the Mac:

```sh
cd Packages/PokyhKit && swift test
```

## Project layout

| Folder | What's in it |
| --- | --- |
| `App` | The iPhone and iPad app |
| `Widgets` | Home Screen and Lock Screen widgets, Live Activity |
| `Watch`, `WatchWidgets` | The Apple Watch app and its complications |
| `Packages/PokyhKit` | Code shared by all of them |
| `Config` | Build settings and the (gitignored) keys |
| `docs` | Notes, e.g. what iOS has that Android doesn't yet |

## Related

- Website: [pokyh.com](https://pokyh.com)
- Web app: [bedchem/pokyh-frontend](https://github.com/bedchem/pokyh-frontend)
- Android app: [bedchem/POKYH_ANDROID](https://github.com/bedchem/POKYH_ANDROID)
- Backend: [bedchem/pokyh-backend](https://github.com/bedchem/pokyh-backend)

POKYH is a student project and is not officially connected to any school or to Untis.

## License

[MIT](LICENSE)
