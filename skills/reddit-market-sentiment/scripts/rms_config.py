from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
from typing import List, Optional, Sequence

from rms_models import AssetConfig

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None  # type: ignore


DEFAULT_MARKER = "/home/shkas/projects/raaz/memory/reddit-market-sentiment-last.txt"


def load_config(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(f"Config not found: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def build_assets(config: dict, selected_groups: Optional[Sequence[str]]) -> List[AssetConfig]:
    groups = config.get("groups", {})
    if selected_groups:
        group_keys = {key.strip() for key in selected_groups if key.strip()}
        groups = {k: v for k, v in groups.items() if k in group_keys}
    assets: List[AssetConfig] = []
    for group_key, group in groups.items():
        for asset_key, asset in (group.get("assets") or {}).items():
            assets.append(
                AssetConfig(
                    key=asset_key,
                    name=asset.get("name", asset_key),
                    keywords=asset.get("keywords", []),
                    group=group_key,
                )
            )
    return assets


def build_subreddits(config: dict, selected_groups: Optional[Sequence[str]]) -> List[str]:
    groups = config.get("groups", {})
    if selected_groups:
        group_keys = {key.strip() for key in selected_groups if key.strip()}
        groups = {k: v for k, v in groups.items() if k in group_keys}
    subs: List[str] = []
    for group in groups.values():
        subs.extend(group.get("subreddits", []))
    return sorted({s.strip().lstrip("r/") for s in subs if s.strip()})


def resolve_timezone(tz_name: str) -> dt.tzinfo:
    if ZoneInfo is None:
        return dt.timezone.utc
    try:
        return ZoneInfo(tz_name)
    except Exception:
        return dt.timezone.utc


def should_run_today(marker_path: Path, tz: dt.tzinfo) -> bool:
    today = dt.datetime.now(tz).strftime("%Y-%m-%d")
    if marker_path.exists():
        contents = marker_path.read_text(encoding="utf-8").strip()
        if contents.startswith(today):
            print(f"[guard] already ran for {today}")
            return False
    return True


def write_marker(marker_path: Path, tz: dt.tzinfo) -> None:
    today = dt.datetime.now(tz).strftime("%Y-%m-%d")
    marker_path.parent.mkdir(parents=True, exist_ok=True)
    marker_path.write_text(f"{today} {dt.datetime.now(tz).isoformat()}\n", encoding="utf-8")
