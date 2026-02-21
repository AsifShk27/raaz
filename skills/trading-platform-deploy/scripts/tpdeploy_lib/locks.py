#!/usr/bin/python3
"""Process lock helpers to prevent concurrent conflicting tpdeploy runs."""

from contextlib import contextmanager

from .constants import DEFAULT_CHART, LOCK_DIR
from .naming import canonical_lock_service_name

try:
    import fcntl
except ImportError:
    fcntl = None


def _sanitize_lock_part(value: str) -> str:
    return "".join(ch if ch.isalnum() or ch in ("-", "_", ".") else "_" for ch in value)


def _lock_key_from_args(args) -> str:
    command = getattr(args, "command", "unknown")
    chart = getattr(args, "chart", DEFAULT_CHART)
    if command in {"build", "push", "delete", "rebuild", "info"} and hasattr(args, "service"):
        service = canonical_lock_service_name(getattr(args, "service", "unknown"))
        return f"{_sanitize_lock_part(chart)}__{_sanitize_lock_part(service)}"
    if command in {"rebuild-all", "upgrade"}:
        return f"{_sanitize_lock_part(chart)}__chart"
    if command == "install":
        return "install__full-platform"
    return _sanitize_lock_part(command)


@contextmanager
def command_lock(args):
    if fcntl is None:
        yield
        return

    LOCK_DIR.mkdir(parents=True, exist_ok=True)
    lock_key = _lock_key_from_args(args)
    lock_path = LOCK_DIR / f"{lock_key}.lock"
    lock_handle = open(lock_path, "w")

    try:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock_handle.close()
        raise RuntimeError(
            f"Another tpdeploy process is already running for '{lock_key}'. "
            "Wait for it to finish before retrying."
        )

    lock_handle.write("locked\n")
    lock_handle.flush()

    try:
        yield
    finally:
        try:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
        except Exception:
            pass
        lock_handle.close()
