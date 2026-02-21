#!/usr/bin/env python3
"""Deterministic coaching CLI for AWS certification prep."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Callable

from coach_adaptive import (
    build_adaptive_daily_session,
    grade_answers,
    render_adaptive_daily_message,
    save_session_for_profile,
    update_adaptive_level,
)
from coach_common import (
    STATE_DIR,
    compute_recommended_weeks,
    default_profile_path,
    load_blueprint,
    parse_confidence_assignments,
    parse_date,
    parse_profile,
    slugify,
    utc_now_iso,
    validate_domain_id,
    weakest_domain,
    write_json,
    write_text,
)
from coach_render import generate_plan_markdown, generate_session_markdown, progress_markdown


def cmd_init_profile(args: argparse.Namespace, blueprint: dict[str, Any]) -> int:
    output = Path(args.output) if args.output else default_profile_path(args.name)
    if output.exists() and not args.force:
        raise ValueError(f"Profile already exists: {output}. Use --force to overwrite.")

    target_date = args.target_date or (date.today() + timedelta(days=84)).isoformat()

    profile = {
        "learner_name": args.name,
        "exam_code": blueprint["exam"]["code"],
        "target_exam_date": target_date,
        "weekly_hours": float(args.weekly_hours),
        "confidence": {domain["id"]: int(args.confidence) for domain in blueprint["domains"]},
        "focus_areas": [],
        "history": [],
        "created_at": utc_now_iso(),
        "updated_at": utc_now_iso(),
    }

    write_json(output, profile)
    print(f"Created profile: {output}")
    return 0


def cmd_update_profile(args: argparse.Namespace, blueprint: dict[str, Any]) -> int:
    profile_path = Path(args.profile)
    profile = parse_profile(profile_path)

    if args.exam_code:
        profile["exam_code"] = args.exam_code
    if args.target_date:
        parse_date(args.target_date)
        profile["target_exam_date"] = args.target_date
    if args.weekly_hours is not None:
        if args.weekly_hours <= 0:
            raise ValueError("weekly-hours must be greater than 0.")
        profile["weekly_hours"] = float(args.weekly_hours)

    confidence_updates = parse_confidence_assignments(args.set_confidence)
    for domain_id, value in confidence_updates.items():
        validate_domain_id(blueprint, domain_id)
        profile["confidence"][domain_id] = value

    focus_areas = list(profile.get("focus_areas", []))
    for item in args.add_focus:
        if item not in focus_areas:
            focus_areas.append(item)
    for item in args.remove_focus:
        focus_areas = [existing for existing in focus_areas if existing != item]
    profile["focus_areas"] = focus_areas

    profile["updated_at"] = utc_now_iso()

    output = Path(args.output) if args.output else profile_path
    write_json(output, profile)
    print(f"Updated profile: {output}")
    return 0


def cmd_generate_plan(args: argparse.Namespace, blueprint: dict[str, Any]) -> int:
    profile = parse_profile(Path(args.profile))
    start_date = args.start_date or date.today().isoformat()
    parse_date(start_date)

    weeks = args.weeks
    if weeks is None:
        weeks = compute_recommended_weeks(profile["target_exam_date"], start_date)
    if weeks <= 0:
        raise ValueError("weeks must be greater than 0.")

    content = generate_plan_markdown(profile, blueprint, int(weeks), start_date)

    default_output = STATE_DIR / f"{slugify(profile['learner_name'])}-study-plan.md"
    output = Path(args.output) if args.output else default_output
    write_text(output, content)
    print(f"Generated study plan: {output}")
    return 0


def cmd_generate_session(args: argparse.Namespace, blueprint: dict[str, Any]) -> int:
    profile = parse_profile(Path(args.profile))
    confidence = {key: int(value) for key, value in profile.get("confidence", {}).items()}
    domain_id = args.domain or weakest_domain(blueprint, confidence)
    validate_domain_id(blueprint, domain_id)

    if args.minutes < 30:
        raise ValueError("minutes must be at least 30.")

    content = generate_session_markdown(profile, blueprint, domain_id, args.minutes, args.seed)

    default_output = STATE_DIR / f"{slugify(profile['learner_name'])}-session-{date.today().strftime('%Y%m%d')}.md"
    output = Path(args.output) if args.output else default_output
    write_text(output, content)
    print(f"Generated session pack: {output}")
    return 0


def cmd_log_session(args: argparse.Namespace, blueprint: dict[str, Any]) -> int:
    profile_path = Path(args.profile)
    profile = parse_profile(profile_path)
    validate_domain_id(blueprint, args.domain)

    score = int(args.score)
    if score < 0 or score > 100:
        raise ValueError("score must be between 0 and 100.")

    session_date = args.date or date.today().isoformat()
    parse_date(session_date)

    entry = {
        "date": session_date,
        "domain": args.domain,
        "score": score,
        "notes": args.notes,
        "logged_at": utc_now_iso(),
    }
    history = profile.get("history", [])
    history.append(entry)
    profile["history"] = history

    current_conf = int(profile.get("confidence", {}).get(args.domain, 2))
    delta = 0
    if score >= 85:
        delta = 1
    elif score < 60:
        delta = -1
    profile["confidence"][args.domain] = max(1, min(5, current_conf + delta))
    level_change = update_adaptive_level(profile, score)

    profile["updated_at"] = utc_now_iso()

    output = Path(args.output) if args.output else profile_path
    write_json(output, profile)
    print(f"Logged session to profile: {output}")
    print(f"Domain {args.domain} confidence: {current_conf} -> {profile['confidence'][args.domain]}")
    adaptive = profile.get("adaptive", {})
    if adaptive:
        print(f"Adaptive level: L{adaptive.get('level', 1)} ({level_change})")
    return 0


def cmd_progress_report(args: argparse.Namespace, blueprint: dict[str, Any]) -> int:
    profile = parse_profile(Path(args.profile))
    content = progress_markdown(profile, blueprint)
    default_output = STATE_DIR / f"{slugify(profile['learner_name'])}-progress.md"
    output = Path(args.output) if args.output else default_output
    write_text(output, content)
    print(f"Generated progress report: {output}")
    return 0


def cmd_list_profiles(args: argparse.Namespace, blueprint: dict[str, Any]) -> int:
    del blueprint
    profile_paths = sorted(STATE_DIR.glob("*-profile.json"))

    profiles: list[dict[str, str]] = []
    errors: list[dict[str, str]] = []

    for profile_path in profile_paths:
        try:
            profile = parse_profile(profile_path)
        except ValueError as exc:
            errors.append({"path": str(profile_path), "error": str(exc)})
            continue

        profiles.append(
            {
                "path": str(profile_path),
                "learner_name": str(profile.get("learner_name", "")),
                "exam_code": str(profile.get("exam_code", "")),
                "target_exam_date": str(profile.get("target_exam_date", "")),
                "updated_at": str(profile.get("updated_at", "")),
            }
        )

    if args.format == "json":
        print(
            json.dumps(
                {
                    "state_dir": str(STATE_DIR),
                    "profiles": profiles,
                    "errors": errors,
                },
                indent=2,
            )
        )
        return 0

    if not profiles and not errors:
        print(f"No profiles found in {STATE_DIR}")
        return 0

    if profiles:
        print(f"Profiles in {STATE_DIR}:")
        for item in profiles:
            print(
                f"- {item['path']} | learner={item['learner_name']} | "
                f"exam={item['exam_code']} | target={item['target_exam_date']} | "
                f"updated={item['updated_at']}"
            )

    if errors:
        print("Profile parse errors:")
        for error in errors:
            print(f"- {error['path']} | {error['error']}")

    return 0


def cmd_daily_brief(args: argparse.Namespace, blueprint: dict[str, Any]) -> int:
    profile_path = Path(args.profile)
    profile = parse_profile(profile_path)
    today = args.date or date.today().isoformat()
    parse_date(today)
    session = build_adaptive_daily_session(profile, blueprint, today, str(profile_path))
    save_session_for_profile(profile, session)
    profile["updated_at"] = utc_now_iso()
    write_json(profile_path, profile)
    text = render_adaptive_daily_message(session, str(profile_path))

    if args.output:
        output = Path(args.output)
        write_text(output, text + "\n")
        print(f"Wrote daily brief: {output}")
        return 0

    print(text)
    return 0


def cmd_check_answers(args: argparse.Namespace, blueprint: dict[str, Any]) -> int:
    del blueprint
    profile_path = Path(args.profile)
    profile = parse_profile(profile_path)

    result_date = args.date or date.today().isoformat()
    parse_date(result_date)

    report, updated_profile = grade_answers(profile, args.session_id, args.answers, result_date)
    write_json(profile_path, updated_profile)

    if args.output:
        output = Path(args.output)
        write_text(output, report + "\n")
        print(f"Wrote answer check report: {output}")
        return 0

    print(report)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="AWS certification coaching helper")
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_profile = subparsers.add_parser("init-profile", help="Create a learner profile")
    init_profile.add_argument("--name", required=True, help="Learner name")
    init_profile.add_argument("--target-date", help="Target exam date (YYYY-MM-DD)")
    init_profile.add_argument("--weekly-hours", type=float, default=8.0, help="Study hours per week")
    init_profile.add_argument(
        "--confidence",
        type=int,
        default=2,
        choices=[1, 2, 3, 4, 5],
        help="Initial confidence level for all domains (1-5)",
    )
    init_profile.add_argument("--output", help="Output profile path")
    init_profile.add_argument("--force", action="store_true", help="Overwrite if profile exists")

    update_profile = subparsers.add_parser("update-profile", help="Update a learner profile")
    update_profile.add_argument("--profile", required=True, help="Profile JSON path")
    update_profile.add_argument("--exam-code", help="Override exam code")
    update_profile.add_argument("--target-date", help="Target exam date (YYYY-MM-DD)")
    update_profile.add_argument("--weekly-hours", type=float, help="Study hours per week")
    update_profile.add_argument(
        "--set-confidence",
        default="",
        help="Comma-separated domain confidence updates. Example: domain-1=3,domain-2=2",
    )
    update_profile.add_argument("--add-focus", action="append", default=[], help="Add focus area")
    update_profile.add_argument("--remove-focus", action="append", default=[], help="Remove focus area")
    update_profile.add_argument("--output", help="Output profile path")

    generate_plan = subparsers.add_parser("generate-plan", help="Generate a study plan")
    generate_plan.add_argument("--profile", required=True, help="Profile JSON path")
    generate_plan.add_argument("--weeks", type=int, help="Number of weeks for the plan")
    generate_plan.add_argument("--start-date", help="Plan start date YYYY-MM-DD")
    generate_plan.add_argument("--output", help="Plan markdown output path")

    generate_session = subparsers.add_parser("generate-session", help="Generate a coaching session")
    generate_session.add_argument("--profile", required=True, help="Profile JSON path")
    generate_session.add_argument("--domain", help="Domain id, e.g. domain-2")
    generate_session.add_argument("--minutes", type=int, default=90, help="Session duration")
    generate_session.add_argument("--seed", type=int, help="Optional random seed")
    generate_session.add_argument("--output", help="Session markdown output path")

    log_session = subparsers.add_parser("log-session", help="Log a session result")
    log_session.add_argument("--profile", required=True, help="Profile JSON path")
    log_session.add_argument("--domain", required=True, help="Domain id")
    log_session.add_argument("--score", type=int, required=True, help="Session score (0-100)")
    log_session.add_argument("--notes", default="", help="Session notes")
    log_session.add_argument("--date", help="Session date YYYY-MM-DD")
    log_session.add_argument("--output", help="Output profile path")

    progress_report = subparsers.add_parser("progress-report", help="Generate readiness report")
    progress_report.add_argument("--profile", required=True, help="Profile JSON path")
    progress_report.add_argument("--output", help="Report markdown output path")

    list_profiles = subparsers.add_parser("list-profiles", help="List learner profiles in state storage")
    list_profiles.add_argument("--format", choices=["text", "json"], default="text", help="Output format")

    daily_brief = subparsers.add_parser("daily-brief", help="Generate adaptive daily coaching drill")
    daily_brief.add_argument("--profile", required=True, help="Profile JSON path")
    daily_brief.add_argument("--date", help="Date YYYY-MM-DD (defaults to today)")
    daily_brief.add_argument("--output", help="Optional output text file path")

    check_answers = subparsers.add_parser("check-answers", help="Grade adaptive daily quiz answers")
    check_answers.add_argument("--profile", required=True, help="Profile JSON path")
    check_answers.add_argument("--session-id", help="Session id (defaults to last generated session)")
    check_answers.add_argument(
        "--answers",
        required=True,
        help="Answers in order (e.g. A,B,C or 1A 2B 3C)",
    )
    check_answers.add_argument("--date", help="Result date YYYY-MM-DD")
    check_answers.add_argument("--output", help="Optional output text file path")

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    blueprint = load_blueprint()

    handlers: dict[str, Callable[[argparse.Namespace, dict[str, Any]], int]] = {
        "init-profile": cmd_init_profile,
        "update-profile": cmd_update_profile,
        "generate-plan": cmd_generate_plan,
        "generate-session": cmd_generate_session,
        "log-session": cmd_log_session,
        "progress-report": cmd_progress_report,
        "list-profiles": cmd_list_profiles,
        "daily-brief": cmd_daily_brief,
        "check-answers": cmd_check_answers,
    }

    return handlers[args.command](args, blueprint)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(1)
