#!/usr/bin/env python3
"""Voteaxis production deploy — back up the remote, rsync, install, restart, verify.

Usage:
    bun run deploy                  # both processes, build on the box
    python3 scripts/deploy.py --help

This replaces the hand-run "Redeploy" recipe in DEPLOY.md (git pull + bun
install + bun run build + pm2 restart) with something that fails *before* it
touches production rather than halfway through it. Unlike a static site,
Voteaxis is two PM2 processes with state on disk that must survive every
deploy — SQLite friend codes, the BICAM index, the waitlist JSONL — so this
script:

  1. checks the local tree, env files, and lockfiles (nothing remote yet)
  2. opens ONE authenticated SSH connection and multiplexes every later step
  3. backs up the remote deploy dir, keeping state, skipping caches
  4. rsyncs source + generated env files; never rsyncs over data/
  5. installs deps and builds the Next.js site ON THE BOX, then pm2 restarts
  6. verifies PM2, loopback health, public health, and that neither process
     is reachable off-proxy

Deliberately not shipped: mobile/ (App Store / Play Store), server/data/*.db
(friend codes live on the server and only there), and any *_SANDBOX / test
credential.

Configuration — repo-root .env (gitignored), or real environment variables,
which win. See .env.example:

    SSH_HOST        required — the VPS
    SSH_USER        default root
    SSH_KEY         optional path to a specific private key
    SSH_PASSWORD    fallback only, needs sshpass; prefer ssh-copy-id
    DEPLOY_PATH     default /srv/voteaxis
    WEB_ORIGIN      default https://voteaxis.org
    API_ORIGIN      default https://api.voteaxis.org
    BACKUP_RETENTION_DAYS   default 7

Why Python and not another bash script: the interesting parts here are pm2's
JSON process list, two env files with different allowlists, and health checks
with retries — all things bash does with grep and prayer. The box already has
python3 (DEPLOY.md installs it for the BICAM sync), and this uses nothing but
the standard library; ssh, rsync, bun, and pm2 do the actual work.
"""

from __future__ import annotations

import argparse
import atexit
import json
import os
import shlex
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence

# PM2 process names. These are declared in the two ecosystem.config.cjs files;
# if you rename one there, rename it here too.
WEB_APP = "voteaxis-web"
API_APP = "voteaxis-api"

# Loopback ports the two processes bind. Used for the on-box health checks and
# for the off-proxy exposure check (they must NOT answer on the public IP).
WEB_PORT = 3020
API_PORT = 8787


class DeployError(Exception):
    """Anything that should stop the deploy with a readable message."""


# ─── Logging ─────────────────────────────────────────────────────

_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _COLOR else text


def log_step(msg: str) -> None:
    print(_c("36", f"🔹 {msg}"), flush=True)


def log_ok(msg: str) -> None:
    print(_c("32", f"✅ {msg}"), flush=True)


def log_warn(msg: str) -> None:
    print(_c("33", f"⚠️  {msg}"), flush=True)


def log_fail(msg: str) -> None:
    print(_c("31", f"❌ {msg}"), file=sys.stderr, flush=True)


def log_info(msg: str) -> None:
    print(f"   {msg}", flush=True)


# ─── Repo + env ──────────────────────────────────────────────────


def find_repo_root(start: Path) -> Path:
    """Walk up until we find the monorepo root, so the script runs from anywhere."""
    for candidate in [start, *start.parents]:
        if (
            (candidate / "package.json").is_file()
            and (candidate / "server").is_dir()
            and (candidate / "web").is_dir()
        ):
            return candidate
    raise DeployError("Not inside the Voteaxis repo (no package.json + server/ + web/).")


def parse_env_file(path: Path) -> Dict[str, str]:
    """Parse KEY=VALUE without word-splitting, so values with spaces survive.

    Only whole-line comments are dropped: a '#' inside a value is part of the
    value (Stripe and Resend keys never contain one, but passwords do).
    """
    env: Dict[str, str] = {}
    if not path.is_file():
        return env
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].lstrip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        env[key] = value
    return env


class Config:
    """Deploy target, resolved from the repo-root .env with environment override."""

    def __init__(self, repo_root: Path):
        file_env = parse_env_file(repo_root / ".env")

        def get(key: str, default: Optional[str] = None) -> Optional[str]:
            # A real environment variable wins, so a one-off deploy to a staging
            # box is `SSH_HOST=staging bun run deploy` and not an edit + revert.
            return os.environ.get(key) or file_env.get(key) or default

        self.host = get("SSH_HOST")
        self.user = get("SSH_USER", "root") or "root"
        self.key = get("SSH_KEY")
        self.password = get("SSH_PASSWORD")
        self.deploy_path = (get("DEPLOY_PATH", "/srv/voteaxis") or "/srv/voteaxis").rstrip("/")
        self.web_origin = (get("WEB_ORIGIN", "https://voteaxis.org") or "").rstrip("/")
        self.api_origin = (get("API_ORIGIN", "https://api.voteaxis.org") or "").rstrip("/")
        # Set to send a real test message on each deploy; unset just probes the
        # relay without putting anything in anyone's inbox.
        self.mail_check_to = get("MAIL_CHECK_TO")
        try:
            self.backup_retention_days = int(get("BACKUP_RETENTION_DAYS", "7") or 7)
        except ValueError:
            raise DeployError("BACKUP_RETENTION_DAYS must be a whole number of days.")

        if not self.host:
            raise DeployError(
                "SSH_HOST is not set.\n"
                "  Copy .env.example to .env at the repo root and fill it in,\n"
                "  or run once as: SSH_HOST=1.2.3.4 bun run deploy"
            )

    @property
    def target(self) -> str:
        return f"{self.user}@{self.host}"


# ─── Local commands ──────────────────────────────────────────────


def run_local(
    cmd: Sequence[str],
    *,
    cwd: Optional[Path] = None,
    check: bool = True,
    capture: bool = False,
    env: Optional[Dict[str, str]] = None,
) -> subprocess.CompletedProcess:
    proc = subprocess.run(
        list(cmd),
        cwd=str(cwd) if cwd else None,
        capture_output=capture,
        text=True,
        env={**os.environ, **env} if env else None,
    )
    if check and proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip() if capture else ""
        raise DeployError(
            f"Command failed ({proc.returncode}): {' '.join(shlex.quote(c) for c in cmd)}"
            + (f"\n{detail}" if detail else "")
        )
    return proc


# ─── Remote (single multiplexed SSH connection) ──────────────────


class Remote:
    """ssh/rsync over ONE authenticated connection.

    A deploy runs a dozen-plus remote steps. Authenticating each one separately
    invites server-side throttling (pam_faillock, fail2ban, OpenSSH
    PerSourcePenalties) to reject a random step mid-deploy, which looks like a
    wrong password with a correct password. Instead: authenticate once, then
    multiplex everything else over that master via ControlMaster.
    """

    def __init__(self, cfg: Config, dry_run: bool = False):
        self.cfg = cfg
        self.dry_run = dry_run
        self.opts: List[str] = []
        self.run_opts: List[str] = []
        self._master_open = False
        # Set in connect(): False when we are reusing someone else's master.
        self._owns_master = True

    def connect(self) -> None:
        log_step("SSH authentication")
        if self.dry_run:
            log_info(f"(dry run) would connect to {self.cfg.target}")
            return

        control_dir = Path.home() / ".ssh" / "cm"
        control_dir.mkdir(parents=True, exist_ok=True)
        control_dir.chmod(0o700)

        self.opts = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "LogLevel=ERROR",
            # The remote build can run for minutes with no traffic on the
            # channel. Without keepalives a NAT or firewall idle timeout drops
            # the connection mid-build, and ssh reports 255 with no explanation.
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=10",
            "-o", "TCPKeepAlive=yes",
            "-o", "ControlMaster=auto",
            # %C is a short hash of (host, port, user) — keeps the socket path
            # well under the ~104-char limit for unix sockets.
            "-o", f"ControlPath={control_dir}/%C",
            "-o", "ControlPersist=5m",
        ]
        if self.cfg.key:
            self.opts += ["-o", "IdentitiesOnly=yes", "-i", os.path.expanduser(self.cfg.key)]

        # Someone may already have a master on this socket (another deploy, or
        # a shell you left open). Reuse it, but do not tear it down on exit —
        # closing a connection we did not open cuts the ground out from under
        # whoever does own it.
        self._owns_master = subprocess.run(
            ["ssh", *self.opts, "-O", "check", self.cfg.target],
            capture_output=True, text=True,
        ).returncode != 0

        # BatchMode makes the probe fail fast instead of dropping into an
        # interactive password prompt. On success this becomes the master.
        probe = subprocess.run(
            ["ssh", *self.opts, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
             self.cfg.target, "true"],
            capture_output=True,
            text=True,
        )
        if probe.returncode == 0:
            log_ok(f"Key auth → {self.cfg.target} (one multiplexed connection)")
        else:
            self._connect_with_password()

        self._master_open = True
        atexit.register(self.close)
        # Every later step rides the master. BatchMode means that if the master
        # dies mid-deploy, they fail loudly instead of hanging on an invisible
        # prompt.
        self.run_opts = [*self.opts, "-o", "BatchMode=yes"]

    def _connect_with_password(self) -> None:
        if not shutil.which("sshpass"):
            raise DeployError(
                f"No SSH key accepted by {self.cfg.target} and sshpass is not installed.\n"
                f"  Preferred:  ssh-copy-id {self.cfg.target}\n"
                f"  Or:         brew install hudochenkov/sshpass/sshpass"
            )
        if not self.cfg.password:
            raise DeployError(
                f"No SSH key accepted by {self.cfg.target} and SSH_PASSWORD is not set.\n"
                f"  Fix this once and for all with: ssh-copy-id {self.cfg.target}"
            )
        # -N -f backgrounds ssh once authenticated, so sshpass exits cleanly and
        # the master survives to serve every later step.
        proc = subprocess.run(
            ["sshpass", "-e", "ssh", *self.opts, "-N", "-f", self.cfg.target],
            env={**os.environ, "SSHPASS": self.cfg.password},
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            raise DeployError(
                f"Password auth to {self.cfg.target} failed.\n"
                f"  If the password is right, the server may be throttling logins\n"
                f"  (pam_faillock / fail2ban). Check:\n"
                f"    ssh {self.cfg.target} 'tail -50 /var/log/auth.log'\n"
                f"{(proc.stderr or '').strip()}"
            )
        log_warn(f"Password auth (sshpass) → {self.cfg.target} — one connection, then multiplexed.")
        log_warn(f"  Switch to keys and drop SSH_PASSWORD from .env: ssh-copy-id {self.cfg.target}")

    def close(self) -> None:
        if not self._master_open or not self._owns_master:
            return
        self._master_open = False
        subprocess.run(
            ["ssh", *self.opts, "-O", "exit", self.cfg.target],
            capture_output=True,
            text=True,
        )

    # -- commands --

    def run(self, command: str, *, check: bool = True, capture: bool = True) -> subprocess.CompletedProcess:
        """Run a shell command on the box."""
        if self.dry_run:
            log_info(f"(dry run) ssh {self.cfg.target} {command}")
            return subprocess.CompletedProcess([], 0, "", "")
        proc = subprocess.run(
            ["ssh", *self.run_opts, self.cfg.target, command],
            capture_output=capture,
            text=True,
        )
        if check and proc.returncode != 0:
            # ssh exits 255 on its own transport/auth errors. Conflating that
            # with "the command failed" reports a healthy box as broken.
            if proc.returncode == 255:
                raise DeployError(
                    f"Lost the connection to {self.cfg.target} — this says nothing about the app.\n"
                    f"{(proc.stderr or '').strip()}"
                )
            raise DeployError(
                f"Remote command failed ({proc.returncode}): {command}\n"
                f"{(proc.stderr or proc.stdout or '').strip()}"
            )
        return proc

    def script(self, body: str, *, check: bool = True, stream: bool = True) -> subprocess.CompletedProcess:
        """Run a bash script on the box, streaming its output by default.

        The script is staged to a file and run with stdin closed, rather than
        piped to `bash -s`. With `bash -s` the script itself occupies stdin, so
        any child that reads stdin — `bun install` does — swallows the rest of
        the script and the run dies partway through with no useful error.
        """
        if self.dry_run:
            log_info("(dry run) would run remote script:")
            for line in body.strip().splitlines():
                log_info(f"    {line}")
            return subprocess.CompletedProcess([], 0, "", "")

        # mktemp, not a name built from pid+timestamp: /tmp is world-writable,
        # and a predictable path lets any local user on the box pre-create it as
        # a symlink and have this deploy's `cat >` follow it — or race the write
        # and swap in their own script, which then runs as us (root).
        remote_path = self.run(
            "mktemp /tmp/voteaxis-deploy-XXXXXXXX.sh"
        ).stdout.strip()
        if not remote_path.startswith("/tmp/voteaxis-deploy-"):
            raise DeployError(f"Unexpected mktemp result on the box: {remote_path!r}")
        self.write_file(remote_path, body, mode="700")
        try:
            proc = subprocess.run(
                ["ssh", *self.run_opts, self.cfg.target,
                 f"bash {shlex.quote(remote_path)} < /dev/null"],
                text=True,
                capture_output=not stream,
            )
        finally:
            subprocess.run(
                ["ssh", *self.run_opts, self.cfg.target, f"rm -f {shlex.quote(remote_path)}"],
                capture_output=True,
                text=True,
            )
        if check and proc.returncode != 0:
            raise DeployError(
                f"Remote script failed ({proc.returncode}).\n"
                f"{(proc.stderr or '').strip() if not stream else ''}"
            )
        return proc

    def write_file(self, path: str, content: str, *, mode: Optional[str] = None) -> None:
        """Create a remote file from a local string — no temp file on either side."""
        if self.dry_run:
            log_info(f"(dry run) would write {path} ({len(content)} bytes)")
            return
        quoted = shlex.quote(path)
        if mode:
            # umask first: `cat >` creates at the shell's default (usually 0644)
            # and the chmod only lands afterwards, so server/.env — which
            # carries CONGRESS_API_KEY — existed world-readable for the length
            # of the upload. Creating it at 0600 and then tightening to the
            # requested mode means it is never more open than intended.
            command = f"umask 077 && cat > {quoted} && chmod {mode} {quoted}"
        else:
            command = f"cat > {quoted}"
        proc = subprocess.run(
            ["ssh", *self.run_opts, self.cfg.target, command],
            input=content,
            text=True,
            capture_output=True,
        )
        if proc.returncode != 0:
            raise DeployError(f"Could not write {path}:\n{(proc.stderr or '').strip()}")

    def rsync(
        self,
        sources: Sequence[Path],
        dest: str,
        *,
        delete: bool = False,
        excludes: Iterable[str] = (),
    ) -> None:
        """Push local paths to `<deploy_path>/<dest>`.

        Only for content that is safe at the default mode. Secrets go through
        `write_file`, which creates them at 0600: macOS ships openrsync as
        /usr/bin/rsync and it rejects --chmod, so mode-on-transfer is not
        something this helper can promise.
        """
        if not sources:
            return
        cmd = [
            "rsync",
            "-az",
            "--no-owner",
            "--no-group",
            "-e", "ssh " + " ".join(shlex.quote(o) for o in self.run_opts),
            "--exclude", ".DS_Store",
        ]
        if delete:
            cmd.append("--delete")
        for pattern in excludes:
            cmd += ["--exclude", pattern]
        cmd += [str(s.relative_to(Path.cwd())) if s.is_relative_to(Path.cwd()) else str(s) for s in sources]
        cmd.append(f"{self.cfg.target}:{self.cfg.deploy_path}/{dest}")
        if self.dry_run:
            log_info("(dry run) " + " ".join(shlex.quote(c) for c in cmd))
            return
        run_local(cmd, capture=True)


# ─── Local preflight ─────────────────────────────────────────────


def check_local_tools(*, needs_bun: bool) -> None:
    log_step("Check local tooling")
    missing = [tool for tool in ("ssh", "rsync") if not shutil.which(tool)]
    if missing:
        raise DeployError(f"Missing required tool(s): {', '.join(missing)}")
    if needs_bun and not shutil.which("bun"):
        raise DeployError("--local-build needs bun on this machine: https://bun.sh/install")
    log_ok("ssh + rsync present")


def check_web_env(repo_root: Path, cfg: Config) -> Dict[str, str]:
    """web/.env.production.local is the one file that must be right *before* the build.

    NEXT_PUBLIC_SITE_URL is inlined into the client bundle by `next build`, so a
    localhost value here does not fail — it silently ships wrong canonical, OG,
    and sitemap URLs to production. Catch it now.
    """
    log_step("Check web production env")
    path = repo_root / "web" / ".env.production.local"
    if not path.is_file():
        raise DeployError(
            "web/.env.production.local is missing.\n"
            "  Create it from web/.env.example — it is gitignored, so it never\n"
            "  arrives with a clone, and the build bakes NEXT_PUBLIC_SITE_URL in."
        )
    env = parse_env_file(path)
    site_url = env.get("NEXT_PUBLIC_SITE_URL", "").strip()
    if not site_url:
        raise DeployError("NEXT_PUBLIC_SITE_URL is unset in web/.env.production.local.")
    if "localhost" in site_url or "127.0.0.1" in site_url:
        raise DeployError(
            f"NEXT_PUBLIC_SITE_URL is {site_url} — that would be baked into the\n"
            "  production bundle. Set it to the public origin before deploying."
        )
    if site_url.endswith("/"):
        raise DeployError(f"NEXT_PUBLIC_SITE_URL must not end in a slash: {site_url}")
    # The bundle is built against one origin and Caddy serves another: canonical
    # tags, OG URLs, the sitemap, and the Stripe return URL would all point at
    # the wrong domain, and nothing about that fails loudly at runtime.
    if cfg.web_origin and site_url != cfg.web_origin:
        log_warn(f"NEXT_PUBLIC_SITE_URL ({site_url}) ≠ WEB_ORIGIN ({cfg.web_origin}).")
        log_warn("  The bundle is baked with the former; the post-deploy check hits the latter.")
        log_warn("  Reconcile web/.env.production.local, the root .env, and deploy/Caddyfile.example.")

    # Stripe answers 503 without both halves; a half-configured pair turns that
    # friendly 503 into a 502 at the first checkout attempt.
    has_key = bool(env.get("STRIPE_SECRET_KEY"))
    has_hook = bool(env.get("STRIPE_WEBHOOK_SECRET"))
    if has_key != has_hook:
        log_warn("Only one of STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET is set — /contribute checkout will 502.")
    if has_key and env.get("STRIPE_SECRET_KEY", "").startswith("sk_test_"):
        log_warn("STRIPE_SECRET_KEY is a TEST key — production will take no real payments.")

    # Mail goes through the box's own Postfix. SMTP_HOST is the switch, and
    # without it (or a webhook) a signup exists only in the JSONL file.
    if not env.get("SMTP_HOST"):
        if env.get("WAITLIST_WEBHOOK_URL"):
            log_warn("SMTP_HOST unset — signups go to the webhook and the JSONL sink, but no mail is sent.")
        else:
            log_warn("SMTP_HOST unset — waitlist signups will exist only in the JSONL sink on the box.")
    else:
        if not env.get("MAIL_NOTIFY_TO") and not env.get("WAITLIST_NOTIFY_TO"):
            log_warn("SMTP_HOST is set but MAIL_NOTIFY_TO is not — notifications have nowhere to go.")
        mail_from = env.get("MAIL_FROM", "Voteaxis <no-reply@voteaxis.org>")
        # DMARC alignment: the From domain has to be one OpenDKIM signs. A
        # mismatch with the site's own domain is the usual way that breaks.
        site_domain = site_url.split("://", 1)[-1].split("/")[0].removeprefix("www.")
        if site_domain not in mail_from:
            log_warn(f"MAIL_FROM ({mail_from}) is not on {site_domain} — check SPF/DKIM/DMARC alignment.")

    log_ok(f"Site URL: {site_url}")
    return env


# Everything the API process actually reads. Anything else in the local
# server/.env stays local: a var that never reaches the box cannot surprise it.
API_ENV_ALLOWLIST = (
    "PORT",
    "DATA_DIR",
    "CODE_TTL_HOURS",
    "BICAM_DB",
    "BICAM_MIN_CONGRESS",
    "CONGRESS_API_KEY",
    "CONGRESS_CACHE",
    "POLITICIANS_API_KEY",
    "POLITICIANS_ALLOW_DEVICE_TOKENS",
)

# Defaults for the path-ish vars, used when the local value points at something
# that only exists on this laptop.
API_PATH_DEFAULTS = {
    "DATA_DIR": "./data",
    "BICAM_DB": "./data/bicam-receipts.sqlite",
    "CONGRESS_CACHE": "./data/congress-gov-cache.sqlite",
}


def build_api_env(repo_root: Path) -> Optional[str]:
    """Produce the sanitized server/.env that ships to the box.

    Returns None when there is no local server/.env, in which case the remote
    one is left exactly as it is.
    """
    log_step("Build sanitized API env")
    path = repo_root / "server" / ".env"
    if not path.is_file():
        log_warn("No local server/.env — leaving the remote API env untouched.")
        return None

    local = parse_env_file(path)
    lines = [
        "# Generated by scripts/deploy.py — do not edit on the server.",
        "# Change your local server/.env and redeploy.",
        "NODE_ENV=production",
        # Not read from the local file on purpose: dev binds 0.0.0.0 for LAN
        # testing against a phone, and that value must never reach the VPS,
        # where it would publish the API on :8787 with no TLS and no
        # trustworthy client IP for rate limiting.
        "HOST=127.0.0.1",
    ]
    for key in API_ENV_ALLOWLIST:
        if key == "PORT":
            lines.append(f"PORT={local.get('PORT', str(API_PORT))}")
            continue
        value = local.get(key)
        if value is None:
            continue
        default = API_PATH_DEFAULTS.get(key)
        if default and os.path.isabs(value):
            # An absolute path inside this checkout cannot exist on the box; an
            # absolute path elsewhere (say /var/lib/voteaxis) may well be
            # deliberate, so that one is only reported.
            if value.startswith(str(repo_root.resolve())):
                log_warn(f"{key}={value} points into this checkout — shipping {default} instead.")
                value = default
            else:
                log_warn(f"{key}={value} is absolute — it must exist on the box, and it is not backed up with the deploy dir.")
        lines.append(f"{key}={value}")

    if not local.get("CONGRESS_API_KEY"):
        log_warn("CONGRESS_API_KEY unset — /health reports congressGov:false and receipts stay BICAM-only.")
    device_tokens_on = (local.get("POLITICIANS_ALLOW_DEVICE_TOKENS") or "").strip().lower() == "true"
    if not local.get("POLITICIANS_API_KEY") and not device_tokens_on:
        log_warn(
            "POLITICIANS_API_KEY unset and POLITICIANS_ALLOW_DEVICE_TOKENS is not "
            "true — /v1/politicians will 401 for everyone, the app included. Set "
            "one of the two (openssl rand -hex 32 for the key) and redeploy."
        )
    elif device_tokens_on:
        log_ok("POLITICIANS_ALLOW_DEVICE_TOKENS=true — /v1/politicians accepts signed per-install devices.")

    log_ok("API env ready (HOST pinned to 127.0.0.1)")
    return "\n".join(lines) + "\n"


def check_web_lockfile(repo_root: Path) -> None:
    """The box installs with --frozen-lockfile, which refuses a drifted lock.

    Catch that here, before the backup and the upload, instead of aborting
    mid-deploy with the new source already on the box.
    """
    log_step("Verify web/bun.lock is in sync")
    if not shutil.which("bun"):
        log_warn("bun not installed locally — skipping the lockfile check.")
        return
    proc = subprocess.run(
        ["bun", "install", "--frozen-lockfile", "--dry-run"],
        cwd=str(repo_root / "web"),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise DeployError(
            "web/package.json and web/bun.lock disagree — the box installs with\n"
            "  --frozen-lockfile and would refuse this. Run `bun install` in web/,\n"
            "  commit the lockfile, then redeploy.\n"
            f"{(proc.stderr or proc.stdout).strip()}"
        )
    log_ok("Lockfile in sync")


def check_remote_prereqs(remote: Remote, *, need_build: bool) -> None:
    log_step("Check remote prerequisites")
    out = remote.run(
        "printf '%s|%s|%s\\n' \"$(command -v bun || true)\" \"$(command -v pm2 || true)\" "
        "\"$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')\"",
    ).stdout.strip()
    if remote.dry_run:
        return
    bun_bin, pm2_bin, mem_mb = (out.split("|") + ["", "", ""])[:3]
    if not bun_bin:
        raise DeployError(
            "bun is not on the remote PATH — both processes run under it.\n"
            "  curl -fsSL https://bun.sh/install | bash"
        )
    if not pm2_bin:
        raise DeployError("pm2 is not on the remote PATH: npm i -g pm2")
    log_ok(f"bun {bun_bin}, pm2 {pm2_bin}")
    # `next build` on a 1GB box gets OOM-killed without swap. We add a swapfile
    # during the remote build, but say so up front.
    if need_build and mem_mb.isdigit() and int(mem_mb) < 1800:
        log_warn(f"Remote RAM is {mem_mb}MB — the Next.js build is memory-hungry; a swapfile will be added if none is active.")


# ─── Backup ──────────────────────────────────────────────────────


def create_backup(remote: Remote, cfg: Config) -> Optional[str]:
    """Copy the deploy dir aside before anything is overwritten.

    State is what matters here — the SQLite files and waitlist.jsonl — so caches
    and installed dependencies are excluded. They are all reproducible; a
    backup of node_modules is just a slow backup.
    """
    log_step("Pre-deploy backup on remote")
    body = f"""
set -euo pipefail
DEPLOY_PATH={shlex.quote(cfg.deploy_path)}
RETENTION={cfg.backup_retention_days}
if [ ! -d "$DEPLOY_PATH" ]; then
  echo "SKIP"
  exit 0
fi
BACKUP="${{DEPLOY_PATH}}.backup_$(date +%Y%m%d_%H%M%S)"
rsync -a \
  --exclude 'node_modules/' \
  --exclude '.next/' \
  --exclude '.git/' \
  --exclude 'server/.venv/' \
  --exclude 'server/data/bicam-cache/' \
  --exclude 'server/data/voteview-cache/' \
  "$DEPLOY_PATH/" "$BACKUP/"
PARENT=$(dirname "$DEPLOY_PATH")
BASE=$(basename "$DEPLOY_PATH")
find "$PARENT" -maxdepth 1 -name "${{BASE}}.backup_*" -mtime +"$RETENTION" -exec rm -rf {{}} + 2>/dev/null || true
echo "$BACKUP"
"""
    result = remote.script(body, stream=False)
    if remote.dry_run:
        return None
    path = (result.stdout or "").strip().splitlines()[-1] if result.stdout.strip() else ""
    if path == "SKIP" or not path:
        log_warn("No existing deploy dir — first deploy, backup skipped.")
        return None
    log_ok(f"Backup: {path}")
    log_info(f"(state included, caches and node_modules excluded; pruned older than {cfg.backup_retention_days}d)")
    return path


# ─── Upload ──────────────────────────────────────────────────────


def ensure_remote_dirs(remote: Remote, cfg: Config, *, web: bool, api: bool) -> None:
    log_step("Ensure remote directories exist")
    dirs = [cfg.deploy_path]
    if web:
        dirs += [f"{cfg.deploy_path}/web", f"{cfg.deploy_path}/web/data"]
    if api:
        dirs += [f"{cfg.deploy_path}/server", f"{cfg.deploy_path}/server/data"]
    remote.run("mkdir -p " + " ".join(shlex.quote(d) for d in dirs))
    log_ok("Remote dirs ready")


def upload_web(remote: Remote, repo_root: Path, *, local_build: bool) -> None:
    web = repo_root / "web"
    log_step("Upload web/")

    # Per-directory --delete, never a --delete on web/ itself: that would take
    # node_modules and .next with it, and the whole point of shipping into a
    # live tree is that the remote's own artifacts survive.
    for name in ("app", "components", "lib", "public", "scripts"):
        src = web / name
        if src.is_dir():
            remote.rsync([src], "web/", delete=True, excludes=("node_modules/",))

    files = [
        web / "package.json",
        web / "bun.lock",
        web / "next.config.mjs",
        web / "tsconfig.json",
        web / "next-env.d.ts",
        web / "ecosystem.config.cjs",
    ]
    remote.rsync([f for f in files if f.is_file()], "web/")

    if local_build:
        dist = web / ".next"
        if not dist.is_dir():
            raise DeployError("--local-build was requested but web/.next does not exist.")
        # cache/ is the incremental build cache: large, machine-specific, and
        # not needed to serve.
        remote.rsync([dist], "web/", delete=True, excludes=("cache/",))
        log_ok("web/ uploaded (including a locally built .next)")
    else:
        log_ok("web/ uploaded (source; the box builds it)")

    # web/data is the waitlist sink. It is never uploaded and never deleted.
    log_info("web/data/ on the box left untouched (waitlist JSONL lives there)")


def upload_web_env(remote: Remote, cfg: Config, repo_root: Path) -> None:
    log_step("Upload web production env")
    # Written, not rsynced. This file holds the live Stripe key, and write_file
    # creates it under `umask 077` so it is never world-readable — not even for
    # the length of the transfer. rsync's own --chmod would do the same, but
    # macOS now ships openrsync as /usr/bin/rsync, which rejects the flag
    # outright ("--chmod=F600: invalid argument") and fails the deploy.
    source = repo_root / "web" / ".env.production.local"
    remote.write_file(
        f"{cfg.deploy_path}/web/.env.production.local",
        source.read_text(),
        mode="600",
    )
    log_ok(".env.production.local uploaded (0600)")


def upload_api(remote: Remote, cfg: Config, repo_root: Path, *, with_index: bool) -> None:
    server = repo_root / "server"
    log_step("Upload server/")

    remote.rsync([server / "src"], "server/", delete=True)
    remote.rsync(
        [server / "scripts"],
        "server/",
        delete=True,
        excludes=("__pycache__/", "*.pyc", ".venv/"),
    )
    files = [server / "package.json", server / "tsconfig.json", server / "ecosystem.config.cjs"]
    remote.rsync([f for f in files if f.is_file()], "server/")

    # Editorial content, tracked in git and safe to overwrite. The SQLite files
    # next to it are not: voteaxis.db holds friend codes created on the box and
    # is never uploaded, under any flag.
    issue = server / "data" / "issue-of-the-week.json"
    if issue.is_file():
        remote.rsync([issue], "server/data/")

    # mobile/ is never shipped to the box (see the module docstring), so this
    # copy is the only way GET /v1/politicians has anything to serve. Keep it
    # current with: python3 scripts/sync_politicians.py
    politicians = server / "data" / "politicians.json"
    if politicians.is_file():
        remote.rsync([politicians], "server/data/")
    else:
        log_warn(
            "server/data/politicians.json missing locally — "
            "run python3 scripts/sync_politicians.py before deploying, "
            "or GET /v1/politicians will 503 on the box."
        )

    if with_index:
        index = server / "data" / "bicam-receipts.sqlite"
        if not index.is_file():
            raise DeployError(
                "--with-index needs server/data/bicam-receipts.sqlite.\n"
                "  Build it first: bun run api:sync"
            )
        size_mb = index.stat().st_size / (1024 * 1024)
        log_step(f"Upload BICAM index ({size_mb:.0f}MB)")
        # rsync writes to a temp file and renames, so the running API keeps
        # reading the old inode until the restart below swings it over.
        remote.rsync([index], "server/data/")
        log_ok("BICAM index uploaded")

    log_ok("server/ uploaded (data/*.db and caches untouched)")


def upload_api_env(remote: Remote, cfg: Config, content: str) -> None:
    log_step("Upload sanitized API env")
    remote.write_file(f"{cfg.deploy_path}/server/.env", content, mode="600")
    log_ok("server/.env written (0600)")


# ─── Install, build, restart ─────────────────────────────────────


def remote_release(
    remote: Remote,
    cfg: Config,
    *,
    web: bool,
    api: bool,
    local_build: bool,
) -> None:
    log_step("Remote install, build, and restart")
    deploy_path = shlex.quote(cfg.deploy_path)

    parts = [
        """
set -euo pipefail
export BUN_BIN="${BUN_BIN:-$(command -v bun)}"
export PATH="$(dirname "$BUN_BIN"):$PATH"
"""
    ]

    if web and not local_build:
        # Guard against the build being OOM-killed on a small VPS. A swapfile
        # absorbs the peak with no downtime, unlike stopping the site first.
        parts.append(
            """
if [ "$(swapon --show --noheadings 2>/dev/null | wc -l)" -eq 0 ] && [ "$(id -u)" -eq 0 ]; then
  echo "🔹 No swap active — adding a 2G swapfile for the build…"
  if fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none 2>/dev/null; then
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1 || true
    swapon /swapfile 2>/dev/null || true
    grep -q '/swapfile' /etc/fstab 2>/dev/null || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  else
    echo "⚠️  Could not create swap; continuing without it."
  fi
fi
"""
        )

    if web:
        # With a remote build we need devDependencies (the build needs
        # TypeScript); with a locally built .next, `next start` needs runtime
        # deps only.
        install = "bun install --frozen-lockfile" + (" --production" if local_build else "")
        build = "" if local_build else 'echo "🔹 next build…"\nbun run build\n'
        parts.append(
            f"""
cd {deploy_path}/web
echo "🔹 bun install (web)…"
{install}
{build}"""
        )

    # startOrRestart re-reads ecosystem.config.cjs, which is what loads the env
    # file — a plain `pm2 restart` would reuse the env captured at first start
    # and quietly ignore everything we just uploaded.
    if api:
        parts.append(
            f"""
cd {deploy_path}/server
echo "🔹 pm2 {API_APP}…"
pm2 startOrRestart ecosystem.config.cjs --update-env
"""
        )
    if web:
        parts.append(
            f"""
cd {deploy_path}/web
echo "🔹 pm2 {WEB_APP}…"
pm2 startOrRestart ecosystem.config.cjs --update-env
"""
        )

    parts.append("pm2 save >/dev/null 2>&1 || true\n")
    remote.script("\n".join(parts))
    log_ok("Installed and restarted")


# ─── Verify ──────────────────────────────────────────────────────


def verify_pm2(remote: Remote, apps: Sequence[str]) -> bool:
    log_step("Verify PM2 processes")
    if remote.dry_run:
        return True
    raw = remote.run("pm2 jlist", check=False)
    if raw.returncode != 0:
        log_fail("Could not read pm2 jlist — deployment NOT verified.")
        return False
    try:
        procs = json.loads(raw.stdout or "[]")
    except json.JSONDecodeError:
        log_fail("pm2 jlist returned something that is not JSON.")
        return False

    by_name = {p.get("name"): p for p in procs}
    ok = True
    for name in apps:
        proc = by_name.get(name)
        if not proc:
            log_fail(f"{name} is not registered with PM2.")
            ok = False
            continue
        env = proc.get("pm2_env", {})
        status = env.get("status")
        restarts = env.get("unstable_restarts", 0)
        if status != "online":
            log_fail(f"{name} is {status}. Logs: ssh … 'pm2 logs {name} --lines 50'")
            ok = False
        elif restarts:
            log_warn(f"{name} online but has {restarts} unstable restart(s) — check the logs.")
        else:
            log_ok(f"{name} online (pid {proc.get('pid')})")
    return ok


def verify_loopback(remote: Remote, *, web: bool, api: bool) -> bool:
    """Health-check on the box, before DNS and TLS get a chance to muddy it."""
    log_step("Verify on-box health")
    if remote.dry_run:
        return True
    ok = True
    if api:
        for attempt in range(1, 6):
            res = remote.run(f"curl -sf --max-time 5 http://127.0.0.1:{API_PORT}/health || true")
            body = (res.stdout or "").strip()
            if '"ok":true' in body.replace(" ", ""):
                log_ok(f"API /health: {body}")
                if '"congress":false' in body.replace(" ", ""):
                    log_warn("congress:false — the BICAM SQLite index is missing on the box (bun run api:sync, or redeploy with --with-index).")
                if '"congressGov":false' in body.replace(" ", ""):
                    log_warn("congressGov:false — CONGRESS_API_KEY is unset; receipts render from BICAM only.")
                flat = body.replace(" ", "")
                if '"politiciansGated":false' in flat and '"politiciansDeviceTokens":false' in flat:
                    log_warn("politiciansGated:false, politiciansDeviceTokens:false — /v1/politicians 401s for everyone.")
                break
            time.sleep(2 * attempt)
        else:
            log_fail(f"API never answered on 127.0.0.1:{API_PORT}/health")
            ok = False
    if web:
        for attempt in range(1, 6):
            res = remote.run(
                f"curl -s -o /dev/null -w '%{{http_code}}' --max-time 10 http://127.0.0.1:{WEB_PORT}/ || true"
            )
            code = (res.stdout or "").strip()
            if code.startswith("2") or code.startswith("3"):
                log_ok(f"Web root on 127.0.0.1:{WEB_PORT} → HTTP {code}")
                break
            time.sleep(2 * attempt)
        else:
            log_fail(f"Web never answered on 127.0.0.1:{WEB_PORT}")
            ok = False
    return ok


def http_get(url: str, timeout: int = 10) -> tuple[int, str]:
    req = urllib.request.Request(url, headers={"User-Agent": "voteaxis-deploy/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read(4096).decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, ""
    except Exception as exc:  # DNS, TLS, timeout — all "not serving yet"
        return 0, str(exc)


def verify_public(cfg: Config, *, web: bool, api: bool, dry_run: bool) -> bool:
    """Same checks again through Caddy, which is what users actually hit."""
    log_step("Verify public endpoints")
    if dry_run:
        return True
    ok = True
    if api and cfg.api_origin:
        for attempt in range(1, 5):
            status, body = http_get(f"{cfg.api_origin}/health")
            if status == 200 and '"ok":true' in body.replace(" ", ""):
                log_ok(f"{cfg.api_origin}/health")
                break
            time.sleep(2 * attempt)
        else:
            log_fail(f"{cfg.api_origin}/health did not return ok:true — check Caddy and DNS.")
            ok = False
    if web and cfg.web_origin:
        for attempt in range(1, 5):
            status, _ = http_get(cfg.web_origin)
            if 200 <= status < 400:
                log_ok(f"{cfg.web_origin} → HTTP {status}")
                break
            time.sleep(2 * attempt)
        else:
            log_fail(f"{cfg.web_origin} did not respond — check Caddy and DNS.")
            ok = False
    return ok


def check_mail(remote: Remote, cfg: Config) -> None:
    """Probe the SMTP relay from the box, against the env we just uploaded.

    Never fatal. Outbound mail being broken is worth a loud warning, but the
    deploy itself succeeded and the site is serving — failing here would send
    people rolling back a good release over a notification channel.
    """
    log_step("Mail check (remote, post-restart)")
    if remote.dry_run:
        return
    recipient = f" {shlex.quote(cfg.mail_check_to)}" if cfg.mail_check_to else ""
    # NODE_ENV=production is what makes Bun load .env.production.local — without
    # it the check reads no SMTP_HOST and reports "no mail configured" on a box
    # that is in fact configured.
    result = remote.run(
        f"cd {shlex.quote(cfg.deploy_path)}/web && NODE_ENV=production bun run mail:check{recipient} 2>&1",
        check=False,
    )
    output = (result.stdout or "").strip()
    if result.returncode == 0:
        for line in output.splitlines():
            log_info(line)
        log_ok("Mail check passed" + (f" (test message sent to {cfg.mail_check_to})" if cfg.mail_check_to else " (relay reachable)"))
    elif result.returncode == 255:
        log_warn("Mail check SKIPPED — lost the connection. Says nothing about SMTP.")
    else:
        log_warn("Mail check FAILED — outbound email is not working on the box.")
        for line in output.splitlines():
            log_warn(f"  {line}")
        log_warn(f"  Diagnose: ssh {cfg.target} 'systemctl status postfix; journalctl -u postfix -n 50'")


def verify_not_exposed(cfg: Config, *, web: bool, api: bool, dry_run: bool) -> None:
    """Both processes must be reachable only through the reverse proxy.

    A direct hit on the public IP means HOST/-H drifted back to 0.0.0.0: the API
    would then serve without TLS and rate-limit every caller as one IP. Not
    fatal to the deploy — the code is live and fine — but it must be loud.
    """
    log_step("Verify neither process is reachable off-proxy")
    if dry_run:
        return
    ports = ([API_PORT] if api else []) + ([WEB_PORT] if web else [])
    for port in ports:
        try:
            with socket.create_connection((cfg.host, port), timeout=4):
                log_warn(f"{cfg.host}:{port} accepts direct connections — it should bind 127.0.0.1 only.")
                log_warn("  Check server/.env HOST=, web ecosystem args '-H 127.0.0.1', and the firewall (ufw allow 22,80,443/tcp).")
        except OSError:
            log_ok(f"{cfg.host}:{port} refused (proxy-only, as intended)")


# ─── Rollback ────────────────────────────────────────────────────


def list_backups(remote: Remote, cfg: Config) -> List[str]:
    parent = os.path.dirname(cfg.deploy_path)
    base = os.path.basename(cfg.deploy_path)
    res = remote.run(
        f"ls -1d {shlex.quote(parent)}/{shlex.quote(base)}.backup_* 2>/dev/null || true"
    )
    return [line.strip() for line in (res.stdout or "").splitlines() if line.strip()]


def rollback(remote: Remote, cfg: Config, requested: Optional[str], assume_yes: bool) -> int:
    log_step("Rollback")
    backups = list_backups(remote, cfg)
    if not backups:
        raise DeployError(f"No backups found next to {cfg.deploy_path}.")
    target = requested or sorted(backups)[-1]
    if target not in backups:
        raise DeployError(f"{target} is not one of:\n  " + "\n  ".join(backups))

    log_warn(f"About to restore {target} over {cfg.deploy_path} and restart both processes.")
    if not assume_yes:
        answer = input("Type 'rollback' to continue: ").strip()
        if answer != "rollback":
            log_info("Aborted.")
            return 1

    # No --delete: files created since the backup (new SQLite WAL, waitlist
    # appends) are left alone. This restores code, it does not erase state.
    remote.script(
        f"""
set -euo pipefail
export BUN_BIN="${{BUN_BIN:-$(command -v bun)}}"
rsync -a {shlex.quote(target)}/ {shlex.quote(cfg.deploy_path)}/
cd {shlex.quote(cfg.deploy_path)}/server && pm2 startOrRestart ecosystem.config.cjs --update-env
cd {shlex.quote(cfg.deploy_path)}/web && pm2 startOrRestart ecosystem.config.cjs --update-env
pm2 save >/dev/null 2>&1 || true
"""
    )
    ok = verify_pm2(remote, [API_APP, WEB_APP])
    ok = verify_loopback(remote, web=True, api=True) and ok
    log_ok(f"Restored {target}") if ok else log_fail("Rollback restored files but the processes are unhealthy.")
    return 0 if ok else 1


# ─── Main ────────────────────────────────────────────────────────


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="deploy.py",
        description="Deploy Voteaxis (Next.js site + Bun API) to the VPS.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""examples:
  bun run deploy                     both processes, build on the box
  bun run deploy -- --only api       API only, no web build
  bun run deploy -- --with-index     also ship the local BICAM SQLite index
  bun run deploy -- --local-build    build .next here and ship it
  bun run deploy -- --dry-run        show every step, change nothing
  bun run deploy -- --rollback       restore the newest backup
""",
    )
    parser.add_argument(
        "--only",
        choices=("web", "api"),
        help="deploy just one of the two processes (default: both)",
    )
    parser.add_argument(
        "--local-build",
        action="store_true",
        help="build web/.next here and rsync it instead of building on the box "
        "(faster on a small VPS; the artifact is built on this OS, not the target's)",
    )
    parser.add_argument(
        "--with-index",
        action="store_true",
        help="also upload server/data/bicam-receipts.sqlite (built by `bun run api:sync`)",
    )
    parser.add_argument("--no-backup", action="store_true", help="skip the pre-deploy backup")
    parser.add_argument(
        "--rollback",
        nargs="?",
        const="",
        metavar="BACKUP_PATH",
        help="restore a backup (default: the newest) and restart, then exit",
    )
    parser.add_argument("--dry-run", action="store_true", help="print every step without changing anything")
    parser.add_argument("-y", "--yes", action="store_true", help="do not prompt for confirmation")
    return parser.parse_args(list(argv))


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    repo_root = find_repo_root(Path(__file__).resolve().parent)
    os.chdir(repo_root)
    cfg = Config(repo_root)

    do_web = args.only in (None, "web")
    do_api = args.only in (None, "api")
    apps = ([API_APP] if do_api else []) + ([WEB_APP] if do_web else [])

    print()
    print(_c("1", "🚀 Voteaxis deploy"))
    print("──────────────────")
    print(f"   📍 {cfg.target}:{cfg.deploy_path}")
    print(f"   📦 {', '.join(apps)}")
    if args.dry_run:
        log_warn("DRY RUN — nothing will be changed.")
    print()

    remote = Remote(cfg, dry_run=args.dry_run)

    if args.rollback is not None:
        remote.connect()
        return rollback(remote, cfg, args.rollback or None, args.yes)

    # ── Local preflight: everything that can fail without touching the box ──
    check_local_tools(needs_bun=args.local_build)
    api_env: Optional[str] = None
    if do_web:
        check_web_env(repo_root, cfg)
        check_web_lockfile(repo_root)
    if do_api:
        api_env = build_api_env(repo_root)

    if do_web and args.local_build:
        log_step("Build web locally")
        run_local(["bun", "install", "--frozen-lockfile"], cwd=repo_root / "web")
        run_local(["bun", "run", "build"], cwd=repo_root / "web")
        log_warn(f"web/.next was built on {sys.platform}; the box runs Linux. If anything looks off at runtime, redeploy without --local-build.")
        log_ok("Local build complete")

    # ── Remote ──
    remote.connect()
    check_remote_prereqs(remote, need_build=do_web and not args.local_build)

    backup_path = None
    if not args.no_backup:
        backup_path = create_backup(remote, cfg)
    else:
        log_warn("Backup skipped (--no-backup).")

    ensure_remote_dirs(remote, cfg, web=do_web, api=do_api)

    if do_web:
        upload_web(remote, repo_root, local_build=args.local_build)
        upload_web_env(remote, cfg, repo_root)
    if do_api:
        upload_api(remote, cfg, repo_root, with_index=args.with_index)
        if api_env:
            upload_api_env(remote, cfg, api_env)

    remote_release(remote, cfg, web=do_web, api=do_api, local_build=args.local_build)

    healthy = verify_pm2(remote, apps)
    healthy = verify_loopback(remote, web=do_web, api=do_api) and healthy
    healthy = verify_public(cfg, web=do_web, api=do_api, dry_run=args.dry_run) and healthy
    verify_not_exposed(cfg, web=do_web, api=do_api, dry_run=args.dry_run)
    if do_web:
        check_mail(remote, cfg)

    # ── Summary ──
    print()
    line = "═" * 59
    print(line)
    print("  ✅ Deploy complete" if healthy else "  ⚠️  Deploy finished with failed checks")
    print(line)
    print(f"  Target:   {cfg.target}:{cfg.deploy_path}")
    print(f"  Apps:     {', '.join(apps)}")
    print(f"  Built:    {'locally (.next shipped)' if args.local_build else 'on the box'}")
    if backup_path:
        print(f"  Backup:   {backup_path}")
        print("  Rollback: bun run deploy -- --rollback")
    if do_web and cfg.web_origin:
        print(f"  Web:      {cfg.web_origin}")
    if do_api and cfg.api_origin:
        print(f"  API:      {cfg.api_origin}/health")
    print(f"  Deployed: {datetime.now(timezone.utc).astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')}")
    print(line)
    if not healthy:
        print()
        log_fail("Some checks failed. Logs:")
        for name in apps:
            log_info(f"ssh {cfg.target} 'pm2 logs {name} --lines 50 --nostream'")
    return 0 if healthy else 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except DeployError as err:
        log_fail(str(err))
        sys.exit(1)
    except KeyboardInterrupt:
        log_fail("Interrupted.")
        sys.exit(130)
