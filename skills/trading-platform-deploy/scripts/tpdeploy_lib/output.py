#!/usr/bin/python3
"""Terminal formatting and logging helpers for tpdeploy."""


class Colors:
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    BOLD = "\033[1m"
    END = "\033[0m"


def log_info(msg: str):
    print(f"{Colors.BLUE}[INFO]{Colors.END} {msg}")


def log_success(msg: str):
    print(f"{Colors.GREEN}[OK]{Colors.END} {msg}")


def log_warning(msg: str):
    print(f"{Colors.YELLOW}[WARN]{Colors.END} {msg}")


def log_error(msg: str):
    print(f"{Colors.RED}[ERROR]{Colors.END} {msg}")


def log_step(msg: str):
    print(f"{Colors.CYAN}[STEP]{Colors.END} {msg}")
