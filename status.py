#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
from pathlib import Path


DEVICE_LINE = re.compile(
    r"^[\s├└│─]+slot\s+(\d+)\s+([●○])\s+(.+?)\s+\(([^,]+),\s*wpid=([0-9a-fA-F?]+),\s*(battery=[^)]+)\)"
)
CAMERA_LINE = re.compile(
    r"^[\s├└│─]+●\s+(.+?)\s+\(camera,\s*vid=([0-9a-fA-F]+)\s+pid=([0-9a-fA-F]+)"
)
RECEIVER_LINE = re.compile(r"^(.+?)\s+\(([^,]+),\s*vid=([0-9a-fA-F]+)\s+pid=([0-9a-fA-F]+)\)")
BATTERY_LINE = re.compile(
    r"battery=(\d+)%\s+(\w+)(?:\s+\((\w+)\))?|battery=—"
)
LOW_BATTERY_THRESHOLD = 20


def command_output(command, timeout=6):
    try:
        completed = subprocess.run(
            command, check=False, capture_output=True, text=True, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired):
        return 127, ""
    return completed.returncode, (completed.stdout + completed.stderr).strip()


def parse_battery(text):
    match = BATTERY_LINE.search(text or "")
    if not match or match.group(1) is None:
        return None
    return {
        "percent": int(match.group(1)),
        "level": match.group(2),
        "status": match.group(3) or "",
    }


def parse_list_output(raw):
    devices = []
    receivers = []
    cameras = []
    current_receiver = None
    section = "receivers"

    for line in raw.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("Cameras ("):
            section = "cameras"
            continue
        if stripped.startswith("Notes:"):
            break

        if section == "cameras":
            match = CAMERA_LINE.match(line)
            if match:
                cameras.append(
                    {
                        "name": match.group(1).strip(),
                        "vendorId": match.group(2),
                        "productId": match.group(3),
                        "kind": "camera",
                        "online": True,
                    }
                )
            continue

        device_match = DEVICE_LINE.match(line)
        if device_match:
            devices.append(
                {
                    "slot": int(device_match.group(1)),
                    "online": device_match.group(2) == "●",
                    "name": device_match.group(3).strip(),
                    "kind": device_match.group(4).strip(),
                    "wpid": device_match.group(5),
                    "battery": parse_battery(device_match.group(6)),
                    "receiver": current_receiver,
                }
            )
            continue

        receiver_match = RECEIVER_LINE.match(stripped)
        if receiver_match and not stripped.startswith("slot "):
            current_receiver = receiver_match.group(2).strip()
            receivers.append(
                {
                    "name": receiver_match.group(1).strip(),
                    "uid": current_receiver,
                    "vendorId": receiver_match.group(3),
                    "productId": receiver_match.group(4),
                }
            )

    return receivers, devices, cameras


def runtime_socket():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        return ""
    for candidate in (
        Path(runtime) / "openlogi" / "agent.sock",
        Path(runtime) / "agent.sock",
    ):
        if candidate.exists():
            return str(candidate)
    return ""


def kind_rank(kind):
    value = str(kind or "").lower()
    if "mouse" in value or "trackball" in value:
        return 0
    if "keyboard" in value:
        return 1
    if "camera" in value:
        return 2
    return 3


def primary_device(devices, cameras):
    items = list(devices) + list(cameras)
    if not items:
        return None
    return min(
        items,
        key=lambda item: kind_rank(item.get("kind")) + (0 if item.get("online", True) else 10),
    )


def has_low_battery(devices, cameras, threshold=LOW_BATTERY_THRESHOLD):
    for item in list(devices) + list(cameras):
        battery = item.get("battery")
        if not battery:
            continue
        percent = battery.get("percent")
        if isinstance(percent, int) and 0 < percent <= threshold:
            return True
    return False


def main():
    openlogi = shutil.which("openlogi")
    desktop = shutil.which("openlogi-desktop")
    agent_bin = shutil.which("openlogi-agent")

    installed = openlogi is not None
    version = ""
    if installed:
        code, output = command_output([openlogi, "--version"])
        if code == 0:
            version = output.strip()

    agent_active = False
    agent_enabled = False
    if shutil.which("systemctl"):
        code, output = command_output(
            ["systemctl", "--user", "is-active", "openlogi-agent.service"]
        )
        agent_active = code == 0 and output.strip() == "active"
        code, output = command_output(
            ["systemctl", "--user", "is-enabled", "openlogi-agent.service"]
        )
        agent_enabled = code == 0 and output.strip() in {"enabled", "enabled-runtime"}

    socket_present = bool(runtime_socket())

    receivers = []
    devices = []
    cameras = []
    scan_exit = None
    scan_failed = False
    status_text = "Not installed"
    if installed:
        scan_exit, list_output = command_output([openlogi, "list"])
        receivers, devices, cameras = parse_list_output(list_output)
        total = len(devices) + len(cameras)
        scan_failed = scan_exit not in (0, 2)
        if scan_failed:
            status_text = "Scan failed"
        elif total > 0:
            status_text = f"{total} device{'s' if total != 1 else ''} connected"
        elif scan_exit == 2:
            status_text = "No devices found"
        else:
            status_text = "Ready"

    primary = primary_device(devices, cameras)

    print(
        json.dumps(
            {
                "ok": True,
                "installed": installed,
                "desktopInstalled": desktop is not None,
                "agentInstalled": agent_bin is not None,
                "version": version,
                "agentActive": agent_active,
                "agentEnabled": agent_enabled,
                "socketPresent": socket_present,
                "scanFailed": scan_failed,
                "lowBattery": has_low_battery(devices, cameras),
                "statusText": status_text,
                "primaryDevice": primary,
                "receivers": receivers,
                "devices": devices,
                "cameras": cameras,
            }
        )
    )


if __name__ == "__main__":
    main()
