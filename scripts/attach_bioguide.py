#!/usr/bin/env python3
"""Attach Congress.gov bioguide IDs to sitting senators and representatives.

ProPublica's Congress API is retired. Congress.gov uses bioguide IDs, which we
take from the unitedstates/congress-legislators current roster.

Nominees and state legislators are left unmatched on purpose.

Former members still in the catalog (Greene, Romney) are mapped by hand so
Congress.gov receipts still load after they leave the current roster.
"""

from __future__ import annotations

import json
import re
import unicodedata
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLITICIANS_PATH = ROOT / "mobile/assets/data/politicians.json"
MAP_PATH = ROOT / "scripts/data/bioguide_ids.json"
LEGISLATORS_URL = (
    "https://unitedstates.github.io/congress-legislators/legislators-current.json"
)

SUFFIXES = {"jr", "sr", "ii", "iii", "iv", "v"}
# Known former members the current-roster match will miss.
OVERRIDES = {
    "mtg": "G000596",
    "mitt_romney": "R000615",
}

NICK = {
    "bernie": "bernard",
    "chuck": "charles",
    "bob": "robert",
    "bill": "william",
    "jim": "james",
    "joe": "joseph",
    "mike": "michael",
    "dick": "richard",
    "ted": "edward",
    "ed": "edward",
    "tom": "thomas",
    "tim": "timothy",
    "pat": "patrick",
    "chris": "christopher",
    "katie": "katherine",
    "jon": "jonathan",
    "greg": "gregory",
    "ron": "ronald",
    "dan": "daniel",
    "dave": "david",
    "ben": "benjamin",
    "maggie": "margaret",
}


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = s.lower()
    s = re.sub(r"[^a-z0-9\s]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def name_parts(name: str) -> tuple[str, str, str]:
    parts = [p for p in norm(name).split() if p not in SUFFIXES]
    if not parts:
        return "", "", ""
    first = parts[0]
    last = parts[-1]
    last_full = " ".join(parts[1:]) if len(parts) > 1 else last
    return first, last, last_full


def load_legislators() -> list[dict]:
    with urllib.request.urlopen(LEGISLATORS_URL, timeout=40) as resp:
        return json.load(resp)


def build_index(legs: list[dict]) -> dict[tuple[str, str, str], list[dict]]:
    index: dict[tuple[str, str, str], list[dict]] = defaultdict(list)
    for member in legs:
        term = member["terms"][-1]
        chamber = "sen" if term["type"] == "sen" else "rep"
        state = term["state"]
        last = norm(member["name"]["last"])
        first = norm(member["name"]["first"])
        official = norm(member["name"].get("official_full") or f"{first} {last}")
        record = {
            "bioguide": member["id"]["bioguide"],
            "first": first,
            "last": last,
            "official": official,
            "district": str(term.get("district") or ""),
        }
        index[(chamber, state, last)].append(record)
        token = last.split()[-1]
        if token != last:
            index[(chamber, state, token)].append(record)
        index[(chamber, state, official)].append(record)
    return index


def names_align(cand: dict, first: str, official: str) -> bool:
    want = NICK.get(first, first)
    cf = NICK.get(cand["first"], cand["first"])
    return first == cand["first"] or want == cf or official == cand["official"]


def pick(cands: list[dict], first: str, official: str, role: str) -> str | None:
    seen: set[str] = set()
    unique: list[dict] = []
    for cand in cands:
        if cand["bioguide"] in seen:
            continue
        seen.add(cand["bioguide"])
        unique.append(cand)
    if not unique:
        return None
    for cand in unique:
        if names_align(cand, first, official):
            return cand["bioguide"]
    district = None
    m = re.search(r"\(([A-Z]{2})-(\d+|AL)\)", role)
    if m:
        district = m.group(2).lstrip("0") or "0"
        if m.group(2) == "AL":
            district = "0"
    if district is not None:
        district_hits = [c for c in unique if c["district"] == district]
        if len(district_hits) == 1:
            return district_hits[0]["bioguide"]
    return None


def main() -> None:
    legs = load_legislators()
    index = build_index(legs)
    politicians = json.loads(POLITICIANS_PATH.read_text())
    mapping: dict[str, str] = {}

    for person in politicians:
        office = person.get("officeType")
        if office not in {"senator", "representative"}:
            person.pop("bioguideId", None)
            continue
        chamber = "sen" if office == "senator" else "rep"
        state = person.get("state") or ""
        first, last, last_full = name_parts(person["name"])
        official = norm(person["name"])
        cands = (
            index.get((chamber, state, last_full), [])
            or index.get((chamber, state, last), [])
            or index.get((chamber, state, official), [])
        )
        bioguide = OVERRIDES.get(person["id"]) or pick(
            cands, first, official, person.get("role") or ""
        )
        if bioguide:
            person["bioguideId"] = bioguide
            mapping[person["id"]] = bioguide
        else:
            person.pop("bioguideId", None)

    MAP_PATH.parent.mkdir(parents=True, exist_ok=True)
    MAP_PATH.write_text(json.dumps(mapping, indent=2, sort_keys=True) + "\n")
    POLITICIANS_PATH.write_text(json.dumps(politicians, indent=2) + "\n")
    print(f"attached {len(mapping)} bioguide ids")


if __name__ == "__main__":
    main()
