# Voteaxis — mobile

Flutter app for **iOS and Android** — this is where the quiz lives.

Take 12, 25, or 40 Likert questions (your pick, drawn from an 81-item bank) on the Spectrum Issue Index, land on a liberal↔conservative axis, and see which American presidents and political figures match your issues (and where you diverge).

## Features

- Onboarding  
- Quiz with save / resume  
- Results: axis placement, filters, ranked matches  
- Politician detail (pillars, stances, bio, Congress receipts)  
- Methodology  
- Contribute to Voteaxis (web contribution; civic loop stays free)  
- Per-question importance + dealbreakers  
- Compare with a friend (QR or 6-digit code, shared axis + Venn)  
- Compare saved runs + run history  
- Share card  
- Issue of the Day home/lock-screen widget (Agree/Disagree micro-calibrates one SII issue in the background)

## Home & lock screen widget

Flutter cannot draw home or lock screen widgets in Dart. The UI is native (SwiftUI on iOS, RemoteViews XML on Android). [`home_widget`](https://pub.dev/packages/home_widget) copies the day’s prompt into an App Group / SharedPreferences and routes Agree/Disagree taps back to Dart (`lib/services/widget_bridge.dart`) so SII updates without opening the quiz.

- iOS: add the **Issue of the Day** widget from the home-screen or lock-screen gallery. Interactive buttons need iOS 17. Enable the App Group `group.com.greighstudios.voteaxis` on both `com.greighstudios.voteaxis` and `com.greighstudios.voteaxis.IssueWidget` in the Apple Developer portal.
- Android: long-press the home screen → Widgets → Voteaxis → **Issue of the Day**.
- One calibration per calendar day. No saved quiz → the widget asks you to open the app. A tap does not replace the full quiz.

## Data

Curated catalogs in [`assets/data/`](assets/data/):

| File | Contents |
|------|----------|
| `questions.json` | 81-item Likert bank (69 modern + 12 Progressive Era) — issue, polarity, and a steel-man argument |
| `issues.json` | 22 issues → five pillars |
| `pillars.json` | Pillar labels |
| `politicians.json` | 738 figures (454 sitting, 284 former) with issue vectors + confidence |
| `rollcall_scores.json` | VoteView overlay for 115 members: lifetime issue blend plus per-Congress coordinates for the profile slider |

Scoring: [`lib/models/scoring.dart`](lib/models/scoring.dart) (SII v1).

## Run

Requires [Flutter](https://docs.flutter.dev/get-started/install).

From the monorepo root:

```bash
bun run ios        # or: bun run android
bun run test
bun run lint
```

Or in this folder:

```bash
flutter pub get
flutter run
flutter test
flutter analyze
```

Device shortcuts from root: `bun run ios` · `bun run android`

Congress receipts need the local API (production `api.voteaxis.org` will not have the BICAM index until that sqlite file is on the VPS):

```bash
bun run api
VOTEAXIS_API_URL=http://127.0.0.1:8787 bun run ios
```

## Related

- Monorepo overview: [`../README.md`](../README.md)  
- Marketing site (no quiz): [`../web/README.md`](../web/README.md)
