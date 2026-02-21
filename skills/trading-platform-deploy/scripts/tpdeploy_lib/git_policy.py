#!/usr/bin/python3
"""Git mutation policy enforcement for tpdeploy commands."""

import argparse
import os
from pathlib import Path
from typing import List, Optional

from .constants import GIT_OPTIONS_WITH_VALUE, READ_ONLY_GIT_SUBCOMMANDS
from .output import log_warning

GIT_MUTATION_ALLOWED = False
GIT_PERMISSION_TICKET = ""


def _is_git_command(cmd: List[str]) -> bool:
    if not cmd:
        return False
    return Path(cmd[0]).name == "git"


def _extract_git_subcommand(cmd: List[str]) -> Optional[str]:
    if not _is_git_command(cmd):
        return None

    i = 1
    while i < len(cmd):
        token = cmd[i]
        if token in GIT_OPTIONS_WITH_VALUE:
            i += 2
            continue
        if token == "--":
            i += 1
            break
        if token.startswith("-"):
            i += 1
            continue
        return token
    return None


def is_mutating_git_command(cmd: List[str]) -> bool:
    if not _is_git_command(cmd):
        return False
    subcommand = _extract_git_subcommand(cmd)
    if not subcommand:
        return False
    return subcommand not in READ_ONLY_GIT_SUBCOMMANDS


def is_mutating_git_allowed() -> bool:
    return GIT_MUTATION_ALLOWED


def configure_git_mutation_policy(args: argparse.Namespace) -> None:
    global GIT_MUTATION_ALLOWED, GIT_PERMISSION_TICKET

    allow_from_arg = bool(getattr(args, "allow_mutating_git", False))
    allow_from_env = os.getenv("TPDEPLOY_ALLOW_MUTATING_GIT", "").strip().lower() in {"1", "true", "yes", "on"}
    ticket_from_arg = str(getattr(args, "git_permission_ticket", "")).strip()
    ticket_from_env = os.getenv("TPDEPLOY_GIT_PERMISSION_TICKET", "").strip()

    allow_requested = allow_from_arg or allow_from_env
    permission_ticket = ticket_from_arg or ticket_from_env

    if allow_requested and not permission_ticket:
        log_warning(
            "Mutating git permission requested but no ticket provided; "
            "continuing with mutating git blocked."
        )
        GIT_MUTATION_ALLOWED = False
        GIT_PERMISSION_TICKET = ""
        return

    if allow_requested:
        GIT_MUTATION_ALLOWED = True
        GIT_PERMISSION_TICKET = permission_ticket
        log_warning(
            "Mutating git commands enabled for this run due to explicit permission ticket: "
            f"{GIT_PERMISSION_TICKET}"
        )
    else:
        GIT_MUTATION_ALLOWED = False
        GIT_PERMISSION_TICKET = ""
