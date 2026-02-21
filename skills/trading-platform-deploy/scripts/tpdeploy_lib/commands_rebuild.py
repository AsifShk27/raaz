#!/usr/bin/python3
"""Parallel rebuild handlers for tpdeploy."""

import argparse
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Dict

from .command_runtime import ensure_registry_available, frontend_docker_run_tests_value, increment_version, run_command
from .commands_basic import cmd_upgrade
from .constants import MAX_REBUILD_ALL_MAX_WORKERS, REGISTRY, TRADING_PLATFORM_ROOT
from .naming import get_namespace, is_flink_job
from .output import Colors, log_error, log_info, log_step, log_success, log_warning
from .service_ops import find_deployment, get_service_info, update_helm_values


def rebuild_single_service(service: str, chart: str) -> Dict[str, Any]:
    result: Dict[str, Any] = {"service": service, "status": "unknown"}
    try:
        info = get_service_info(service, chart)
        if "error" in info:
            result["status"] = "failed"
            result["error"] = info["error"]
            return result

        current_tag = info["tag"]
        new_tag = increment_version(current_tag)
        repository = info["repository"]
        service_dir = Path(info["service_directory"])
        registry = info["registry"] or REGISTRY
        build_image = f"{repository}:{new_tag}"
        full_image = f"{registry}/{repository}:{new_tag}"

        result["old_tag"] = current_tag
        result["new_tag"] = new_tag

        values_updated = update_helm_values(service, chart, new_tag)
        if not values_updated:
            log_warning(f"[{service}] Failed to update helm values")

        if service == "frontend":
            run_tests = frontend_docker_run_tests_value()
            log_info(f"[{service}] Frontend Docker build arg RUN_TESTS={run_tests}")
            build_cmd = [
                "docker",
                "build",
                "--no-cache",
                "--build-arg",
                f"RUN_TESTS={run_tests}",
                "-t",
                build_image,
                "./frontend/web-app",
            ]
            build_cwd = TRADING_PLATFORM_ROOT
        elif service == "dhan-adapter":
            build_cmd = ["docker", "build", "--no-cache", "-t", build_image, "--build-context", "refdata_client=../refdata-client", "."]
            build_cwd = service_dir
        elif service_dir.parent.name == "flink-jobs":
            dir_name = service_dir.name
            if (
                service.endswith("-java")
                or service.endswith("-sql")
                or dir_name.endswith("-java")
                or dir_name.endswith("-sql")
                or (service.endswith("-v2") and "-sql-" in service)
            ):
                build_cmd = ["docker", "build", "--no-cache", "-t", build_image, "-f", str(service_dir / "Dockerfile"), "."]
                build_cwd = service_dir.parent
            else:
                dockerfile_path = service_dir / "Dockerfile"
                build_cmd = [
                    "docker",
                    "build",
                    "--no-cache",
                    "-t",
                    build_image,
                    "-f",
                    str(dockerfile_path.relative_to(TRADING_PLATFORM_ROOT)),
                    str(service_dir.parent.relative_to(TRADING_PLATFORM_ROOT)),
                ]
                build_cwd = TRADING_PLATFORM_ROOT
        else:
            build_cmd = ["docker", "build", "--no-cache", "-t", build_image, "."]
            build_cwd = service_dir

        build_result = run_command(build_cmd, cwd=build_cwd, timeout=3600, capture_output=False)
        if build_result["status"] != "success":
            if values_updated:
                if update_helm_values(service, chart, current_tag):
                    log_info(f"[{service}] Rolled back helm values to {current_tag} after build failure")
                else:
                    log_warning(f"[{service}] Failed to roll back helm values to {current_tag}")
            result["status"] = "build_failed"
            result["error"] = build_result.get("error", "Unknown build error")
            return result

        if not ensure_registry_available(registry):
            result["status"] = "registry_unavailable"
            result["error"] = f"Registry preflight failed for {registry}"
            return result

        tag_result = run_command(["docker", "tag", build_image, full_image], capture_output=False)
        if tag_result["status"] != "success":
            result["status"] = "tag_failed"
            result["error"] = tag_result.get("error", "Tag failed")
            return result

        push_result = run_command(["docker", "push", full_image], timeout=900, capture_output=False)
        if push_result["status"] != "success":
            result["status"] = "push_failed"
            result["error"] = push_result.get("error", "Push failed")
            return result

        result["status"] = "success"
        return result
    except Exception as exc:
        result["status"] = "exception"
        result["error"] = str(exc)
        return result


def cmd_rebuild_all(args):
    services = args.services
    chart = args.chart
    requested_workers = max(1, int(args.max_workers))
    max_workers = min(requested_workers, len(services), MAX_REBUILD_ALL_MAX_WORKERS)

    if requested_workers != max_workers:
        log_warning(
            f"Adjusted rebuild-all workers from {requested_workers} to {max_workers} "
            f"(services={len(services)}, hard-cap={MAX_REBUILD_ALL_MAX_WORKERS})"
        )

    log_step(
        f"Rebuilding {len(services)} services in parallel with {max_workers} workers: "
        f"{', '.join(services)}"
    )

    results: Dict[str, Dict[str, Any]] = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(rebuild_single_service, svc, chart): svc for svc in services}
        for future in futures:
            service = futures[future]
            try:
                results[service] = future.result()
            except Exception as exc:
                results[service] = {"service": service, "status": "exception", "error": str(exc)}

    successful = [s for s, r in results.items() if r.get("status") == "success"]
    failed = [s for s, r in results.items() if r.get("status") != "success"]

    if failed:
        for service in failed:
            log_error(f"[{service}] {results[service].get('error', 'Unknown error')}")

    if not successful:
        log_error("All builds failed")
        return 1

    log_success(f"Built and pushed: {', '.join(successful)}")

    namespace = get_namespace(chart)
    log_step("Deleting existing deployments")
    for service in successful:
        flink = is_flink_job(service)
        deployment_name = find_deployment(service, namespace)
        if deployment_name:
            resource_type = "flinkdeployment" if flink else "deployment"
            log_info(f"Deleting {resource_type} {deployment_name}")
            run_command(
                ["kubectl", "delete", f"{resource_type}/{deployment_name}", "-n", namespace, "--wait=false"],
                capture_output=False,
            )

    log_info("Waiting for deletions to complete...")
    time.sleep(5)

    args_upgrade = argparse.Namespace(chart=chart)
    if cmd_upgrade(args_upgrade) != 0:
        return 1

    print(f"\n{Colors.BOLD}Rebuild Summary{Colors.END}")
    print("-" * 40)
    print(f"  Successful: {len(successful)}")
    print(f"  Failed:     {len(failed)}")
    for service in successful:
        r = results[service]
        print(f"  {Colors.GREEN}[OK]{Colors.END} {service}: {r.get('old_tag', '?')} -> {r.get('new_tag', '?')}")
    for service in failed:
        r = results[service]
        print(f"  {Colors.RED}[FAIL]{Colors.END} {service}: {r.get('error', 'Unknown error')}")
    print()
    return 0 if not failed else 1
