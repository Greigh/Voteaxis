# Privacy declarations

Answers for the App Store "App Privacy" questionnaire and the Play "Data
safety" form. Both forms ask the same questions differently; the honest
answers come from the same facts:

- Quiz answers, scores, home state, district, and settings are stored on the
  device (answers/progress in platform secure storage; preferences in plain
  app storage). They are never transmitted.
- A shared result is uploaded only when the user taps "Create my link" or
  sends a transfer link — and it can be password-sealed on-device first.
- Friend sync sends a short code plus issue scores to the API, only when the
  user initiates it; the API stores coordinates, not quiz answers.
- The Issue of the Day fetch is an unauthenticated GET with no identifiers.
- The home-screen widget fetches the same public issue — same request.
- No ads, no analytics SDK, no crash-reporting SDK, no runtime font fetches.

## Apple App Privacy

| Data type | Collected? | Linked to user? | Purpose |
| --- | --- | --- | --- |
| Contact info | No | — | — |
| Identifiers | See device token note | — | — |
| User content (quiz answers) | **Not collected** — never leaves device unless user explicitly shares | — | — |
| Usage data | No | — | — |
| Diagnostics | No SDK. Only the OS-provided crash logs the user already opted into at the Apple ID level | — | — |

**Device token note:** the app registers an APNs/FCM device token + public key
with the API only when it is running (`POLITICIANS_ALLOW_DEVICE_TOKENS=false`
keeps it server-side-off until launch). If the declaration form forces a
choice, declare **Identifiers → Device ID → collected, not linked, app
functionality**. If the flag stays off at submission, "No" is also defensible —
re-check this at ship time.

## Google Play Data Safety

| Question | Answer |
| --- | --- |
| Does your app collect or share any user data? | **Yes** (be conservative — see below) |
| Location | No |
| Personal info | No |
| App activity (quiz answers) | **Collected ephemerally / user-initiated shares only** — declare "App activity → Other user-generated content, optional, not linked, encrypted in transit, user can delete (revoke link)" to cover shared results |
| Device IDs | Optional, app functionality — the device token note above applies here too |
| Data encrypted in transit | Yes (TLS; shared results optionally end-to-end encrypted) |
| Data can be deleted | Yes — links can be revoked; local data via "Delete everything" |

If the reviewer pushes back: shared results are user-created, user-initiated,
and revocable — that is the honest framing, not "we collect nothing."

## Permissions

| Permission | Why | Declared |
| --- | --- | --- |
| `INTERNET` | Issue of the Day, shared links, roster refresh | Android manifest |
| `CAMERA` | Scanning a friend's sync QR in friend compare | Android manifest; iOS `NSCameraUsageDescription` must be set in Info.plist |
| `POST_NOTIFICATIONS` | Optional daily Issue of the Day reminder — local, user-toggle | Android manifest (runtime prompt on 13+) |
| `RECEIVE_BOOT_COMPLETED` | Re-arm the local reminder after reboot | Android manifest |
| Associated domains | Open `voteaxis.org/result/…` links in-app | iOS entitlements |
| App group | Home-screen widget reads shared container | iOS entitlements |

**Check `NSCameraUsageDescription` exists in `ios/Runner/Info.plist`** — camera
is used for QR sync and App Review rejects without the string.

## Crash reporting decision

No SDK (Firebase Crashlytics, Sentry, etc.) — a crash reporter would break the
"nothing leaves this phone" promise for its exact failure modes. Coverage comes
from the stores' own opt-in crash reporting (App Store Connect / Play Vitals),
which requires no code and no disclosure beyond what the OS already says.

## Advertising / tracking

- `IDFA`: not used. No AppTrackingTransparency prompt — do not add one.
- Play ads declaration: no ads.
