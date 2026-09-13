"""Build portable test products and validate their commit/toolchain provenance."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import subprocess
import tarfile
import time

from planning import read_manifest
from results import command, is_infrastructure_failure, verify_inventory


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def environment(family):
    sdk = "macosx" if family == "macOS" else "iphonesimulator"
    developer = Path(os.environ.get("DEVELOPER_DIR") or output("xcode-select", "-p"))
    name = "MacOSX" if family == "macOS" else "iPhoneSimulator"
    sdk_path = developer / "Platforms" / f"{name}.platform" / "Developer/SDKs" / f"{name}.sdk"
    settings = json.loads((sdk_path / "SDKSettings.json").read_text())
    system = plistlib.loads((sdk_path / "System/Library/CoreServices/SystemVersion.plist").read_bytes())
    # Read the selected SDK's authoritative metadata directly. Repeated xcrun
    # SDK discovery can serialize behind simulator setup for several minutes.
    return {"xcode": output("xcodebuild", "-version"), "sdk": sdk,
            "sdkVersion": settings["Version"], "sdkBuild": system["ProductBuildVersion"],
            "architecture": platform.machine(), "configuration": "Debug"}


def verify_products(directory, sha, family):
    metadata = json.loads((directory / "metadata.json").read_text())
    if metadata["sha"] != sha or metadata["family"] != family:
        raise ValueError("Test products belong to another commit or platform")
    current = environment(family)
    if metadata["environment"] != current:
        raise ValueError(f"Test toolchain mismatch: built={metadata['environment']}; current={current}")
    if not (directory / "Tests.xctestproducts" / "Info.plist").is_file():
        raise ValueError("Missing test product bundle")
    inventory = json.loads((directory / "inventory.json").read_text())
    verify_inventory(inventory, read_manifest(), "macOS" if family == "macOS" else "iPhone")
    return metadata, inventory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("family", choices=["macOS", "iOS"])
    parser.add_argument("--destination", required=True, help="Concrete destination used only for discovery")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    args = parser.parse_args()
    directory = args.output.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    start = time.time()
    sha = output("git", "rev-parse", "HEAD")
    env = environment(args.family)
    destination = "platform=macOS,arch=arm64" if args.family == "macOS" else "generic/platform=iOS Simulator"
    products = directory / "Tests.xctestproducts"
    code, build_start, build_end = command([
        "xcodebuild", "build-for-testing", "-project", "shopware.xcodeproj", "-scheme", "CI",
        "-testPlan", "UIRegression", "-configuration", "Debug", "-destination", destination,
        "-derivedDataPath", args.derived_data, "-testProductsPath", products,
        "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=",
        "PROVISIONING_PROFILE_SPECIFIER=", "CODE_SIGN_ENTITLEMENTS=", "ARCHS=arm64",
        "ONLY_ACTIVE_ARCH=YES", "COMPILER_INDEX_STORE_ENABLE=NO"], directory / "build.log", timeout=600)
    if code:
        raise SystemExit(code)
    discovery = []
    for number in range(1, 3):
        inventory_path = directory / f"inventory-{number}.json"
        log_path = directory / f"discovery-{number}.log"
        code, discover_start, discover_end = command([
            "xcodebuild", "test-without-building", "-testProductsPath", products,
            "-destination", args.destination, "-enumerate-tests", "-test-enumeration-style", "flat",
            "-test-enumeration-format", "json", "-test-enumeration-output-path", inventory_path,
            "-resultBundlePath", directory / f"discovery-{number}.xcresult"], log_path, timeout=240)
        error = None
        try:
            if code:
                raise ValueError(f"Discovery exited {code}")
            inventory = json.loads(inventory_path.read_text())
            verify_inventory(inventory, read_manifest(), "macOS" if args.family == "macOS" else "iPhone")
        except (ValueError, OSError) as failure:
            error = str(failure)
        discovery.append({"number": number, "seconds": discover_end - discover_start,
                          "exitCode": code, "error": error})
        (directory / "discovery-report.json").write_text(json.dumps(discovery, indent=2) + "\n")
        if error is None:
            (directory / "inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
            break
        # Enumeration never runs test methods. Permit one bounded setup retry,
        # retaining both attempts, only for a timeout or recognized runner error.
        if number == 2 or not (code == 124 or is_infrastructure_failure([log_path.read_text()])):
            raise ValueError(error)
        print("Retrying test discovery after a runner startup failure", flush=True)
        match = re.search(r"id=([0-9a-f-]+)", args.destination, re.IGNORECASE)
        if match:
            subprocess.run(["xcrun", "simctl", "shutdown", match[1]], check=False, timeout=30)
            subprocess.run(["xcrun", "simctl", "bootstatus", match[1], "-b"], check=True, timeout=120)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as output_file:
            output_file.write(f"diagnostics={str(len(discovery) > 1).lower()}\n")
    metadata = {"version": 1, "sha": sha, "family": args.family, "environment": env,
                "runId": os.environ.get("GITHUB_RUN_ID"),
                "buildSeconds": build_end - build_start, "discoverySeconds": sum(d["seconds"] for d in discovery), "discoveryAttempts": discovery,
                "startedAt": start, "finishedAt": time.time()}
    (directory / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    archive = directory.parent / f"test-products-{args.family}.tar.gz"
    with tarfile.open(archive, "w:gz", compresslevel=3) as tar:
        for filename in ["Tests.xctestproducts", "metadata.json", "inventory.json"]:
            tar.add(directory / filename, arcname=filename)
    digest = hashlib.sha256()
    with archive.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    digest = digest.hexdigest()
    archive.with_suffix(archive.suffix + ".sha256").write_text(f"{digest}  {archive.name}\n")
    print(f"Build products: {archive.stat().st_size / 1024**2:.1f} MiB; SHA256 {digest}")


if __name__ == "__main__":
    main()
