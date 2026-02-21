#!/usr/bin/env python3
"""Daily micro-lesson rendering for SAP-C02 WhatsApp coaching."""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any

from coach_common import domain_priorities, task_without_prefix

TASK_COACHING_KITS = [
    {
        "keywords": ["network connectivity", "multi-account"],
        "learn": [
            "Separate north-south and east-west traffic decisions before selecting services.",
            "Choose Transit Gateway for many-to-many connectivity; keep route ownership explicit.",
            "Use Direct Connect/VPN failover design with tested failback runbooks.",
        ],
        "scenario": (
            "You are connecting 12 AWS accounts and one on-prem data center. "
            "Design two connectivity options and include route control, blast radius, and ops overhead."
        ),
        "checklist": [
            "Target-state topology with account boundaries",
            "Route propagation and segmentation plan",
            "Failure simulation plan (DX down, region issue)",
        ],
        "questions": [
            (
                "When does Transit Gateway beat VPC peering for scale?",
                "When connection count and route management complexity grow across many VPCs/accounts.",
            ),
            (
                "What is the first risk if route ownership is unclear?",
                "Unintended transitive access and hard-to-debug reachability outages.",
            ),
            (
                "What validates the design beyond diagrams?",
                "A tested failover/failback procedure with measured recovery time.",
            ),
        ],
    },
    {
        "keywords": ["security controls", "security"],
        "learn": [
            "Map controls to identity, network, data, and detective layers.",
            "Prefer preventive guardrails (SCP, IAM boundaries) before detective-only controls.",
            "Design evidence collection at the same time as controls (CloudTrail, Config, Security Hub).",
        ],
        "scenario": (
            "A regulated workload is moving to AWS. Build two control strategies and justify "
            "which one scales better for 30+ accounts."
        ),
        "checklist": [
            "Least-privilege identity model",
            "Encryption and key ownership model",
            "Continuous compliance and evidence flow",
        ],
        "questions": [
            (
                "Why are detective controls alone insufficient?",
                "They find violations after exposure; preventive controls reduce blast radius upfront.",
            ),
            (
                "Where should baseline restrictions live in multi-account orgs?",
                "At org level with SCPs plus account-level IAM for least privilege execution.",
            ),
            (
                "What makes audit sign-off faster?",
                "Automated, centralized evidence from logs/config/compliance services.",
            ),
        ],
    },
    {
        "keywords": ["business continuity", "reliability", "resilient"],
        "learn": [
            "Define RTO/RPO first; architecture follows those numbers.",
            "Design recovery patterns per tier: stateless compute, stateful data, control plane.",
            "Run game days; reliability claims without drills are assumptions.",
        ],
        "scenario": (
            "A payments API needs RTO 15m and RPO 5m. Compare two continuity designs "
            "and defend the operational cost of each."
        ),
        "checklist": [
            "RTO/RPO mapped to each component",
            "Failover decision automation and manual override",
            "Drill schedule with pass/fail criteria",
        ],
        "questions": [
            ("What drives region vs AZ strategy?", "Business RTO/RPO and fault-domain tolerance."),
            (
                "Why include manual override in failover?",
                "To handle false positives and prevent cascading mistakes.",
            ),
            (
                "What proves continuity readiness?",
                "Observed recovery metrics from regular failover exercises.",
            ),
        ],
    },
    {
        "keywords": ["performance"],
        "learn": [
            "Find bottlenecks before scaling; do not optimize blind.",
            "Use right caching layer and data access pattern before adding compute.",
            "Performance fixes must preserve security and reliability constraints.",
        ],
        "scenario": (
            "A global API has p95 latency spikes during business peaks. "
            "Propose two improvement paths and quantify trade-offs."
        ),
        "checklist": [
            "Baseline metrics and bottleneck hypothesis",
            "Two options with cost/perf/reliability comparison",
            "Rollback and canary plan",
        ],
        "questions": [
            ("What is the first performance mistake?", "Scaling before isolating the bottleneck."),
            (
                "Which metric should drive decision quality?",
                "User-impact latency/error metrics, not instance utilization alone.",
            ),
            ("Why is rollback mandatory?", "Performance changes can regress correctness or stability."),
        ],
    },
    {
        "keywords": ["cost optimization", "cost"],
        "learn": [
            "Treat cost optimization as design-time and runtime practice.",
            "Right-size using observed load; pair with autoscaling and savings plans where fit.",
            "Always evaluate cost against SLO impact, not in isolation.",
        ],
        "scenario": (
            "Leadership wants 25% cloud cost reduction with no reliability loss. "
            "Present two strategies and decision criteria."
        ),
        "checklist": [
            "Cost drivers ranked by impact",
            "Optimization moves with risk assessment",
            "Guardrails to prevent cost regressions",
        ],
        "questions": [
            ("What usually saves fastest?", "Idle/oversized resources and storage lifecycle cleanup."),
            (
                "What can make cost optimization fail?",
                "Ignoring workload variability and SLO constraints.",
            ),
            ("How do you keep savings durable?", "Budgets, anomaly alerts, and recurring optimization reviews."),
        ],
    },
    {
        "keywords": ["migration", "modernization", "deployment strategy", "new architecture"],
        "learn": [
            "Pick migration strategy per workload criticality, coupling, and business timeline.",
            "Modernization succeeds when you reduce operational risk, not just rewrite tech.",
            "Plan cutover/rollback before touching production traffic.",
        ],
        "scenario": (
            "A legacy monolith with strict change windows must move in 6 months. "
            "Compare two migration/modernization paths and recommend one."
        ),
        "checklist": [
            "Wave plan by business risk",
            "Cutover criteria and rollback triggers",
            "Post-migration performance and reliability checks",
        ],
        "questions": [
            ("What is the common migration anti-pattern?", "Big-bang moves without reversible milestones."),
            ("Why modernize selectively?", "Different components have different ROI and risk profiles."),
            ("What marks a good cutover plan?", "Clear go/no-go gates with tested rollback."),
        ],
    },
]

DEFAULT_COACHING_KIT = {
    "learn": [
        "State business and technical constraints before choosing services.",
        "Generate two architecture options and compare trade-offs explicitly.",
        "Validate with measurable outcomes, not assumptions.",
    ],
    "scenario": (
        "Build two architecture options for the target task, then pick one and defend the decision "
        "using cost, reliability, security, and performance trade-offs."
    ),
    "checklist": [
        "Decision table with trade-offs",
        "Failure mode and mitigation plan",
        "Measurement plan for success criteria",
    ],
    "questions": [
        ("What makes an answer strong in SAP-C02?", "Clear trade-offs tied to stated requirements."),
        ("What weakens an architecture choice?", "Service-first decisions without requirement mapping."),
        ("How do you close learning loop daily?", "Log mistakes and convert them into next-session targets."),
    ],
}


def _task_coaching_kit(task: str) -> dict[str, Any]:
    task_lower = task.lower()
    for kit in TASK_COACHING_KITS:
        if any(keyword in task_lower for keyword in kit["keywords"]):
            return kit
    return DEFAULT_COACHING_KIT


def _daily_phase(utc_hour: int) -> str:
    return "AM build sprint" if utc_hour < 12 else "PM defense sprint"


def _score_target(history: list[dict[str, Any]], domain_id: str) -> tuple[int, str]:
    recent = [entry for entry in history if entry.get("domain") == domain_id][-3:]
    if not recent:
        return (80, "no prior attempts logged")
    avg = sum(int(entry.get("score", 0)) for entry in recent) / len(recent)
    if avg < 70:
        return (75, f"last {len(recent)} attempts avg {avg:.1f}")
    if avg < 85:
        return (85, f"last {len(recent)} attempts avg {avg:.1f}")
    return (90, f"last {len(recent)} attempts avg {avg:.1f}")


def daily_brief_text(
    profile: dict[str, Any],
    blueprint: dict[str, Any],
    today_iso: str,
    profile_path: str | None = None,
) -> str:
    """Create a WhatsApp-ready daily SAP-C02 micro-lesson with practice and self-check."""
    today = date.fromisoformat(today_iso)
    confidence = {key: int(value) for key, value in profile.get("confidence", {}).items()}
    priorities = domain_priorities(blueprint, confidence)
    ranked = sorted(blueprint["domains"], key=lambda domain: (-priorities[domain["id"]], domain["id"]))

    now_utc = datetime.now(timezone.utc)
    phase = _daily_phase(now_utc.hour)
    cycle = today.toordinal() + (0 if now_utc.hour < 12 else 1)

    domain = ranked[cycle % len(ranked)]
    domain_id = domain["id"]
    tasks = domain["tasks"]
    task = tasks[cycle % len(tasks)]
    kit = _task_coaching_kit(task)

    minutes = max(30, min(75, int(float(profile.get("weekly_hours", 8)) * 7)))
    learn_minutes = max(10, int(minutes * 0.2))
    drill_minutes = max(15, int(minutes * 0.5))
    check_minutes = max(10, minutes - learn_minutes - drill_minutes)

    target_score, target_context = _score_target(profile.get("history", []), domain_id)
    log_command = (
        "python3 /home/shkas/projects/raaz/skills/aws-certification-coach/scripts/coach.py "
        f"log-session --profile {profile_path} --domain {domain_id} --score <0-100> --notes "
        "\"<biggest mistake + fix>\""
        if profile_path
        else "python3 coach.py log-session --profile <profile.json> --domain <domain-id> "
        "--score <0-100> --notes \"<mistake + fix>\""
    )

    lines: list[str] = []
    lines.append(f"SAP-C02 Coaching Session ({today_iso} | {phase})")
    lines.append("")
    lines.append(f"*Focus:* {domain['title']}")
    lines.append(f"*Task Anchor:* {task_without_prefix(task)}")
    lines.append(f"*Target Score:* {target_score}/100 ({target_context})")
    lines.append("")
    lines.append("How to learn from this message:")
    lines.append("1) Read Learn bullets and say each one in your own words.")
    lines.append("2) Solve Scenario and write a 5-line decision memo.")
    lines.append("3) Do Self-Check without notes, then compare against answer key.")
    lines.append("")
    lines.append(f"Learn ({learn_minutes}m):")
    for point in kit["learn"][:3]:
        lines.append(f"- {point}")
    lines.append("")
    lines.append(f"Scenario Drill ({drill_minutes}m):")
    lines.append(kit["scenario"])
    lines.append("Deliverable checklist:")
    for item in kit["checklist"][:3]:
        lines.append(f"- {item}")
    lines.append("")
    lines.append(f"Self-Check ({check_minutes}m):")
    for index, question in enumerate(kit["questions"], start=1):
        lines.append(f"Q{index}) {question[0]}")
    lines.append("Answer key:")
    for index, question in enumerate(kit["questions"], start=1):
        lines.append(f"A{index}) {question[1]}")
    lines.append("")
    lines.append("Log your evidence (3m):")
    lines.append("- Score yourself 0-100.")
    lines.append("- Note biggest mistake and one concrete fix.")
    lines.append(f"- Command: {log_command}")
    lines.append("")
    lines.append("If score < target, repeat the same task tomorrow with a new scenario variant.")
    return "\n".join(lines)
