# Deploying Voteaxis to a VPS

Two processes under PM2 behind Caddy. The Flutter app is not deployed here — it
ships through the App Store and Play Store and only talks to `api.voteaxis.org`.

| Process | PM2 name | Binds | Public host |
|---------|----------|-------|-------------|
| Next.js marketing site | `voteaxis-web` | `127.0.0.1:3020` | `voteaxis.org` |
| Bun API | `voteaxis-api` | `127.0.0.1:8787` | `api.voteaxis.org` |

Neither process listens on a public interface. Caddy terminates TLS and is the
only thing bound to `0.0.0.0`.

## 1. Box setup (once)

```bash
curl -fsSL https://bun.sh/install | bash     # Bun (runs both processes)
sudo ln -sfn /root/.bun/bin/bun /usr/local/bin/bun   # see note below
npm i -g pm2                                 # PM2
sudo apt install -y nginx certbot python3-certbot-nginx python3 python3-venv
```

The symlink is not optional. Bun's installer only edits `~/.bashrc`, which a
non-interactive `ssh host 'command -v bun'` never reads — so PM2 and
`scripts/deploy.py` would both fail to find it.

DNS: point `voteaxis.org`, `www.voteaxis.org`, and `api.voteaxis.org` at the
box (A/AAAA) **before** issuing certificates, or validation fails.

Firewall — only 80/443 need to be open:

```bash
sudo ufw allow 22,80,443/tcp && sudo ufw enable
```

**This box is shared** with other sites. The site listens on `127.0.0.1:3020`
rather than Next's default 3000, which belongs to another app. Check before
assuming a port is free:

```bash
ss -lntp | grep LISTEN
```

## 2. Clone

```bash
sudo mkdir -p /srv && cd /srv
git clone <your-remote> voteaxis && cd voteaxis
```

`.env` files and the SQLite databases are gitignored, so nothing secret rides
along with the clone. You create them in the next two steps.

## 3. API

```bash
cd /srv/voteaxis/server
cp .env.example .env        # set CONGRESS_API_KEY; leave HOST=127.0.0.1
```

The API has no npm dependencies (Bun builtins only) — there is nothing to
install. Build the Congress index:

```bash
python3 -m venv .venv && .venv/bin/pip install -r scripts/requirements-bicam.txt
.venv/bin/python3 scripts/sync_bicam.py
```

The bills download is ~2GB and the resulting `data/bicam-receipts.sqlite` is
much smaller. You can instead `scp` a sqlite file built on your laptop.

```bash
BUN_BIN=$(command -v bun) pm2 start ecosystem.config.cjs
curl -s http://127.0.0.1:8787/health
# {"ok":true,"service":"voteaxis-api","congress":true,"congressGov":true}
```

`congress: false` means the sqlite index is missing; `congressGov: false` means
`CONGRESS_API_KEY` is unset (optional — receipts still render from BICAM).

## 4. Web

`web/.env.production.local` is gitignored, so it does not arrive with the
clone. Copy it from your machine (or recreate it from `.env.example`):

```bash
scp web/.env.production.local you@vps:/srv/voteaxis/web/.env.production.local
```

```bash
cd /srv/voteaxis/web
bun install                             # dev deps included: the build needs TypeScript
bun run build                           # AFTER the env file is in place — see below
BUN_BIN=$(command -v bun) pm2 start ecosystem.config.cjs
curl -sI http://127.0.0.1:3020 | head -1
```

**Order matters.** `NEXT_PUBLIC_SITE_URL` and `NEXT_PUBLIC_API_URL` are inlined
into the client bundle at build time, so editing either later does nothing until
you rebuild. Everything else (`SMTP_*`, `MAIL_*`, `STRIPE_*`, `WAITLIST_*`) is
read per request and takes effect on `pm2 restart`.

`NEXT_PUBLIC_API_URL` has to be the public API hostname. `/result/<id>` is
rendered from it *and* the visitor's browser calls it directly to fetch a
shared result, so a loopback address works on the box and nowhere else.

The waitlist sink defaults to `web/data/waitlist.jsonl`. Leave it there:
`scripts/deploy.py` never deletes `web/data/` and copies it into every
pre-deploy backup. Parking it under `/var/lib/voteaxis` survives a fresh clone
into a new directory, but is outside those backups — pick one deliberately.

## 5. Persist PM2

```bash
pm2 save
pm2 startup     # run the command it prints, then `pm2 save` again
```

## 6. TLS + reverse proxy (nginx)

Cloudflare proxies these hostnames, so nginx sees a Cloudflare edge IP as
`$remote_addr`. The API rate-limits on `X-Real-IP`; without the snippet below
every caller would share one bucket. Scope it to this site rather than editing
nginx.conf, so the other domains on the box are untouched:

```bash
{
  curl -fsSL https://www.cloudflare.com/ips-v4 | grep -v '^$' | sed 's/^/set_real_ip_from /; s/$/;/'
  echo
  curl -fsSL https://www.cloudflare.com/ips-v6 | grep -v '^$' | sed 's/^/set_real_ip_from /; s/$/;/'
  echo
  echo "real_ip_header CF-Connecting-IP;"
  echo "real_ip_recursive on;"
} | sudo tee /etc/nginx/snippets/cloudflare-real-ip.conf
```

Issue the certificate, then install the site config:

```bash
sudo certbot certonly --nginx -d voteaxis.org -d www.voteaxis.org -d api.voteaxis.org
sudo cp /srv/voteaxis/deploy/nginx.voteaxis.org.example /etc/nginx/sites-available/voteaxis.org
sudo ln -sfn /etc/nginx/sites-available/voteaxis.org /etc/nginx/sites-enabled/voteaxis.org
sudo nginx -t && sudo systemctl reload nginx
```

Certbot needs the three names to answer on port 80 before it can validate, so
put an HTTP-only server block in place first (or run `certbot --nginx`, which
writes one for you). `proxy_buffering off` on the site is required: without it
Next.js streaming responses arrive all at once.

Prefer Caddy on a box of your own? `deploy/Caddyfile.example` is the equivalent,
and Caddy does not buffer by default.

## 7. Mail

The site sends two notifications — a waitlist signup and a completed contribution
checkout — through the box's own Postfix on `127.0.0.1:25`, which OpenDKIM
signs on the way out. No third-party provider, no API key.

This box already relays for `fihaven.app`, and OpenDKIM there is configured
multi-domain (`KeyTable` / `SigningTable`), so `voteaxis.org` is added
alongside rather than replacing anything.

**Generate a key and register the domain** (once, as root):

```bash
mkdir -p /etc/opendkim/keys/voteaxis.org && cd /etc/opendkim/keys/voteaxis.org
opendkim-genkey -b 2048 -d voteaxis.org -s default
chown opendkim:opendkim default.private && chmod 600 default.private

cat >> /etc/opendkim/KeyTable <<'EOF'
default._domainkey.voteaxis.org voteaxis.org:default:/etc/opendkim/keys/voteaxis.org/default.private
EOF
cat >> /etc/opendkim/SigningTable <<'EOF'
*@voteaxis.org default._domainkey.voteaxis.org
EOF

systemctl restart opendkim && systemctl reload postfix
cat /etc/opendkim/keys/voteaxis.org/default.txt   # the DKIM record for DNS
```

**DNS** — three TXT records in the `voteaxis.org` zone (Cloudflare), plus the
MX and the `mail.` host records:

| Type | Name | Value |
|------|------|-------|
| TXT | `default._domainkey` | the `p=…` blob printed above, joined into one string |
| TXT | `@` | `v=spf1 ip4:82.25.91.225 -all` |
| TXT | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:dmarc@voteaxis.org; ruf=mailto:dmarc@voteaxis.org; adkim=s; aspf=s` |
| MX | `@` | `mail.voteaxis.org` (priority 10) |
| A / AAAA | `mail` | `82.25.91.225` / `2a02:4780:2d:19da::1` — **grey-cloud, DNS only** |

Start DMARC at `p=quarantine` and move to `p=reject` once reports look clean.

`mail.` must stay DNS-only: Cloudflare proxies neither SMTP nor IMAP, and a
proxied record also hides the origin from Let's Encrypt's HTTP-01 check.

### Certificate for the mail hostname

`mail.voteaxis.org` gets its own certificate, served by SNI so the box can
present the right one per mail domain:

```bash
certbot certonly --nginx -d mail.voteaxis.org      # needs the :80 vhost first

echo 'mail.voteaxis.org /etc/letsencrypt/live/mail.voteaxis.org/privkey.pem /etc/letsencrypt/live/mail.voteaxis.org/fullchain.pem' \
  >> /etc/postfix/sni_maps
postmap -F hash:/etc/postfix/sni_maps      # -F is REQUIRED, see below
postfix reload
```

Then the Dovecot half, in `/etc/dovecot/conf.d/10-ssl.conf`:

```
local_name mail.voteaxis.org {
  ssl_server {
    cert_file = /etc/letsencrypt/live/mail.voteaxis.org/fullchain.pem
    key_file = /etc/letsencrypt/live/mail.voteaxis.org/privkey.pem
  }
}
```

**`postmap -F` is not optional.** `tls_server_sni_maps` stores the *contents* of
the key and certificate files, not their paths. Rebuilding that database with a
plain `postmap` makes Postfix log `malformed BASE64 value` and fail every SMTP
TLS handshake **for all four domains on the box**, not just this one. Recover
with `postmap -F hash:/etc/postfix/sni_maps && postfix reload`.

Check any port:

```bash
openssl s_client -connect mail.voteaxis.org:993 -servername mail.voteaxis.org \
  </dev/null 2>/dev/null | openssl x509 -noout -subject -enddate
```

### Receiving mail as well

Signing alone makes the domain send-only: Postfix would reject anything
addressed to `@voteaxis.org`, including DMARC reports and replies to the
`no-reply@` envelope sender. Adding it as a fourth virtual domain on the same
mail server fixes that:

```bash
postconf -e "virtual_mailbox_domains = fihaven.app, danielhipskind.com, greighstudios.com, voteaxis.org"

# Real mailbox
echo "daniel@voteaxis.org:$(doveadm pw -s SHA512-CRYPT):5000:5000::/var/vmail/voteaxis.org/daniel::" >> /etc/dovecot/users
printf 'daniel@voteaxis.org\tvoteaxis.org/daniel/\n' >> /etc/postfix/vmailbox
postmap /etc/postfix/vmailbox
install -d -o vmail -g vmail -m700 /var/vmail/voteaxis.org/daniel

# Role aliases into it
printf 'support@voteaxis.org\tdaniel@voteaxis.org\n' >> /etc/postfix/virtual
postmap /etc/postfix/virtual

systemctl reload dovecot && postfix reload
```

Back up `/etc/postfix/{vmailbox,virtual,main.cf}` and `/etc/dovecot/users`
first — the same files serve three other live domains.

The addresses, passwords, and client settings are in `mail-server-logins.md`
at the repo root (gitignored, never committed), matching how fihaven.app and
greighstudios.com record theirs.

Confirm DNS and the private key agree before trusting any of it:

```bash
sudo opendkim-testkey -d voteaxis.org -s default -vvv   # expect "key OK"
```

**Point the site at it** — in `web/.env.production.local`:

```
SMTP_HOST=localhost
SMTP_PORT=25
MAIL_FROM=Voteaxis <no-reply@voteaxis.org>
MAIL_NOTIFY_TO=hello@greighstudios.com
```

`SMTP_HOST` is the switch: unset, the app sends nothing (the dev default) and
waitlist signups live only in the JSONL sink. All of it is read per request, so
a change needs `pm2 restart voteaxis-web`, not a rebuild.

`MAIL_FROM` must be on a domain OpenDKIM signs. Sending as `@voteaxis.org`
while only `fihaven.app` is signed fails DMARC alignment and lands in spam.
The address does not need a mailbox — nothing replies to `no-reply@`; the
waitlist notification sets `Reply-To` to the person who signed up.

**Verify**:

```bash
cd /srv/voteaxis/web && NODE_ENV=production bun run mail:check you@example.com
```

That probes the relay and, with an address, sends a real message. Check the
spam folder too — landing there means the DNS above is wrong or not yet
propagated. Every `bun run deploy` runs the same check and reports it without
failing the deploy; set `MAIL_CHECK_TO` in the root `.env` to have it send a
live message each time.

## 8. Stripe webhook

In the Stripe dashboard, add an endpoint at
`https://voteaxis.org/api/contribute/webhook` for `checkout.session.completed`,
then put its signing secret in `STRIPE_WEBHOOK_SECRET` and
`pm2 restart voteaxis-web`. Without both `STRIPE_SECRET_KEY` and the signing
secret, the route answers 503 and `/contribute` renders without live payments.

## Verify

```bash
curl -s https://api.voteaxis.org/health
curl -s https://api.voteaxis.org/v1/congress
curl -sI https://voteaxis.org | head -1
curl -s https://voteaxis.org/robots.txt
curl -s -X POST https://voteaxis.org/api/waitlist \
  -H 'content-type: application/json' -d '{"email":"you@example.com"}'
```

Then confirm the API is *not* reachable off-proxy: `curl http://<vps-ip>:8787/health`
should fail to connect.

## Redeploy

From your machine, not the box:

```bash
cp .env.example .env     # once: SSH_HOST, DEPLOY_PATH, public origins
bun run deploy
```

`scripts/deploy.py` does the whole run over one multiplexed SSH connection:
checks the local tree, env files, and `web/bun.lock` **before** touching
production; backs up the deploy dir (state kept, caches skipped); rsyncs source
— never over `server/data/` or `web/data/` — writes a sanitized `server/.env`
with `HOST` pinned to loopback; installs, builds, and `pm2 startOrRestart`s both
apps; then verifies PM2, on-box health, the public endpoints, and that neither
process answers off-proxy.

```bash
bun run deploy -- --dry-run       # print every step, change nothing
bun run deploy:api                # API only (no web build)
bun run deploy:web                # site only
bun run deploy -- --with-index    # also ship server/data/bicam-receipts.sqlite
bun run deploy -- --local-build   # build .next here instead of on the box
bun run deploy:rollback           # restore the newest backup and restart
```

Only `bun run deploy -- --with-index` ever uploads a SQLite file, and only the
BICAM index. `server/data/voteaxis.db` holds friend codes created on the box and
is never uploaded — deploying cannot overwrite it.

By hand, if you would rather:

```bash
cd /srv/voteaxis && git pull
cd server && pm2 restart voteaxis-api                      # code only, no build
cd ../web && bun install && bun run build && pm2 restart voteaxis-web
```

`pm2 logs voteaxis-web` / `pm2 logs voteaxis-api` for output.

## Shipping the app

The Flutter app does not go through this deploy — it only talks to
`api.voteaxis.org`. Two things have to be true before a build leaves your
machine.

**Release signing.** Without `mobile/android/key.properties`, the release build
falls back to the SDK's shared debug key and prints a warning. That build runs
locally and is not distributable: the debug key is identical on every machine,
Play rejects it, and a package once published under it can only ever be updated
by that same key.

```bash
keytool -genkey -v -keystore ~/voteaxis-upload.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp mobile/android/key.properties.example mobile/android/key.properties
$EDITOR mobile/android/key.properties     # absolute path + the two passwords
```

Both the keystore and `key.properties` are gitignored. **Back the keystore up
somewhere that is not this machine, and put the password in a password
manager** — losing either ends your ability to update the listing. The package
is permanently bound to this key.

**R8 smoke test.** Release builds are minified and resource-shrunk.
`android/app/proguard-rules.pro` keeps what R8 cannot see being used, but a
build succeeding is not the same as a build working. Before the first Play
upload, install a release APK on a real device and exercise the two paths that
depend on reflection:

- scan a friend's QR code (mobile_scanner → ML Kit), and
- take the quiz, force-quit, reopen (flutter_secure_storage → Keystore).

```bash
cd mobile
flutter build appbundle --release      # Play
flutter build ipa --release            # App Store
```

## Jobs that are not services

Do not put these under PM2 — they are one-shot, run from cron or by hand:

```bash
bun run api:sync         # rebuild the BICAM index
bun run scores:rollcall   # VoteView overlay → mobile/assets/data (rebuild the app after)
```

### Issue of the Week

`/v1/week` refuses to serve a prompt more than 10 days old, so a forgotten file
makes the card disappear from the app rather than claim a three-week-old prompt
is this week's. Nothing announces that, so put the check on a cron and let a
non-zero exit mail you:

```bash
cd server
bun run week:check                    # 0 while current, 1 once due or stale
bun run week:set --issue immigration \\
  --headline "Who belongs, and on what terms?" \\
  --question "Expand legal paths, or tighten enforcement?"
bun run deploy:api                    # from the repo root, to ship it
```

```cron
0 9 * * 1 cd /srv/voteaxis/server && /usr/local/bin/bun run week:check
```

## Scaling note

Both PM2 apps are `instances: 1`, `exec_mode: fork`, deliberately. The API owns
three SQLite files and the site appends to a JSONL file — each needs a single
writer. Do not switch either to cluster mode without moving that state first.
