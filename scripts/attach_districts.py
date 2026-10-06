#!/usr/bin/env python3
"""Attach `district` (1-based int) to current U.S. House entries in politicians.json.

`Your ballot` narrows House matches to the user's own district, which needs a
district field the roster never had. For nearly every current representative
the answer is already sitting in their `role` ("U.S. Representative (CA-12)"),
so this script reads it out rather than re-fetching. Anything missing falls
back to the `unitedstates/congress-legislators` current roster by bioguideId —
the same feed `check_roster_staleness.py` uses.

Normalization: at-large seats (AL) and DC's delegate become district 1 — those
states have exactly one House seat, so the district picker offers a single
choice either way.

District is only written on `current: true` representatives. Former members
served different lines over their careers, so a stale number is worse than
none — non-current entries get the field stripped instead.

    python3 scripts/attach_districts.py            # write in place
    python3 scripts/attach_districts.py --check    # report only, no writes
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLITICIANS_PATH = ROOT / "mobile/assets/data/politicians.json"
CURRENT_URL = (
    "https://unitedstates.github.io/congress-legislators/"
    "legislators-current.json"
)

ROLE_DISTRICT = re.compile(r"\([A-Z]{2}-(\d+|AL)\)")


def role_district(role: str) -> int | None:
    m = ROLE_DISTRICT.search(role or "")
    if not m:
        return None
    raw = m.group(1)
    return 1 if raw == "AL" else int(raw)


def live_districts() -> dict[str, int]:
    """bioguide -> district for sitting House members, at-large as 1."""
    import urllib.request

    with urllib.request.urlopen(CURRENT_URL, timeout=40) as resp:
        members = json.load(resp)
    out: dict[str, int] = {}
    for m in members:
        bio = m.get("id", {}).get("bioguide")
        if not bio:
            continue
        term = m["terms"][-1]
        if term.get("type") != "rep":
            continue
        out[bio] = max(1, int(term.get("district") or 0))
    return out


def main() -> int:
    check_only = "--check" in sys.argv
    politicians = json.loads(POLITICIANS_PATH.read_text())

    current_reps = [
        p
        for p in politicians
        if p.get("officeType") == "representative" and p.get("current")
    ]
    missing_role = [
        p for p in current_reps if role_district(p.get("role") or "") is None
    ]

    live: dict[str, int] = {}
    if missing_role:
        try:
            live = live_districts()
        except OSError as exc:
            print(
                f"warning: {len(missing_role)} entries need the live roster, "
                f"but the fetch failed: {exc}",
                file=sys.stderr,
            )

    unresolved: list[str] = []
    attached = 0
    stripped = 0
    for person in politicians:
        if person.get("officeType") == "representative" and person.get(
            "current"
        ):
            district = role_district(person.get("role") or "")
            if district is None:
                district = live.get(person.get("bioguideId") or "")
            if district is None:
                unresolved.append(person["id"])
                continue
            person["district"] = district
            attached += 1
        elif "district" in person:
            # Former members and non-House offices: a stale district implies
            # a current seat they no longer hold.
            del person["district"]
            stripped += 1

    print(
        f"{len(current_reps)} current representatives: "
        f"{attached} with district, {len(unresolved)} unresolved"
    )
    for pid in unresolved:
        print(f"  unresolved: {pid}")
    if stripped:
        print(f"stripped stale district from {stripped} non-current entries")

    if check_only:
        return 1 if unresolved else 0
    POLITICIANS_PATH.write_text(
        json.dumps(politicians, indent=2, ensure_ascii=False) + "\n"
    )
    print(f"wrote {POLITICIANS_PATH}")
    return 1 if unresolved else 0


if __name__ == "__main__":
    raise SystemExit(main())
