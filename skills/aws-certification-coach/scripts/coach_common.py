#!/usr/bin/env python3
"""Common helpers for AWS certification coach scripts."""

from __future__ import annotations

import json
import math
import re
from collections import defaultdict
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any


def skill_root() -> Path:
    return Path(__file__).resolve().parents[1]


BLUEPRINT_PATH = skill_root() / "references" / "domain-blueprint.json"
STATE_DIR = Path.home() / ".openclaw" / "state" / "aws-certification-coach"


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_date(raw: str) -> date:
    try:
        return datetime.strptime(raw, "%Y-%m-%d").date()
    except ValueError as exc:
        raise ValueError(f"Invalid date '{raw}'. Expected YYYY-MM-DD.") from exc


def slugify(value: str) -> str:
    normalized = value.strip().lower()
    normalized = re.sub(r"[^a-z0-9]+", "-", normalized)
    normalized = re.sub(r"-{2,}", "-", normalized).strip("-")
    return normalized or "learner"


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def load_blueprint() -> dict[str, Any]:
    blueprint = load_json(BLUEPRINT_PATH)
    if "exam" not in blueprint or "domains" not in blueprint:
        raise ValueError(f"Blueprint at {BLUEPRINT_PATH} is missing required keys.")
    return blueprint


def domain_lookup(blueprint: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {domain["id"]: domain for domain in blueprint["domains"]}


def default_profile_path(name: str) -> Path:
    return STATE_DIR / f"{slugify(name)}-profile.json"


def validate_domain_id(blueprint: dict[str, Any], domain_id: str) -> None:
    if domain_id not in domain_lookup(blueprint):
        allowed = ", ".join(domain_lookup(blueprint).keys())
        raise ValueError(f"Unknown domain '{domain_id}'. Allowed: {allowed}")


def parse_confidence_assignments(raw: str) -> dict[str, int]:
    parsed: dict[str, int] = {}
    if not raw:
        return parsed
    for item in raw.split(","):
        piece = item.strip()
        if not piece:
            continue
        if "=" not in piece:
            raise ValueError(f"Invalid confidence entry '{piece}'. Expected domain=value")
        domain_id, value = piece.split("=", 1)
        domain_id = domain_id.strip()
        try:
            confidence = int(value.strip())
        except ValueError as exc:
            raise ValueError(f"Confidence for {domain_id} must be an integer (1-5).") from exc
        if confidence < 1 or confidence > 5:
            raise ValueError(f"Confidence for {domain_id} must be between 1 and 5.")
        parsed[domain_id] = confidence
    return parsed


def parse_profile(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise ValueError(f"Profile not found: {path}")
    profile = load_json(path)
    required = {"learner_name", "exam_code", "target_exam_date", "weekly_hours", "confidence"}
    missing = sorted(required - set(profile.keys()))
    if missing:
        raise ValueError(f"Profile missing required fields: {', '.join(missing)}")
    return profile


def compute_recommended_weeks(target_exam_date: str, start_date: str) -> int:
    target = parse_date(target_exam_date)
    start = parse_date(start_date)
    delta_days = (target - start).days
    if delta_days <= 0:
        return 4
    return max(2, min(24, math.ceil(delta_days / 7)))


def domain_priorities(blueprint: dict[str, Any], confidence: dict[str, int]) -> dict[str, float]:
    priorities: dict[str, float] = {}
    for domain in blueprint["domains"]:
        domain_id = domain["id"]
        score = confidence.get(domain_id, 2)
        gap = max(1, 6 - score)
        priorities[domain_id] = float(domain["weight_pct"] * gap)
    return priorities


def proportional_counts(weights: dict[str, float], slots: int) -> dict[str, int]:
    if slots <= 0:
        return {key: 0 for key in weights}
    total = sum(weights.values())
    if total <= 0:
        per_domain = slots // max(1, len(weights))
        counts = {key: per_domain for key in weights}
        remainder = slots - sum(counts.values())
        for key in list(weights.keys())[:remainder]:
            counts[key] += 1
        return counts

    quotas = {key: (value / total) * slots for key, value in weights.items()}
    counts = {key: int(math.floor(value)) for key, value in quotas.items()}
    remainder = slots - sum(counts.values())

    ranked_remainders = sorted(
        ((key, quotas[key] - counts[key]) for key in quotas),
        key=lambda item: (-item[1], item[0]),
    )
    for key, _ in ranked_remainders[:remainder]:
        counts[key] += 1

    return counts


def spread_sequence(counts: dict[str, int]) -> list[str]:
    remaining = dict(counts)
    usage = defaultdict(int)
    last = None
    sequence: list[str] = []

    total_slots = sum(remaining.values())
    for _ in range(total_slots):
        ranked = sorted(remaining.keys(), key=lambda key: (-remaining[key], usage[key], key))
        pick = None
        for candidate in ranked:
            if remaining[candidate] <= 0:
                continue
            if candidate != last:
                pick = candidate
                break
        if pick is None:
            for candidate in ranked:
                if remaining[candidate] > 0:
                    pick = candidate
                    break
        if pick is None:
            break
        sequence.append(pick)
        remaining[pick] -= 1
        usage[pick] += 1
        last = pick

    return sequence


def allocate_hours(weekly_hours: float, priorities: dict[str, float]) -> dict[str, float]:
    total = sum(priorities.values())
    if total <= 0:
        return {domain_id: round(weekly_hours / max(1, len(priorities)), 1) for domain_id in priorities}
    return {domain_id: round((weekly_hours * value) / total, 1) for domain_id, value in priorities.items()}


def task_without_prefix(task: str) -> str:
    return re.sub(r"^Task\s+\d+\.\d+:\s*", "", task).rstrip(".")


def weakest_domain(blueprint: dict[str, Any], confidence: dict[str, int]) -> str:
    ranked = sorted(
        blueprint["domains"],
        key=lambda domain: (confidence.get(domain["id"], 2), -domain["weight_pct"], domain["id"]),
    )
    return ranked[0]["id"]
