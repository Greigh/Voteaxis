#!/usr/bin/env python3
"""Flag politicians.json entries that may be stale against the live Congress roster.

The recurring failure mode across this roster's history is officeholder facts
drifting out from under us — resignations, retirements, primary losses — caught
so far only by a web search done by hand right before writing each bio. This
script automates the one slice of that problem with a reliable live feed:
sitting members of Congress.

It cross-checks every senator/representative entry against the
`unitedstates/congress-legislators` current + historical rosters (the same
source `attach_bioguide.py` uses) and flags:

- a `current: true` member whose bioguideId only shows up in the historical
  roster (resigned, died, or otherwise left office already)
- a bioguideId that isn't in either roster (typo, or a dataset gap)
- a party, chamber, state, or district that no longer matches the live term
- a `current: false` entry whose bioguideId is still in the live current
  roster (marked retired/former too early)
- a sitting senator/representative with no bioguideId at all

This only covers what the congress-legislators feed tracks: seat changes for
sitting members of Congress. It says nothing about governors, AGs, state
legislators, or in-flight primary/general election results — those still need
a web search before you write or trust a bio. Run after roster edits, or any
time you want a quick "did anything change under us" pass:

    python3 scripts/check_roster_staleness.py
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLITICIANS_PATH = ROOT / "mobile/assets/data/politicians.json"
CURRENT_URL = "https://unitedstates.github.io/congress-legislators/legislators-current.json"
HISTORICAL_URL = "https://unitedstates.github.io/congress-legislators/legislators-historical.json"

# The live feed spells parties differently than our catalog does.
PARTY_ALIASES = {"Democrat": "Democratic"}

CHAMBER_BY_OFFICE = {"senator": "sen", "representative": "rep"}
OFFICE_BY_CHAMBER = {"sen": "senator", "rep": "representative"}


def fetch(url: str) -> list[dict]:
    with urllib.request.urlopen(url, timeout=40) as resp:
        return json.load(resp)


def index_by_bioguide(members: list[dict]) -> dict[str, dict]:
    return {m["id"]["bioguide"]: m for m in members if m.get("id", {}).get("bioguide")}


def district_str(term: dict) -> str:
    district = term.get("district")
    if district is None:
        return ""
    return "AL" if district == 0 else str(district)


def role_district(role: str) -> str | None:
    m = re.search(r"\([A-Z]{2}-(\d+|AL)\)", role or "")
    return m.group(1) if m else None


def check(person: dict, current_idx: dict, historical_idx: dict) -> list[str]:
    office = person.get("officeType")
    if office not in CHAMBER_BY_OFFICE:
        return []

    bioguide = person.get("bioguideId")
    is_current = bool(person.get("current"))

    if not bioguide:
        return ["current sitting member has no bioguideId"] if is_current else []

    live = current_idx.get(bioguide)
    if live is None:
        if bioguide in historical_idx:
            if is_current:
                return [
                    "marked current:true but bioguideId only appears in the "
                    "historical roster — likely resigned, died, or otherwise left office"
                ]
            return []
        return [f"bioguideId {bioguide} not found in current or historical roster"]

    if not is_current:
        return ["marked current:false but bioguideId is still in the live current roster"]

    term = live["terms"][-1]
    issues: list[str] = []

    live_party = PARTY_ALIASES.get(term.get("party"), term.get("party"))
    if person.get("party") and live_party and person["party"] != live_party:
        issues.append(f"party mismatch: file says {person['party']!r}, live roster says {live_party!r}")

    live_chamber = term.get("type")
    if live_chamber != CHAMBER_BY_OFFICE[office]:
        issues.append(f"chamber mismatch: file says {office}, live roster says {OFFICE_BY_CHAMBER.get(live_chamber, live_chamber)}")

    if person.get("state") and term.get("state") and person["state"] != term["state"]:
        issues.append(f"state mismatch: file says {person['state']}, live roster says {term['state']}")

    if office == "representative":
        want = role_district(person.get("role") or "")
        have = district_str(term)
        if want and have and want != have:
            issues.append(f"district mismatch: role says {want}, live roster says {have}")

    return issues


def main() -> int:
    politicians = json.loads(POLITICIANS_PATH.read_text())

    print("fetching live congress-legislators rosters...")
    try:
        current_idx = index_by_bioguide(fetch(CURRENT_URL))
        historical_idx = index_by_bioguide(fetch(HISTORICAL_URL))
    except OSError as exc:
        print(f"could not fetch live roster: {exc}", file=sys.stderr)
        return 2

    flagged = 0
    checked = 0
    for person in politicians:
        if person.get("officeType") not in CHAMBER_BY_OFFICE:
            continue
        checked += 1
        issues = check(person, current_idx, historical_idx)
        if issues:
            flagged += 1
            print(f"\n{person['id']} — {person.get('name')} ({person.get('role')})")
            for issue in issues:
                print(f"  - {issue}")

    print(f"\nchecked {checked} senator/representative entries, {flagged} flagged")
    if flagged:
        print(
            "\nNote: this only covers Congress seat changes. Governors, AGs, state "
            "legislators, and in-flight primary/general results still need a manual "
            "web search before you write or trust a bio."
        )
    return 1 if flagged else 0


if __name__ == "__main__":
    raise SystemExit(main())
