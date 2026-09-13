"""Select a declared toolchain and create an isolated simulator at the exact OS version."""

import argparse
import json
import os
from pathlib import Path
import subprocess


def capture(*args):
    return subprocess.check_output(args, text=True).strip()


def runtime_images(directory):
    candidates = list(directory.glob("**/*.dmg")) + list(directory.glob("**/*.exportedBundle"))
    # Newer Xcode exports an asset bundle; do not also import images inside it.
    return sorted(p for p in candidates if not any(parent in candidates for parent in p.parents))


def install_runtime(directory, version):
    directory.mkdir(parents=True, exist_ok=True)
    images = runtime_images(directory)
    if not images:
        subprocess.run(["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", version,
                        "-architectureVariant", "arm64", "-exportPath", str(directory)], check=True)
        images = runtime_images(directory)
    if not images:
        raise ValueError("Xcode did not export a simulator runtime image")
    # -exportPath downloads an image; a separate import installs the runtime.
    for image in images:
        subprocess.run(["xcodebuild", "-importPlatform", str(image)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("toolchain", choices=["required", "minimum", "canary", "release"])
    parser.add_argument("platform", choices=["macOS", "iPhone", "iPad"])
    parser.add_argument("--runtime-cache", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(Path(".github/ci/toolchains.json").read_text())[args.toolchain]
    developer = config["application"] + "/Contents/Developer"
    os.environ["DEVELOPER_DIR"] = developer
    version = capture("xcodebuild", "-version")
    if config.get("build") and version.splitlines()[-1] != "Build version " + config["build"]:
        raise ValueError(f"Pinned Xcode is unavailable: {version}")
    with open(os.environ["GITHUB_ENV"], "a") as output:
        output.write(f"DEVELOPER_DIR={developer}\n")
    print(version, flush=True)
    destination = "platform=macOS,arch=arm64"
    if args.platform != "macOS":
        def runtimes():
            return json.loads(capture("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
        def matching():
            return [r for r in runtimes() if r.get("isAvailable") and r["name"].startswith("iOS ")
                    and (config["runtime"] == "latest" or r["version"] == config["runtime"])]
        if not matching():
            install_runtime(args.runtime_cache, config["runtime"])
        available = matching()
        if not available:
            raise ValueError(f"Required iOS {config['runtime']} runtime was not installed")
        runtime = max(available, key=lambda r: tuple(int(p) for p in r["version"].split(".")))
        device_types = json.loads(capture("xcrun", "simctl", "list", "devicetypes", "--json"))["devicetypes"]
        # These models exist at the app's minimum OS; avoid newest hardware that needs a later runtime.
        model = "iPhone 16" if args.platform == "iPhone" else "iPad (A16)"
        device = next(d for d in device_types if d["name"] == model)
        udid = capture("xcrun", "simctl", "create", "CI " + args.platform, device["identifier"], runtime["identifier"])
        subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True)
        destination = "platform=iOS Simulator,id=" + udid
        print(f"{model}: iOS {runtime['version']} ({runtime['buildversion']})", flush=True)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"destination={destination}\n")


if __name__ == "__main__":
    main()
