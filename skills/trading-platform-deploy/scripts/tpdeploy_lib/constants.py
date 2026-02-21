#!/usr/bin/python3
"""Static constants for tpdeploy."""

import threading
from pathlib import Path

TRADING_PLATFORM_ROOT = Path("/mnt/d/projects/trading-platform")
REGISTRY = "localhost:30500"
LOCAL_ZOT_REGISTRY = "localhost:30500"
LOCAL_ZOT_STACK_SCRIPT = TRADING_PLATFORM_ROOT / "scripts" / "ci" / "local_zot_stack.sh"
DEFAULT_CHART = "trading-platform-apps"
INSTALLER_POWERSHELL_WINDOWS_PATH = r"D:\projects\trading-platform\scripts\Install-TradingPlatform-Python.ps1"
INSTALLER_POWERSHELL_POSIX_PATH = TRADING_PLATFORM_ROOT / "scripts" / "Install-TradingPlatform-Python.ps1"
LOCK_DIR = Path("/tmp/tpdeploy-locks")
VALUES_FILE_LOCK = threading.Lock()
REGISTRY_PREFLIGHT_LOCK = threading.Lock()
REGISTRY_PREFLIGHT_READY = set()
DEFAULT_REBUILD_ALL_MAX_WORKERS = 3
MAX_REBUILD_ALL_MAX_WORKERS = 6
DEFAULT_INSTALL_MAX_WORKERS = 3

READ_ONLY_GIT_SUBCOMMANDS = {
    "status",
    "log",
    "show",
    "diff",
    "rev-parse",
    "branch",
}

GIT_OPTIONS_WITH_VALUE = {
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--exec-path",
    "--super-prefix",
    "--config-env",
}

NAMESPACE_MAP = {
    "trading-platform-apps": "trading-platform-apps",
    "trading-platform-data": "data-services",
    "trading-platform-infra": "streaming",
    "trading-platform-monitoring": "monitoring",
    "helm": "default",
}

FLINK_JOB_NAMES = [
    "ict-confluence-aggregator",
    "ict-event-tagger",
    "ict-lifecycle-tracker",
    "ohlcv-aggregation",
    "portfolio-pnl",
    "raw-tick-storage",
    "bars-storage",
    "ict-confluence-stream",
    "technical-indicators",
]
