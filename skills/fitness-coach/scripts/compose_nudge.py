#!/usr/bin/env python3
"""Generate short habit-focused coaching nudges with anti-repetition state."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

IST = ZoneInfo("Asia/Kolkata")
STATE_FILE_DEFAULT = Path.home() / ".openclaw" / "state" / "fitness-coach" / "rotation_state.json"
LOOKBACK_RECENT_RUNS = 8
LOOKBACK_HOURS = 24
HISTORY_CAP = 400

BANNED_TERMS = (
    "liver",
    "fitness",
    "weight loss",
    "obese",
    "kg",
)

TIPS_BY_SLOT: dict[str, list[dict[str, str]]] = {
    "morning": [
        {"id": "m_warm_water", "text": "Start the day with one glass of warm water before tea or coffee."},
        {"id": "m_sunlight", "text": "Get 5-10 minutes of morning light and easy breathing to set your day rhythm."},
        {"id": "m_simple_breakfast", "text": "Keep breakfast simple with protein plus fiber, and skip packaged sugary options."},
        {"id": "m_gentle_mobility", "text": "Do 3 minutes of gentle chair mobility before work to reduce stiffness early."},
        {"id": "m_water_bottle_ready", "text": "Fill your water bottle now and keep it visible so hydration stays automatic."},
    ],
    "mid_morning": [
        {"id": "mm_water_check", "text": "Take a quick water break now and finish one full glass slowly."},
        {"id": "mm_unsweetened_swap", "text": "Choose an unsweetened drink for this slot instead of anything sugary."},
        {"id": "mm_snack_upgrade", "text": "Pick a light snack like fruit or nuts and skip fried packaged bites."},
        {"id": "mm_posture_reset", "text": "Stand up for 2 minutes, roll your shoulders, and reset posture before the next task."},
        {"id": "mm_breathing_pause", "text": "Take a short 60-second breathing pause to lower stress snacking later."},
    ],
    "afternoon": [
        {"id": "a_half_plate_veg", "text": "At lunch, make half your plate vegetables and add one protein source."},
        {"id": "a_fried_food_limit", "text": "Keep today’s lunch less oily and avoid deep-fried sides."},
        {"id": "a_sugar_cut", "text": "Skip sweet drinks with lunch and choose plain water instead."},
        {"id": "a_portion_pace", "text": "Eat a little slower today and stop when comfortably full, not heavy."},
        {"id": "a_after_meal_walk", "text": "Take an easy 8-10 minute walk after lunch if possible."},
    ],
    "evening": [
        {"id": "e_short_walk", "text": "Take a comfortable 10-15 minute walk this evening at a relaxed pace."},
        {"id": "e_joint_mobility", "text": "Try 5 minutes of low-impact mobility: ankle circles, shoulder rolls, and seated twists."},
        {"id": "e_alcohol_free", "text": "Choose an alcohol-free evening and hydrate well instead."},
        {"id": "e_snack_cleanup", "text": "Keep evening snacks light and skip fried or highly processed options."},
        {"id": "e_dinner_prep", "text": "Plan a lighter dinner now so late-night cravings stay low."},
    ],
    "night": [
        {"id": "n_light_dinner", "text": "Keep dinner lighter than lunch and avoid heavy oily foods tonight."},
        {"id": "n_early_finish", "text": "Try to finish dinner a bit earlier and keep a gap before sleep."},
        {"id": "n_post_dinner_walk", "text": "Do a gentle 10-minute walk after dinner to feel lighter before bed."},
        {"id": "n_sleep_winddown", "text": "Start a calm wind-down routine and reduce screen time before sleeping."},
        {"id": "n_hydration_close", "text": "Have a small final hydration check now, without overdrinking right before bed."},
    ],
}

OPENINGS_BY_SLOT: dict[str, list[dict[str, str]]] = {
    "morning": [
        {"id": "o_m_1", "text": "Good morning, let’s keep today simple and steady."},
        {"id": "o_m_2", "text": "Morning check-in: one small step now can shape the full day."},
        {"id": "o_m_3", "text": "New day, gentle start."},
    ],
    "mid_morning": [
        {"id": "o_mm_1", "text": "Quick check-in before the day gets busy."},
        {"id": "o_mm_2", "text": "Small reset moment for your body and mind."},
        {"id": "o_mm_3", "text": "A tiny mid-morning nudge for consistency."},
    ],
    "afternoon": [
        {"id": "o_a_1", "text": "Afternoon reset: keep it clean and practical."},
        {"id": "o_a_2", "text": "Lunch-hour nudge for stable energy later."},
        {"id": "o_a_3", "text": "This is a good point to make one better choice."},
    ],
    "evening": [
        {"id": "o_e_1", "text": "Evening rhythm matters more than intensity."},
        {"id": "o_e_2", "text": "A calm evening step can improve how tomorrow feels."},
        {"id": "o_e_3", "text": "Let’s keep tonight easy and intentional."},
    ],
    "night": [
        {"id": "o_n_1", "text": "Night reset: aim for light and calm."},
        {"id": "o_n_2", "text": "As the day closes, gentle choices help recovery."},
        {"id": "o_n_3", "text": "One last steady habit before sleep."},
    ],
}

CLOSINGS: list[dict[str, str]] = [
    {"id": "c_1", "text": "You're building this through consistency, not perfection."},
    {"id": "c_2", "text": "Small daily wins compound quickly."},
    {"id": "c_3", "text": "Keep it easy and repeatable."},
    {"id": "c_4", "text": "You’re on the right track."},
    {"id": "c_5", "text": "One step at a time is enough."},
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compose anti-repetition coaching nudge.")
    parser.add_argument("--state-file", default=str(STATE_FILE_DEFAULT), help="State file path")
    parser.add_argument("--now-iso", default="", help="Override time in ISO format")
    parser.add_argument("--json", action="store_true", help="Emit JSON with metadata instead of plain text")
    return parser.parse_args()


def parse_now(now_iso: str) -> dt.datetime:
    if not now_iso:
        return dt.datetime.now(IST)
    parsed = dt.datetime.fromisoformat(now_iso)
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=IST)
    return parsed.astimezone(IST)


def slot_for_time(now: dt.datetime) -> str:
    hour = now.hour
    if 7 <= hour < 9:
        return "morning"
    if 9 <= hour < 12:
        return "mid_morning"
    if 12 <= hour < 15:
        return "afternoon"
    if 15 <= hour < 19:
        return "evening"
    return "night"


def load_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"history": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"history": []}
    if not isinstance(data, dict):
        return {"history": []}
    history = data.get("history", [])
    if not isinstance(history, list):
        history = []
    return {"history": history}


def parse_ts(ts_raw: str) -> dt.datetime | None:
    try:
        parsed = dt.datetime.fromisoformat(ts_raw)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=IST)
    return parsed.astimezone(IST)


def prune_history(history: list[dict[str, Any]], now: dt.datetime) -> list[dict[str, Any]]:
    floor = now - dt.timedelta(days=30)
    pruned: list[dict[str, Any]] = []
    for entry in history:
        ts_raw = str(entry.get("ts", ""))
        ts = parse_ts(ts_raw)
        if ts is None or ts < floor:
            continue
        pruned.append(entry)
    return pruned[-HISTORY_CAP:]


def recent_blocks(history: list[dict[str, Any]], now: dt.datetime) -> tuple[set[str], set[str]]:
    last_runs = {
        str(entry.get("tip_id", ""))
        for entry in history[-LOOKBACK_RECENT_RUNS:]
        if entry.get("tip_id")
    }
    floor = now - dt.timedelta(hours=LOOKBACK_HOURS)
    last_24h: set[str] = set()
    for entry in history:
        tip_id = str(entry.get("tip_id", ""))
        if not tip_id:
            continue
        ts = parse_ts(str(entry.get("ts", "")))
        if ts is not None and ts >= floor:
            last_24h.add(tip_id)
    return last_runs, last_24h


def last_seen_map(history: list[dict[str, Any]], key_name: str) -> dict[str, dt.datetime]:
    seen: dict[str, dt.datetime] = {}
    for entry in history:
        key = str(entry.get(key_name, ""))
        if not key:
            continue
        ts = parse_ts(str(entry.get("ts", "")))
        if ts is None:
            continue
        prior = seen.get(key)
        if prior is None or ts > prior:
            seen[key] = ts
    return seen


def choose_least_recent(
    items: list[dict[str, str]],
    key_name: str,
    history: list[dict[str, Any]],
) -> dict[str, str]:
    seen = last_seen_map(history, key_name)

    def sort_key(item: dict[str, str]) -> tuple[float, str]:
        item_id = item["id"]
        ts = seen.get(item_id)
        score = ts.timestamp() if ts is not None else -1.0
        return (score, item_id)

    return sorted(items, key=sort_key)[0]


def choose_tip(slot: str, history: list[dict[str, Any]], now: dt.datetime) -> dict[str, str]:
    pool = TIPS_BY_SLOT[slot]
    recent_runs, recent_24h = recent_blocks(history, now)
    candidates = [item for item in pool if item["id"] not in recent_runs and item["id"] not in recent_24h]
    if not candidates:
        candidates = [item for item in pool if item["id"] not in recent_24h]
    if not candidates:
        candidates = pool
    return choose_least_recent(candidates, "tip_id", history)


def choose_opening(slot: str, history: list[dict[str, Any]]) -> dict[str, str]:
    return choose_least_recent(OPENINGS_BY_SLOT[slot], "opening_id", history)


def choose_closing(history: list[dict[str, Any]]) -> dict[str, str]:
    return choose_least_recent(CLOSINGS, "closing_id", history)


def validate_message(message: str) -> None:
    compact = re.sub(r"\s+", " ", message).strip()
    for term in BANNED_TERMS:
        if re.search(rf"\b{re.escape(term)}\b", compact, flags=re.IGNORECASE):
            raise ValueError(f"Generated message contains banned term: {term}")
    sentence_count = len([part for part in re.split(r"[.!?]+", compact) if part.strip()])
    if sentence_count < 2 or sentence_count > 3:
        raise ValueError("Generated message must have 2-3 sentences")


def compose(history: list[dict[str, Any]], now: dt.datetime) -> dict[str, str]:
    slot = slot_for_time(now)
    opening = choose_opening(slot, history)
    tip = choose_tip(slot, history, now)
    closing = choose_closing(history)
    message = f"{opening['text']} {tip['text']} {closing['text']}"
    message = re.sub(r"\s+", " ", message).strip()
    validate_message(message)
    return {
        "slot": slot,
        "tip_id": tip["id"],
        "opening_id": opening["id"],
        "closing_id": closing["id"],
        "message": message,
    }


def save_state(path: Path, history: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"history": history[-HISTORY_CAP:]}
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    tmp_path.replace(path)


def main() -> int:
    args = parse_args()
    state_path = Path(args.state_file).expanduser()
    now = parse_now(args.now_iso)
    state = load_state(state_path)
    history = prune_history(state.get("history", []), now)
    result = compose(history, now)

    history.append(
        {
            "ts": now.isoformat(),
            "slot": result["slot"],
            "tip_id": result["tip_id"],
            "opening_id": result["opening_id"],
            "closing_id": result["closing_id"],
            "message": result["message"],
        }
    )
    save_state(state_path, history)

    if args.json:
        print(json.dumps(result, ensure_ascii=True))
    else:
        print(result["message"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
