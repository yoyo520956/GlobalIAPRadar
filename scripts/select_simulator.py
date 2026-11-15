#!/usr/bin/env python3
"""Pick an Xcode and a simulator destination that actually work together.

GitHub's macOS runners ship several Xcode versions side by side and several
simulator runtimes in /Library/Developer/CoreSimulator. `xcrun simctl list`
shows every runtime on the box, but a given Xcode can only host the runtimes
it was built for -- so picking a UDID from simctl alone regularly produces a
destination that xcodebuild then rejects ("Unable to find a destination
matching the provided destination specifier").

This script therefore asks Xcode itself which destinations are eligible
(`xcodebuild -showdestinations`) and returns a verified (Xcode, UDID) pair.

Outputs GitHub Actions step outputs when GITHUB_OUTPUT is set, otherwise
plain key=value lines on stdout.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

PROJECT = "GlobalIAPRadar.xcodeproj"
SCHEME = "GlobalIAPRadar"

# Preference order for the simulator model. The target device for this app is
# an iPhone SE (3rd generation), so it is tried first.
PREFERRED_DEVICES = [
    "iPhone SE (3rd generation)",
    "iPhone 16",
    "iPhone SE",
    "iPhone",
]

APP_DIRS = ["/Applications"]


def log(message: str) -> None:
    print(f"[select-simulator] {message}", flush=True)


def run(command, env, timeout):
    try:
        return subprocess.run(
            command,
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=os.getcwd(),
        )
    except subprocess.TimeoutExpired:
        return None


def discover_xcodes():
    """All installed Xcode bundles, de-duplicated by version, oldest first.

    Oldest-first keeps the Swift compiler as close as possible to the
    already-verified toolchain while still finding one whose simulator
    runtimes are actually present on the image.
    """
    candidates = {}
    for directory in APP_DIRS:
        base = Path(directory)
        if not base.is_dir():
            continue
        for app in base.glob("Xcode*.app"):
            real = app.resolve()
            key = str(real)
            if key in candidates:
                continue
            candidates[key] = app

    found = []
    for key, app in candidates.items():
        env = dict(os.environ, DEVELOPER_DIR=str(app))
        result = run(["xcodebuild", "-version"], env, 120)
        if result is None or result.returncode != 0:
            continue
        match = re.search(r"Xcode\s+(\d+(?:\.\d+)*)", result.stdout)
        if not match:
            continue
        version = match.group(1)
        if version in [item[0] for item in found]:
            continue
        found.append((version, app))

    def version_key(entry):
        return tuple(int(part) for part in entry[0].split("."))

    found.sort(key=version_key)
    return found


def eligible_destinations(app):
    """Destinations Xcode itself considers usable for this scheme."""
    env = dict(os.environ, DEVELOPER_DIR=str(app))
    result = run(
        ["xcodebuild", "-project", PROJECT, "-scheme", SCHEME, "-showdestinations"],
        env,
        900,
    )
    if result is None:
        return []
    text = result.stdout + result.stderr
    found = []
    for line in text.splitlines():
        if "platform:iOS Simulator" not in line:
            continue
        udid = re.search(r"id:([0-9A-Fa-f-]{36})", line)
        name = re.search(r"name:([^}]+)", line)
        os_version = re.search(r"OS:([^,}]+)", line)
        if not udid or not name:
            continue
        found.append(
            {
                "udid": udid.group(1).upper(),
                "name": name.group(1).strip(),
                "os": os_version.group(1).strip() if os_version else "",
            }
        )
    return found


def rank_destination(candidates):
    """Pick the best device: SE 3rd gen first, then any iPhone, then anything."""
    for preferred in PREFERRED_DEVICES:
        for device in candidates:
            if device["name"] == preferred:
                return device
    for device in candidates:
        if device["name"].startswith("iPhone"):
            return device
    return candidates[0] if candidates else None


def main() -> int:
    if not Path(PROJECT).exists():
        log(f"error: {PROJECT} not found -- run xcodegen generate first")
        return 1

    xcodes = discover_xcodes()
    if not xcodes:
        log("error: no usable Xcode found on this runner")
        return 1
    log("installed Xcodes: " + ", ".join(version for version, _ in xcodes))

    chosen_xcode = None
    chosen_device = None
    for version, app in xcodes:
        destinations = eligible_destinations(app)
        simulators = [d for d in destinations if d["udid"]]
        log(f"Xcode {version} ({app}): {len(simulators)} eligible simulator destination(s)")
        if not simulators:
            continue
        device = rank_destination(simulators)
        if device is None:
            continue
        chosen_xcode = (version, app)
        chosen_device = device
        break

    if chosen_xcode is None or chosen_device is None:
        log("error: no Xcode on this runner has an eligible iOS Simulator destination")
        log("hint: check `xcodebuild -showdestinations` output for the real error")
        return 2

    version, app = chosen_xcode
    log(f"selected Xcode {version} at {app}")
    log(f"selected simulator {chosen_device['name']} (iOS {chosen_device['os']}) udid={chosen_device['udid']}")

    results = {
        "xcode_path": str(app),
        "xcode_version": version,
        "sim_udid": chosen_device["udid"],
        "sim_name": chosen_device["name"],
        "sim_os": chosen_device["os"],
    }

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as handle:
            for key, value in results.items():
                handle.write(f"{key}={value}\n")
    else:
        for key, value in results.items():
            print(f"{key}={value}")

    print(json.dumps(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
