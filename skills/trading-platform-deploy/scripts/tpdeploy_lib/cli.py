#!/usr/bin/python3
"""CLI parser and command dispatcher for tpdeploy."""

import argparse
import os

from .commands_basic import cmd_build, cmd_delete, cmd_info, cmd_install, cmd_push, cmd_rebuild, cmd_upgrade
from .commands_rebuild import cmd_rebuild_all
from .constants import DEFAULT_CHART, DEFAULT_INSTALL_MAX_WORKERS, DEFAULT_REBUILD_ALL_MAX_WORKERS, MAX_REBUILD_ALL_MAX_WORKERS
from .git_policy import configure_git_mutation_policy
from .locks import command_lock
from .output import log_error


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Trading Platform Deploy CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  tpdeploy info order-router
  tpdeploy build order-router
  tpdeploy push order-router
  tpdeploy delete order-router
  tpdeploy upgrade --chart trading-platform-apps
  tpdeploy rebuild order-router
  tpdeploy rebuild-all order-router dhan-adapter
  tpdeploy install --max-workers 3 --no-confirm
        """,
    )
    parser.add_argument(
        "--allow-mutating-git",
        action="store_true",
        help="Allow mutating git commands for this run (requires --git-permission-ticket).",
    )
    parser.add_argument(
        "--git-permission-ticket",
        default="",
        help="User-permission reference required when --allow-mutating-git is used.",
    )

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    info_parser = subparsers.add_parser("info", help="Get service info")
    info_parser.add_argument("service", help="Service name")
    info_parser.add_argument("--chart", default=DEFAULT_CHART, help=f"Helm chart (default: {DEFAULT_CHART})")

    build_parser = subparsers.add_parser("build", help="Build Docker image")
    build_parser.add_argument("service", help="Service name")
    build_parser.add_argument("--chart", default=DEFAULT_CHART, help=f"Helm chart (default: {DEFAULT_CHART})")

    push_parser = subparsers.add_parser("push", help="Push to registry")
    push_parser.add_argument("service", help="Service name")
    push_parser.add_argument("--chart", default=DEFAULT_CHART, help=f"Helm chart (default: {DEFAULT_CHART})")

    delete_parser = subparsers.add_parser("delete", help="Delete deployment")
    delete_parser.add_argument("service", help="Service name")
    delete_parser.add_argument("--chart", default=DEFAULT_CHART, help=f"Helm chart (default: {DEFAULT_CHART})")

    upgrade_parser = subparsers.add_parser("upgrade", help="Run helm upgrade")
    upgrade_parser.add_argument("--chart", default=DEFAULT_CHART, help=f"Helm chart (default: {DEFAULT_CHART})")

    rebuild_parser = subparsers.add_parser("rebuild", help="Full rebuild (build + push + delete + upgrade)")
    rebuild_parser.add_argument("service", help="Service name")
    rebuild_parser.add_argument("--chart", default=DEFAULT_CHART, help=f"Helm chart (default: {DEFAULT_CHART})")

    rebuild_all_parser = subparsers.add_parser("rebuild-all", help="Rebuild multiple services in parallel")
    rebuild_all_parser.add_argument("services", nargs="+", help="Service names")
    rebuild_all_parser.add_argument("--chart", default=DEFAULT_CHART, help=f"Helm chart (default: {DEFAULT_CHART})")
    rebuild_all_parser.add_argument(
        "--max-workers",
        type=int,
        default=DEFAULT_REBUILD_ALL_MAX_WORKERS,
        help=(
            "Parallel build workers for rebuild-all "
            f"(default: {DEFAULT_REBUILD_ALL_MAX_WORKERS}, max: {MAX_REBUILD_ALL_MAX_WORKERS})"
        ),
    )

    install_parser = subparsers.add_parser("install", help="Run full platform install script")
    install_parser.add_argument(
        "--max-workers",
        type=int,
        default=DEFAULT_INSTALL_MAX_WORKERS,
        help=f"Parallel image build workers for installer (default: {DEFAULT_INSTALL_MAX_WORKERS})",
    )
    install_parser.add_argument("--timeout", type=int, default=21600, help="Installer timeout in seconds (default: 21600)")
    install_parser.add_argument("--force", dest="force", action="store_true", default=True, help="Pass -Force to installer (default: true)")
    install_parser.add_argument("--no-force", dest="force", action="store_false", help="Do not pass -Force to installer")
    install_parser.add_argument(
        "--no-confirm",
        dest="no_confirm",
        action="store_true",
        default=True,
        help="Pass -NoConfirm to installer (default: true)",
    )
    install_parser.add_argument("--confirm", dest="no_confirm", action="store_false", help="Require interactive installer confirmation")
    install_parser.add_argument("--skip-images", action="store_true", help="Pass -SkipImages to installer")
    install_parser.add_argument("--skip-metrics-server", action="store_true", help="Pass -SkipMetricsServer to installer")
    install_parser.add_argument("--skip-helm", action="store_true", help="Pass -SkipHelm to installer")
    install_parser.add_argument(
        "--force-metrics-server-upgrade",
        action="store_true",
        help="Pass -ForceMetricsServerUpgrade to installer",
    )
    install_parser.add_argument("--cleanup-cluster", action="store_true", help="Pass -CleanupCluster to installer")
    install_scope_group = install_parser.add_mutually_exclusive_group()
    install_scope_group.add_argument("--infra-only", action="store_true", help="Pass -InfraOnly to installer")
    install_scope_group.add_argument("--data-only", action="store_true", help="Pass -DataOnly to installer")
    install_scope_group.add_argument("--apps-only", action="store_true", help="Pass -AppsOnly to installer")
    install_scope_group.add_argument("--monitoring-only", action="store_true", help="Pass -MonitoringOnly to installer")

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        return 1

    os.environ.setdefault("DOCKER_BUILDKIT", "1")
    configure_git_mutation_policy(args)

    commands = {
        "info": cmd_info,
        "build": cmd_build,
        "push": cmd_push,
        "delete": cmd_delete,
        "upgrade": cmd_upgrade,
        "rebuild": cmd_rebuild,
        "rebuild-all": cmd_rebuild_all,
        "install": cmd_install,
    }

    handler = commands.get(args.command)
    if not handler:
        parser.print_help()
        return 1

    try:
        with command_lock(args):
            return handler(args)
    except RuntimeError as err:
        log_error(str(err))
        return 2
