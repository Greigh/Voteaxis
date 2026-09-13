# Voteaxis API

Small Bun service for a VPS. **Scoring stays in the Flutter app.** This process stores temporary 6-digit friend profiles, serves Issue of the Week JSON, and runs our Congress REST API indexed from [BICAM](https://bicam.net/) (ProPublica’s Congress API is retired).

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/health` | Liveness (`congress: true` when the BICAM index is loaded) |
| `POST` | `/v1/codes` | Publish or refresh your profile; returns `{ code, token, expiresAt }` |
| `GET` | `/v1/codes/:code` | Lookup a friend’s public scores |
| `GET` | `/v1/week` | Current Issue of the Week (edit `data/issue-of-the-week.json`) |
| `GET` | `/v1/congress` | Index coverage (member/bill counts, source) |
| `GET` | `/v1/members/:bioguideId` | Member profile from BICAM |
| `GET` | `/v1/members/:bioguideId/bills` | Sponsored / cosponsored bills (`?kind=` `?limit=`) |
| `GET` | `/v1/bills/:congress/:type/:number` | One bill by citation |
| `GET` | `/v1/receipts/:bioguideId` | Convenience: recent sponsored + cosponsored bills |
| `GET` | `/v1/politicians` | **Locked down.** The curated roster. Filter with `?state=` `?officeType=` `?party=` `?current=` `?q=` (name substring) |
| `GET` | `/v1/politicians/:id` | **Locked down.** One figure by id |
| `POST` | `/v1/device-tokens` | Registers a per-install public key for the roster gate below. Open — see why |

Codes last 48 hours (`CODE_TTL_HOURS`). Republish with the same `token` to keep the same code. The payload is issue scores — not Likert answers, email, or a device id.

The Congress API is ours. BICAM is only the bulk source. On the VPS:

```bash
pip install -r scripts/requirements-bicam.txt
python3 scripts/sync_bicam.py
```

That writes `data/bicam-receipts.sqlite`. The bills download is about 2GB; the sqlite index is much smaller. Members with a `bioguideId` show recent sponsored and cosponsored bills; nominees and state legislators do not. Receipts never rescore the Spectrum Issue Index.

Optional: set `CONGRESS_API_KEY` (free at [api.congress.gov/sign-up](https://api.congress.gov/sign-up/)) so `GET /v1/receipts/:bioguideId` hydrates **latest action** and an official summary for the 10 bills already on screen. BICAM stays the roster. Hits are cached 18 hours in `data/congress-gov-cache.sqlite`. No key means today’s BICAM-only receipts. A fresher “Became Public Law…” line still does not change SII scores.

See [BICAM installation](https://py.docs.bicam.net/en/latest/installation.html).

`/v1/politicians` is ours too — it serves `server/data/politicians.json`, a copy of the app's bundled `mobile/assets/data/politicians.json` (the source of truth stays there; `mobile/` is never shipped to the box, so a served copy has to live here instead). After editing the roster:

```bash
python3 scripts/sync_politicians.py   # or: bun run sync:politicians
```

The app fetches this to refresh its bundled copy at launch (falling back to the bundled asset when offline or on a fresh install — see `mobile/lib/services/politicians_cache.dart`); the response carries an `ETag` and `Cache-Control: public, max-age=3600` so a repeat check that finds nothing changed is a `304`, not a re-download of the ~1.5 MB roster.

### Locking down `/v1/politicians`

`/v1/politicians*` accepts **two independent credentials** — a request needs either one, not both:

1. **Shared key** (`x-voteaxis-key` matching `POLITICIANS_API_KEY`). Personal-only: fine for you, not for a shipped app, because a value baked in with `--dart-define` can be pulled back out of the binary. This is what's active today.
2. **Signed per-install device** (`x-voteaxis-device-id` / `-timestamp` / `-nonce` / `-signature`, from a keypair registered by `POST /v1/device-tokens`). This is the mechanism meant for general release, and it is *not* a bearer token: the private key is generated on-device and never leaves it, `POST /v1/device-tokens` only ever receives the public half, and every request is signed fresh. There is no static value anywhere — not in the binary, not on the wire — that by itself unlocks the roster. Registration is deliberately unauthenticated — a fresh install has no credential yet to check it against, so it's the bootstrap step, not a protected route. What keeps that from being an open roster proxy is `POLITICIANS_ALLOW_DEVICE_TOKENS`: **devices register fine regardless, but a signature doesn't unlock anything until it's `true`.** It's `false` by default.

A signed request is checked five ways, in order: the deviceId/nonce/signature are the right shape; the deviceId is a registered device; the timestamp is within 5 minutes of the server's clock; the signature verifies over `method\npath\ndeviceId\ntimestamp\nnonce` under that device's registered public key (binding the method and path means a signature captured off one route can't be replayed against another); and the exact (deviceId, nonce) pair hasn't been used before (so even a byte-for-byte captured request is single-use, not just time-limited). Only a request that clears all five bumps the device's last-seen time — a rejected attempt never extends a real device's idle window or spends its nonce.

With both `POLITICIANS_API_KEY` unset and `POLITICIANS_ALLOW_DEVICE_TOKENS` not `true`, both routes 401 for every caller — that's today's state, and it's deliberate, not a bug to fix. `GET /health` reports `politiciansGated` and `politiciansDeviceTokens` so you can see which (if either) is live; `bun run deploy` warns if neither is set.

**To open the roster to real app installs later:**
1. Set `POLITICIANS_ALLOW_DEVICE_TOKENS=true` in `server/.env` and redeploy. `POLITICIANS_API_KEY` can stay set (your own access keeps working) or be unset entirely (the app never needs it — see below).
2. Ship the app with no `VOTEAXIS_POLITICIANS_KEY` dart-define. It already generates a keypair and registers it on first need (`mobile/lib/services/device_token.dart`), keeps the private key in `flutter_secure_storage`, and signs every roster fetch — no app-side change required.

**Be honest with yourself about what this buys you.** A verified signature is not proof the caller is *your app* — `POST /v1/device-tokens` has no way to check that, since there's no account or app-store receipt verification behind it, and nothing stops someone from reading this scheme out of the shipped app (or this repo) and reimplementing the same register-then-sign dance in their own client. What it buys, genuinely: there is no static secret anywhere for anyone to grep out and reuse — the shipped binary contains only *code*, not a value that works on its own — registration is rate-limited (5/hour/IP — a real install needs one, ever), and a captured request is useless outside its 5-minute window and unusable even inside it a second time. That is real friction and a real improvement over a single embedded key; it is still not cryptographic proof of app authenticity. Closing that gap for real needs platform app-attestation (Apple's App Attest, Google's Play Integrity) verified server-side — a genuinely bigger lift (native code on both platforms, developer-account and cloud-project setup on both), not something to reach for until scraping is an actual observed problem rather than a theoretical one.

**Telling "theoretical" from "observed":** every failed `/v1/politicians*` auth attempt logs a line (`politicians auth failed ip=… path=…`, never the key or signature that was tried), and more than 10 failures from one IP inside 15 minutes escalates to a louder `repeated politicians auth failures … possible scraping or key-guessing` line. `pm2 logs voteaxis-api | grep politicians` is the whole mechanism — a cheap way to notice scraping before deciding whether App Attest / Play Integrity is worth building, not a defense by itself (the existing 60/hour-per-IP rate limit on both routes is what actually throttles it).

An idle device (no request in ~180 days) is swept the next time anything triggers `Store.purgeExpired()` — a reinstalled or long-dormant app just registers again, same as a fresh install. A device row carries only its public key and timestamps: no IP, no other identifier, matching the rest of this API's privacy stance.

## Run locally

```bash
cd server
bun run dev
# http://localhost:8787/health  →  { "congress": true } when bicam-receipts.sqlite is present
```

Point the app at it:

```bash
VOTEAXIS_API_URL=http://127.0.0.1:8787 bun run mobile
```

On a physical device, use your computer’s LAN IP instead of `127.0.0.1`.

## VPS (PM2)

One Bun process. Do not cluster — friend codes, BICAM, and the Congress.gov cache are SQLite.

Full box-level runbook (both processes, DNS, TLS, firewall): [`../DEPLOY.md`](../DEPLOY.md). The short version for this package:

On the box: Bun, PM2 (`npm i -g pm2`), Python 3 for the BICAM sync, and Caddy or nginx for TLS.

```bash
cd server
cp .env.example .env   # then set CONGRESS_API_KEY
# copy bicam-receipts.sqlite into data/ (or run the sync below)
pip install -r scripts/requirements-bicam.txt
python3 scripts/sync_bicam.py --db ./data/bicam-receipts.sqlite
pm2 start ecosystem.config.cjs
pm2 save
pm2 startup            # follow the command it prints so it survives reboot
```

`ecosystem.config.cjs` sets `cwd` to this folder, runs `src/index.ts` with Bun, and loads `.env`. After a git pull:

```bash
cd server
pm2 restart voteaxis-api
```

Logs: `pm2 logs voteaxis-api`. Health: `curl -s http://127.0.0.1:8787/health` — `congress: true` when the BICAM index is present, `congressGov: true` when the key is loaded.

BICAM sync and the VoteView scorer stay one-shot jobs (cron or manual). Do not put them under PM2.

Put TLS in front with Caddy or nginx. Keep `HOST=127.0.0.1` so the proxy is the only way in — binding `0.0.0.0` on a VPS serves the API over plain HTTP on `:8787` and lets callers bypass the rate limiter. The API does not reflect CORS origins (Flutter does not need them). Rate limits use `X-Real-IP` or `CF-Connecting-IP` — not client-supplied `X-Forwarded-For`, so the proxy **must** set `X-Real-IP` or every caller shares one bucket. Ready-made config: [`../deploy/Caddyfile.example`](../deploy/Caddyfile.example).

```
api.voteaxis.org {
  reverse_proxy 127.0.0.1:8787 {
    header_up X-Real-IP {remote_host}
  }
}
```

Then ship the app with:

```bash
flutter run --dart-define=VOTEAXIS_API_URL=https://api.voteaxis.org
```

The default in `lib/config.dart` is `https://api.voteaxis.org`.
