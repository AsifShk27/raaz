#!/usr/bin/env python3
"""Rendering helpers for study plans, sessions, and progress reports."""

from __future__ import annotations

import random
from datetime import datetime, timezone
from typing import Any

from coach_daily import daily_brief_text
from coach_common import (
    allocate_hours,
    domain_lookup,
    domain_priorities,
    proportional_counts,
    spread_sequence,
    task_without_prefix,
    utc_now_iso,
    weakest_domain,
)


def generate_plan_markdown(
    profile: dict[str, Any], blueprint: dict[str, Any], weeks: int, start_date: str
) -> str:
    confidence: dict[str, int] = {key: int(value) for key, value in profile["confidence"].items()}
    priorities = domain_priorities(blueprint, confidence)
    hours = allocate_hours(float(profile["weekly_hours"]), priorities)

    primary_counts = proportional_counts(priorities, weeks)
    secondary_counts = proportional_counts(priorities, weeks)
    primary_sequence = spread_sequence(primary_counts)
    secondary_sequence = spread_sequence(secondary_counts)

    domains = domain_lookup(blueprint)
    ranked_domain_ids = [
        domain["id"] for domain in sorted(blueprint["domains"], key=lambda d: (-priorities[d["id"]], d["id"]))
    ]

    weekly_rows: list[tuple[int, str, str]] = []
    for index in range(weeks):
        primary = (
            primary_sequence[index]
            if index < len(primary_sequence)
            else weakest_domain(blueprint, confidence)
        )
        secondary = secondary_sequence[index] if index < len(secondary_sequence) else primary
        if secondary == primary:
            for candidate in ranked_domain_ids:
                if candidate != primary:
                    secondary = candidate
                    break
        weekly_rows.append((index + 1, primary, secondary))

    lines: list[str] = []
    lines.append(f"# Study Plan - {profile['learner_name']} ({profile['exam_code']})")
    lines.append("")
    lines.append(f"Generated (UTC): {utc_now_iso()}")
    lines.append(f"Start date: {start_date}")
    lines.append(f"Target exam date: {profile['target_exam_date']}")
    lines.append(f"Weekly hours: {profile['weekly_hours']}")
    lines.append(f"Plan length: {weeks} weeks")
    lines.append("")
    lines.append("## Official Exam Snapshot")
    lines.append("")
    lines.append(f"- Exam: {blueprint['exam']['name']} ({blueprint['exam']['code']})")
    lines.append(f"- Duration: {blueprint['exam']['duration_minutes']} minutes")
    lines.append(f"- Total questions: {blueprint['exam']['total_questions']}")
    lines.append(
        f"- Scored vs unscored: {blueprint['exam']['scored_questions']} scored + {blueprint['exam']['unscored_questions']} unscored"
    )
    lines.append(f"- Passing score: scaled {blueprint['exam']['passing_scaled_score']}")
    lines.append("")
    lines.append("## Domain Allocation")
    lines.append("")
    lines.append("| Domain | Weight | Confidence (1-5) | Priority | Hours/Week |")
    lines.append("|---|---:|---:|---:|---:|")

    ranked_domains = sorted(blueprint["domains"], key=lambda d: (-priorities[d["id"]], d["id"]))
    for domain in ranked_domains:
        domain_id = domain["id"]
        lines.append(
            "| "
            + f"{domain['title']} ({domain_id})"
            + f" | {domain['weight_pct']}%"
            + f" | {confidence.get(domain_id, 2)}"
            + f" | {priorities[domain_id]:.1f}"
            + f" | {hours[domain_id]:.1f}h"
            + " |"
        )

    lines.append("")
    lines.append("## Weekly Focus Schedule")
    lines.append("")
    lines.append("| Week | Primary Focus | Secondary Focus | Suggested Hours Split | Core Objective |")
    lines.append("|---:|---|---|---|---|")

    for week, primary, secondary in weekly_rows:
        primary_domain = domains[primary]
        secondary_domain = domains[secondary]
        objective = task_without_prefix(primary_domain["tasks"][(week - 1) % len(primary_domain["tasks"])])
        split = f"{hours[primary]:.1f}h + {max(1.0, round(hours[secondary] * 0.6, 1)):.1f}h"
        lines.append(
            f"| {week} | {primary_domain['title']} | {secondary_domain['title']} | {split} | {objective} |"
        )

    lines.append("")
    lines.append("## Weekly Rhythm")
    lines.append("")
    lines.append("- 20%: concept refresh and service comparison notes")
    lines.append("- 40%: architecture scenarios and trade-off drills")
    lines.append("- 25%: timed question practice and error-log updates")
    lines.append("- 15%: recap, weak-area rework, and next-week planning")

    focus_areas = profile.get("focus_areas", [])
    if focus_areas:
        lines.append("")
        lines.append("## Learner Focus Areas")
        lines.append("")
        for item in focus_areas:
            lines.append(f"- {item}")

    lines.append("")
    lines.append("## Domain Drill Bank")
    lines.append("")
    for domain in blueprint["domains"]:
        lines.append(f"### {domain['title']} ({domain['id']})")
        for task in domain["tasks"]:
            lines.append(f"- {task}")
        lines.append("")

    lines.append("## Evidence Log Template")
    lines.append("")
    lines.append("- Date:")
    lines.append("- Domain:")
    lines.append("- Scenario practiced:")
    lines.append("- Mistakes found:")
    lines.append("- Services to revisit:")
    lines.append("- Next action:")

    return "\n".join(lines).rstrip() + "\n"


def generate_session_markdown(
    profile: dict[str, Any],
    blueprint: dict[str, Any],
    domain_id: str,
    minutes: int,
    seed: int | None,
) -> str:
    domains = domain_lookup(blueprint)
    domain = domains[domain_id]
    rng = random.Random(seed if seed is not None else int(datetime.now(timezone.utc).timestamp()))

    tasks = domain["tasks"]
    task_samples = [tasks[i % len(tasks)] for i in range(3)]

    blocks = [
        ("Warm-up recall", max(10, int(minutes * 0.15))),
        ("Scenario architecture", max(20, int(minutes * 0.35))),
        ("Trade-off defense", max(20, int(minutes * 0.30))),
    ]
    consumed = sum(value for _, value in blocks)
    blocks.append(("Review and error-log", max(10, minutes - consumed)))

    workloads = [
        "multi-account enterprise landing zone",
        "global ecommerce platform",
        "regulated payments architecture",
        "media streaming platform",
        "hybrid data processing platform",
    ]
    constraints = [
        "strict RTO/RPO requirements",
        "aggressive cost reduction target",
        "zero-trust security baseline",
        "regional data residency constraints",
        "high-throughput burst traffic",
    ]
    upgrades = [
        "migration with minimal downtime",
        "modernization from monolith to event-driven design",
        "organization-wide governance and guardrails",
        "performance bottleneck remediation",
        "observability and reliability hardening",
    ]

    scenarios: list[str] = []
    for task in task_samples:
        scenarios.append(
            "Design a "
            + rng.choice(workloads)
            + " focusing on "
            + task_without_prefix(task)
            + "; account for "
            + rng.choice(constraints)
            + " and "
            + rng.choice(upgrades)
            + "."
        )

    flash_prompts = [
        "What trade-off would make you reject your first design option?",
        "Which two AWS services are strongest candidates and why?",
        "What is the failure mode you would test first?",
        "Which metric proves the design objective was met?",
        "How would you reduce cost without violating reliability goals?",
        "Which control enforces least privilege in this design?",
    ]

    confidence = int(profile.get("confidence", {}).get(domain_id, 2))

    lines: list[str] = []
    lines.append(f"# Session Pack - {profile['learner_name']} - {profile['exam_code']}")
    lines.append("")
    lines.append(f"Generated (UTC): {utc_now_iso()}")
    lines.append(f"Domain: {domain['title']} ({domain_id})")
    lines.append(f"Duration: {minutes} minutes")
    lines.append(f"Current self-confidence (1-5): {confidence}")
    lines.append("")
    lines.append("## Session Objectives")
    lines.append("")
    for task in task_samples:
        lines.append(f"- {task}")

    lines.append("")
    lines.append("## Agenda")
    lines.append("")
    for label, block_minutes in blocks:
        lines.append(f"- {label}: {block_minutes} minutes")

    lines.append("")
    lines.append("## Scenario Drills")
    lines.append("")
    for idx, scenario in enumerate(scenarios, start=1):
        lines.append(f"{idx}. {scenario}")

    lines.append("")
    lines.append("## Flash Defense Questions")
    lines.append("")
    for idx in range(8):
        task = task_without_prefix(tasks[idx % len(tasks)])
        prompt = flash_prompts[idx % len(flash_prompts)]
        lines.append(f"{idx + 1}. For '{task}', {prompt}")

    lines.append("")
    lines.append("## Session Debrief Template")
    lines.append("")
    lines.append("- Score (0-100):")
    lines.append("- Best decision made:")
    lines.append("- Biggest mistake:")
    lines.append("- Service to revisit:")
    lines.append("- Follow-up action for next session:")

    return "\n".join(lines).rstrip() + "\n"


def progress_markdown(profile: dict[str, Any], blueprint: dict[str, Any]) -> str:
    history = profile.get("history", [])
    confidence = {key: int(value) for key, value in profile.get("confidence", {}).items()}
    domains = blueprint["domains"]

    grouped: dict[str, list[dict[str, Any]]] = {domain["id"]: [] for domain in domains}
    for entry in history:
        domain_id = entry.get("domain")
        if domain_id in grouped:
            grouped[domain_id].append(entry)

    weighted_scores = []
    for domain in domains:
        domain_id = domain["id"]
        entries = grouped[domain_id]
        if entries:
            avg = sum(item["score"] for item in entries) / len(entries)
        else:
            avg = 60.0
        weighted_scores.append((avg, domain["weight_pct"], domain_id))

    overall = sum(avg * weight for avg, weight, _ in weighted_scores) / 100.0

    priority_rank = []
    for domain in domains:
        domain_id = domain["id"]
        entries = grouped[domain_id]
        avg = sum(item["score"] for item in entries) / len(entries) if entries else 60.0
        conf = confidence.get(domain_id, 2)
        priority = domain["weight_pct"] * (100 - avg) * max(1, 6 - conf)
        priority_rank.append((priority, domain_id, avg, conf))
    priority_rank.sort(reverse=True)

    lines: list[str] = []
    lines.append(f"# Progress Report - {profile['learner_name']} ({profile['exam_code']})")
    lines.append("")
    lines.append(f"Generated (UTC): {utc_now_iso()}")
    lines.append(f"Target exam date: {profile['target_exam_date']}")
    lines.append(f"Overall readiness score (weighted): {overall:.1f}/100")
    lines.append("")
    lines.append("## Domain Summary")
    lines.append("")
    lines.append("| Domain | Attempts | Avg Score | Latest Score | Confidence (1-5) |")
    lines.append("|---|---:|---:|---:|---:|")
    for domain in domains:
        domain_id = domain["id"]
        entries = grouped[domain_id]
        attempts = len(entries)
        avg = sum(item["score"] for item in entries) / attempts if attempts else None
        latest = entries[-1]["score"] if attempts else None
        conf = confidence.get(domain_id, 2)
        lines.append(
            f"| {domain['title']} ({domain_id}) | {attempts} | "
            + (f"{avg:.1f}" if avg is not None else "N/A")
            + " | "
            + (str(latest) if latest is not None else "N/A")
            + f" | {conf} |"
        )

    lines.append("")
    lines.append("## Highest-Priority Improvement Domains")
    lines.append("")
    for rank, item in enumerate(priority_rank[:3], start=1):
        _, domain_id, avg, conf = item
        domain_title = next(domain["title"] for domain in domains if domain["id"] == domain_id)
        lines.append(
            f"{rank}. {domain_title} ({domain_id}) - avg {avg:.1f}, confidence {conf}, next action: run a focused session"
        )

    lines.append("")
    lines.append("## Recommendation")
    lines.append("")
    if overall >= 85:
        lines.append("- Shift to timed mocks and post-mock error-log refinement.")
    elif overall >= 70:
        lines.append("- Continue domain drills; add one timed mixed-domain block each week.")
    else:
        lines.append("- Increase guided architecture drills in top-priority domains before full mocks.")

    return "\n".join(lines).rstrip() + "\n"
