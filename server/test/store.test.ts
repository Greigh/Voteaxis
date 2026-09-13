import { describe, expect, test } from "bun:test";
import type { Database } from "bun:sqlite";
import { Store } from "../src/store";

const payload = {
  displayName: "Alex",
  axisScore: -10,
  issueScores: { taxes: -10 },
  issueWeights: {},
  pillarScores: {},
  dealbreakerIssueIds: [] as string[],
};

/** Raw row count, reaching past the API to prove what a read did or did not do. */
function rawCount(store: Store, where = ""): number {
  const db = (store as unknown as { db: Database }).db;
  const row = db
    .query(`SELECT COUNT(*) AS n FROM profiles ${where}`)
    .get() as { n: number };
  return row.n;
}

describe("Store", () => {
  test("publish then lookup", () => {
    const store = new Store(":memory:");
    const published = store.publish(payload, undefined, 60_000);
    expect(published.code).toHaveLength(6);
    const found = store.lookup(published.code);
    expect(found?.payload.axisScore).toBe(-10);
    expect(found?.payload.displayName).toBe("Alex");
  });

  test("same token updates the same code", () => {
    const store = new Store(":memory:");
    const first = store.publish(payload, undefined, 60_000);
    const second = store.publish(
      { ...payload, axisScore: 20 },
      first.token,
      60_000,
    );
    expect(second.code).toBe(first.code);
    expect(store.lookup(first.code)?.payload.axisScore).toBe(20);
  });

  test("unknown client token is not stored", () => {
    const store = new Store(":memory:");
    const planted = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const published = store.publish(payload, planted, 60_000);
    expect(published.token).not.toBe(planted);
    expect(published.token).toMatch(/^[0-9a-f]{48}$/);
    const again = store.publish({ ...payload, axisScore: 5 }, planted, 60_000);
    expect(again.code).not.toBe(published.code);
  });

  test("expired rows disappear", () => {
    const store = new Store(":memory:");
    const published = store.publish(payload, undefined, -1);
    expect(store.lookup(published.code)).toBeNull();
  });

  test("a read does not write", () => {
    // Lookups used to purge on every call, turning reads into writes against a
    // single-writer DB. The expired row must not resolve (WHERE clause) but it
    // is also not deleted by the read — that is the sweep's job now.
    const store = new Store(":memory:");
    const live = store.publish(payload, undefined, 60_000);
    // Insert an expired row directly so no write path purges it first.
    (store as unknown as { db: Database }).db.run(
      "INSERT INTO profiles (code, token, payload, created_at, expires_at) VALUES (?, ?, ?, ?, ?)",
      ["EXPIRE", "t".repeat(48), "{}", 0, 1],
    );
    expect(store.lookup("EXPIRE")).toBeNull();
    expect(store.lookup(live.code)?.payload.axisScore).toBe(-10);
    // The read left the stale row in place rather than deleting it.
    expect(rawCount(store, "WHERE code = 'EXPIRE'")).toBe(1);
  });

  test("the opt-in sweep purges and close() stops it", async () => {
    const store = new Store(":memory:", { autoSweepMs: 5 });
    store.publish(payload, undefined, -1); // inserted already expired
    expect(rawCount(store)).toBe(1); // the WHERE clause hides it, but it is there
    for (let i = 0; i < 100 && rawCount(store) > 0; i++) await Bun.sleep(10);
    expect(rawCount(store)).toBe(0); // the timer removed it

    expect(() => store.close()).not.toThrow();
    expect(() => store.close()).not.toThrow(); // idempotent
  });

  test("no sweep timer without autoSweepMs", async () => {
    // The default must not start a timer — tests create many Stores.
    const store = new Store(":memory:");
    store.publish(payload, undefined, -1);
    await Bun.sleep(30);
    expect(rawCount(store)).toBe(1); // still there — nothing swept it
    store.close();
  });
});

/** Raw row count against `devices`, same reasoning as rawCount above. */
function rawDeviceCount(store: Store, where = ""): number {
  const db = (store as unknown as { db: Database }).db;
  const row = db
    .query(`SELECT COUNT(*) AS n FROM devices ${where}`)
    .get() as { n: number };
  return row.n;
}

/** Raw row count against `device_nonces`. */
function rawNonceCount(store: Store, where = ""): number {
  const db = (store as unknown as { db: Database }).db;
  const row = db
    .query(`SELECT COUNT(*) AS n FROM device_nonces ${where}`)
    .get() as { n: number };
  return row.n;
}

// Store never validates key shape — that's app.ts's job (DEVICE_PUBLIC_KEY_HEX)
// — so any fixed string stands in for "a public key" here.
const PUBLIC_KEY_A = "a".repeat(64);
const PUBLIC_KEY_B = "b".repeat(64);

describe("Store devices", () => {
  test("registerDevice mints a fresh deviceId per call", () => {
    const store = new Store(":memory:");
    const a = store.registerDevice(PUBLIC_KEY_A);
    const b = store.registerDevice(PUBLIC_KEY_B);
    expect(a.deviceId).toMatch(/^[0-9a-f]{48}$/);
    expect(a.deviceId).not.toBe(b.deviceId);
    expect(a.issuedAt).toBeGreaterThan(0);
  });

  test("getDevicePublicKey returns the registered key, null for unknown", () => {
    const store = new Store(":memory:");
    const { deviceId } = store.registerDevice(PUBLIC_KEY_A);
    expect(store.getDevicePublicKey(deviceId)).toBe(PUBLIC_KEY_A);
    expect(store.getDevicePublicKey("f".repeat(48))).toBeNull();
  });

  test("touchDevice bumps last_seen_at", () => {
    const store = new Store(":memory:");
    const { deviceId } = store.registerDevice(PUBLIC_KEY_A);
    const db = (store as unknown as { db: Database }).db;
    db.run("UPDATE devices SET last_seen_at = 0 WHERE device_id = ?", [deviceId]);
    store.touchDevice(deviceId);
    const row = db
      .query("SELECT last_seen_at FROM devices WHERE device_id = ?")
      .get(deviceId) as { last_seen_at: number };
    expect(row.last_seen_at).toBeGreaterThan(0);
  });

  test("nonceIsFresh is true once per (deviceId, nonce) pair, false on repeat", () => {
    const store = new Store(":memory:");
    const { deviceId } = store.registerDevice(PUBLIC_KEY_A);
    expect(store.nonceIsFresh(deviceId, "nonce-1")).toBe(true);
    expect(store.nonceIsFresh(deviceId, "nonce-1")).toBe(false);
    // A different device reusing the same nonce string is a distinct pair.
    const other = store.registerDevice(PUBLIC_KEY_B);
    expect(store.nonceIsFresh(other.deviceId, "nonce-1")).toBe(true);
  });

  test("purgeExpired sweeps a device idle past the window, not a fresh one", () => {
    const store = new Store(":memory:");
    const stale = store.registerDevice(PUBLIC_KEY_A);
    const fresh = store.registerDevice(PUBLIC_KEY_B);
    const db = (store as unknown as { db: Database }).db;
    // Backdate as if unused since the epoch — any real idle window is well
    // past this, so the constant's exact value does not need exporting.
    db.run("UPDATE devices SET last_seen_at = 0 WHERE device_id = ?", [
      stale.deviceId,
    ]);
    expect(rawDeviceCount(store)).toBe(2);

    store.purgeExpired();

    expect(store.getDevicePublicKey(stale.deviceId)).toBeNull();
    expect(store.getDevicePublicKey(fresh.deviceId)).toBe(PUBLIC_KEY_B);
    expect(rawDeviceCount(store)).toBe(1);
  });

  test("purgeExpired sweeps a nonce older than the replay window, not a fresh one", () => {
    const store = new Store(":memory:");
    const { deviceId } = store.registerDevice(PUBLIC_KEY_A);
    store.nonceIsFresh(deviceId, "old-nonce");
    store.nonceIsFresh(deviceId, "new-nonce");
    const db = (store as unknown as { db: Database }).db;
    db.run(
      "UPDATE device_nonces SET seen_at = 0 WHERE device_id = ? AND nonce = ?",
      [deviceId, "old-nonce"],
    );
    expect(rawNonceCount(store)).toBe(2);

    store.purgeExpired();

    expect(rawNonceCount(store)).toBe(1);
    // The swept nonce is usable again; the fresh one still is not.
    expect(store.nonceIsFresh(deviceId, "old-nonce")).toBe(true);
    expect(store.nonceIsFresh(deviceId, "new-nonce")).toBe(false);
  });
});
