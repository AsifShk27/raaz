#!/usr/bin/env python3
"""Control Wipro/Tuya smart lights on LAN using tinytuya and local config."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


DEFAULT_CONFIG_PATH = Path.home() / ".config" / "raaz" / "wipro-light-discovery" / "devices.json"

# Typical DPS mappings used by Tuya bulbs.
DPS_PROFILES: dict[str, dict[str, str]] = {
    "new": {
        "switch": "20",
        "mode": "21",
        "brightness": "22",
        "temperature": "23",
        "colour": "24",
    },
    "legacy": {
        "switch": "1",
        "mode": "2",
        "brightness": "3",
        "temperature": "4",
        "colour": "5",
    },
}


def load_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"version": 1, "default_device": None, "devices": []}

    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    if not isinstance(data, dict):
        raise ValueError("invalid config: expected object")
    data.setdefault("version", 1)
    data.setdefault("default_device", None)
    data.setdefault("devices", [])
    if not isinstance(data["devices"], list):
        raise ValueError("invalid config: devices must be a list")
    return data


def save_config(path: Path, config: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2)
        handle.write("\n")


def validate_profile(profile: str) -> None:
    if profile not in DPS_PROFILES:
        raise ValueError(f"unknown profile '{profile}', expected one of: {', '.join(sorted(DPS_PROFILES))}")


def resolve_dps(profile: str, overrides: dict[str, str]) -> dict[str, str]:
    validate_profile(profile)
    dps = dict(DPS_PROFILES[profile])
    for key, value in overrides.items():
        if value:
            dps[key] = str(value)
    return dps


def upsert_device(
    config: dict[str, Any],
    *,
    name: str,
    device_id: str,
    ip: str,
    local_key: str,
    version: str,
    profile: str,
    dps: dict[str, str],
    make_default: bool,
) -> None:
    entry = {
        "name": name,
        "id": device_id,
        "ip": ip,
        "local_key": local_key,
        "version": version,
        "profile": profile,
        "dps": dps,
    }

    devices = config["devices"]
    idx = next((i for i, item in enumerate(devices) if item.get("name") == name), None)
    if idx is None:
        devices.append(entry)
    else:
        devices[idx] = entry

    if make_default or config.get("default_device") is None:
        config["default_device"] = name


def remove_device(config: dict[str, Any], name: str) -> bool:
    devices = config["devices"]
    idx = next((i for i, item in enumerate(devices) if item.get("name") == name), None)
    if idx is None:
        return False
    devices.pop(idx)
    if config.get("default_device") == name:
        config["default_device"] = devices[0]["name"] if devices else None
    return True


def pick_device(config: dict[str, Any], name: str | None) -> dict[str, Any]:
    devices: list[dict[str, Any]] = config.get("devices", [])
    if not devices:
        raise ValueError("no configured devices; use 'add' first")

    target = name or config.get("default_device")
    if target:
        for item in devices:
            if item.get("name") == target:
                return item
        raise ValueError(f"device '{target}' not found in config")
    return devices[0]


def load_tinytuya() -> Any:
    try:
        import tinytuya  # type: ignore
    except ImportError:
        print(
            "tinytuya is not installed. Run: python3 -m pip install tinytuya",
            file=sys.stderr,
        )
        raise SystemExit(2)
    return tinytuya


def connect_device(entry: dict[str, Any], tinytuya: Any) -> Any:
    bulb = tinytuya.BulbDevice(entry["id"], entry["ip"], entry["local_key"])
    version = entry.get("version", "3.3")
    try:
        bulb.set_version(float(version))
    except (TypeError, ValueError):
        bulb.set_version(version)
    return bulb


def summarize_response(label: str, response: Any) -> int:
    ok = True
    if isinstance(response, dict):
        err = response.get("Err")
        ok = err in (None, "0", 0)
    print(f"{label}: {'ok' if ok else 'failed'}")
    if isinstance(response, (dict, list)):
        print(json.dumps(response, indent=2))
    elif response is not None:
        print(response)
    return 0 if ok else 1


def set_switch(device: Any, dps: dict[str, str], state: bool) -> Any:
    switch_id = int(dps["switch"])
    if hasattr(device, "set_status"):
        return device.set_status(state, switch=switch_id)
    return device.set_value(switch_id, state)


def set_mode(device: Any, mode: str, dps: dict[str, str]) -> Any:
    if hasattr(device, "set_mode"):
        return device.set_mode(mode)
    return device.set_value(int(dps["mode"]), mode)


def set_brightness(device: Any, dps: dict[str, str], percent: int) -> Any:
    if hasattr(device, "set_brightness_percentage"):
        return device.set_brightness_percentage(percent)
    raw = max(10, min(1000, int(percent * 10)))
    return device.set_value(int(dps["brightness"]), raw)


def set_temperature(device: Any, dps: dict[str, str], percent: int) -> Any:
    if hasattr(device, "set_colourtemp_percentage"):
        return device.set_colourtemp_percentage(percent)
    raw = max(0, min(1000, int(percent * 10)))
    return device.set_value(int(dps["temperature"]), raw)


def parse_hex_color(raw: str) -> tuple[int, int, int]:
    value = raw.strip().lstrip("#")
    if len(value) != 6:
        raise ValueError("color must be 6 hex chars, e.g. FFA500")
    r = int(value[0:2], 16)
    g = int(value[2:4], 16)
    b = int(value[4:6], 16)
    return r, g, b


def set_color(device: Any, dps: dict[str, str], rgb: tuple[int, int, int]) -> Any:
    r, g, b = rgb
    if hasattr(device, "set_colour"):
        return device.set_colour(r, g, b)
    return device.set_value(int(dps["colour"]), f"{r:02x}{g:02x}{b:02x}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Control Wipro/Tuya smart lights via tinytuya.")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH), help="Path to device config JSON file.")
    parser.add_argument("--name", help="Target configured device name.")

    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="List configured devices.")

    add = sub.add_parser("add", help="Add or update a device in local config.")
    add.add_argument("--device-id", required=True, help="Tuya device id.")
    add.add_argument("--ip", required=True, help="LAN IP address of device.")
    add.add_argument("--local-key", required=True, help="Tuya local key.")
    add.add_argument("--version", default="3.3", help="Protocol version, e.g. 3.3 or 3.4.")
    add.add_argument("--profile", choices=sorted(DPS_PROFILES), default="new", help="DPS profile.")
    add.add_argument("--switch-dps", help="Override switch DPS id.")
    add.add_argument("--mode-dps", help="Override mode DPS id.")
    add.add_argument("--brightness-dps", help="Override brightness DPS id.")
    add.add_argument("--temperature-dps", help="Override white temperature DPS id.")
    add.add_argument("--colour-dps", help="Override colour DPS id.")
    add.add_argument("--default", action="store_true", help="Set this device as default.")

    remove = sub.add_parser("remove", help="Remove a configured device.")
    remove.add_argument("--remove-name", required=True, help="Configured device name to remove.")

    set_default = sub.add_parser("set-default", help="Set default device.")
    set_default.add_argument("--default-name", required=True, help="Configured device name to use by default.")

    sub.add_parser("status", help="Fetch device DPS status.")
    sub.add_parser("on", help="Turn the light on.")
    sub.add_parser("off", help="Turn the light off.")
    sub.add_parser("toggle", help="Toggle the current on/off state.")

    brightness = sub.add_parser("brightness", help="Set brightness percent (1-100).")
    brightness.add_argument("--percent", type=int, required=True, help="Brightness percentage.")

    temperature = sub.add_parser("temperature", help="Set white temperature percent (0-100).")
    temperature.add_argument("--percent", type=int, required=True, help="Temperature percentage.")

    color = sub.add_parser("color", help="Set RGB color using HEX value.")
    color.add_argument("--hex", required=True, help="Hex color, e.g. FFA500.")

    return parser


def cmd_list(config: dict[str, Any]) -> int:
    devices = config.get("devices", [])
    if not devices:
        print("No devices configured.")
        return 0
    default_name = config.get("default_device")
    for device in devices:
        mark = "*" if device.get("name") == default_name else " "
        print(
            f"{mark} {device.get('name')} ip={device.get('ip')} version={device.get('version')} "
            f"profile={device.get('profile')}"
        )
    return 0


def run_control_action(command: str, config: dict[str, Any], name: str | None, args: argparse.Namespace) -> int:
    entry = pick_device(config, name)
    dps = entry.get("dps") or dict(DPS_PROFILES.get(entry.get("profile", "new"), DPS_PROFILES["new"]))

    tinytuya = load_tinytuya()
    device = connect_device(entry, tinytuya)

    if command == "status":
        return summarize_response("status", device.status())
    if command == "on":
        return summarize_response("on", set_switch(device, dps, True))
    if command == "off":
        return summarize_response("off", set_switch(device, dps, False))
    if command == "toggle":
        status = device.status()
        current = False
        if isinstance(status, dict):
            dps_map = status.get("dps", {})
            current = bool(dps_map.get(str(dps["switch"])))
        result = set_switch(device, dps, not current)
        return summarize_response("toggle", {"previous": current, "result": result})
    if command == "brightness":
        if not (1 <= args.percent <= 100):
            raise ValueError("--percent must be 1..100")
        set_mode(device, "white", dps)
        return summarize_response("brightness", set_brightness(device, dps, args.percent))
    if command == "temperature":
        if not (0 <= args.percent <= 100):
            raise ValueError("--percent must be 0..100")
        set_mode(device, "white", dps)
        return summarize_response("temperature", set_temperature(device, dps, args.percent))
    if command == "color":
        rgb = parse_hex_color(args.hex)
        set_mode(device, "colour", dps)
        return summarize_response("color", set_color(device, dps, rgb))

    raise ValueError(f"unsupported command '{command}'")


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    config_path = Path(args.config)

    try:
        config = load_config(config_path)
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"Failed to load config {config_path}: {exc}", file=sys.stderr)
        return 2

    try:
        if args.command == "list":
            return cmd_list(config)

        if args.command == "add":
            if not args.name:
                raise ValueError("--name is required when using add")
            dps = resolve_dps(
                args.profile,
                {
                    "switch": args.switch_dps,
                    "mode": args.mode_dps,
                    "brightness": args.brightness_dps,
                    "temperature": args.temperature_dps,
                    "colour": args.colour_dps,
                },
            )
            upsert_device(
                config,
                name=args.name,
                device_id=args.device_id,
                ip=args.ip,
                local_key=args.local_key,
                version=args.version,
                profile=args.profile,
                dps=dps,
                make_default=args.default,
            )
            save_config(config_path, config)
            print(f"Saved device '{args.name}' to {config_path}")
            return 0

        if args.command == "remove":
            ok = remove_device(config, args.remove_name)
            if not ok:
                print(f"Device '{args.remove_name}' not found", file=sys.stderr)
                return 1
            save_config(config_path, config)
            print(f"Removed device '{args.remove_name}'")
            return 0

        if args.command == "set-default":
            device_names = {item.get("name") for item in config.get("devices", [])}
            if args.default_name not in device_names:
                print(f"Device '{args.default_name}' not found", file=sys.stderr)
                return 1
            config["default_device"] = args.default_name
            save_config(config_path, config)
            print(f"Default device set to '{args.default_name}'")
            return 0

        return run_control_action(args.command, config, args.name, args)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
