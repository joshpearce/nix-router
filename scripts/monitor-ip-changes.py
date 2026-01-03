#!/usr/bin/env python3
"""
Monitor for MAC→IP mapping changes.
Builds an initial manifest then reports any changes.
Run this directly on the router.
"""

import subprocess
import sys
import time
from datetime import datetime


def get_arp_table():
    """Fetch ARP table locally."""
    result = subprocess.run(
        ["ip", "neigh", "show"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Error fetching ARP table: {result.stderr}", file=sys.stderr)
        return None
    return result.stdout


def parse_arp_table(output):
    """Parse ip neigh output into {mac: {ip, interface, state}} dict."""
    mappings = {}
    for line in output.strip().split("\n"):
        if not line:
            continue
        parts = line.split()
        if len(parts) < 4:
            continue

        ip = parts[0]
        iface = None
        mac = None
        state = None

        # Parse: IP dev IFACE lladdr MAC STATE
        for i, part in enumerate(parts):
            if part == "dev" and i + 1 < len(parts):
                iface = parts[i + 1]
            elif part == "lladdr" and i + 1 < len(parts):
                mac = parts[i + 1].lower()
            elif part in ("REACHABLE", "STALE", "DELAY", "PROBE", "PERMANENT", "NOARP", "INCOMPLETE", "FAILED"):
                state = part

        if mac and ip:
            mappings[mac] = {"ip": ip, "interface": iface, "state": state}

    return mappings


def format_entry(mac, info):
    """Format a mapping entry for display."""
    return f"{mac} -> {info['ip']} ({info['interface']}, {info['state']})"


def monitor(interval=5):
    """Monitor for changes in MAC→IP mappings."""
    print("Building initial manifest...")

    output = get_arp_table()
    if output is None:
        sys.exit(1)

    baseline = parse_arp_table(output)
    print(f"Initial manifest built: {len(baseline)} entries")
    print("-" * 60)

    # Track current state (may differ from baseline as we detect changes)
    current = dict(baseline)

    try:
        while True:
            time.sleep(interval)

            output = get_arp_table()
            if output is None:
                continue

            new_state = parse_arp_table(output)
            now = datetime.now().strftime("%H:%M:%S")

            # Check for new MACs (not in baseline)
            for mac, info in new_state.items():
                if mac not in baseline:
                    if mac not in current:
                        print(f"[{now}] NEW: {format_entry(mac, info)}")
                        current[mac] = info
                    elif current[mac]["ip"] != info["ip"]:
                        print(f"[{now}] CHANGED (new device): {mac} {current[mac]['ip']} -> {info['ip']}")
                        current[mac] = info

            # Check for changes in baseline MACs
            for mac, baseline_info in baseline.items():
                if mac in new_state:
                    new_info = new_state[mac]
                    if new_info["ip"] != baseline_info["ip"]:
                        if current.get(mac, {}).get("ip") != new_info["ip"]:
                            print(f"[{now}] CHANGED: {mac} {baseline_info['ip']} -> {new_info['ip']} (was {baseline_info['ip']} at start)")
                            current[mac] = new_info
                else:
                    # MAC disappeared - only note if it was recently seen
                    if mac in current and current[mac].get("state") not in ("FAILED", "INCOMPLETE"):
                        pass  # Don't spam about devices going offline

            # Update current state for next iteration
            current = dict(new_state)

    except KeyboardInterrupt:
        print("\nMonitoring stopped.")


if __name__ == "__main__":
    interval = int(sys.argv[1]) if len(sys.argv) > 1 else 5

    print(f"Monitoring ARP table every {interval}s for IP changes...")
    print("Press Ctrl+C to stop.\n")
    monitor(interval)
