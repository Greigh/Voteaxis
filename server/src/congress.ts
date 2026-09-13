import { Database } from "bun:sqlite";
import { existsSync } from "node:fs";

const BILL_PATH: Record<string, string> = {
  HR: "house-bill",
  S: "senate-bill",
  HRES: "house-resolution",
  SRES: "senate-resolution",
  HJRES: "house-joint-resolution",
  SJRES: "senate-joint-resolution",
  HCONRES: "house-concurrent-resolution",
  SCONRES: "senate-concurrent-resolution",
};

export const BIOGUIDE = /^[A-Za-z][0-9]{6}$/;
export const BILL_TYPE = /^[A-Za-z]{1,8}$/;

export type ReceiptBill = {
  kind: "sponsored" | "cosponsored";
  congress: number;
  type: string;
  number: string;
  title: string;
  introducedDate: string | null;
  latestAction: string | null;
  summary?: string;
  enrichedFrom?: "congress.gov";
  url: string;
};

export type CongressMember = {
  bioguideId: string;
  name: string | null;
  party: string | null;
  state: string | null;
  district: string | null;
  current: boolean | null;
  url: string;
};

export type Receipts = {
  source: "bicam.net";
  bioguideId: string;
  name: string | null;
  memberUrl: string;
  sponsored: ReceiptBill[];
  cosponsored: ReceiptBill[];
};

export type CongressMeta = {
  source: "bicam.net";
  attribution: string;
  members: number;
  bills: number;
  minCongress: number | null;
};

export function congressOrdinal(n: number): string {
  const v = n % 100;
  if (v >= 11 && v <= 13) return `${n}th`;
  switch (n % 10) {
    case 1:
      return `${n}st`;
    case 2:
      return `${n}nd`;
    case 3:
      return `${n}rd`;
    default:
      return `${n}th`;
  }
}

export function billPageUrl(congress: number, type: string, number: string): string {
  const path = BILL_PATH[type.toUpperCase()] ?? "bill";
  return `https://www.congress.gov/bill/${congressOrdinal(congress)}-congress/${path}/${number}`;
}

export function memberPageUrl(bioguideId: string): string {
  return `https://bioguide.congress.gov/search/bio/${bioguideId}`;
}

type BillRow = {
  congress: number;
  type: string;
  number: string;
  title: string;
  introduced_date: string | null;
};

type MemberRow = {
  bioguide_id: string;
  name: string | null;
  party: string | null;
  state: string | null;
  district: string | null;
  current: number | null;
};

function toBill(row: BillRow, kind: ReceiptBill["kind"]): ReceiptBill {
  return {
    kind,
    congress: row.congress,
    type: row.type,
    number: String(row.number),
    title: row.title,
    introducedDate: row.introduced_date?.trim() || null,
    latestAction: null,
    url: billPageUrl(row.congress, row.type, String(row.number)),
  };
}

function toMember(row: MemberRow): CongressMember {
  const id = row.bioguide_id.toUpperCase();
  return {
    bioguideId: id,
    name: row.name,
    party: row.party,
    state: row.state,
    district: row.district,
    current: row.current == null ? null : row.current === 1,
    url: memberPageUrl(id),
  };
}

export type BicamApi = {
  configured: boolean;
  meta: () => CongressMeta;
  member: (bioguideId: string) => CongressMember | null;
  memberBills: (
    bioguideId: string,
    kind: ReceiptBill["kind"] | "all",
    limit: number,
  ) => ReceiptBill[];
  bill: (congress: number, type: string, number: string) => ReceiptBill | null;
  getReceipts: (bioguideId: string) => Receipts;
};

export function createBicamClient(opts: {
  dbPath: string;
  limit?: number;
}): BicamApi {
  const defaultLimit = opts.limit ?? 8;
  let db: Database | null = null;

  const open = (): Database | null => {
    if (db) return db;
    if (!existsSync(opts.dbPath)) return null;
    db = new Database(opts.dbPath, { readonly: true });
    return db;
  };

  const requireDb = (): Database => {
    const conn = open();
    if (!conn) throw new Error("BICAM congress database is not loaded.");
    return conn;
  };

  const billsFor = (
    conn: Database,
    bioguideId: string,
    kind: ReceiptBill["kind"],
    limit: number,
  ): ReceiptBill[] => {
    const rows = conn
      .query(
        `SELECT b.congress, b.type, b.number, b.title, b.introduced_date
         FROM sponsorships s
         JOIN bills b ON b.bill_id = s.bill_id
         WHERE s.bioguide_id = ? AND s.kind = ?
         ORDER BY b.congress DESC, b.introduced_date DESC, CAST(b.number AS INTEGER) DESC
         LIMIT ?`,
      )
      .all(bioguideId, kind, limit) as BillRow[];
    return rows.map((row) => toBill(row, kind));
  };

  return {
    get configured() {
      return open() != null;
    },
    meta() {
      const conn = requireDb();
      const members = (
        conn.query("SELECT COUNT(*) AS n FROM members").get() as { n: number }
      ).n;
      const bills = (
        conn.query("SELECT COUNT(*) AS n FROM bills").get() as { n: number }
      ).n;
      const minRow = conn
        .query("SELECT value FROM meta WHERE key = 'min_congress'")
        .get() as { value: string } | null;
      return {
        source: "bicam.net" as const,
        attribution:
          "Voteaxis Congress API, indexed from BICAM (bicam.net). Scoring stays on-device.",
        members,
        bills,
        minCongress: minRow ? Number(minRow.value) : null,
      };
    },
    member(bioguideId: string) {
      const conn = requireDb();
      const id = bioguideId.toUpperCase();
      const row = conn
        .query(
          "SELECT bioguide_id, name, party, state, district, current FROM members WHERE bioguide_id = ?",
        )
        .get(id) as MemberRow | null;
      return row ? toMember(row) : null;
    },
    memberBills(bioguideId, kind, limit) {
      const conn = requireDb();
      const id = bioguideId.toUpperCase();
      const cap = Math.min(50, Math.max(1, limit || defaultLimit));
      if (kind === "all") {
        return [
          ...billsFor(conn, id, "sponsored", cap),
          ...billsFor(conn, id, "cosponsored", cap),
        ];
      }
      return billsFor(conn, id, kind, cap);
    },
    bill(congress, type, number) {
      const conn = requireDb();
      const row = conn
        .query(
          `SELECT congress, type, number, title, introduced_date
           FROM bills
           WHERE congress = ? AND type = ? AND number = ?
           LIMIT 1`,
        )
        .get(congress, type.toUpperCase(), String(number).replace(/\D/g, "")) as
        | BillRow
        | null;
      return row ? toBill(row, "sponsored") : null;
    },
    getReceipts(bioguideId: string) {
      const conn = requireDb();
      const id = bioguideId.toUpperCase();
      const member = conn
        .query("SELECT name FROM members WHERE bioguide_id = ?")
        .get(id) as { name: string | null } | null;
      return {
        source: "bicam.net" as const,
        bioguideId: id,
        name: member?.name ?? null,
        memberUrl: memberPageUrl(id),
        sponsored: billsFor(conn, id, "sponsored", defaultLimit),
        cosponsored: billsFor(conn, id, "cosponsored", defaultLimit),
      };
    },
  };
}

export function seedBicamDb(path: string): void {
  const conn = new Database(path);
  conn.exec(`
    CREATE TABLE members (
      bioguide_id TEXT PRIMARY KEY,
      name TEXT,
      party TEXT,
      state TEXT,
      district TEXT,
      current INTEGER
    );
    CREATE TABLE bills (
      bill_id TEXT PRIMARY KEY,
      congress INTEGER NOT NULL,
      type TEXT NOT NULL,
      number TEXT NOT NULL,
      title TEXT NOT NULL,
      introduced_date TEXT
    );
    CREATE TABLE sponsorships (
      bioguide_id TEXT NOT NULL,
      bill_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      PRIMARY KEY (bioguide_id, bill_id, kind)
    );
    CREATE INDEX idx_bills_cite ON bills(congress, type, number);
    CREATE TABLE meta (
      key TEXT PRIMARY KEY,
      value TEXT
    );
  `);
  conn.run(
    "INSERT INTO members (bioguide_id, name, party, state, district, current) VALUES (?, ?, ?, ?, ?, ?)",
    ["S000033", "Bernard Sanders", "Independent", "Vermont", null, 1],
  );
  conn.run(
    "INSERT INTO bills (bill_id, congress, type, number, title, introduced_date) VALUES (?, ?, ?, ?, ?, ?)",
    ["s1655-118", 118, "S", "1655", "Medicare for All Act", "2023-05-17"],
  );
  conn.run(
    "INSERT INTO sponsorships (bioguide_id, bill_id, kind) VALUES (?, ?, ?)",
    ["S000033", "s1655-118", "sponsored"],
  );
  conn.run("INSERT INTO meta (key, value) VALUES ('source', 'bicam.net')");
  conn.run("INSERT INTO meta (key, value) VALUES ('min_congress', '117')");
  conn.close();
}
