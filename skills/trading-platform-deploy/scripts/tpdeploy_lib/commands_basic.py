#!/usr/bin/python3
"""Primary tpdeploy command handlers."""

import argparse
import time
from pathlib import Path

from .command_runtime import ensure_registry_available, frontend_docker_run_tests_value, increment_version, run_command
from .constants import REGISTRY, TRADING_PLATFORM_ROOT
from .naming import get_namespace, is_flink_job
from .output import Colors, log_error, log_info, log_step, log_success, log_warning
from .service_ops import (
    build_install_command,
    find_deployment,
    get_service_info,
    resolve_powershell_executable,
    update_helm_values,
)


def cmd_info(args):
    info = get_service_info(args.service, args.chart)
    if "error" in info:
        log_error(info["error"])
        if "available_keys" in info:
            log_info(f"Available keys: {', '.join(info['available_keys'])}")
        return 1

    print(f"\n{Colors.BOLD}Service Info: {args.service}{Colors.END}")
    print("-" * 40)
    print(f"  Namespace:    {info['namespace']}")
    print(f"  Chart:        {info['chart']}")
    print(f"  Registry:     {info['registry']}")
    print(f"  Repository:   {info['repository']}")
    print(f"  Tag:          {info['tag']}")
    print(f"  Full Image:   {info['full_image']}")
    print(f"  Service Dir:  {info['service_directory']}")
    print(f"  Dockerfile:   {'Yes' if info['dockerfile_exists'] else 'No'}")
    print()
    return 0


def cmd_build(args):
    log_step(f"Building {args.service}")

    info = get_service_info(args.service, args.chart)
    if "error" in info:
        log_error(info["error"])
        return 1

    current_tag = info["tag"]
    new_tag = increment_version(current_tag)
    repository = info["repository"]
    service_dir = Path(info["service_directory"])
    build_image = f"{repository}:{new_tag}"

    log_info(f"Incrementing version: {current_tag} -> {new_tag}")

    values_updated = update_helm_values(args.service, args.chart, new_tag)
    if not values_updated:
        log_warning("Failed to update helm values")

    if args.service == "frontend":
        run_tests = frontend_docker_run_tests_value()
        log_info(f"Frontend Docker build arg RUN_TESTS={run_tests}")
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
    elif args.service == "dhan-adapter":
        build_cmd = ["docker", "build", "--no-cache", "-t", build_image, "--build-context", "refdata_client=../refdata-client", "."]
        build_cwd = service_dir
    elif service_dir.parent.name == "flink-jobs":
        dir_name = service_dir.name
        if (
            args.service.endswith("-java")
            or args.service.endswith("-sql")
            or dir_name.endswith("-java")
            or dir_name.endswith("-sql")
            or (args.service.endswith("-v2") and "-sql-" in args.service)
        ):
            build_context = service_dir.parent
            build_cmd = ["docker", "build", "--no-cache", "-t", build_image, "-f", str(service_dir / "Dockerfile"), "."]
            build_cwd = build_context
        else:
            build_context = service_dir.parent
            dockerfile_path = service_dir / "Dockerfile"
            build_cmd = [
                "docker",
                "build",
                "--no-cache",
                "-t",
                build_image,
                "-f",
                str(dockerfile_path.relative_to(TRADING_PLATFORM_ROOT)),
                str(build_context.relative_to(TRADING_PLATFORM_ROOT)),
            ]
            build_cwd = TRADING_PLATFORM_ROOT
    else:
        build_cmd = ["docker", "build", "--no-cache", "-t", build_image, "."]
        build_cwd = service_dir

    result = run_command(build_cmd, cwd=build_cwd, timeout=3600, capture_output=False)
    if result["status"] == "success":
        log_success(f"Built {build_image}")
        return 0

    log_error(f"Build failed: {result.get('error', 'Unknown error')}")
    if values_updated:
        if update_helm_values(args.service, args.chart, current_tag):
            log_info(f"Rolled back helm values to {current_tag} after build failure")
        else:
            log_warning(f"Failed to roll back helm values to {current_tag}")
    return 1


def cmd_push(args):
    log_step(f"Pushing {args.service}")
    info = get_service_info(args.service, args.chart)
    if "error" in info:
        log_error(info["error"])
        return 1

    repository = info["repository"]
    tag = info["tag"]
    registry = info["registry"] or REGISTRY

    if not ensure_registry_available(registry):
        return 1

    local_image = f"{repository}:{tag}"
    full_image = f"{registry}/{repository}:{tag}"

    log_info(f"Tagging {local_image} -> {full_image}")
    result = run_command(["docker", "tag", local_image, full_image], capture_output=False)
    if result["status"] != "success":
        log_error(f"Tag failed: {result.get('error', 'Unknown error')}")
        return 1

    log_info(f"Pushing {full_image}")
    result = run_command(["docker", "push", full_image], timeout=900, capture_output=False)
    if result["status"] == "success":
        log_success(f"Pushed {full_image}")
        return 0

    log_error(f"Push failed: {result.get('error', 'Unknown error')}")
    return 1


def cmd_delete(args):
    log_step(f"Deleting {args.service}")
    namespace = get_namespace(args.chart)
    flink = is_flink_job(args.service)
    deployment_name = find_deployment(args.service, namespace)

    if not deployment_name:
        log_info(f"No deployment found for {args.service}")
        return 0

    resource_type = "flinkdeployment" if flink else "deployment"
    log_info(f"Deleting {resource_type} {deployment_name}")
    result = run_command(["kubectl", "delete", f"{resource_type}/{deployment_name}", "-n", namespace, "--wait=true", "--timeout=30s"])

    if result["status"] == "success" or "NotFound" in result.get("error", ""):
        log_success(f"Deleted {deployment_name}")
        return 0

    log_error(f"Delete failed: {result.get('error', 'Unknown error')}")
    return 1


def cmd_upgrade(args):
    log_step(f"Running helm upgrade for {args.chart}")

    namespace = get_namespace(args.chart)
    helm_dir = TRADING_PLATFORM_ROOT / "helm-deployments" / args.chart
    values_file = helm_dir / "values.yaml"

    if not helm_dir.exists():
        log_error(f"Helm chart directory not found: {helm_dir}")
        return 1
    if not values_file.exists():
        log_error(f"Helm values file not found: {values_file}")
        return 1

    log_info("Running helm dependency update")
    result = run_command(["helm", "dependency", "update", "."], cwd=helm_dir, capture_output=False)
    if result["status"] != "success":
        log_error(f"Dependency update failed: {result.get('error', '')}")
        return 1

    helm_args = [
        "helm",
        "upgrade",
        args.chart,
        ".",
        "-n",
        namespace,
        "--install",
        "--reset-values",
        "-f",
        str(values_file),
        "--atomic",
        "--timeout",
        "10m0s",
    ]
    result = run_command(helm_args, cwd=helm_dir, capture_output=False)

    if result["status"] == "success":
        log_success(f"Helm upgrade completed for {args.chart}")
        return 0

    log_error(f"Helm upgrade failed: {result.get('error', 'Unknown error')}")
    return 1


def cmd_install(args):
    if args.max_workers < 1:
        log_error("--max-workers must be >= 1")
        return 1

    powershell_executable = resolve_powershell_executable()
    if not powershell_executable:
        log_error("PowerShell executable not found. Install/access powershell.exe and retry.")
        return 1

    installer_cmd = build_install_command(args, powershell_executable)
    log_step("Running full platform install via tpdeploy")
    result = run_command(installer_cmd, cwd=TRADING_PLATFORM_ROOT, timeout=args.timeout, capture_output=False)

    if result["status"] == "success":
        log_success("Full platform install completed")
        return 0

    log_error(f"Install failed: {result.get('error', 'Unknown error')}")
    return 1


def cmd_rebuild(args):
    log_step(f"Rebuilding {args.service}")

    args_copy = argparse.Namespace(service=args.service, chart=args.chart)
    if cmd_build(args_copy) != 0:
        return 1
    if cmd_push(args_copy) != 0:
        return 1
    if cmd_delete(args_copy) != 0:
        log_warning("Delete had issues, continuing with upgrade")

    time.sleep(3)
    args_upgrade = argparse.Namespace(chart=args.chart)
    if cmd_upgrade(args_upgrade) != 0:
        return 1

    log_success(f"Rebuild completed for {args.service}")
    return 0
