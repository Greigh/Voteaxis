#!/usr/bin/env python3
"""Fixture checks for session coordinates in the VoteView overlay."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "score_rollcalls.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures" / "voteview"


class ScoreRollcallsTest(unittest.TestCase):
    def test_sessions_group_by_congress(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "rollcall.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--from-dir",
                    str(FIXTURES),
                    "--out",
                    str(out),
                    "--min-congress",
                    "117",
                    "--max-congress",
                    "118",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("members scored", result.stdout)
            payload = json.loads(out.read_text())
            self.assertEqual(payload["method"], "sii-rollcall-v2")
            member = payload["members"]["S000033"]
            self.assertIn("healthcare", member["issues"])
            sessions = member["sessions"]
            self.assertEqual([s["congress"] for s in sessions], [117, 118])
            self.assertEqual(sessions[0]["year"], 2021)
            self.assertEqual(sessions[1]["year"], 2023)
            self.assertNotEqual(sessions[0]["axisScore"], sessions[1]["axisScore"])
            self.assertTrue(sessions[0]["moves"])
            self.assertEqual(sessions[0]["moves"][0]["cast"], "Yea")
            self.assertIn("voteview.com/rollcall/", sessions[1]["moves"][0]["url"])


if __name__ == "__main__":
    unittest.main()
