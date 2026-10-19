# Store assets

Listing copy, privacy declarations, and the screenshot checklist for the
Voteaxis iOS and Android submissions. Everything in here has to match what the
app actually does — the declarations are legal statements, not marketing.

| File | Contents |
| --- | --- |
| `app-store.md` | Apple App Store listing copy |
| `play-store.md` | Google Play listing copy |
| `privacy-declarations.md` | App Privacy + Data Safety answers, permissions, crash reporting |
| `screenshots.md` | Shot list and caption copy |
| `release-runbook.md` | Beta/release pipeline: credentials, scripts, workflows, tagging |

## Before submitting

- [ ] `privacy-declarations.md` reviewed against a current build — the answers
      track shipped behavior, so re-check after adding any network call or
      permission.
- [ ] Privacy policy live at `https://voteaxis.org/privacy`.
- [ ] Support page live at `https://voteaxis.org/support`.
- [ ] Screenshots regenerated against the current build (both light and dark
      themes once — pick light for the listing).
- [ ] `android/key.properties` stays out of git; the Play/App signing
      fingerprints in `web/public/.well-known/assetlinks.json` are public by
      design.
- [ ] iOS bundle id `com.greighstudios.voteaxis`, team `365KR8NF53` — matches
      `apple-app-site-association`.
