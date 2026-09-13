#!/usr/bin/env python3
"""Build a compact Congress SQLite from BICAM for the Voteaxis REST API.

ProPublica's Congress API is retired. BICAM is bulk CSV. This script downloads
members + bills via the official Python package and writes the index served at
GET /v1/members, /v1/bills, and /v1/receipts.

Install:  pip install -r server/scripts/requirements-bicam.txt
Run:      python3 server/scripts/sync_bicam.py

The bills zip is ~2GB. After indexing you can `bicam clear bills` to reclaim cache.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sqlite3
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB = Path(os.environ.get("BICAM_DB") or ROOT / "data" / "bicam-receipts.sqlite")
MIN_CONGRESS = int(os.environ.get("BICAM_MIN_CONGRESS") or "117")

MEMBER_FILES = ("members.csv", "members_current.csv", "members_metadata.csv")
BILL_FILES = ("bills.csv", "bills_metadata.csv")
TITLE_FILES = ("bills_titles.csv",)
SPONSOR_FILES = ("bills_sponsors.csv",)
COSPONSOR_FILES = ("bills_cosponsors.csv",)

BILL_ID_RE = re.compile(
    r"(?:(?P<congress>\d{2,3})[-_])?(?P<type>[A-Za-z]+)[-_]?(?P<number>\d+)",
)


def _cell(row: dict, *keys: str) -> str | None:
    for key in keys:
        value = row.get(key)
        if value is None:
            continue
        text = str(value).strip()
        if text and text.lower() not in {"nan", "none", "null"}:
            return text
    return None


def _norm_row(row: dict) -> dict[str, object]:
    return {str(k).lower().strip(): v for k, v in row.items()}


def _rows_from_csv(path: Path) -> list[dict[str, object]]:
    import csv

    with path.open(newline="", encoding="utf-8") as handle:
        return [_norm_row(r) for r in csv.DictReader(handle)]


def _find_csv(root: Path, filenames: tuple[str, ...]) -> Path | None:
    for name in filenames:
        direct = root / name
        if direct.exists():
            return direct
        matches = list(root.rglob(name))
        if matches:
            return matches[0]
    return None


def ensure_extracted(dataset: str, cache_dir: Path, needed: tuple[str, ...]) -> Path:
    """Download a BICAM zip and extract only the CSVs we use.

    The official package refuses the bills zip because it lists files (like
    bills_cboestimates.csv) that are not in the archive.
    """
    extract = cache_dir / dataset
    found = _find_csv(extract, needed) if extract.exists() else None
    if found:
        return extract

    from bicam.datasets import DATASET_TYPES
    from bicam.downloader import BICAMDownloader

    info = DATASET_TYPES[dataset]
    cache_dir.mkdir(parents=True, exist_ok=True)
    zip_path = cache_dir / f"{dataset}.zip"
    downloader = BICAMDownloader(cache_dir)
    if not zip_path.exists():
        print(f"downloading {dataset} ({info['size_mb']} MB)…", flush=True)
        downloader._download_from_s3(info["key"], zip_path, info["size_mb"])

    extract.mkdir(parents=True, exist_ok=True)
    wanted = {name.lower() for name in needed}
    with zipfile.ZipFile(zip_path) as zf:
        for member in zf.namelist():
            base = Path(member).name.lower()
            if base in wanted and not member.endswith("/"):
                target = extract / Path(member).name
                if not target.exists():
                    print(f"extracting {Path(member).name}…", flush=True)
                    with zf.open(member) as src, target.open("wb") as dest:
                        shutil.copyfileobj(src, dest)
    if not _find_csv(extract, needed):
        raise FileNotFoundError(
            f"BICAM {dataset} zip had none of: {', '.join(needed)}"
        )
    return extract


def load_table(dataset: str, filenames: tuple[str, ...], from_dir: Path | None):
    if from_dir is not None:
        path = _find_csv(from_dir, filenames)
        if not path:
            raise FileNotFoundError(
                f"No {dataset} file in {from_dir} (tried {', '.join(filenames)})"
            )
        return _rows_from_csv(path)

    cache_dir = Path(
        os.environ.get("BICAM_DATA") or Path.home() / ".bicam"
    )
    extract = ensure_extracted(dataset, cache_dir, filenames)
    path = _find_csv(extract, filenames)
    if not path:
        raise FileNotFoundError(
            f"No {dataset} file after extract (tried {', '.join(filenames)})"
        )
    print(f"loading {path.name}…", flush=True)
    return _rows_from_csv(path)


def parse_bill_id(bill_id: str) -> tuple[int | None, str | None, str | None]:
    match = BILL_ID_RE.search(bill_id.replace(" ", ""))
    if not match:
        return None, None, None
    congress = int(match.group("congress")) if match.group("congress") else None
    return congress, match.group("type").upper(), match.group("number")


def member_name(row: dict) -> str | None:
    direct = _cell(
        row,
        "official_full_name",
        "official_full",
        "full_name",
        "direct_order_name",
        "name",
    )
    if direct:
        return direct
    first = _cell(row, "first_name", "first", "firstname")
    last = _cell(row, "last_name", "last", "lastname")
    combined = " ".join(p for p in (first, last) if p)
    return combined or None


def as_flag(value: str | None) -> int | None:
    if value is None:
        return None
    return 1 if value.lower() in {"true", "1", "yes", "t"} else 0


def member_id(row: dict) -> str | None:
    value = _cell(row, "bioguide_id", "bioguideid", "bioguide", "member_id", "sponsor_id")
    return value.upper() if value else None


def bill_fields(row: dict) -> dict | None:
    bill_id = _cell(row, "bill_id", "billid", "id")
    if not bill_id:
        return None
    parsed_congress, parsed_type, parsed_number = parse_bill_id(bill_id)
    congress_raw = _cell(row, "congress")
    congress = int(congress_raw) if congress_raw and congress_raw.isdigit() else parsed_congress
    bill_type = (_cell(row, "bill_type", "type", "billtype") or parsed_type or "").upper()
    number = _cell(row, "bill_number", "number", "billnumber") or parsed_number
    title = _cell(row, "title", "official_title", "short_title") or ""
    if congress is None or not bill_type or not number:
        return None
    return {
        "bill_id": bill_id,
        "congress": congress,
        "type": bill_type,
        "number": re.sub(r"\D", "", number) or number,
        "title": title,
        "introduced_date": _cell(row, "introduced_date", "introduceddate", "date"),
    }


def sponsorships(rows: list[dict], kind: str) -> list[tuple[str, str, str]]:
    out: list[tuple[str, str, str]] = []
    for row in rows:
        bio = member_id(row)
        bill_id = _cell(row, "bill_id", "billid")
        if bio and bill_id:
            out.append((bio, bill_id, kind))
    return out


def write_db(
    db_path: Path,
    members: list[dict],
    bills: list[dict],
    titles: list[dict],
    sponsored: list[tuple[str, str, str]],
    cosponsored: list[tuple[str, str, str]],
    min_congress: int,
) -> None:
    title_by_id: dict[str, str] = {}
    for row in titles:
        bill_id = _cell(row, "bill_id", "billid")
        title = _cell(row, "title", "official_title", "short_title")
        if bill_id and title and bill_id not in title_by_id:
            title_by_id[bill_id] = title

    bill_rows: list[tuple] = []
    kept_ids: set[str] = set()
    for row in bills:
        parsed = bill_fields(row)
        if not parsed or parsed["congress"] < min_congress:
            continue
        if not parsed["title"]:
            parsed["title"] = title_by_id.get(parsed["bill_id"], "")
        if not parsed["title"]:
            continue
        kept_ids.add(parsed["bill_id"])
        bill_rows.append(
            (
                parsed["bill_id"],
                parsed["congress"],
                parsed["type"],
                parsed["number"],
                parsed["title"],
                parsed["introduced_date"],
            )
        )

    member_rows = []
    for row in members:
        bio = member_id(row)
        name = member_name(row)
        if bio:
            member_rows.append(
                (
                    bio,
                    name,
                    _cell(row, "party"),
                    _cell(row, "state"),
                    _cell(row, "district"),
                    as_flag(_cell(row, "is_current_member", "current")),
                )
            )

    links = [
        row
        for row in (*sponsored, *cosponsored)
        if row[1] in kept_ids
    ]

    db_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = db_path.with_suffix(".tmp.sqlite")
    if tmp.exists():
        tmp.unlink()
    conn = sqlite3.connect(tmp)
    try:
        conn.executescript(
            """
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
            CREATE INDEX idx_sponsorships_lookup ON sponsorships(bioguide_id, kind);
            CREATE INDEX idx_bills_cite ON bills(congress, type, number);
            CREATE TABLE meta (
              key TEXT PRIMARY KEY,
              value TEXT
            );
            """
        )
        conn.executemany(
            """
            INSERT OR REPLACE INTO members
              (bioguide_id, name, party, state, district, current)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            member_rows,
        )
        conn.executemany(
            """
            INSERT OR REPLACE INTO bills
              (bill_id, congress, type, number, title, introduced_date)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            bill_rows,
        )
        conn.executemany(
            """
            INSERT OR IGNORE INTO sponsorships (bioguide_id, bill_id, kind)
            VALUES (?, ?, ?)
            """,
            links,
        )
        conn.execute(
            "INSERT INTO meta (key, value) VALUES ('source', 'bicam.net')"
        )
        conn.execute(
            "INSERT INTO meta (key, value) VALUES ('min_congress', ?)",
            (str(min_congress),),
        )
        conn.commit()
    finally:
        conn.close()
    tmp.replace(db_path)


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync BICAM receipts into SQLite")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--from-dir", type=Path, help="Load CSVs from a folder instead of bicam")
    parser.add_argument("--min-congress", type=int, default=MIN_CONGRESS)
    args = parser.parse_args()

    print("loading BICAM members + bills…", flush=True)
    members = load_table("members", MEMBER_FILES, args.from_dir)
    bills = load_table("bills", BILL_FILES, args.from_dir)
    try:
        titles = load_table("bills", TITLE_FILES, args.from_dir)
    except (FileNotFoundError, ValueError):
        titles = []
    sponsored = sponsorships(load_table("bills", SPONSOR_FILES, args.from_dir), "sponsored")
    try:
        cosponsored = sponsorships(
            load_table("bills", COSPONSOR_FILES, args.from_dir),
            "cosponsored",
        )
    except FileNotFoundError:
        cosponsored = []

    write_db(
        args.db,
        members,
        bills,
        titles,
        sponsored,
        cosponsored,
        args.min_congress,
    )
    print(f"wrote {args.db}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
