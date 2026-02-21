#!/usr/bin/env python3
"""Adaptive training engine for basics-first SAP-C02 coaching."""

from __future__ import annotations

import hashlib
import json
import random
import re
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

from coach_adaptive_data import (
    ADVANCED_DISTRACTORS,
    DEFAULT_KIT,
    GENERIC_DISTRACTORS,
    KEYWORD_KITS,
    LEVEL_DESCRIPTION,
    LEVEL_LABELS,
    PITFALL_DISTRACTORS,
    STEP_DISTRACTORS,
    TRADEOFF_DISTRACTORS,
)
from coach_common import STATE_DIR, domain_priorities, task_without_prefix, utc_now_iso, write_json


def ensure_adaptive_state(profile: dict[str, Any]) -> dict[str, Any]:
    adaptive = profile.setdefault("adaptive", {})
    level = int(adaptive.get("level", 1))
    adaptive["level"] = max(1, min(5, level))
    adaptive["success_streak"] = int(adaptive.get("success_streak", 0))
    adaptive["fail_streak"] = int(adaptive.get("fail_streak", 0))
    adaptive.setdefault("last_session_id", "")
    adaptive.setdefault("last_session_file", "")
    adaptive.setdefault("last_level_change", "initialized")
    return adaptive


def update_adaptive_level(profile: dict[str, Any], score: int) -> str:
    adaptive = ensure_adaptive_state(profile)
    old_level = adaptive["level"]
    change_note = "level unchanged"

    if score >= 85:
        adaptive["success_streak"] += 1
        adaptive["fail_streak"] = 0
        if adaptive["success_streak"] >= 2 and adaptive["level"] < 5:
            adaptive["level"] += 1
            adaptive["success_streak"] = 0
            change_note = f"level up {old_level}->{adaptive['level']}"
    elif score < 65:
        adaptive["fail_streak"] += 1
        adaptive["success_streak"] = 0
        if adaptive["fail_streak"] >= 2 and adaptive["level"] > 1:
            adaptive["level"] -= 1
            adaptive["fail_streak"] = 0
            change_note = f"level down {old_level}->{adaptive['level']}"
    else:
        adaptive["success_streak"] = 0
        adaptive["fail_streak"] = 0

    adaptive["last_level_change"] = change_note
    return change_note


def _normalize_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "learner"


def _session_dir() -> Path:
    path = STATE_DIR / "sessions"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _session_path(profile: dict[str, Any], session_id: str) -> Path:
    base = _normalize_name(profile.get("learner_name", "learner"))
    safe_session = re.sub(r"[^a-zA-Z0-9._-]+", "-", session_id)
    return _session_dir() / f"{base}-{safe_session}.json"


def _select_kit(task_anchor: str) -> dict[str, Any]:
    lowered = task_anchor.lower()
    for kit in KEYWORD_KITS:
        if any(keyword in lowered for keyword in kit["keywords"]):
            return kit
    return DEFAULT_KIT


def _seeded_rng(seed_text: str) -> random.Random:
    seed = int(hashlib.sha256(seed_text.encode("utf-8")).hexdigest()[:16], 16)
    return random.Random(seed)


def _shuffle_options(correct: str, distractors: list[str], rng: random.Random) -> tuple[dict[str, str], str]:
    options = [("correct", correct)] + [("wrong", item) for item in distractors[:3]]
    rng.shuffle(options)
    labels = ["A", "B", "C", "D"]
    rendered: dict[str, str] = {}
    correct_label = "A"
    for index, (kind, text) in enumerate(options):
        label = labels[index]
        rendered[label] = text
        if kind == "correct":
            correct_label = label
    return rendered, correct_label


def _build_question(
    prompt: str,
    correct: str,
    distractors: list[str],
    explanation: str,
    rng: random.Random,
) -> dict[str, Any]:
    options, correct_label = _shuffle_options(correct, distractors, rng)
    return {
        "prompt": prompt,
        "options": options,
        "correct": correct_label,
        "explanation": explanation,
    }


def _question_set(task_anchor: str, level: int, kit: dict[str, Any], rng: random.Random) -> list[dict[str, Any]]:
    q1 = _build_question(
        f"For '{task_anchor}', which statement is most correct?",
        kit["principle"],
        GENERIC_DISTRACTORS,
        "Strong SAP-C02 answers start with requirement-aligned principles.",
        rng,
    )
    q2 = _build_question(
        "What is the best first step before final architecture selection?",
        kit["first_step"],
        STEP_DISTRACTORS,
        "The first step should reduce ambiguity and improve decision quality.",
        rng,
    )

    if level <= 2:
        prompt = "Which option is the highest-risk pitfall for this type of design?"
        correct = kit["pitfall"]
        distractors = PITFALL_DISTRACTORS
        explanation = "Avoiding common pitfalls is the fastest path from basics to reliable execution."
    elif level == 3:
        prompt = "Which trade-off decision is strongest for this scenario?"
        correct = kit["tradeoff_best"]
        distractors = TRADEOFF_DISTRACTORS
        explanation = "Level 3 emphasizes trade-off defense, not one-dimensional optimization."
    else:
        prompt = "Which advanced strategy best handles complexity while keeping operations safe?"
        correct = kit["advanced_best"]
        distractors = ADVANCED_DISTRACTORS
        explanation = "Higher levels require safe operation under multiple constraints."

    q3 = _build_question(prompt, correct, distractors, explanation, rng)
    return [q1, q2, q3]


def _pick_domain(profile: dict[str, Any], blueprint: dict[str, Any], today: date, level: int) -> dict[str, Any]:
    confidence = {key: int(value) for key, value in profile.get("confidence", {}).items()}
    priorities = domain_priorities(blueprint, confidence)
    ranked = sorted(blueprint["domains"], key=lambda domain: (-priorities[domain["id"]], domain["id"]))

    if level <= 2:
        by_confidence = sorted(
            blueprint["domains"],
            key=lambda domain: (confidence.get(domain["id"], 2), -domain["weight_pct"], domain["id"]),
        )
        ranked = by_confidence

    return ranked[today.toordinal() % len(ranked)]


def build_adaptive_daily_session(
    profile: dict[str, Any],
    blueprint: dict[str, Any],
    today_iso: str,
    profile_path: str | None,
) -> dict[str, Any]:
    adaptive = ensure_adaptive_state(profile)
    level = adaptive["level"]
    today = date.fromisoformat(today_iso)

    domain = _pick_domain(profile, blueprint, today, level)
    task_raw = domain["tasks"][today.toordinal() % len(domain["tasks"])]
    task_anchor = task_without_prefix(task_raw)
    kit = _select_kit(task_anchor)

    utc_now = datetime.now(timezone.utc)
    slot = "am" if utc_now.hour < 12 else "pm"
    session_id = f"{today_iso}-{slot}-{domain['id']}-l{level}"
    rng = _seeded_rng(session_id)
    questions = _question_set(task_anchor, level, kit, rng)

    minutes = max(30, min(75, int(float(profile.get("weekly_hours", 8)) * 7)))
    learn_minutes = max(10, int(minutes * 0.2))
    drill_minutes = max(15, int(minutes * 0.5))
    quiz_minutes = max(8, minutes - learn_minutes - drill_minutes)

    session = {
        "session_id": session_id,
        "date": today_iso,
        "domain_id": domain["id"],
        "domain_title": domain["title"],
        "task_anchor": task_anchor,
        "level": level,
        "level_label": LEVEL_LABELS[level],
        "level_description": LEVEL_DESCRIPTION[level],
        "kit": {"learn": kit["learn"], "scenario": kit["scenario"]},
        "minutes": {
            "learn": learn_minutes,
            "drill": drill_minutes,
            "quiz": quiz_minutes,
        },
        "questions": questions,
        "profile_path": profile_path or "",
        "created_at": utc_now_iso(),
        "status": "open",
    }
    return session


def render_adaptive_daily_message(session: dict[str, Any], profile_path: str | None) -> str:
    command = (
        "python3 /home/shkas/projects/raaz/skills/aws-certification-coach/scripts/coach.py "
        f"check-answers --profile {profile_path} --session-id {session['session_id']} --answers A,B,C"
        if profile_path
        else "python3 coach.py check-answers --profile <profile.json> --session-id <session-id> --answers A,B,C"
    )

    lines: list[str] = []
    lines.append(f"SAP-C02 Adaptive Coaching ({session['date']})")
    lines.append(f"*Level:* L{session['level']} - {session['level_label']}")
    lines.append(f"*Focus:* {session['domain_title']}")
    lines.append(f"*Task Anchor:* {session['task_anchor']}")
    lines.append("")
    lines.append("Today flow:")
    lines.append(f"1) Learn ({session['minutes']['learn']}m)")
    for item in session["kit"]["learn"][:3]:
        lines.append(f"- {item}")
    lines.append(f"2) Scenario Drill ({session['minutes']['drill']}m)")
    lines.append(f"- {session['kit']['scenario']}")
    lines.append(f"3) Quiz Check ({session['minutes']['quiz']}m)")
    lines.append("")
    lines.append("Quiz (choose A/B/C/D):")
    for index, question in enumerate(session["questions"], start=1):
        lines.append(f"Q{index}) {question['prompt']}")
        for label in ["A", "B", "C", "D"]:
            lines.append(f"{label}) {question['options'][label]}")
    lines.append("")

    lines.append(f"Session ID: {session['session_id']}")
    lines.append("Reply format (recommended): /sap_ans <session-id> A,B,C")
    lines.append("Fallback format: SAP-ANS <session-id> A,B,C")
    lines.append(f"Auto-check command: {command}")
    lines.append("")
    lines.append("I will raise complexity automatically when your recent scores stay strong.")
    return "\n".join(lines).rstrip()


def save_session_for_profile(profile: dict[str, Any], session: dict[str, Any]) -> Path:
    path = _session_path(profile, session["session_id"])
    write_json(path, session)
    adaptive = ensure_adaptive_state(profile)
    adaptive["last_session_id"] = session["session_id"]
    adaptive["last_session_file"] = str(path)
    return path


def _load_session(profile: dict[str, Any], session_id: str | None) -> tuple[dict[str, Any], Path]:
    adaptive = ensure_adaptive_state(profile)
    if session_id:
        path = _session_path(profile, session_id)
    else:
        last = adaptive.get("last_session_file", "")
        if not last:
            raise ValueError("No prior session found. Run daily-brief first.")
        path = Path(last)

    if not path.exists():
        raise ValueError(f"Session not found: {path}")
    payload = path.read_text(encoding="utf-8")
    session = json.loads(payload)
    return session, path


def parse_answers(raw: str, expected: int) -> list[str]:
    if expected <= 0:
        raise ValueError("Session has no quiz questions to grade.")

    normalized = raw.strip().upper()
    numbered = re.findall(r"(?:^|[\s,;])(?:Q?\d+)\s*[:=-]?\s*([ABCD])(?=$|[\s,;])", normalized)
    if numbered:
        if len(numbered) != expected:
            raise ValueError(f"Expected {expected} answers but got {len(numbered)}.")
        return numbered

    single_tokens = [token for token in re.split(r"[,\s;/]+", normalized) if token in {"A", "B", "C", "D"}]
    if single_tokens:
        if len(single_tokens) != expected:
            raise ValueError(f"Expected {expected} answers but got {len(single_tokens)}.")
        return single_tokens

    raise ValueError("Could not parse answers. Use format: A,B,C or 1A 2B 3C.")


def grade_answers(
    profile: dict[str, Any],
    session_id: str | None,
    answers_raw: str,
    result_date: str,
) -> tuple[str, dict[str, Any]]:
    session, session_path = _load_session(profile, session_id)
    questions = session.get("questions", [])

    status = str(session.get("status", "open")).strip().lower()
    if status == "graded":
        previous = session.get("result", {})
        lines: list[str] = []
        lines.append(f"SAP-C02 Check Result ({result_date})")
        lines.append(f"Session: {session['session_id']}")
        if previous:
            total = int(previous.get("total", max(1, len(questions))))
            correct = int(previous.get("correct", 0))
            score = int(previous.get("score", round((correct / max(1, total)) * 100)))
            lines.append(f"Score: {score}/100 ({correct}/{total} correct)")
        lines.append(f"Status: already graded at {session.get('graded_at', 'unknown time')}")
        lines.append("No profile changes were applied.")
        lines.append("")
        lines.append("Next step: run daily-brief again for the next drill.")
        return "\n".join(lines), profile

    if status and status != "open":
        raise ValueError(
            f"Session {session['session_id']} is not open for grading (status={session.get('status')})."
        )

    answers = parse_answers(answers_raw, len(questions))

    checks: list[dict[str, Any]] = []
    correct_count = 0
    for index, question in enumerate(questions):
        expected = question["correct"]
        given = answers[index]
        ok = expected == given
        if ok:
            correct_count += 1
        checks.append(
            {
                "q": index + 1,
                "given": given,
                "expected": expected,
                "ok": ok,
                "explanation": question["explanation"],
            }
        )

    score = int(round((correct_count / max(1, len(questions))) * 100))
    level_change = update_adaptive_level(profile, score)

    domain_id = session["domain_id"]
    current_conf = int(profile.get("confidence", {}).get(domain_id, 2))
    delta = 1 if score >= 85 else -1 if score < 60 else 0
    new_conf = max(1, min(5, current_conf + delta))
    profile["confidence"][domain_id] = new_conf

    history = profile.get("history", [])
    history.append(
        {
            "date": result_date,
            "domain": domain_id,
            "score": score,
            "notes": (
                f"adaptive-quiz session={session['session_id']} level=L{session['level']} "
                f"answers={','.join(answers)} correct={correct_count}/{len(questions)}"
            ),
            "source": "adaptive-quiz",
            "logged_at": utc_now_iso(),
        }
    )
    profile["history"] = history
    profile["updated_at"] = utc_now_iso()

    session["status"] = "graded"
    session["graded_at"] = utc_now_iso()
    session["result"] = {
        "answers": answers,
        "correct": correct_count,
        "total": len(questions),
        "score": score,
    }
    write_json(session_path, session)

    lines: list[str] = []
    lines.append(f"SAP-C02 Check Result ({result_date})")
    lines.append(f"Session: {session['session_id']}")
    lines.append(f"Score: {score}/100 ({correct_count}/{len(questions)} correct)")
    lines.append(f"Confidence update ({domain_id}): {current_conf} -> {new_conf}")
    lines.append(f"Adaptive level: L{ensure_adaptive_state(profile)['level']} ({level_change})")
    lines.append("")
    lines.append("Question review:")
    for item in checks:
        status = "OK" if item["ok"] else "MISS"
        lines.append(
            f"- Q{item['q']}: {status} (you: {item['given']}, expected: {item['expected']}) | {item['explanation']}"
        )
    lines.append("")
    lines.append(
        "Next step: run daily-brief again for the next drill, or continue with the same domain using generate-session."
    )

    return "\n".join(lines), profile
