#!/usr/bin/python3
"""Service metadata and Helm values mutation logic for tpdeploy."""

import json
import shutil
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from .command_runtime import deep_merge_dict, run_command, write_yaml_atomic
from .constants import (
    DEFAULT_CHART,
    INSTALLER_POWERSHELL_POSIX_PATH,
    INSTALLER_POWERSHELL_WINDOWS_PATH,
    REGISTRY,
    TRADING_PLATFORM_ROOT,
    VALUES_FILE_LOCK,
)
from .naming import is_flink_job, normalize_flink_job_name, service_name_variants


def resolve_powershell_executable() -> Optional[str]:
    for candidate in ("powershell.exe", "powershell"):
        if shutil.which(candidate):
            return candidate
    return None


def build_install_command(args, powershell_executable: str) -> List[str]:
    script_path = (
        INSTALLER_POWERSHELL_WINDOWS_PATH
        if powershell_executable.endswith(".exe")
        else str(INSTALLER_POWERSHELL_POSIX_PATH)
    )

    cmd = [
        powershell_executable,
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        script_path,
        "-MaxWorkers",
        str(args.max_workers),
    ]

    if args.force:
        cmd.append("-Force")
    if args.no_confirm:
        cmd.append("-NoConfirm")
    if args.skip_images:
        cmd.append("-SkipImages")
    if args.skip_metrics_server:
        cmd.append("-SkipMetricsServer")
    if args.skip_helm:
        cmd.append("-SkipHelm")
    if args.force_metrics_server_upgrade:
        cmd.append("-ForceMetricsServerUpgrade")
    if args.cleanup_cluster:
        cmd.append("-CleanupCluster")
    if args.infra_only:
        cmd.append("-InfraOnly")
    if args.data_only:
        cmd.append("-DataOnly")
    if args.apps_only:
        cmd.append("-AppsOnly")
    if args.monitoring_only:
        cmd.append("-MonitoringOnly")

    return cmd


def get_service_directory(service: str) -> Path:
    variants = service_name_variants(service)
    locations: List[Path] = []
    seen = set()

    def add(path: Path) -> None:
        path_key = str(path)
        if path_key not in seen:
            seen.add(path_key)
            locations.append(path)

    for variant in variants:
        if variant == "frontend":
            add(TRADING_PLATFORM_ROOT / "frontend" / "web-app")

        add(TRADING_PLATFORM_ROOT / "services" / variant)
        add(TRADING_PLATFORM_ROOT / "services" / variant.replace("_", "-"))
        add(TRADING_PLATFORM_ROOT / "services" / variant.replace("-", "_"))
        add(TRADING_PLATFORM_ROOT / "services" / "flink-jobs" / variant)
        add(TRADING_PLATFORM_ROOT / "services" / "flink-jobs" / f"{variant}-java")
        add(TRADING_PLATFORM_ROOT / "services" / "flink-jobs" / f"{variant}-sql")
        add(TRADING_PLATFORM_ROOT / "frontend" / variant)

        if variant == "technical-indicators":
            add(TRADING_PLATFORM_ROOT / "services" / "flink-jobs" / "technical-indicators-java")
        if variant == "ict-event-tagger":
            add(TRADING_PLATFORM_ROOT / "services" / "flink-jobs" / "ict-event-tagger-java")
        if variant == "ict-lifecycle-tracker":
            add(TRADING_PLATFORM_ROOT / "services" / "flink-jobs" / "ict-lifecycle-tracker-java")
        if variant == "raw-tick-storage":
            add(TRADING_PLATFORM_ROOT / "services" / "flink-jobs" / "raw-tick-storage-java")

    for location in locations:
        if location.exists() and (location / "Dockerfile").exists():
            return location

    return locations[0] if locations else (TRADING_PLATFORM_ROOT / "services" / service)


def get_service_info(service: str, chart: str = DEFAULT_CHART) -> Dict[str, Any]:
    try:
        from .naming import get_namespace

        namespace = get_namespace(chart)
        values_file = TRADING_PLATFORM_ROOT / f"helm-deployments/{chart}/values.yaml"
        if not values_file.exists():
            return {"error": f"Values file not found: {values_file}"}

        with VALUES_FILE_LOCK:
            with open(values_file, "r") as f:
                values = yaml.safe_load(f)

        registry = values.get("global", {}).get("imageRegistry", REGISTRY)
        service_config = None
        service_variants = service_name_variants(service)
        matched_service_key = service_variants[0] if service_variants else service

        for candidate in service_variants:
            candidate_clean = candidate.replace("-", "_")
            if candidate in values and isinstance(values[candidate], dict):
                service_config = values[candidate]
                matched_service_key = candidate
                break
            if candidate_clean in values and isinstance(values[candidate_clean], dict):
                service_config = values[candidate_clean]
                matched_service_key = candidate_clean
                break
            if isinstance(values.get("services"), dict) and candidate in values["services"] and isinstance(values["services"][candidate], dict):
                service_config = values["services"][candidate]
                matched_service_key = candidate
                break

        if not service_config and chart == "trading-platform-infra":
            normalized_job_names: List[str] = []
            for candidate in service_variants:
                normalized = normalize_flink_job_name(candidate)
                if normalized and normalized not in normalized_job_names:
                    normalized_job_names.append(normalized)

            for flink_job_name in normalized_job_names:
                base_job_config = None
                ict_jobs_values_file = TRADING_PLATFORM_ROOT / f"helm-deployments/{chart}/charts/ict-flink-jobs/values.yaml"
                if ict_jobs_values_file.exists():
                    with VALUES_FILE_LOCK:
                        with open(ict_jobs_values_file, "r") as f:
                            ict_values = yaml.safe_load(f)
                    if "jobs" in ict_values and flink_job_name in ict_values["jobs"]:
                        base_job_config = ict_values["jobs"][flink_job_name]

                override_job_config = None
                for override_root in ("ict-flink-jobs", "ictFlinkJobs"):
                    jobs = values.get(override_root, {}).get("jobs", {})
                    if flink_job_name in jobs:
                        override_job_config = jobs[flink_job_name]
                        break

                if base_job_config or override_job_config:
                    service_config = deep_merge_dict(base_job_config, override_job_config)
                    matched_service_key = flink_job_name
                    break

        if not service_config:
            return {"service": service, "error": "Service not found in values", "available_keys": list(values.keys())[:10]}

        image_config = service_config.get("image", {})
        tag = image_config.get("tag", "latest")
        repository = image_config.get("repository", matched_service_key)
        full_image = f"{registry}/{repository}:{tag}" if registry and registry not in ["none", ""] else f"{repository}:{tag}"

        service_dir = get_service_directory(matched_service_key)
        return {
            "service": matched_service_key,
            "namespace": namespace,
            "chart": chart,
            "registry": registry,
            "repository": repository,
            "tag": tag,
            "full_image": full_image,
            "service_directory": str(service_dir),
            "dockerfile_exists": (service_dir / "Dockerfile").exists(),
        }
    except Exception as exc:
        return {"error": str(exc), "service": service}


def update_helm_values(service: str, chart: str, new_tag: str) -> bool:
    try:
        service_variants = service_name_variants(service)
        updated_files: List[str] = []
        with VALUES_FILE_LOCK:
            main_values_updated = False
            main_values_file = TRADING_PLATFORM_ROOT / "helm-deployments" / chart / "values.yaml"
            values = None
            if main_values_file.exists():
                with open(main_values_file, "r") as f:
                    values = yaml.safe_load(f)

            if chart == "trading-platform-infra":
                ict_jobs_values_file = TRADING_PLATFORM_ROOT / "helm-deployments" / chart / "charts" / "ict-flink-jobs" / "values.yaml"
                normalized_job_names: List[str] = []
                for candidate in service_variants:
                    normalized = normalize_flink_job_name(candidate)
                    if normalized and normalized not in normalized_job_names:
                        normalized_job_names.append(normalized)

                if ict_jobs_values_file.exists():
                    with open(ict_jobs_values_file, "r") as f:
                        ict_values = yaml.safe_load(f)

                    ict_jobs_updated = False
                    if isinstance(ict_values, dict) and isinstance(ict_values.get("jobs"), dict):
                        for flink_job_name in normalized_job_names:
                            if flink_job_name in ict_values["jobs"]:
                                ict_values["jobs"][flink_job_name].setdefault("image", {})
                                if not isinstance(ict_values["jobs"][flink_job_name]["image"], dict):
                                    ict_values["jobs"][flink_job_name]["image"] = {}
                                ict_values["jobs"][flink_job_name]["image"]["tag"] = new_tag
                                ict_jobs_updated = True

                    if ict_jobs_updated:
                        write_yaml_atomic(ict_jobs_values_file, ict_values)
                        updated_files.append(str(ict_jobs_values_file))

                if isinstance(values, dict):
                    for override_root in ("ict-flink-jobs", "ictFlinkJobs"):
                        jobs = values.get(override_root, {}).get("jobs", {})
                        if not isinstance(jobs, dict):
                            continue
                        for flink_job_name in normalized_job_names:
                            if flink_job_name in jobs:
                                jobs[flink_job_name].setdefault("image", {})
                                if not isinstance(jobs[flink_job_name]["image"], dict):
                                    jobs[flink_job_name]["image"] = {}
                                jobs[flink_job_name]["image"]["tag"] = new_tag
                                main_values_updated = True

            if isinstance(values, dict):
                updated = main_values_updated
                for candidate in service_variants:
                    candidate_clean = candidate.replace("-", "_")
                    if candidate in values and isinstance(values[candidate], dict):
                        values[candidate].setdefault("image", {})
                        if not isinstance(values[candidate]["image"], dict):
                            values[candidate]["image"] = {}
                        values[candidate]["image"]["tag"] = new_tag
                        updated = True

                    if candidate_clean in values and isinstance(values[candidate_clean], dict):
                        values[candidate_clean].setdefault("image", {})
                        if not isinstance(values[candidate_clean]["image"], dict):
                            values[candidate_clean]["image"] = {}
                        values[candidate_clean]["image"]["tag"] = new_tag
                        updated = True

                    services_map = values.get("services")
                    if isinstance(services_map, dict):
                        for service_key in (candidate, candidate_clean):
                            if service_key in services_map and isinstance(services_map[service_key], dict):
                                services_map[service_key].setdefault("image", {})
                                if not isinstance(services_map[service_key]["image"], dict):
                                    services_map[service_key]["image"] = {}
                                services_map[service_key]["image"]["tag"] = new_tag
                                updated = True

                if updated:
                    write_yaml_atomic(main_values_file, values)
                    updated_files.append(str(main_values_file))

            subchart_name_candidates: List[str] = []
            seen_subcharts = set()
            for candidate in service_variants:
                for subchart_name in (candidate, candidate.replace("_", "-"), candidate.replace("-", "_")):
                    if subchart_name and subchart_name not in seen_subcharts:
                        seen_subcharts.add(subchart_name)
                        subchart_name_candidates.append(subchart_name)

            for subchart_name in subchart_name_candidates:
                subchart_values_file = TRADING_PLATFORM_ROOT / "helm-deployments" / chart / "charts" / subchart_name / "values.yaml"
                if not subchart_values_file.exists():
                    continue
                with open(subchart_values_file, "r") as f:
                    subchart_values = yaml.safe_load(f)

                if not isinstance(subchart_values, dict):
                    subchart_values = {}
                subchart_values.setdefault("image", {})
                if not isinstance(subchart_values["image"], dict):
                    subchart_values["image"] = {}
                subchart_values["image"]["tag"] = new_tag

                write_yaml_atomic(subchart_values_file, subchart_values)
                updated_files.append(str(subchart_values_file))

        return len(updated_files) > 0
    except Exception:
        return False


def find_deployment(service: str, namespace: str) -> Optional[str]:
    service_variants = service_name_variants(service)
    flink = is_flink_job(service)
    result = run_command(["kubectl", "get", "flinkdeployments" if flink else "deployments", "-n", namespace, "-o", "json"])

    if result["status"] != "success":
        return None

    try:
        resources = json.loads(result["output"])
        for item in resources.get("items", []):
            name = item["metadata"]["name"]
            if flink:
                for candidate in service_variants:
                    base = normalize_flink_job_name(candidate)
                    if base in name or base.replace("-", "_") in name or base.replace("_", "-") in name:
                        return name
            else:
                for candidate in service_variants:
                    if candidate in name or candidate.replace("-", "_") in name or candidate.replace("_", "-") in name:
                        return name
    except Exception:
        return None

    return None
