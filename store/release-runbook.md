# Release runbook

How a Voteaxis build reaches Google Play and TestFlight. The pipeline is the
same shape locally and on CI: `scripts/play-upload.js` for Android,
`scripts/ios-testflight.sh` for iOS, `scripts/native-versions.js` keeping
build numbers coherent, `scripts/check-credentials.js` telling you what is
missing before a release starts.

The workflows live on GitHub (`.github/workflows/play-release.yml`,
`ios-testflight.yml`) and are **dispatch-only** — they never run on push.
Dispatch them from the GitHub Actions tab, not Forgejo: the runner there has
no macOS, no Xcode, and none of the store secrets.

## One-time setup

### 1. Android signing (done on this machine)

`mobile/android/key.properties` exists and points at
`~/voteaxis-upload.p12` (alias `upload`). Both are gitignored — the keystore
is backed up off this machine, because losing it locks the Play listing
forever.

For CI, encode it once:

    base64 -i ~/voteaxis-upload.p12 | pbcopy

…then `gh secret set PLAY_UPLOAD_KEYSTORE_BASE64` (paste), plus
`PLAY_UPLOAD_STORE_PASSWORD`, `PLAY_UPLOAD_KEY_ALIAS` (`upload`),
`PLAY_UPLOAD_KEY_PASSWORD`.

### 2. Google Play service account

Play Console → Setup → API access → link a Google Cloud project → create a
service account → grant it **Release** permissions on the app. Download its
JSON key.

- Locally: `GOOGLE_PLAY_SA_LOCAL=~/voteaxis-play-sa.json` in `.env`
- CI: `gh secret set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON < voteaxis-play-sa.json`

Note: the app must exist in Play Console first (create it, fill the store
listing from `store/play-store.md`). The first upload to a *track* can come
from the API; the app entry itself cannot.

### 3. App Store Connect API key

App Store Connect → Users and Access → Integrations → App Store Connect API
→ Team Keys → generate. **Role: Developer** — App Manager can upload but
cannot create the distribution certificate and profile that
`-allowProvisioningUpdates` makes on the runner.

Download `AuthKey_XXXXXXXXXX.p8` (one download, ever — Apple does not keep
a copy).

- Locally: `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`
  and `APP_STORE_CONNECT_API_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8`
  in `.env` (or drop the .p8 there and it is found by convention).
- CI: same three as secrets; paste the .p8 *contents* as
  `APP_STORE_CONNECT_API_KEY` (real newlines are fine in a GitHub secret).

## Cutting a release

1. Write release notes — `docs/changelogs/android/<next-build>.txt` and
   `docs/changelogs/ios/<next-build>.txt`, first line
   `Voteaxis X.Y.Z (Build N)`. The bump refuses to proceed without them;
   see `docs/changelogs/README.md`.
2. `npm install` at the root once (fetches `googleapis` for the Play script).
3. `node scripts/check-credentials.js` — every line OK/WARN understood.
4. Bump: `npm run version:bump` — mints `max(pubspec, tags, live builds)+1`
   and syncs pubspec, the Xcode project, and the generated store notes.

### Local

    node scripts/play-upload.js --build              # AAB → internal track
    node scripts/play-upload.js --build --track beta # → open testing
    ./scripts/ios-testflight.sh                      # IPA → TestFlight

### CI (GitHub Actions)

- "Play Release (AAB)" — pick track + optional rollout fraction.
- "iOS TestFlight (IPA)" — archives, signs via automatic provisioning with
  the API key, uploads. `manageAppVersionAndBuildNumber` lets Apple assign
  the build number, so no bump is needed on the runner.

5. Tag it: `git tag v1.0.0+<build> && git push --tags` — the tags are the
   build-number registry; without them the next bump can collide.
6. When a build actually goes live to users, record it in
   `docs/changelogs/production-builds.json` so the next release's notes
   aggregate correctly.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Unresolved reference HomeWidgetGlance…` on build | home_widget 0.10.0 is broken upstream — pubspec pins `^0.9.4` |
| `URIError`/PEM errors from the ASC key | the `.p8` lost its END marker or newlines — re-paste; in `.env` use `\n` escapes |
| Play upload `packageNotFound` | the app entry doesn't exist in Play Console yet — create it manually once |
| `App Manager` key can't sign | ASC key role too low — needs **Developer** for `-allowProvisioningUpdates` |
| versionCode already used on Play | a tag was skipped — `git tag v<ver>+<build>` every shipped build |
| Debug-signed AAB rejected | `key.properties` missing on that machine — Play refuses debug signatures |
