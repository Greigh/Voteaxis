#!/usr/bin/env python3
"""Ingest current U.S. senators (119th Congress) into politicians.json.

Existing documented senators keep their curated issue scores. New senators
receive party/faction-inferred SII v1 issue maps (confidence: inferred).
"""

from __future__ import annotations

import json
import re
import unicodedata
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROSTER_PATH = ROOT / "scripts/data/us_senators_119.json"
POLITICIANS_PATH = ROOT / "mobile/assets/data/politicians.json"

ISSUE_IDS = [
    "jobs",
    "taxes",
    "deficit",
    "inflation",
    "free_market",
    "welfare",
    "abortion",
    "civil_rights",
    "lgbtq",
    "education",
    "traditional_values",
    "healthcare",
    "medicare",
    "social_security",
    "crime",
    "gun_control",
    "immigration",
    "climate",
    "energy",
    "foreign_policy",
    "terrorism",
    "military",
]

# Faction templates roughly track curated senators already in the app.
TEMPLATES: dict[str, dict[str, int]] = {
    "dem_prog": {
        "jobs": -72,
        "taxes": -78,
        "deficit": -62,
        "inflation": -68,
        "free_market": -70,
        "welfare": -74,
        "abortion": -78,
        "civil_rights": -80,
        "lgbtq": -78,
        "education": -65,
        "traditional_values": -62,
        "healthcare": -82,
        "medicare": -86,
        "social_security": -86,
        "crime": -52,
        "gun_control": -68,
        "immigration": -58,
        "climate": -72,
        "energy": -60,
        "foreign_policy": -55,
        "terrorism": -40,
        "military": -48,
    },
    "dem_main": {
        "jobs": -48,
        "taxes": -53,
        "deficit": -38,
        "inflation": -43,
        "free_market": -43,
        "welfare": -48,
        "abortion": -62,
        "civil_rights": -60,
        "lgbtq": -58,
        "education": -45,
        "traditional_values": -42,
        "healthcare": -60,
        "medicare": -65,
        "social_security": -65,
        "crime": -30,
        "gun_control": -48,
        "immigration": -40,
        "climate": -50,
        "energy": -38,
        "foreign_policy": -35,
        "terrorism": -22,
        "military": -28,
    },
    "dem_mod": {
        "jobs": -28,
        "taxes": -32,
        "deficit": -18,
        "inflation": -22,
        "free_market": -20,
        "welfare": -28,
        "abortion": -45,
        "civil_rights": -40,
        "lgbtq": -38,
        "education": -25,
        "traditional_values": -18,
        "healthcare": -40,
        "medicare": -42,
        "social_security": -42,
        "crime": -8,
        "gun_control": -28,
        "immigration": -18,
        "climate": -30,
        "energy": -18,
        "foreign_policy": -15,
        "terrorism": -5,
        "military": -8,
    },
    "ind_mod": {
        "jobs": -12,
        "taxes": -15,
        "deficit": -5,
        "inflation": -8,
        "free_market": -5,
        "welfare": -15,
        "abortion": -35,
        "civil_rights": -25,
        "lgbtq": -25,
        "education": -10,
        "traditional_values": 5,
        "healthcare": -25,
        "medicare": -28,
        "social_security": -28,
        "crime": 10,
        "gun_control": -15,
        "immigration": 5,
        "climate": -20,
        "energy": -5,
        "foreign_policy": 5,
        "terrorism": 10,
        "military": 8,
    },
    "rep_mod": {
        "jobs": 28,
        "taxes": 32,
        "deficit": 35,
        "inflation": 30,
        "free_market": 30,
        "welfare": 28,
        "abortion": 18,
        "civil_rights": 12,
        "lgbtq": 15,
        "education": 25,
        "traditional_values": 22,
        "healthcare": 22,
        "medicare": 15,
        "social_security": 12,
        "crime": 35,
        "gun_control": 25,
        "immigration": 28,
        "climate": 10,
        "energy": 22,
        "foreign_policy": 25,
        "terrorism": 30,
        "military": 28,
    },
    "rep_main": {
        "jobs": 55,
        "taxes": 60,
        "deficit": 58,
        "inflation": 52,
        "free_market": 58,
        "welfare": 55,
        "abortion": 60,
        "civil_rights": 42,
        "lgbtq": 55,
        "education": 55,
        "traditional_values": 58,
        "healthcare": 48,
        "medicare": 38,
        "social_security": 35,
        "crime": 62,
        "gun_control": 65,
        "immigration": 65,
        "climate": 50,
        "energy": 55,
        "foreign_policy": 52,
        "terrorism": 58,
        "military": 58,
    },
    "rep_cons": {
        "jobs": 72,
        "taxes": 70,
        "deficit": 78,
        "inflation": 72,
        "free_market": 75,
        "welfare": 72,
        "abortion": 78,
        "civil_rights": 65,
        "lgbtq": 72,
        "education": 78,
        "traditional_values": 82,
        "healthcare": 62,
        "medicare": 55,
        "social_security": 52,
        "crime": 80,
        "gun_control": 78,
        "immigration": 80,
        "climate": 62,
        "energy": 68,
        "foreign_policy": 60,
        "terrorism": 75,
        "military": 72,
    },
}

# Name → faction for better-than-party defaults (new records only).
FACTIONS: dict[str, str] = {
    # Progressive / left
    "Bernie Sanders": "dem_prog",
    "Elizabeth Warren": "dem_prog",
    "Ed Markey": "dem_prog",
    "Jeff Merkley": "dem_prog",
    "Ron Wyden": "dem_prog",
    "Mazie Hirono": "dem_prog",
    "Brian Schatz": "dem_prog",
    "Tammy Baldwin": "dem_prog",
    "Chris Murphy": "dem_prog",
    "Richard Blumenthal": "dem_prog",
    "Cory Booker": "dem_prog",
    "Raphael Warnock": "dem_prog",
    "Jon Ossoff": "dem_prog",
    "Tina Smith": "dem_prog",
    "Peter Welch": "dem_prog",
    "Sheldon Whitehouse": "dem_prog",
    "Jack Reed": "dem_main",
    "Patty Murray": "dem_main",
    "Maria Cantwell": "dem_main",
    "Chuck Schumer": "dem_main",
    "Kirsten Gillibrand": "dem_main",
    "Alex Padilla": "dem_main",
    "Adam Schiff": "dem_main",
    "Dick Durbin": "dem_main",
    "Tammy Duckworth": "dem_main",
    "Chris Van Hollen": "dem_main",
    "Angela Alsobrooks": "dem_main",
    "Chris Coons": "dem_main",
    "Lisa Blunt Rochester": "dem_main",
    "Gary Peters": "dem_main",
    "Elissa Slotkin": "dem_mod",
    "Mark Kelly": "dem_mod",
    "Ruben Gallego": "dem_main",
    "Michael Bennet": "dem_mod",
    "John Hickenlooper": "dem_mod",
    "Catherine Cortez Masto": "dem_mod",
    "Jacky Rosen": "dem_mod",
    "Jeanne Shaheen": "dem_mod",
    "Maggie Hassan": "dem_mod",
    "Amy Klobuchar": "dem_mod",
    "Martin Heinrich": "dem_main",
    "Ben Ray Luján": "dem_main",
    "Mark Warner": "dem_mod",
    "Tim Kaine": "dem_mod",
    "John Fetterman": "dem_main",
    "Andy Kim": "dem_main",
    "Angus King": "ind_mod",
    # Republicans
    "Susan Collins": "rep_mod",
    "Lisa Murkowski": "rep_mod",
    "Mitch McConnell": "rep_main",
    "Rand Paul": "rep_mod",  # libertarian lean handled by existing curated scores
    "Ted Cruz": "rep_cons",
    "John Cornyn": "rep_main",
    "Tom Cotton": "rep_cons",
    "Josh Hawley": "rep_cons",
    "Eric Schmitt": "rep_cons",
    "Marsha Blackburn": "rep_cons",
    "Bill Hagerty": "rep_cons",
    "Rick Scott": "rep_cons",
    "Ashley Moody": "rep_cons",
    "Tommy Tuberville": "rep_cons",
    "Katie Britt": "rep_cons",
    "Joni Ernst": "rep_main",
    "Chuck Grassley": "rep_main",
    "Ron Johnson": "rep_cons",
    "Mike Lee": "rep_cons",
    "John Curtis": "rep_main",
    "John Thune": "rep_main",
    "Mike Rounds": "rep_main",
    "Tim Scott": "rep_cons",
    "Darline Graham": "rep_cons",
    "Jim Justice": "rep_main",
    "Shelley Moore Capito": "rep_main",
    "Bernie Moreno": "rep_cons",
    "Jon Husted": "rep_main",
    "Thom Tillis": "rep_main",
    "Ted Budd": "rep_cons",
    "Dave McCormick": "rep_main",
    "Jim Banks": "rep_cons",
    "Todd Young": "rep_main",
    "James Lankford": "rep_cons",
    "Alan Armstrong": "rep_cons",
    "Steve Daines": "rep_cons",
    "Tim Sheehy": "rep_cons",
    "John Barrasso": "rep_cons",
    "Cynthia Lummis": "rep_cons",
    "Mike Crapo": "rep_cons",
    "Jim Risch": "rep_cons",
    "John Boozman": "rep_main",
    "Jerry Moran": "rep_main",
    "Roger Marshall": "rep_cons",
    "Roger Wicker": "rep_main",
    "Cindy Hyde-Smith": "rep_cons",
    "Deb Fischer": "rep_main",
    "Pete Ricketts": "rep_main",
    "John Hoeven": "rep_main",
    "Kevin Cramer": "rep_cons",
    "Dan Sullivan": "rep_main",
    "Bill Cassidy": "rep_main",
    "John Kennedy": "rep_cons",
}


def slugify(name: str) -> str:
    normalized = unicodedata.normalize("NFKD", name)
    ascii_name = normalized.encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-z0-9]+", "_", ascii_name.lower()).strip("_")
    return slug


def inferred_confidence() -> dict[str, str]:
    return {issue: "inferred" for issue in ISSUE_IDS}


def build_senator(entry: dict) -> dict:
    name = entry["name"]
    party = entry["party"]
    abbr = entry["abbr"]
    faction = FACTIONS.get(name)
    if faction is None:
        if party == "Democratic":
            faction = "dem_main"
        elif party == "Independent":
            faction = "ind_mod"
        else:
            faction = "rep_main"
    issues = deepcopy(TEMPLATES[faction])
    return {
        "id": slugify(name),
        "name": name,
        "role": f"U.S. Senator ({abbr})",
        "party": party,
        "state": abbr,
        "officeType": "senator",
        "current": True,
        "bio": (
            f"{name} serves as a U.S. senator from {entry['state']}. "
            "Issue placements are inferred from public record and party/"
            "caucus alignment for Spectrum Issue Index v1."
        ),
        "officeHistory": [f"U.S. Senator ({abbr})"],
        "issues": issues,
        "confidence": inferred_confidence(),
        "signatureStances": [
            {
                "issueId": "taxes",
                "blurb": "Core fiscal and tax posture in the Senate.",
            },
            {
                "issueId": "healthcare",
                "blurb": "Signature contrast on health and entitlements.",
            },
        ],
    }


def is_documented(person: dict) -> bool:
    conf = person.get("confidence") or {}
    if not conf:
        return False
    return sum(1 for v in conf.values() if v == "documented") >= 8


def merge() -> None:
    roster = json.loads(ROSTER_PATH.read_text())
    politicians = json.loads(POLITICIANS_PATH.read_text())

    by_name = {p["name"]: i for i, p in enumerate(politicians)}
    # Also map common id collisions
    by_id = {p["id"]: i for i, p in enumerate(politicians)}

    added = 0
    updated = 0
    preserved = 0

    for entry in roster:
        name = entry["name"]
        record = build_senator(entry)
        existing_idx = by_name.get(name)
        if existing_idx is None and record["id"] in by_id:
            existing_idx = by_id[record["id"]]

        if existing_idx is None:
            politicians.append(record)
            by_name[name] = len(politicians) - 1
            by_id[record["id"]] = len(politicians) - 1
            added += 1
            continue

        existing = politicians[existing_idx]
        if is_documented(existing):
            # Keep curated scores; refresh roster metadata.
            existing["role"] = record["role"]
            existing["party"] = record["party"]
            existing["state"] = record["state"]
            existing["officeType"] = "senator"
            existing["current"] = True
            if "U.S. Senator" not in " ".join(existing.get("officeHistory") or []):
                history = list(existing.get("officeHistory") or [])
                history.append(record["role"])
                existing["officeHistory"] = history
            preserved += 1
            updated += 1
            continue

        # Replace inferred / thin records with senate roster entry.
        # Keep id if already present.
        record["id"] = existing["id"]
        politicians[existing_idx] = record
        updated += 1

    POLITICIANS_PATH.write_text(
        json.dumps(politicians, indent=2, ensure_ascii=False) + "\n"
    )

    senators = [
        p
        for p in politicians
        if p.get("officeType") == "senator" and p.get("current") is True
    ]
    print(
        json.dumps(
            {
                "added": added,
                "updated": updated,
                "preserved_documented": preserved,
                "current_senators": len(senators),
                "total_politicians": len(politicians),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    merge()
