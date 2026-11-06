# What POKYH keeps on the device, and how

Short version for App Review and the privacy label: passwords live in the Keychain behind
Face ID, Touch ID or the device passcode. Everything else the app stores is school data the
account can already see in WebUntis or POKYH, sealed with AES-GCM under a key that never
leaves the device. Nothing syncs to iCloud, nothing goes into backups, and tokens never touch
the disk.

## Where things are

| What | Where | Protection |
| --- | --- | --- |
| WebUntis password (or app key) per account | Keychain, one item per account | `WhenPasscodeSetThisDeviceOnly` + `.userPresence`: opens only with Face ID, Touch ID or the passcode, only while unlocked, deleted if the passcode is turned off. Never synced, never backed up. Without a passcode nothing is saved and the account asks again. |
| Copy of the watch account | Keychain | `WhenUnlockedThisDeviceOnly`, no biometry (the watch asks in the background). Only the one account handed to the watch. |
| WebUntis session, POKYH access and refresh tokens | Memory only | Gone on lock, sign-out and quit. |
| Vault key (seals all files below) | Keychain, app group shared with the widgets | `AfterFirstUnlockThisDeviceOnly`, so widgets can read their data on a locked phone. |
| Offline copies: timetable weeks, grades, absences, class register, messages, to-dos, reminders, class, exams, homework, menu, a token-free session snapshot | `Application Support/Sealed/offline`, one folder per account | AES-GCM with the vault key, file names are keyed hashes, file protection `complete` (unreadable while locked), excluded from backup. |
| New to-dos and reminders typed offline | Same folder as the account's copies | Same. Sent on the next sign-in. |
| Profile pictures | `Caches/Sealed/images` | Same sealing, file protection `complete`. |
| Widget data (default account only) | App group `Sealed/widgets` | Sealed with the vault key, file protection until first unlock. |
| Account list (username, class, nickname, picture URL, school), settings | UserDefaults | No secrets. |
| Dish photos | URLCache | Public pictures only; people's pictures skip URLCache. |

## When it goes

- **Sign-out:** the password, the account's offline folder, its queued items, the watch copy,
  the widgets' data if it was the default account, the Live Activity and scheduled reminders.
  The account stays in the list with its name and picture.
- **Remove account:** the same, plus the list entry and the picture.
- **Clear all data:** every Keychain item, every sealed file, the vault key itself, all app
  settings, scheduled and delivered notifications.
- **Lock** (launch, ten minutes in the background, signing out): the session and the in-memory
  caches go; the disk copies stay sealed. Opening again needs Face ID or the passcode.
- **Pruning:** a copy not written for 45 days is deleted, at most once a day after an online
  sign-in. Offline nothing is pruned, the old copy is all there is.

## Offline

An account that signed in on this device before opens without a network after Face ID or the
passcode. The unlock reads the password (which is what proves the person), then shows the
token-free snapshot and the stored copies if WebUntis can't be reached (at once without a
network path, else after five seconds). The app never sends a request with the offline session;
it signs in for real as soon as the connection is back. Ticking, editing and deleting say "not
available offline"; new to-dos and reminders wait in the queue.

## Screens and the system

- The app switcher and Control Center see a cover, not the content.
- Passwords are typed in secure fields. The two-factor secret is `privacySensitive` and, when
  copied, stays on this device and leaves the clipboard after two minutes.
- No logging of requests, answers or credentials. Credentials only travel in request bodies,
  never in URLs.
- TLS: URLSession defaults, ephemeral sessions, no custom trust handling. ATS only allows the
  local network beyond the defaults.
- No jailbreak or debugger checks: they don't protect anything the Keychain and data
  protection don't already, and App Review frowns on them.

## The watch

The watch signs in to WebUntis on its own, so it needs the password (or app key). The phone
hands it over through WatchConnectivity, which Apple encrypts end to end between the paired
devices, and keeps one copy to answer the watch later. That copy has no Face ID in front of it,
since the watch asks while the app is in the background; it only opens while the phone is
unlocked, and a locked phone doesn't answer at all rather than telling the watch "signed out".

Open point: WatchConnectivity keeps the last application context on disk itself, and that
context carries the account. Moving the secret out of it changes the hand-off on both sides and
needs testing on a paired device first.
