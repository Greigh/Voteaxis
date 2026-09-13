#!/usr/bin/env python3
"""Sync the curated politicians roster into the API's served copy.

`mobile/assets/data/politicians.json` stays the single source of truth (it's
what `flutter build` embeds). The API server can't read into `mobile/` on a
production box — `scripts/deploy.py` deliberately never ships `mobile/` there
— so `GET /v1/politicians` serves a copy at `server/data/politicians.json`
instead. Run this after editing the roster and before `bun run deploy`.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "mobile" / "assets" / "data" / "politicians.json"
DEST = ROOT / "server" / "data" / "politicians.json"


def main() -> int:
    raw = SRC.read_text()
    data = json.loads(raw)
    if not isinstance(data, list) or not data:
        print(f"refusing to sync: {SRC} is not a non-empty JSON array", file=sys.stderr)
        return 1
    DEST.write_text(raw)
    print(f"synced {len(data)} figures: {SRC} -> {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
