"""Build portable test products and validate their commit/toolchain provenance."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import time

from planning import read_manifest
from results import command, verify_inventory


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def environment(family):
    sdk = "macosx" if family == "macOS" else "iphonesimulator"
    return {"xcode": output("xcodebuild", "-version"), "sdk": sdk,
            "sdkVersion": output("xcrun", "--sdk", sdk, "--show-sdk-version"),
            "sdkBuild": output("xcrun", "--sdk", sdk, "--show-sdk-build-version"),
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
        "ONLY_ACTIVE_ARCH=YES", "COMPILER_INDEX_STORE_ENABLE=NO"], directory / "build.log")
    if code:
        raise SystemExit(code)
    inventory_path = directory / "inventory.json"
    code, discover_start, discover_end = command([
        "xcodebuild", "test-without-building", "-testProductsPath", products,
        "-destination", args.destination, "-enumerate-tests", "-test-enumeration-style", "flat",
        "-test-enumeration-format", "json", "-test-enumeration-output-path", inventory_path],
        directory / "discovery.log")
    if code:
        raise SystemExit(code)
    inventory = json.loads(inventory_path.read_text())
    verify_inventory(inventory, read_manifest(), "macOS" if args.family == "macOS" else "iPhone")
    metadata = {"version": 1, "sha": sha, "family": args.family, "environment": env,
                "runId": os.environ.get("GITHUB_RUN_ID"),
                "buildSeconds": build_end - build_start, "discoverySeconds": discover_end - discover_start,
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
