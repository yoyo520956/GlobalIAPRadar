#!/usr/bin/env python3
"""Pick an Xcode and a simulator destination that actually work together.

GitHub's macOS runners ship many Xcode versions side by side and several
simulator runtimes in /Library/Developer/CoreSimulator. `xcrun simctl list`
shows every runtime on the box, but a given Xcode can only host the runtimes
that match its simulator SDK -- picking a UDID from simctl alone regularly
produces a destination that xcodebuild then rejects ("Unable to find a
destination matching the provided destination specifier").

Two sources of truth are combined here:

1.  Runtime/SDK compatibility. Each Xcode exposes its simulator SDK version
    (`xcrun --sdk iphonesimulator --show-sdk-version`). A runtime of the same
    iOS major version and a version <= that SDK is the pairing Apple ships
    (Xcode 16.4 -> iOS 18.5, Xcode 26.x -> iOS 26.0).
2.  xcodebuild itself. The candidate destination is validated with
    `xcodebuild -showBuildSettings -destination ...`, which fails loudly when
    the destination is not usable. That check is the final word.

The lowest Xcode version with a working pair is preferred so the Swift
compiler stays close to the already-verified toolchain.

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
LOG_DIR = Path("build")

# Preference order for the simulator model. The target device for this app is
# an iPhone SE (3rd generation), so it is tried first.
PREFERRED_DEVICES = [
    "iPhone SE (3rd generation)",
    "iPhone 16",
    "iPhone SE",
    "iPhone",
]


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
    """All installed Xcode bundles, de-duplicated by version, oldest first."""
    found = []
    seen_versions = set()
    for app in sorted(Path("/Applications").glob("Xcode*.app")):
        real = app.resolve()
        env = dict(os.environ, DEVELOPER_DIR=str(real))
        result = run(["xcodebuild", "-version"], env, 120)
        if result is None or result.returncode != 0:
            continue
        match = re.search(r"Xcode\s+(\d+(?:\.\d+)*)", result.stdout)
        if not match:
            continue
        version = match.group(1)
        if version in seen_versions:
            continue
        seen_versions.add(version)
        found.append((version, real))

    def version_key(entry):
        return tuple(int(part) for part in entry[0].split("."))

    found.sort(key=version_key)
    return found


def simulator_sdk_version(xcode_path):
    """iOS simulator SDK version shipped with this Xcode, e.g. 18.5."""
    env = dict(os.environ, DEVELOPER_DIR=str(xcode_path))
    result = run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], env, 120)
    if result is None or result.returncode != 0:
        return None
    text = result.stdout.strip()
    match = re.search(r"(\d+(?:\.\d+)*)", text)
    return match.group(1) if match else None


def available_ios_runtimes():
    """Runtime identifier -> (major, minor) for every installed iOS runtime."""
    result = run(["xcrun", "simctl", "list", "runtimes", "-j"], dict(os.environ), 180)
    if result is None or result.returncode != 0:
        return {}
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}

    runtimes = {}
    for runtime in payload.get("runtimes", []):
        identifier = runtime.get("identifier", "")
        if not identifier.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
            continue
        if not runtime.get("isAvailable", True):
            continue
        match = re.search(r"iOS-(\d+)-(\d+)", identifier)
        if not match:
            continue
        runtimes[identifier] = (int(match.group(1)), int(match.group(2)))
    return runtimes


def available_devices_by_runtime():
    """Runtime identifier -> list of available devices."""
    result = run(["xcrun", "simctl", "list", "devices", "available", "-j"], dict(os.environ), 180)
    if result is None or result.returncode != 0:
        return {}
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}

    devices = {}
    for runtime, entries in payload.get("devices", {}).items():
        for device in entries:
            if not device.get("isAvailable", False):
                continue
            devices.setdefault(runtime, []).append(
                {
                    "udid": device.get("udid", "").upper(),
                    "name": device.get("name", ""),
                    "runtime": runtime,
                }
            )
    return devices


def runtime_matches_sdk(runtime_version, sdk_version):
    """Apple pairs an Xcode with the runtime of the same iOS major version."""
    runtime_major, runtime_minor = runtime_version
    sdk_parts = [int(part) for part in sdk_version.split(".")]
    sdk_major = sdk_parts[0]
    sdk_minor = sdk_parts[1] if len(sdk_parts) > 1 else 0
    return runtime_major == sdk_major and runtime_minor <= sdk_minor


def rank_device(devices):
    for preferred in PREFERRED_DEVICES:
        for device in devices:
            if device["name"] == preferred:
                return device
    for device in devices:
        if device["name"].startswith("iPhone"):
            return device
    return devices[0] if devices else None


def validate_destination(xcode_path, udid):
    """Ask xcodebuild whether the destination is usable. Returns (ok, detail)."""
    env = dict(os.environ, DEVELOPER_DIR=str(xcode_path))
    result = run(
        [
            "xcodebuild",
            "-project",
            PROJECT,
            "-scheme",
            SCHEME,
            "-destination",
            f"platform=iOS Simulator,id={udid}",
            "-showBuildSettings",
        ],
        env,
        900,
    )
    if result is None:
        return False, "xcodebuild timed out"
    if result.returncode != 0:
        detail = (result.stdout + result.stderr).strip().splitlines()
        tail = detail[-1] if detail else "unknown error"
        return False, tail
    return True, "ok"


def dump_destinations(xcode_path, version):
    """Keep the raw xcodebuild output for post-mortem debugging."""
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, DEVELOPER_DIR=str(xcode_path))
    result = run(
        ["xcodebuild", "-project", PROJECT, "-scheme", SCHEME, "-showdestinations"],
        env,
        900,
    )
    if result is None:
        return
    path = LOG_DIR / f"destinations-xcode-{version}.txt"
    path.write_text(result.stdout + "\n" + result.stderr, encoding="utf-8")


def main() -> int:
    if not Path(PROJECT).exists():
        log(f"error: {PROJECT} not found -- run xcodegen generate first")
        return 1

    xcodes = discover_xcodes()
    if not xcodes:
        log("error: no usable Xcode found on this runner")
        return 1
    log("installed Xcodes: " + ", ".join(version for version, _ in xcodes))

    runtimes = available_ios_runtimes()
    devices_by_runtime = available_devices_by_runtime()
    if not runtimes:
        log("error: could not enumerate iOS simulator runtimes")
        return 1
    log("iOS runtimes on this box: " + ", ".join(
        f"{identifier.rsplit('.', 1)[-1].replace('-', '.')}" for identifier in sorted(runtimes)
    ))

    chosen_xcode = None
    chosen_device = None
    for version, xcode_path in xcodes:
        sdk = simulator_sdk_version(xcode_path)
        if sdk is None:
            log(f"Xcode {version}: simulator SDK version unknown, skipping")
            continue
        log(f"Xcode {version} ({xcode_path}): simulator SDK {sdk}")

        candidates = []
        for runtime_identifier, runtime_version in sorted(runtimes.items()):
            if not runtime_matches_sdk(runtime_version, sdk):
                continue
            devices = devices_by_runtime.get(runtime_identifier, [])
            device = rank_device(devices)
            if device is None:
                continue
            candidates.append((runtime_identifier, device))

        if not candidates:
            log(f"Xcode {version}: no installed runtime matches simulator SDK {sdk}")
            continue

        for runtime_identifier, device in candidates:
            ok, detail = validate_destination(xcode_path, device["udid"])
            if not ok:
                log(f"Xcode {version}: destination rejected for {device['name']} ({detail})")
                dump_destinations(xcode_path, version)
                continue
            log(f"Xcode {version}: destination accepted for {device['name']} "
                f"[{runtime_identifier.rsplit('.', 1)[-1]}] udid={device['udid']}")
            chosen_xcode = (version, xcode_path, sdk)
            chosen_device = device
            break

        if chosen_device is not None:
            break

    if chosen_xcode is None or chosen_device is None:
        log("error: no Xcode on this runner has a usable iOS Simulator destination")
        log("hint: build/destinations-xcode-*.txt holds the raw xcodebuild output")
        return 2

    version, xcode_path, sdk = chosen_xcode
    log(f"selected Xcode {version} at {xcode_path} (simulator SDK {sdk})")
    log(f"selected simulator {chosen_device['name']} udid={chosen_device['udid']}")

    results = {
        "xcode_path": str(xcode_path),
        "xcode_version": version,
        "simulator_sdk": sdk,
        "sim_udid": chosen_device["udid"],
        "sim_name": chosen_device["name"],
        "sim_runtime": chosen_device["runtime"],
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
