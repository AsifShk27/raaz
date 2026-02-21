#!/usr/bin/python3
"""Service naming and detection helpers."""

from typing import List

from .constants import FLINK_JOB_NAMES, NAMESPACE_MAP


def get_namespace(chart: str) -> str:
    return NAMESPACE_MAP.get(chart, "default")


def service_name_variants(service: str) -> List[str]:
    variants: List[str] = []
    seen = set()

    def add(value: str) -> None:
        if not value:
            return
        cleaned = value.strip()
        if not cleaned or cleaned in seen:
            return
        seen.add(cleaned)
        variants.append(cleaned)

    add(service)
    add(service.replace("_", "-"))
    add(service.replace("-", "_"))

    for existing in list(variants):
        if "/" in existing:
            tail = existing.split("/")[-1]
            add(tail)
            add(tail.replace("_", "-"))
            add(tail.replace("-", "_"))

    for existing in list(variants):
        if existing.startswith("trading-platform-"):
            stripped = existing[len("trading-platform-") :]
            add(stripped)
            add(stripped.replace("_", "-"))
            add(stripped.replace("-", "_"))

    return variants


def canonical_lock_service_name(service: str) -> str:
    variants = service_name_variants(service)
    for candidate in variants:
        if "/" not in candidate and not candidate.startswith("trading-platform-"):
            return candidate
    return variants[0] if variants else service


def normalize_flink_job_name(service: str) -> str:
    for candidate in service_name_variants(service):
        name = candidate
        for suffix in ("-java", "-datastream", "-python", "-sql"):
            if name.endswith(suffix):
                name = name[: -len(suffix)]
                break
        if "-flink-" in name:
            name = name.replace("-flink", "")
        if name:
            return name
    return service


def is_flink_job(service: str) -> bool:
    for candidate in service_name_variants(service):
        if (
            candidate.endswith("-java")
            or candidate.endswith("-datastream")
            or candidate.endswith("-python")
            or candidate.endswith("-sql")
            or candidate in FLINK_JOB_NAMES
        ):
            return True
    return False
