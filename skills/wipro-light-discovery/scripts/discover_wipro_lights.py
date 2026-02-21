#!/usr/bin/env python3
"""Discover likely smart lights on the local network, focused on Wipro/Tuya devices."""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import ipaddress
import json
import platform
import re
import shlex
import socket
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass, field
from typing import Iterable


TUYA_PORTS = {6666, 6667, 6668, 6669, 55443}
DEFAULT_PORTS = [80, 443, 6666, 6667, 6668, 6669, 8080, 8443, 55443]
HTTP_PROBE_PORTS = {80, 8080, 8443}
WIPRO_HINT_WORDS = ("wipro", "smart bulb", "smart light", "tuya", "smartlife")
ESPRESSIF_HINT_WORDS = ("espressif",)


@dataclass
class HostRecord:
    ip: str
    mac: str | None = None
    vendor: str | None = None
    open_ports: list[int] = field(default_factory=list)
    banner: str | None = None
    score: int = 0
    confidence: str = "low"
    tags: list[str] = field(default_factory=list)
    reason: str = ""
    wipro_likely: bool = False


def run_command(cmd: list[str], timeout: int = 10) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return 127, "", ""
    return proc.returncode, proc.stdout, proc.stderr


def parse_port_list(raw: str) -> list[int]:
    ports: list[int] = []
    for token in raw.split(","):
        token = token.strip()
        if not token:
            continue
        ports.append(int(token))
    return sorted(set(ports))


def is_wsl() -> bool:
    if "microsoft" in platform.release().lower():
        return True
    code, out, _ = run_command(["uname", "-r"])
    return code == 0 and "microsoft" in out.lower()


def local_linux_interfaces() -> list[tuple[str, int]]:
    code, out, _ = run_command(["ip", "-o", "-4", "addr", "show", "scope", "global"])
    if code != 0:
        return []

    results: list[tuple[str, int]] = []
    for line in out.splitlines():
        match = re.search(r"\sinet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)\s", line)
        if not match:
            continue
        ip = match.group(1)
        prefix = int(match.group(2))
        results.append((ip, prefix))
    return results


def windows_ipv4_interfaces() -> list[tuple[str, int]]:
    ps = (
        "$ips = Get-NetIPAddress -AddressFamily IPv4 | "
        "Where-Object { "
        "$_.IPAddress -notlike '169.*' -and "
        "$_.IPAddress -ne '127.0.0.1' -and "
        "$_.InterfaceAlias -notlike 'vEthernet*' "
        "}; "
        "$ips | ForEach-Object { \"$($_.IPAddress)/$($_.PrefixLength)\" }"
    )
    code, out, _ = run_command(["powershell.exe", "-NoProfile", "-Command", ps], timeout=20)
    if code != 0:
        return []

    results: list[tuple[str, int]] = []
    for line in out.splitlines():
        line = line.strip()
        if not line or "/" not in line:
            continue
        ip, prefix = line.split("/", 1)
        try:
            results.append((ip.strip(), int(prefix.strip())))
        except ValueError:
            continue
    return results


def networks_from_sources(
    manual_subnets: list[str],
    max_hosts: int,
    allow_large: bool,
) -> tuple[list[ipaddress.IPv4Network], list[str]]:
    notes: list[str] = []

    if manual_subnets:
        networks: list[ipaddress.IPv4Network] = []
        for item in manual_subnets:
            net = ipaddress.ip_network(item, strict=False)
            if not isinstance(net, ipaddress.IPv4Network):
                continue
            networks.append(net)
        return dedupe_networks(networks), notes

    networks: list[ipaddress.IPv4Network] = []
    for ip, prefix in local_linux_interfaces():
        net = ipaddress.ip_network(f"{ip}/{prefix}", strict=False)
        if not isinstance(net, ipaddress.IPv4Network):
            continue
        if net.is_loopback or net.is_link_local:
            continue
        networks.append(net)

    if is_wsl():
        for ip, prefix in windows_ipv4_interfaces():
            net = ipaddress.ip_network(f"{ip}/{prefix}", strict=False)
            if isinstance(net, ipaddress.IPv4Network):
                networks.append(net)

    normalized: list[ipaddress.IPv4Network] = []
    for net in dedupe_networks(networks):
        if net.num_addresses <= max_hosts or allow_large:
            normalized.append(net)
            continue
        if net.prefixlen < 24 and net.is_private:
            # Clamp huge private ranges to /24 for faster, practical discovery.
            host_ip = next(net.hosts(), None)
            if host_ip is not None:
                smaller = ipaddress.ip_network(f"{host_ip}/24", strict=False)
                normalized.append(smaller)
                notes.append(f"clamped {net} to {smaller} due to host limit")
                continue
        notes.append(f"skipped {net} due to host limit ({net.num_addresses} addresses)")

    return dedupe_networks(normalized), notes


def dedupe_networks(networks: Iterable[ipaddress.IPv4Network]) -> list[ipaddress.IPv4Network]:
    seen: set[str] = set()
    out: list[ipaddress.IPv4Network] = []
    for net in networks:
        key = str(net)
        if key in seen:
            continue
        seen.add(key)
        out.append(net)
    return out


def ping_host(ip: str) -> bool:
    code, _, _ = run_command(["ping", "-c", "1", "-W", "1", ip], timeout=3)
    return code == 0


def discover_live_hosts(networks: list[ipaddress.IPv4Network], workers: int) -> list[str]:
    targets: list[str] = []
    for net in networks:
        targets.extend([str(host) for host in net.hosts()])

    live_hosts: list[str] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(ping_host, ip): ip for ip in targets}
        for future in concurrent.futures.as_completed(futures):
            ip = futures[future]
            try:
                if future.result():
                    live_hosts.append(ip)
            except Exception:
                continue
    return sorted(set(live_hosts), key=lambda x: tuple(int(p) for p in x.split(".")))


def read_linux_neighbors() -> dict[str, str]:
    code, out, _ = run_command(["ip", "neigh", "show"], timeout=10)
    if code != 0:
        return {}
    mapping: dict[str, str] = {}
    for line in out.splitlines():
        # Example: 192.168.0.112 dev eth0 lladdr DC:4F:22:A4:F1:9D REACHABLE
        match = re.match(r"^(\d+\.\d+\.\d+\.\d+)\s+.*lladdr\s+([0-9a-fA-F:]{17})\s", line)
        if not match:
            continue
        mapping[match.group(1)] = match.group(2).upper().replace(":", "-")
    return mapping


def read_windows_neighbors() -> dict[str, str]:
    ps = (
        "Get-NetNeighbor -AddressFamily IPv4 | "
        "Where-Object { $_.LinkLayerAddress -ne '00-00-00-00-00-00' } | "
        "ForEach-Object { \"$($_.IPAddress),$($_.LinkLayerAddress)\" }"
    )
    code, out, _ = run_command(["powershell.exe", "-NoProfile", "-Command", ps], timeout=20)
    if code != 0:
        return {}
    mapping: dict[str, str] = {}
    for line in out.splitlines():
        line = line.strip()
        if "," not in line:
            continue
        ip, mac = line.split(",", 1)
        ip = ip.strip()
        mac = mac.strip().upper()
        if re.match(r"^\d+\.\d+\.\d+\.\d+$", ip):
            mapping[ip] = mac
    return mapping


def probe_port(ip: str, port: int, timeout: float) -> bool:
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except OSError:
        return False


def http_banner(ip: str, port: int, timeout: float) -> str | None:
    scheme = "https" if port in {443, 8443} else "http"
    url = f"{scheme}://{ip}:{port}/"
    req = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            server = response.headers.get("Server")
            if server:
                return server.strip()
            return f"status={response.status}"
    except Exception:
        return None


def lookup_vendor(mac: str | None, enabled: bool, cache: dict[str, str]) -> str | None:
    if not enabled or not mac:
        return None
    key = mac.upper()
    if key in cache:
        return cache[key]

    try:
        with urllib.request.urlopen(f"https://api.macvendors.com/{key}", timeout=4) as response:
            text = response.read().decode("utf-8", errors="ignore").strip()
            cache[key] = text if text else "UNKNOWN"
            return cache[key]
    except Exception:
        cache[key] = "UNKNOWN"
        return "UNKNOWN"


def classify(record: HostRecord) -> None:
    score = 0
    tags: list[str] = []

    tuya_open = sorted(set(record.open_ports).intersection(TUYA_PORTS))
    if tuya_open:
        score += 70
        tags.append(f"tuya_ports={','.join(map(str, tuya_open))}")

    vendor_l = (record.vendor or "").lower()
    banner_l = (record.banner or "").lower()
    combined = f"{vendor_l} {banner_l}"

    if any(word in combined for word in ESPRESSIF_HINT_WORDS):
        score += 15
        tags.append("espressif")
    if "tuya" in combined:
        score += 25
        tags.append("tuya")
    if "wipro" in combined:
        score += 35
        tags.append("wipro")
    if any(word in combined for word in WIPRO_HINT_WORDS):
        score += 10

    if score >= 80:
        confidence = "high"
    elif score >= 50:
        confidence = "medium"
    elif score >= 25:
        confidence = "low"
    else:
        confidence = "very-low"

    # Treat strong Tuya LAN port signatures as likely candidate devices even if
    # OUI vendor lookup is unavailable in the current ARP/neighbor table.
    wipro_likely = (
        "wipro" in tags
        or (6668 in record.open_ports and "espressif" in tags)
        or (score >= 70 and any(port in record.open_ports for port in (6668, 6669, 55443)))
    )

    reason_parts: list[str] = []
    if tuya_open:
        reason_parts.append(f"Tuya-style ports open: {', '.join(map(str, tuya_open))}")
    if "espressif" in tags:
        reason_parts.append("ESP-class chipset signature")
    if "wipro" in tags:
        reason_parts.append("Wipro text signature")
    if "tuya" in tags:
        reason_parts.append("Tuya text signature")

    record.score = score
    record.confidence = confidence
    record.tags = tags
    record.reason = "; ".join(reason_parts) if reason_parts else "No strong smart-light signatures"
    record.wipro_likely = wipro_likely


def scan_host(
    ip: str,
    ports: list[int],
    timeout: float,
    mac_map: dict[str, str],
    vendor_lookup_enabled: bool,
    vendor_cache: dict[str, str],
) -> HostRecord:
    record = HostRecord(ip=ip, mac=mac_map.get(ip))
    record.vendor = lookup_vendor(record.mac, vendor_lookup_enabled, vendor_cache)

    open_ports: list[int] = []
    for port in ports:
        if probe_port(ip, port, timeout=timeout):
            open_ports.append(port)
    record.open_ports = sorted(open_ports)

    for port in record.open_ports:
        if port in HTTP_PROBE_PORTS:
            banner = http_banner(ip, port, timeout=max(2.0, timeout))
            if banner:
                record.banner = banner
                break

    classify(record)
    return record


def render_markdown(
    generated_at: str,
    networks: list[ipaddress.IPv4Network],
    notes: list[str],
    live_hosts: list[str],
    records: list[HostRecord],
    only_wipro: bool,
) -> str:
    lines: list[str] = []
    lines.append("# Wipro Smart Light Discovery")
    lines.append("")
    lines.append(f"Generated: {generated_at}")
    lines.append(f"Scanned networks: {', '.join(str(n) for n in networks)}")
    lines.append(f"Live hosts: {len(live_hosts)}")
    if notes:
        lines.append("Notes:")
        for note in notes:
            lines.append(f"- {note}")
    lines.append("")

    rows = records
    if only_wipro:
        rows = [r for r in rows if r.wipro_likely]
    else:
        rows = [r for r in rows if r.score >= 25]

    if not rows:
        lines.append("No likely Wipro/Tuya smart lights detected.")
        return "\n".join(lines)

    rows = sorted(rows, key=lambda r: (r.wipro_likely, r.score, len(r.open_ports)), reverse=True)
    lines.append("| IP | MAC | Vendor | Open Ports | Confidence | Wipro Likely | Reason |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    for row in rows:
        ports = ",".join(str(p) for p in row.open_ports) if row.open_ports else "-"
        lines.append(
            "| {ip} | {mac} | {vendor} | {ports} | {confidence} ({score}) | {wipro} | {reason} |".format(
                ip=row.ip,
                mac=row.mac or "-",
                vendor=row.vendor or "-",
                ports=ports,
                confidence=row.confidence,
                score=row.score,
                wipro="yes" if row.wipro_likely else "no",
                reason=row.reason,
            )
        )
    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Discover likely Wipro/Tuya smart lights on local network.")
    parser.add_argument("--subnet", action="append", default=[], help="CIDR subnet to scan (repeatable).")
    parser.add_argument("--ports", default=",".join(str(p) for p in DEFAULT_PORTS), help="Comma-separated TCP ports.")
    parser.add_argument("--timeout", type=float, default=0.8, help="Per-port timeout in seconds.")
    parser.add_argument("--workers", type=int, default=96, help="Parallel workers for ping/scan.")
    parser.add_argument("--max-hosts", type=int, default=512, help="Max addresses per subnet unless --allow-large.")
    parser.add_argument("--allow-large", action="store_true", help="Allow scanning large subnets as-is.")
    parser.add_argument("--vendor-lookup", action="store_true", help="Resolve MAC OUI vendor via macvendors API.")
    parser.add_argument("--only-wipro", action="store_true", help="Show only high-confidence Wipro-likely devices.")
    parser.add_argument("--format", choices=("md", "json"), default="md", help="Output format.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    try:
        ports = parse_port_list(args.ports)
    except ValueError as exc:
        print(f"Invalid --ports value: {exc}", file=sys.stderr)
        return 2

    networks, notes = networks_from_sources(args.subnet, max_hosts=args.max_hosts, allow_large=args.allow_large)
    if not networks:
        print("No usable subnets found. Pass --subnet explicitly.", file=sys.stderr)
        return 1

    live_hosts = discover_live_hosts(networks, workers=max(8, args.workers))

    mac_map: dict[str, str] = {}
    mac_map.update(read_linux_neighbors())
    mac_map.update(read_windows_neighbors())

    vendor_cache: dict[str, str] = {}
    records: list[HostRecord] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(8, args.workers)) as pool:
        futures = [
            pool.submit(
                scan_host,
                ip,
                ports,
                args.timeout,
                mac_map,
                args.vendor_lookup,
                vendor_cache,
            )
            for ip in live_hosts
        ]
        for future in concurrent.futures.as_completed(futures):
            try:
                records.append(future.result())
            except Exception:
                continue

    generated_at = dt.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    records = sorted(records, key=lambda r: tuple(int(x) for x in r.ip.split(".")))

    if args.format == "json":
        payload = {
            "generated_at": generated_at,
            "networks": [str(n) for n in networks],
            "notes": notes,
            "live_hosts": live_hosts,
            "records": [asdict(r) for r in records],
        }
        print(json.dumps(payload, indent=2))
        return 0

    print(
        render_markdown(
            generated_at=generated_at,
            networks=networks,
            notes=notes,
            live_hosts=live_hosts,
            records=records,
            only_wipro=args.only_wipro,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
