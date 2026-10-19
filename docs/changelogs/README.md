# Store release notes

Every shipped build has a notes file per platform named for its build number:

    docs/changelogs/android/<build>.txt   → Google Play "What's new" (500 chars max)
    docs/changelogs/ios/<build>.txt       → TestFlight / App Store notes (4000 chars max)

Format — first line names the build, bullets follow:

    Voteaxis 1.0.0 (Build 3)

    • First line of what changed
    • Second line of what changed

`npm run version:bump` (or `--bump` on either release script) refuses to mint a
build number until both files exist for it — that is deliberate: build numbers
are what the notes are keyed by, and a bump without notes used to ship the
previous build's copy.

`whatsnew-en-US.txt` and `release_notes.txt` are **generated** by
`scripts/native-versions.js`, not edited: when the store is already serving an
older build the file aggregates every build newer than that one, so users
updating past several builds read all of them.

`production-builds.json` records what each store currently serves the public:

    { "android": { "version": "1.0.0", "build": 2 }, "ios": null }

Update it when a build actually goes live (after review, not at upload). It
drives both the notes aggregation and the high-water build number — together
with `v<version>+<build>` git tags it is why a versionCode is never reused.
