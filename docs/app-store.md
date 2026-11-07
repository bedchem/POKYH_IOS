# App Store

What App Store Connect asks for, and the answers. Keep it in step with the app.

## App Privacy (the label)

Nothing is used for tracking. Everything collected is linked to the account, because it is the
account's own data on the POKYH server. WebUntis data (timetable, grades, absences, messages)
goes from WebUntis straight to the device and is not collected by POKYH.

| Data type | Collected | Why | Linked | Tracking |
| --- | --- | --- | --- | --- |
| User ID (WebUntis username, POKYH id) | yes | App functionality | yes | no |
| Device ID (install id for "Geräte & Anmeldungen", push token) | yes | App functionality | yes | no |
| Other user content (to-dos, reminders, comments, dish ratings) | yes | App functionality | yes | no |
| Product interaction (time in the app, tabs opened) | yes | Analytics (only shown to the account itself and in aggregate to admins) | yes | no |
| Coarse location (city from the sign-in's IP, shown under devices) | yes | App functionality, security | yes | no |
| Crash data, performance data | no | | | |
| Contact info, health, financial, contacts, photos, browsing, search | no | | | |

The privacy manifests (`App/`, `Widgets/`, `Watch/`, `WatchWidgets/` `PrivacyInfo.xcprivacy`)
list the same, plus the required-reason APIs: UserDefaults (CA92.1, 1C8F.1 for the app group)
and file timestamps (C617.1, pruning old copies in the app's container). `docs/security.md`
says what is stored on the device and how.

## Legal

- **Privacy policy, terms, imprint:** linked on the sign-in screen and in Settings → Datenschutz
  (URLs from `POKYH_WEBSITE_URL`, nothing hard-coded).
- **Account deletion (5.1.1(v)):** Settings → Konto & Sicherheit → Konto löschen. Deletes the POKYH
  account on the server (`DELETE /users/me`) and everything on the device. Needs the backend from
  `pokyh-backend` 63e8c49 or later deployed. The WebUntis account belongs to the school and stays.
- **Data export (GDPR Art. 20):** Settings → Geräte & Anmeldungen → export.
- **User-generated content (1.2):** comments on dishes and class reminders. Each comment from
  someone else can be reported (an e-mail to POKYH in the form of DSA Art. 16) and its author
  blocked on the device (Settings → Datenschutz lists and clears blocks). Admins moderate in the
  web admin panel. The terms forbid abusive content.
- **Not affiliated:** the settings footer says POKYH isn't official from Untis or the school.
  "WebUntis" and "Untis" are named only to say what account signs in.
- **Age:** the sign-in states "ab 14 Jahren" (Italy's age of digital consent). Suggested rating
  13+ for user comments; no ads, no purchases, no gambling, no unrestricted web.
- **Encryption:** `ITSAppUsesNonExemptEncryption = NO`. Only Apple's own crypto (CryptoKit
  AES-GCM for local files, TLS through URLSession, Keychain); no proprietary encryption.
- **Push:** APNs with the `aps-environment` entitlement; needs a paid developer team
  (`POKYH_APP_ENTITLEMENTS`, see `Config/Base.xcconfig`).
- **Permissions:** camera (QR sign-in on a computer), Face ID (opening the app), adding to Photos
  (saving the recap picture). Texts in German, Italian and English (`App/InfoPlist.xcstrings`).

## Review notes (paste into App Store Connect)

> POKYH is a school companion for WebUntis. It needs a WebUntis school account to sign in:
> pick the school "<demo school>", then sign in with the demo account below. Face ID or the
> passcode protects the app; on the review device the passcode works the same.
>
> Demo account: <username> / <password> (student). A guardian account: <username> / <password>.
>
> Comments (Mensa dishes, class reminders) can be reported and their authors blocked from the
> "…" menu on each comment. The account can be deleted in Settings → Konto & Sicherheit.
>
> POKYH is not affiliated with Untis GmbH or the school.

Fill in the demo accounts before submitting; App Review rejects apps it can't sign in to.
