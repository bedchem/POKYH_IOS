# iOS features Android doesn't have yet

The iOS app follows the Android app screen for screen. These are the things iOS has (or is
getting) on top, so Android can catch up. Checked against `POKYH_ANDROID` v2.1.0.

Status: **done** = in the iOS app on `redesign`, **planned** = part of the rewrite, not built yet.

| Feature | iOS | Android today | What Android would need | Status |
| --- | --- | --- | --- | --- |
| Push from the server | APNs via `POST /push/apns`; new messages, due to-dos and reminders arrive even when the app hasn't run | `NotificationSyncWorker` polls every so often, nothing arrives while the worker sleeps | FCM: a `push/fcm` route next to `push/apns` in `pushPoller.ts`, same notices (`pushNotices.ts`) | backend done, app planned |
| Current lesson on the Lock Screen | Live Activity with countdown, Dynamic Island | nothing | Live Update notification (`Notification.ProgressStyle`, Android 16) with the same countdown | planned |
| More home screen widgets | Next lesson, today's schedule, grades, messages, overview | next lesson, grades | `TodayScheduleWidget`, `MessagesWidget`, `OverviewWidget` in Glance from the existing `WidgetSnapshots` | planned |
| Lock Screen / always-on widgets | accessory widgets for the next lesson and room | nothing | — (no Android equivalent; closest is At a Glance) | planned |
| To-dos ticked off in a widget | interactive widget (App Intent) | read-only | Glance `actionRunCallback` that patches the to-do through the outbox | planned |
| Control Center | open the timetable / next lesson | nothing | Quick Settings tile (`TileService`) | planned |
| Siri and Shortcuts | "Nächste Stunde", "Stundenplan heute" as App Intents | nothing | App Actions / `shortcuts.xml` | planned |
| Watch | watchOS app: today, grades, Mensa, to-dos; complications; works without the phone nearby | nothing | Wear OS app + tiles, same data via the Data Layer API | planned |
| Current lesson above the tab bar | `tabViewBottomAccessory` shows the running lesson on every tab | nothing | a slim bar above `PokyhBottomNav` | planned |

Not iOS-only, even though the old iOS app had them first: calendar export (`.ics` for the week
and for exams) and the offline mode exist on Android too.
