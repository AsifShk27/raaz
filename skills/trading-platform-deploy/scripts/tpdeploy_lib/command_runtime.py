#!/usr/bin/python3
"""Low-level command execution and shared generic helpers."""

import os
import subprocess
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from .constants import (
    LOCAL_ZOT_REGISTRY,
    LOCAL_ZOT_STACK_SCRIPT,
    REGISTRY_PREFLIGHT_LOCK,
    REGISTRY_PREFLIGHT_READY,
    TRADING_PLATFORM_ROOT,
)
from .git_policy import is_mutating_git_allowed, is_mutating_git_command
from .output import log_error, log_info


def frontend_docker_run_tests_value() -> str:
    value = os.getenv("TPDEPLOY_FRONTEND_RUN_TESTS", "false").strip().lower()
    return "true" if value in {"1", "true", "yes", "on"} else "false"


def increment_version(version: str) -> str:
    try:
        parts = version.split('.')
        if len(parts) == 3:
            parts[2] = str(int(parts[2]) + 1)
        elif len(parts) == 2:
            parts[1] = str(int(parts[1]) + 1)
        else:
            return version + ".1"
        return '.'.join(parts)
    except Exception:
        return version + ".1"


def deep_merge_dict(base: Optional[Dict[str, Any]], override: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    merged = deepcopy(base) if isinstance(base, dict) else {}
    if not isinstance(override, dict):
        return merged

    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge_dict(merged.get(key), value)
        else:
            merged[key] = deepcopy(value)
    return merged


def write_yaml_atomic(path: Path, data: Dict[str, Any]) -> None:
    temp_path = path.with_suffix(path.suffix + ".tmp")
    with open(temp_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)
    os.replace(temp_path, path)


def run_command(
    cmd: List[str],
    cwd: Optional[Path] = None,
    timeout: int = 1800,
    capture_output: bool = True,
) -> Dict[str, Any]:
    try:
        if is_mutating_git_command(cmd) and not is_mutating_git_allowed():
            return {
                "status": "blocked",
                "return_code": 126,
                "error": (
                    "Blocked mutating git command by tpdeploy policy. "
                    "Read-only git commands are allowed by default. "
                    "For explicit user-approved exceptions, pass --allow-mutating-git "
                    "with --git-permission-ticket (or env equivalents)."
                ),
            }

        log_info(f"Running: {' '.join(cmd)}" + (f" in {cwd}" if cwd else ""))
        result = subprocess.run(
            cmd,
            cwd=str(cwd) if cwd else None,
            capture_output=capture_output,
            text=True,
            timeout=timeout,
        )
        command_output = result.stdout if capture_output and result.stdout else ""
        command_error = result.stderr if capture_output and result.stderr else ""
        if result.returncode == 0:
            return {"status": "success", "output": command_output}
        return {
            "status": "failed",
            "error": command_error or command_output or f"Command failed with exit code {result.returncode}",
            "return_code": result.returncode,
        }
    except subprocess.TimeoutExpired:
        return {"status": "timeout", "error": f"Command timed out after {timeout}s"}
    except Exception as exc:
        return {"status": "error", "error": str(exc)}


def _normalize_registry(registry: Optional[str]) -> str:
    value = (registry or "").strip()
    if value.startswith("http://"):
        value = value[len("http://") :]
    elif value.startswith("https://"):
        value = value[len("https://") :]
    return value.rstrip("/")


def _is_local_zot_registry(registry: Optional[str]) -> bool:
    return _normalize_registry(registry) == LOCAL_ZOT_REGISTRY


def ensure_registry_available(registry: Optional[str]) -> bool:
    registry_key = _normalize_registry(registry)
    if not _is_local_zot_registry(registry_key):
        return True

    with REGISTRY_PREFLIGHT_LOCK:
        if registry_key in REGISTRY_PREFLIGHT_READY:
            return True

        if not LOCAL_ZOT_STACK_SCRIPT.exists():
            log_error(
                f"Local Zot stack script not found: {LOCAL_ZOT_STACK_SCRIPT}. "
                "Cannot auto-start registry for push."
            )
            return False

        log_info(f"Ensuring local Zot registry is ready for {registry_key}")
        up_result = run_command(["bash", str(LOCAL_ZOT_STACK_SCRIPT), "up"], cwd=TRADING_PLATFORM_ROOT, timeout=300)
        if up_result["status"] != "success":
            log_error(f"Failed to start local Zot stack: {up_result.get('error', 'unknown error')}")
            return False

        wait_result = run_command(["bash", str(LOCAL_ZOT_STACK_SCRIPT), "wait"], cwd=TRADING_PLATFORM_ROOT, timeout=300)
        if wait_result["status"] != "success":
            run_command(["bash", str(LOCAL_ZOT_STACK_SCRIPT), "health"], cwd=TRADING_PLATFORM_ROOT, timeout=60)
            log_error(f"Local Zot registry did not become ready: {wait_result.get('error', 'unknown error')}")
            return False

        REGISTRY_PREFLIGHT_READY.add(registry_key)
        return True
