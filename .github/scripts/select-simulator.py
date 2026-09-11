"""Select an installed iPhone/iPad simulator supported by the selected Xcode SDK.

Usage: xcrun simctl list devices available --json | python3 select-simulator.py iPhone 27.0
Only the UDID goes to stdout, so the workflow can use it as a destination.
"""

import argparse
import json
import re
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("family", choices=["iPhone", "iPad"])
parser.add_argument("sdk_version")
args = parser.parse_args()


def version(value):
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


sdk_version = version(args.sdk_version)
candidates = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-([\d-]+)", runtime)
    if not match:
        continue
    runtime_version = version(match[1].replace("-", "."))
    if not (version("26.0") <= runtime_version <= sdk_version):
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith(args.family + " "):
            candidates.append((runtime_version, device))

if not candidates:
    sys.exit(
        f"No available {args.family} simulator with iOS 26.0–{args.sdk_version}. "
        "Install a compatible runtime and device on the runner."
    )

# Prefer the newest runtime, then keep the model choice stable within that runtime.
newest = max(runtime for runtime, _ in candidates)
device = min(
    (device for runtime, device in candidates if runtime == newest),
    key=lambda device: (device["name"], device["udid"]),
)
print(f"Selected {device['name']} ({'.'.join(map(str, newest))}): {device['udid']}", file=sys.stderr)
print(device["udid"])
