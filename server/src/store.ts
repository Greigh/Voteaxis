import { Database } from "bun:sqlite";
import { timingSafeEqual } from "node:crypto";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { randomCode, randomToken } from "./codes";
import {
  randomResultId,
  type EncryptedEnvelope,
  type ResultPayload,
} from "./results";
import type { FriendPayload } from "./validate";

export type StoredProfile = {
  code: string;
  payload: FriendPayload;
  createdAt: number;
  expiresAt: number;
};

/**
 * A shared result as stored. Exactly one of [payload] and [envelope] is set:
 * an open link keeps readable scores, a password-protected one keeps bytes
 * this process cannot decrypt.
 */
export type StoredResult = {
  id: string;
  payload: ResultPayload | null;
  envelope: EncryptedEnvelope | null;
  createdAt: number;
  expiresAt: number;
};

/**
 * Constant-time token compare.
 *
 * The token is 192 bits of `crypto.getRandomValues`, so remote timing against
 * a SQLite lookup was never a practical attack — but comparing secrets in
 * constant time is one line and removes the question entirely. Length is
 * checked first because `timingSafeEqual` throws on a mismatch.
 */
function tokensMatch(stored: string, given: string): boolean {
  if (stored.length !== given.length) return false;
  return timingSafeEqual(Buffer.from(stored), Buffer.from(given));
}

/**
 * A device idle this long is swept on the next `purgeExpired()` — the app
 * re-registers on its next launch past that point, same as it would after a
 * reinstall. Unlike `profiles`/`results`, there's no fixed TTL at
 * registration: an install opened every few months stays valid indefinitely,
 * only a truly abandoned one ages out. Six months is arbitrary; nothing
 * downstream reads this constant, so raising it costs nothing but table size.
 */
const DEVICE_IDLE_MS = 180 * 24 * 60 * 60 * 1000;

/**
 * How long a (deviceId, nonce) pair is remembered for replay checking. Must
 * be at least as long as `DEVICE_SIGNATURE_WINDOW_MS` in app.ts — a signed
 * request already outside that window is rejected on the timestamp alone, so
 * nothing older than the window needs a nonce on file to be caught.
 */
const DEVICE_NONCE_WINDOW_MS = 10 * 60 * 1000;

export class Store {
  private db: Database;
  private sweepTimer: ReturnType<typeof setInterval> | null = null;

  constructor(path: string, opts: { autoSweepMs?: number } = {}) {
    if (path !== ":memory:") {
      mkdirSync(dirname(path), { recursive: true });
    }
    this.db = new Database(path);
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS profiles (
        code TEXT PRIMARY KEY,
        token TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_profiles_token ON profiles(token);
      CREATE INDEX IF NOT EXISTS idx_profiles_expires ON profiles(expires_at);

      CREATE TABLE IF NOT EXISTS results (
        id TEXT PRIMARY KEY,
        token TEXT NOT NULL,
        payload TEXT NOT NULL,
        encrypted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_results_token ON results(token);
      CREATE INDEX IF NOT EXISTS idx_results_expires ON results(expires_at);

      -- One row per app install that has ever registered a roster keypair —
      -- see POLITICIANS_ALLOW_DEVICE_TOKENS in app.ts. public_key is a raw
      -- 32-byte Ed25519 public key (hex); the matching private key is
      -- generated on-device and never sent here. device_id is a random
      -- lookup handle, not a secret — knowing it proves nothing without a
      -- signature the stored public key verifies.
      CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT PRIMARY KEY,
        public_key TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen_at);

      -- Signed requests already seen, so a captured (deviceId, timestamp,
      -- nonce, signature) cannot be replayed even inside the timestamp
      -- window a clock-skew allowance otherwise has to leave open. Rows age
      -- out with DEVICE_NONCE_WINDOW_MS, same idea as expires_at above.
      CREATE TABLE IF NOT EXISTS device_nonces (
        device_id TEXT NOT NULL,
        nonce TEXT NOT NULL,
        seen_at INTEGER NOT NULL,
        PRIMARY KEY (device_id, nonce)
      );
      CREATE INDEX IF NOT EXISTS idx_device_nonces_seen ON device_nonces(seen_at);
    `);

    // Lookups already filter on expires_at, so a stale row never resolves — but
    // it still occupies space until something clears it. The write paths purge
    // (see publish/publishResult); this timer covers a long read-only stretch
    // with no writes. Opt-in: tests spin up many Stores and should not each
    // accrue a timer. index.ts turns it on for the real process.
    const sweepMs = opts.autoSweepMs ?? 0;
    if (sweepMs > 0) {
      this.sweepTimer = setInterval(() => {
        try {
          this.purgeExpired();
        } catch {
          // Database closed under us — nothing to sweep.
        }
      }, sweepMs);
      // Housekeeping must not be the reason the process stays alive.
      this.sweepTimer.unref?.();
    }
  }

  /** Stops the background sweep and closes the database. */
  close(): void {
    if (this.sweepTimer) {
      clearInterval(this.sweepTimer);
      this.sweepTimer = null;
    }
    this.db.close();
  }

  purgeExpired(now = Date.now()): void {
    this.db.run("DELETE FROM profiles WHERE expires_at <= ?", [now]);
    this.db.run("DELETE FROM results WHERE expires_at <= ?", [now]);
    this.db.run("DELETE FROM devices WHERE last_seen_at <= ?", [
      now - DEVICE_IDLE_MS,
    ]);
    this.db.run("DELETE FROM device_nonces WHERE seen_at <= ?", [
      now - DEVICE_NONCE_WINDOW_MS,
    ]);
  }

  /**
   * Registers a per-install roster keypair — see POLITICIANS_ALLOW_DEVICE_TOKENS
   * in app.ts. [publicKeyHex] must already be shape-validated
   * (`DEVICE_PUBLIC_KEY_HEX` in app.ts): 64 lowercase hex characters, the raw
   * 32-byte Ed25519 public key. The returned deviceId is a lookup handle, not
   * a credential — app.ts still requires a signature the stored key verifies
   * on every request. Never expires on its own; `purgeExpired` sweeps one
   * that goes unused for DEVICE_IDLE_MS.
   */
  registerDevice(publicKeyHex: string): { deviceId: string; issuedAt: number } {
    const now = Date.now();
    let deviceId = randomToken();
    // TOKEN_BYTES is 192 bits; a collision is not a realistic outcome, but
    // the retry costs nothing and removes the question, same as the id/code
    // retry loops in publish()/publishResult() below.
    for (let i = 0; i < 8; i++) {
      const clash = this.db
        .query("SELECT 1 FROM devices WHERE device_id = ?")
        .get(deviceId);
      if (!clash) break;
      deviceId = randomToken();
    }
    this.db.run(
      "INSERT INTO devices (device_id, public_key, created_at, last_seen_at) VALUES (?, ?, ?, ?)",
      [deviceId, publicKeyHex, now, now],
    );
    return { deviceId, issuedAt: now };
  }

  /**
   * The registered public key for [deviceId], or null if nothing (or an
   * idled-out device) matches. [deviceId] must already be shape-validated —
   * this does a bare lookup, no format check.
   */
  getDevicePublicKey(deviceId: string): string | null {
    const row = this.db
      .query("SELECT public_key FROM devices WHERE device_id = ?")
      .get(deviceId) as { public_key: string } | null;
    return row?.public_key ?? null;
  }

  /**
   * Bumps a device's last-seen time so an install that keeps using the app
   * never ages out under DEVICE_IDLE_MS. Call only after its signature has
   * verified — this does not check anything itself.
   */
  touchDevice(deviceId: string): void {
    this.db.run("UPDATE devices SET last_seen_at = ? WHERE device_id = ?", [
      Date.now(),
      deviceId,
    ]);
  }

  /**
   * True the first time [deviceId] and [nonce] are seen together, recording
   * the pair so a second signed request reusing the same nonce reads as a
   * replay and fails — even a byte-for-byte captured request is single-use.
   * Call only after the signature has verified: recording a nonce for an
   * unverified request would let an attacker burn a victim's nonce ahead of
   * their real one.
   */
  nonceIsFresh(deviceId: string, nonce: string, now = Date.now()): boolean {
    try {
      this.db.run(
        "INSERT INTO device_nonces (device_id, nonce, seen_at) VALUES (?, ?, ?)",
        [deviceId, nonce, now],
      );
      return true;
    } catch {
      // PRIMARY KEY collision: this exact (deviceId, nonce) already landed.
      return false;
    }
  }

  /**
   * Publishes a shareable result. Passing the token minted by an earlier call
   * replaces that result in place, so re-sharing after a retake keeps the same
   * link instead of leaving a trail of stale pages.
   */
  publishResult(
    body: ResultPayload | EncryptedEnvelope,
    encrypted: boolean,
    token: string | undefined,
    ttlMs: number,
  ): { id: string; token: string; expiresAt: number } {
    this.purgeExpired();
    const now = Date.now();
    const expiresAt = now + ttlMs;
    const stored = JSON.stringify(body);
    const flag = encrypted ? 1 : 0;

    if (token) {
      const existing = this.db
        .query("SELECT id FROM results WHERE token = ? AND expires_at > ?")
        .get(token, now) as { id: string } | null;
      if (existing) {
        this.db.run(
          "UPDATE results SET payload = ?, encrypted = ?, created_at = ?, expires_at = ? WHERE id = ?",
          [stored, flag, now, expiresAt, existing.id],
        );
        return { id: existing.id, token, expiresAt };
      }
    }

    const newToken = randomToken();
    let id = randomResultId();
    for (let i = 0; i < 8; i++) {
      const clash = this.db.query("SELECT 1 FROM results WHERE id = ?").get(id);
      if (!clash) break;
      id = randomResultId();
    }
    this.db.run(
      "INSERT INTO results (id, token, payload, encrypted, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
      [id, newToken, stored, flag, now, expiresAt],
    );
    return { id, token: newToken, expiresAt };
  }

  lookupResult(id: string): StoredResult | null {
    // No purge here: the WHERE clause already excludes an expired row, and
    // making every read a write is lock contention on a single-writer DB.
    const row = this.db
      .query(
        "SELECT id, payload, encrypted, created_at, expires_at FROM results WHERE id = ? AND expires_at > ?",
      )
      .get(id, Date.now()) as
      | {
          id: string;
          payload: string;
          encrypted: number;
          created_at: number;
          expires_at: number;
        }
      | null;
    if (!row) return null;
    try {
      const body = JSON.parse(row.payload);
      const encrypted = row.encrypted === 1;
      return {
        id: row.id,
        payload: encrypted ? null : (body as ResultPayload),
        envelope: encrypted ? (body as EncryptedEnvelope) : null,
        createdAt: row.created_at,
        expiresAt: row.expires_at,
      };
    } catch {
      return null;
    }
  }

  /** Revoking is the only way a shared link goes away before its TTL. */
  deleteResult(id: string, token: string): boolean {
    const row = this.db
      .query("SELECT token FROM results WHERE id = ?")
      .get(id) as { token: string } | null;
    if (!row || !tokensMatch(row.token, token)) return false;
    this.db.run("DELETE FROM results WHERE id = ?", [id]);
    return true;
  }

  publish(
    payload: FriendPayload,
    token: string | undefined,
    ttlMs: number,
  ): { code: string; token: string; expiresAt: number } {
    this.purgeExpired();
    const now = Date.now();
    const expiresAt = now + ttlMs;

    if (token) {
      const existing = this.db
        .query("SELECT code FROM profiles WHERE token = ? AND expires_at > ?")
        .get(token, now) as { code: string } | null;
      if (existing) {
        this.db.run(
          "UPDATE profiles SET payload = ?, created_at = ?, expires_at = ? WHERE code = ?",
          [JSON.stringify(payload), now, expiresAt, existing.code],
        );
        return { code: existing.code, token, expiresAt };
      }
    }

    const newToken = randomToken();
    let code = randomCode();
    for (let i = 0; i < 8; i++) {
      const clash = this.db
        .query("SELECT 1 FROM profiles WHERE code = ?")
        .get(code);
      if (!clash) break;
      code = randomCode();
    }
    this.db.run(
      "INSERT INTO profiles (code, token, payload, created_at, expires_at) VALUES (?, ?, ?, ?, ?)",
      [code, newToken, JSON.stringify(payload), now, expiresAt],
    );
    return { code, token: newToken, expiresAt };
  }

  lookup(code: string): StoredProfile | null {
    // No purge here: see lookupResult.
    const row = this.db
      .query(
        "SELECT code, payload, created_at, expires_at FROM profiles WHERE code = ? AND expires_at > ?",
      )
      .get(code, Date.now()) as
      | {
          code: string;
          payload: string;
          created_at: number;
          expires_at: number;
        }
      | null;
    if (!row) return null;
    try {
      return {
        code: row.code,
        payload: JSON.parse(row.payload) as FriendPayload,
        createdAt: row.created_at,
        expiresAt: row.expires_at,
      };
    } catch {
      return null;
    }
  }
}
