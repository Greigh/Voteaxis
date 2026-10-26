# App Store Connect — Voteaxis 1.0

Copy-paste-ready fields for the App Store listing. URLs must already resolve —
all verified live 2026-10-25.

## App information

- **Name:** Voteaxis
- **Subtitle (30 chars max):** `Where do you land?`
- **Bundle ID:** com.greighstudios.voteaxis
- **Primary category:** News → Politics is not a category; use **News**
- **Secondary category:** Education
- **Content rights:** No third-party content requiring rights clearance.
  Candidate roster is factual public-record data.

## Description (4000 char max)

```
Voteaxis answers a question every voter asks: where do I actually stand, and
who on my ballot is closest to me?

Take a short quiz on real issues — about three minutes — and land on a single
Liberal 100 ← 0 → Conservative 100 axis. Then see how your answers break down
across five pillars: economy, rights, health, justice, and the world.

YOUR BALLOT, RANKED
Pick your state once and Voteaxis puts your candidates first. Every figure in
the roster carries a Spectrum Issue Index placement, so you see overlap —
not party labels — before you see names.

THE ISSUE OF THE WEEK
One national question, every week, with the context that matters. Answer from
the app or the Home Screen widget — a nudge to that issue's score, never a
rescore unless you retake the quiz.

PRIVATE BY DESIGN
No account. No email. Your answers are encrypted on this device and never
leave it unless you explicitly share — QR or a 6-digit code, friend to friend,
with nothing stored on a server.

WHAT YOU GET
• One overall placement and per-pillar breakdowns
• Candidate matches ranked by issue overlap, with the record behind each score
• Steel man — the strongest case against your own strongest leans
• Saved runs — retake any time and compare where you moved
• Voter registration links for every state
• iPhone Duo support — the quiz works like a book, with context on one pane
  and your answers on the other

Voteaxis doesn't tell you what to think. It shows you where you land — and
who already stands there.
```

## Promotional text (170 char, updatable without review)

```
New: full iPhone Duo support — the quiz opens like a book, issues on one side
and answers on the other. Plus a fresh Issue of the Week every Monday.
```

## Keywords (100 char max, comma-separated, no spaces needed)

```
political,spectrum,quiz,voter,election,candidates,ballot,issues,compare,liberal,conservative,match
```

## URLs

- **Support URL:** https://voteaxis.org/support
- **Marketing URL:** https://voteaxis.org
- **Privacy policy:** https://voteaxis.org/privacy

## App review notes

```
No account is required — the app is fully usable immediately.

Test path: launch → pick any state → "Start the quiz" → answer → results.
A faster path exists from Home: "Skip the quiz — set your level" jumps
straight to placement for quick review.

The candidate roster is bundled in the app; no login, no IAP, no paywall.
If offered online, the roster refreshes via a device-key signature over
HTTPS to api.voteaxis.org — no user data is transmitted.

Notification permission is requested only inside Settings → weekly reminder,
or when iOS needs push registration for roster updates.

Camera is used only for the optional QR "compare with a friend" scan;
nothing is captured or stored.

The Home Screen widget ("Issue of the Day") reads a shared app-group store
the app writes locally — it exists so the widget can render the weekly
issue without an account.
```

## App privacy (nutrition labels)

Answer these in App Store Connect → App Privacy:

- **Data collected:** Identifiers → Device ID → **Yes** (a random per-install
  device key registers with the API for roster authorization; not linked to
  identity, not used for tracking)
- **Contact info / User content / Location / Diagnostics:** **No** —
  quiz answers and results are stored only on-device (encrypted); they leave
  only if the user shares via QR/code, which is peer-to-peer.
- **Tracking:** No. No third-party SDKs, no ads, no analytics.

## Age rating

- Political content: answer truthfully per the questionnaire; expected
  outcome is **9+ or 12+** (Infrequent/Mild for any contested-topic
  language). No violence, no gambling, no UGC, no unfiltered web.

## Screenshots (docs/store-screenshots/ios/)

iPhone 6.9" (1320×2868): onboarding, home, quiz, results, matches
iPad 13" (2064×2752): home, quiz, results, matches

Suggested order: home → quiz → results → matches (funnel), onboarding
optional as first or dropped.
