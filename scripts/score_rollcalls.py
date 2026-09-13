#!/usr/bin/env python3
"""Precompute SII issue scores from VoteView floor votes.

Scoring stays on-device. This script writes a small overlay the Flutter app
blends into curated politician issue vectors. We do not import DW-NOMINATE
member scores — VoteView is only the roll-call tape and a cutting-line
compass for which side of a vote is conservative.

Usage:
  python3 scripts/score_rollcalls.py
  python3 scripts/score_rollcalls.py --from-dir scripts/test/fixtures/voteview --out /tmp/rollcall.json
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import urllib.error
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "mobile" / "assets" / "data" / "rollcall_scores.json"
DEFAULT_CACHE = Path(
    os.environ.get("VOTEVIEW_CACHE") or ROOT / "server" / "data" / "voteview-cache"
)
MAP_PATH = ROOT / "scripts" / "data" / "sii_vote_map.json"
POLITICIANS = ROOT / "mobile" / "assets" / "data" / "politicians.json"
VOTEVIEW = "https://voteview.com/static/data/out"
MIN_CONGRESS = int(os.environ.get("VOTEVIEW_MIN_CONGRESS") or "117")
MAX_CONGRESS = int(os.environ.get("VOTEVIEW_MAX_CONGRESS") or "119")
SPREAD_MIN = 0.08
YEA = {1, 2, 3}
NAY = {4, 5, 6}
SESSION_MIN_VOTES = 3
MAX_MOVES = 6


def load_map() -> dict[str, list[str]]:
    return json.loads(MAP_PATH.read_text())


def congress_ordinal(n: int) -> str:
    v = n % 100
    if 11 <= v <= 13:
        return f"{n}th"
    return {1: f"{n}st", 2: f"{n}nd", 3: f"{n}rd"}.get(n % 10, f"{n}th")


def congress_start_year(n: int) -> int:
    return 1789 + (n - 1) * 2


def voteview_rollcall_url(congress: str, chamber: str, number: str) -> str:
    prefix = "H" if chamber[:1].upper() == "H" else "S"
    try:
        roll = int(float(number))
        cong = int(float(congress))
    except ValueError:
        return ""
    return f"https://voteview.com/rollcall/R{prefix}{cong}{roll:04d}"


def axis_from_issues(issues: dict[str, float]) -> float:
    if not issues:
        return 0.0
    return round(sum(issues.values()) / len(issues), 1)


def pick_moves(
    events: list[dict[str, object]],
    prev_axis: float | None,
    session_axis: float,
) -> list[dict[str, object]]:
    delta = session_axis - (prev_axis if prev_axis is not None else session_axis)
    ranked: list[tuple[float, dict[str, object]]] = []
    seen: set[tuple[object, object, object]] = set()
    for event in events:
        key = (event.get("congress"), event.get("chamber"), event.get("rollnumber"))
        if key in seen:
            continue
        seen.add(key)
        contribution = float(event.get("contribution") or 0)
        align = 1.15 if delta != 0 and contribution * delta > 0 else 1.0
        ranked.append((abs(contribution) * align, event))
    ranked.sort(key=lambda item: -item[0])
    return [event for _, event in ranked[:MAX_MOVES]]


def issues_for(text: str, mapping: dict[str, list[str]]) -> list[str]:
    blob = f" {text.lower()} "
    found: list[str] = []
    for issue_id, terms in mapping.items():
        if any(term.lower() in blob for term in terms):
            found.append(issue_id)
    return found


def download(url: str, dest: Path) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        return True
    try:
        print(f"downloading {url}…", flush=True)
        with urllib.request.urlopen(url, timeout=60) as res, dest.open("wb") as out:
            out.write(res.read())
        return True
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            dest.unlink(missing_ok=True)
            return False
        raise


def chamber_files(congress: int, chamber: str) -> dict[str, str]:
    prefix = "H" if chamber == "H" else "S"
    stem = f"{prefix}{congress}"
    return {
        "rollcalls": f"{stem}_rollcalls.csv",
        "votes": f"{stem}_votes.csv",
        "members": f"{stem}_members.csv",
    }


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return [{str(k).lower(): (v or "").strip() for k, v in row.items()} for row in csv.DictReader(handle)]


def collect_from_dir(from_dir: Path) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, str]]]:
    rollcalls: list[dict[str, str]] = []
    votes: list[dict[str, str]] = []
    members: list[dict[str, str]] = []
    for path in sorted(from_dir.glob("*_rollcalls.csv")):
        rollcalls.extend(read_csv(path))
    for path in sorted(from_dir.glob("*_votes.csv")):
        votes.extend(read_csv(path))
    for path in sorted(from_dir.glob("*_members.csv")):
        members.extend(read_csv(path))
    return rollcalls, votes, members


def collect_live(cache: Path, min_congress: int, max_congress: int):
    rollcalls: list[dict[str, str]] = []
    votes: list[dict[str, str]] = []
    members: list[dict[str, str]] = []
    for congress in range(min_congress, max_congress + 1):
        for chamber in ("H", "S"):
            names = chamber_files(congress, chamber)
            local = {}
            ok = True
            for kind, filename in names.items():
                dest = cache / filename
                url = f"{VOTEVIEW}/{'rollcalls' if kind == 'rollcalls' else 'votes' if kind == 'votes' else 'members'}/{filename}"
                if not download(url, dest):
                    ok = False
                    break
                local[kind] = dest
            if not ok:
                print(f"skip {chamber}{congress} (not on VoteView yet)", flush=True)
                continue
            rollcalls.extend(read_csv(local["rollcalls"]))
            votes.extend(read_csv(local["votes"]))
            members.extend(read_csv(local["members"]))
    return rollcalls, votes, members


def score(
    rollcalls: list[dict[str, str]],
    votes: list[dict[str, str]],
    members: list[dict[str, str]],
    wanted: set[str],
    mapping: dict[str, list[str]],
) -> dict[str, dict[str, object]]:
    icpsr_to_bio: dict[str, str] = {}
    for row in members:
        bio = (row.get("bioguide_id") or "").upper()
        icpsr = row.get("icpsr") or ""
        if bio and icpsr and (not wanted or bio in wanted):
            icpsr_to_bio[icpsr] = bio

    coded: dict[tuple[str, str, str, str], int] = {}
    meta: dict[tuple[str, str, str], dict[str, str]] = {}
    skipped = 0
    used = 0
    for row in rollcalls:
        congress = row.get("congress") or ""
        chamber = row.get("chamber") or ""
        number = row.get("rollnumber") or ""
        bill = (row.get("bill_number") or "").upper()
        if bill.startswith("PN") or "nomination" in (row.get("vote_question") or "").lower():
            skipped += 1
            continue
        try:
            spread = float(row.get("nominate_spread_1") or "0")
        except ValueError:
            skipped += 1
            continue
        if abs(spread) < SPREAD_MIN:
            skipped += 1
            continue
        text = " ".join(
            [
                bill,
                row.get("vote_desc") or "",
                row.get("vote_question") or "",
                row.get("dtl_desc") or "",
            ]
        )
        issue_ids = issues_for(text, mapping)
        if not issue_ids:
            skipped += 1
            continue
        # Empirically, VoteView spread_1 > 0 is the liberal Yea side on
        # the first dimension (Sanders yea on health bills, MTG nay).
        polarity = -1 if spread > 0 else 1
        meta[(congress, chamber, number)] = {
            "bill": bill,
            "question": row.get("vote_question") or "",
            "desc": (row.get("vote_desc") or row.get("dtl_desc") or "").strip(),
            "date": row.get("date") or "",
        }
        for issue_id in issue_ids:
            coded[(congress, chamber, number, issue_id)] = polarity
            used += 1

    votes_by_roll: dict[tuple[str, str, str], list[tuple[str, int]]] = defaultdict(list)
    for row in votes:
        bio = icpsr_to_bio.get(row.get("icpsr") or "")
        if not bio:
            continue
        try:
            cast = int(float(row.get("cast_code") or "9"))
        except ValueError:
            continue
        if cast in YEA:
            side = 1
        elif cast in NAY:
            side = -1
        else:
            continue
        votes_by_roll[
            (row.get("congress") or "", row.get("chamber") or "", row.get("rollnumber") or "")
        ].append((bio, side))

    sums: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    counts: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    session_sums: dict[str, dict[str, dict[str, float]]] = defaultdict(
        lambda: defaultdict(lambda: defaultdict(float))
    )
    session_counts: dict[str, dict[str, dict[str, int]]] = defaultdict(
        lambda: defaultdict(lambda: defaultdict(int))
    )
    session_events: dict[str, dict[str, list[dict[str, object]]]] = defaultdict(
        lambda: defaultdict(list)
    )
    for (congress, chamber, number, issue_id), polarity in coded.items():
        info = meta.get((congress, chamber, number), {})
        for bio, side in votes_by_roll.get((congress, chamber, number), ()):
            # Yea on a conservative-coded vote, or nay on a liberal-coded vote, is +100.
            contribution = 100.0 if (side * polarity) > 0 else -100.0
            sums[bio][issue_id] += contribution
            counts[bio][issue_id] += 1
            session_sums[bio][congress][issue_id] += contribution
            session_counts[bio][congress][issue_id] += 1
            session_events[bio][congress].append(
                {
                    "date": info.get("date") or "",
                    "congress": int(float(congress)) if congress else 0,
                    "chamber": "House" if chamber[:1].upper() == "H" else "Senate",
                    "rollnumber": number,
                    "bill": info.get("bill") or "",
                    "question": info.get("question") or "",
                    "desc": info.get("desc") or "",
                    "issueId": issue_id,
                    "cast": "Yea" if side > 0 else "Nay",
                    "contribution": contribution,
                    "url": voteview_rollcall_url(congress, chamber, number),
                }
            )

    members_out: dict[str, dict[str, object]] = {}
    for bio, issue_sums in sums.items():
        issues = {
            issue_id: round(total / counts[bio][issue_id], 1)
            for issue_id, total in issue_sums.items()
            if counts[bio][issue_id] > 0
        }
        sessions: list[dict[str, object]] = []
        prev_axis: float | None = None
        for congress in sorted(session_sums[bio].keys(), key=lambda c: int(float(c or 0))):
            try:
                cong_n = int(float(congress))
            except ValueError:
                continue
            raw_counts = session_counts[bio][congress]
            session_issues = {
                issue_id: round(total / raw_counts[issue_id], 1)
                for issue_id, total in session_sums[bio][congress].items()
                if raw_counts[issue_id] >= SESSION_MIN_VOTES
            }
            if not session_issues:
                continue
            year = congress_start_year(cong_n)
            axis = axis_from_issues(session_issues)
            moves = pick_moves(session_events[bio][congress], prev_axis, axis)
            sessions.append(
                {
                    "congress": cong_n,
                    "year": year,
                    "label": f"{congress_ordinal(cong_n)} Congress",
                    "axisScore": axis,
                    "issues": session_issues,
                    "counts": {
                        k: int(v)
                        for k, v in raw_counts.items()
                        if k in session_issues
                    },
                    "moves": moves,
                }
            )
            prev_axis = axis
        members_out[bio] = {
            "issues": issues,
            "counts": {k: int(v) for k, v in counts[bio].items()},
            "sessions": sessions,
        }
    print(
        f"coded {used} issue-linked roll calls; skipped {skipped}; members scored {len(members_out)}",
        flush=True,
    )
    return members_out


def wanted_bioguides(path: Path) -> set[str]:
    if not path.exists():
        return set()
    people = json.loads(path.read_text())
    return {
        str(p["bioguideId"]).upper()
        for p in people
        if isinstance(p, dict) and p.get("bioguideId")
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Score SII issues from VoteView roll calls")
    parser.add_argument("--from-dir", type=Path, help="Local VoteView CSVs (tests; skip download)")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--min-congress", type=int, default=MIN_CONGRESS)
    parser.add_argument("--max-congress", type=int, default=MAX_CONGRESS)
    parser.add_argument("--politicians", type=Path, default=POLITICIANS)
    args = parser.parse_args()

    mapping = load_map()
    wanted = wanted_bioguides(args.politicians)
    if args.from_dir:
        rollcalls, votes, members = collect_from_dir(args.from_dir)
    else:
        rollcalls, votes, members = collect_live(args.cache, args.min_congress, args.max_congress)
    overlay = score(rollcalls, votes, members, wanted, mapping)
    payload = {
        "source": "voteview.com",
        "method": "sii-rollcall-v2",
        "minCongress": args.min_congress,
        "maxCongress": args.max_congress,
        "attribution": "Floor votes from VoteView. Cutting line sets bill polarity; member DW-NOMINATE scores are not used.",
        "members": overlay,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"wrote {args.out} ({len(overlay)} members)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
