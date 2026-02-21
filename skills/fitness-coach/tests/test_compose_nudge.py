#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import tempfile
import unittest
from pathlib import Path
from zoneinfo import ZoneInfo

import sys

SCRIPT_DIR = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

import compose_nudge  # noqa: E402


IST = ZoneInfo("Asia/Kolkata")


class ComposeNudgeTests(unittest.TestCase):
    def test_slot_for_time(self) -> None:
        self.assertEqual(compose_nudge.slot_for_time(dt.datetime(2026, 2, 15, 8, 0, tzinfo=IST)), "morning")
        self.assertEqual(compose_nudge.slot_for_time(dt.datetime(2026, 2, 15, 10, 0, tzinfo=IST)), "mid_morning")
        self.assertEqual(compose_nudge.slot_for_time(dt.datetime(2026, 2, 15, 13, 0, tzinfo=IST)), "afternoon")
        self.assertEqual(compose_nudge.slot_for_time(dt.datetime(2026, 2, 15, 16, 0, tzinfo=IST)), "evening")
        self.assertEqual(compose_nudge.slot_for_time(dt.datetime(2026, 2, 15, 21, 0, tzinfo=IST)), "night")

    def test_avoid_recent_repeats(self) -> None:
        now = dt.datetime(2026, 2, 15, 8, 30, tzinfo=IST)
        history = []
        pool = compose_nudge.TIPS_BY_SLOT["morning"]
        for idx, item in enumerate(pool[:3]):
            history.append(
                {
                    "ts": (now - dt.timedelta(hours=idx + 1)).isoformat(),
                    "tip_id": item["id"],
                    "opening_id": "o_m_1",
                    "closing_id": "c_1",
                }
            )
        result = compose_nudge.compose(history, now)
        blocked = {entry["tip_id"] for entry in history}
        self.assertNotIn(result["tip_id"], blocked)

    def test_generated_message_has_no_banned_terms(self) -> None:
        now = dt.datetime(2026, 2, 15, 19, 30, tzinfo=IST)
        result = compose_nudge.compose([], now)
        lower = result["message"].lower()
        for term in compose_nudge.BANNED_TERMS:
            self.assertNotIn(term, lower)

    def test_state_persists_and_rotates(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            state_file = Path(tmpdir) / "state.json"
            first_now = dt.datetime(2026, 2, 15, 10, 0, tzinfo=IST)
            second_now = first_now + dt.timedelta(minutes=30)

            first = compose_nudge.compose([], first_now)
            compose_nudge.save_state(
                state_file,
                [
                    {
                        "ts": first_now.isoformat(),
                        "slot": first["slot"],
                        "tip_id": first["tip_id"],
                        "opening_id": first["opening_id"],
                        "closing_id": first["closing_id"],
                        "message": first["message"],
                    }
                ],
            )

            loaded = compose_nudge.load_state(state_file)
            history = compose_nudge.prune_history(loaded["history"], second_now)
            second = compose_nudge.compose(history, second_now)
            self.assertNotEqual(first["tip_id"], second["tip_id"])


if __name__ == "__main__":
    unittest.main()
