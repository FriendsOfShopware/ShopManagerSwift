"""Conservative impact selection and duration-balanced UI workers (stdlib only)."""

import argparse
import fnmatch
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(__file__).resolve().parent
PLATFORMS = ("macOS", "iPhone", "iPad")


def read_manifest():
    return json.loads((CONFIG / "areas.json").read_text())


def matches(path, patterns):
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def validate_manifest(manifest, root=ROOT):
    entries = manifest["tests"]
    identifiers = [entry["id"] for entry in entries]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("Duplicate test identifiers in areas.json")
    for entry in entries:
        if entry["area"] not in manifest["areas"]:
            raise ValueError(f"Unknown area: {entry}")
        if not entry["platforms"] or not set(entry["platforms"]) <= set(PLATFORMS):
            raise ValueError(f"Invalid platforms: {entry}")
    source_ids = set()
    for path in (root / "shopwareUITests").glob("*.swift"):
        source = path.read_text()
        classes = re.findall(r"(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase", source)
        methods = re.findall(r"\bfunc\s+(test\w+)\s*\(", source)
        if methods and len(classes) != 1:
            raise ValueError(f"Expected one test class in {path}")
        if classes and classes[0] not in manifest["excludedTests"]:
            source_ids.update(f"{classes[0]}/{method}" for method in methods)
    if source_ids != set(identifiers):
        raise ValueError(f"Unassigned tests: {sorted(source_ids - set(identifiers))}; "
                         f"stale entries: {sorted(set(identifiers) - source_ids)}")
    for platform in PLATFORMS:
        if not any(t["smoke"] and platform in t["platforms"] for t in entries):
            raise ValueError(f"Empty smoke suite for {platform}")
    for area, config in manifest["areas"].items():
        if not set(config.get("dependents", [])) <= set(manifest["areas"]):
            raise ValueError(f"Invalid dependency mapping for {area}")


def include_dependents(found, manifest):
    found = set(found)
    previous = set()
    while previous != found:
        previous = found.copy()
        for area in previous:
            found.update(manifest["areas"][area].get("dependents", []))
    return found


def affected_areas(paths, manifest):
    """None means unknown baseline: full coverage. Only explicit docs may skip."""
    all_areas = set(manifest["areas"])
    if paths is None:
        return all_areas, True, True, "No verified comparison base; full coverage"
    if not paths or all(matches(p, manifest["docsOnlyPaths"]) for p in paths):
        return set(), False, False, "Only documentation/resources outside the app changed"
    found = set()
    contracts = any(matches(path, manifest.get("contractPaths", ["Packages/**", ".github/**"]))
                    for path in paths)
    for path in paths:
        if matches(path, manifest["docsOnlyPaths"]):
            continue
        if matches(path, manifest["fullCoveragePaths"]):
            return all_areas, True, contracts, f"Shared infrastructure: {path}"
        owners = {area for area, config in manifest["areas"].items()
                  if matches(path, config["sources"])}
        if not owners:
            return all_areas, True, True, f"Unmapped change: {path}"
        found.update(owners)
    # Traverse to a fixed point so transitive shared dependencies cannot be missed.
    return include_dependents(found, manifest), True, contracts, "Affected areas and their dependents"


def make_plan(manifest, paths, mode="changed", durations=None, areas=None, tests=None, platforms=None):
    durations = durations or {}
    affected, app, contracts, reason = affected_areas(paths, manifest)
    if mode in ("full", "compatibility"):
        affected, app, contracts = set(manifest["areas"]), True, True
        reason = f"Explicit {mode} verification"
    elif mode == "smoke":
        affected, app, contracts, reason = set(), True, False, "Explicit smoke verification"
    elif mode == "diagnostic":
        known = {test["id"]: test for test in manifest["tests"]}
        if not tests or not set(tests) <= set(known):
            raise ValueError("Diagnostic mode requires exact, known UI test identifiers")
        platforms = list(PLATFORMS) if platforms is None else platforms
        if not platforms or not set(platforms) <= set(PLATFORMS):
            raise ValueError("Diagnostic mode requires known, nonempty platforms")
        if any(not set(known[test]["platforms"]) & set(platforms) for test in tests):
            raise ValueError("A selected test is unsupported on every requested platform")
        platforms = [platform for platform in PLATFORMS if platform in platforms]
        affected = {known[test]["area"] for test in tests}
        app, contracts, reason = True, False, "Diagnostic selection only; not full regression or release verification"
    elif mode != "changed":
        raise ValueError(f"Unknown mode: {mode}")
    if mode != "diagnostic" and (tests is not None or platforms is not None):
        raise ValueError("Test and platform filters require diagnostic mode")
    if areas is not None:
        if mode != "changed":
            raise ValueError("Manual areas require changed mode; full verification cannot be narrowed")
        if not set(areas) <= set(manifest["areas"]) or not areas:
            raise ValueError("Manual area selection must name known, nonempty areas")
        affected, app, contracts, reason = include_dependents(areas, manifest), True, True, "Manual area verification"
    workers = []
    for platform in (platforms if mode == "diagnostic" else PLATFORMS):
        selected = [t["id"] for t in manifest["tests"] if app and platform in t["platforms"]
                    and ((t["id"] in tests) if mode == "diagnostic" else
                         (t["smoke"] or (t["compatibility"] if mode == "compatibility" else t["area"] in affected)))]
        if not selected:
            continue
        cost = lambda test: durations.get(platform + "/" + test, 60)
        count = 1 if platform == "macOS" else min(2, max(1, int(sum(map(cost, selected)) > 600) + 1))
        buckets = [{"tests": [], "estimatedSeconds": 0} for _ in range(count)]
        for test in sorted(selected, key=lambda test: (-cost(test), test)):
            bucket = min(buckets, key=lambda b: b["estimatedSeconds"])
            bucket["tests"].append("shopwareUITests/" + test)
            bucket["estimatedSeconds"] += cost(test)
        for i, bucket in enumerate(buckets, 1):
            workers.append({"id": f"{platform}-{i}", "platform": platform,
                            "build": "macOS" if platform == "macOS" else "iOS",
                            "tests": sorted(bucket["tests"]),
                            "estimatedSeconds": round(bucket["estimatedSeconds"], 1)})
    return {"version": 1, "mode": mode, "app": app, "contracts": contracts,
            "areas": sorted(affected), "reason": reason, "changedPaths": paths,
            "builds": [family for family in ["macOS", "iOS"] if any(w["build"] == family for w in workers)], "workers": workers,
            "testPlatformCount": sum(len(w["tests"]) for w in workers)}


def git(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=ROOT).decode().strip()


def changed_paths(event, head):
    """Only successful automatic main runs advance the main comparison base."""
    try:
        if "pull_request" in event:
            base = git("merge-base", head, event["pull_request"]["base"]["sha"])
        elif os.environ.get("GITHUB_REF") == "refs/heads/main":
            runs = json.loads(subprocess.check_output([
                "gh", "api", f"repos/{os.environ['GITHUB_REPOSITORY']}/actions/workflows/tests.yml/runs",
                "--method", "GET", "-f", "branch=main", "-f", "event=push",
                "-f", "status=success", "-f", "per_page=100"], text=True))["workflow_runs"]
            base = None
            for run in runs:
                sha = run["head_sha"]
                if sha != head and subprocess.run(["git", "merge-base", "--is-ancestor", sha, head],
                                                   cwd=ROOT, capture_output=True).returncode == 0:
                    base = sha
                    break
            if base is None:
                return None
        else:
            return None
        data = subprocess.check_output(["git", "diff", "--no-renames", "--name-only", "-z", base, head], cwd=ROOT)
        return [p.decode() for p in data.split(b"\0") if p]
    except (subprocess.CalledProcessError, KeyError, ValueError):
        # API permissions, shallow histories and missing bases must expand coverage.
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["changed", "full", "smoke", "compatibility", "diagnostic"], default="changed")
    parser.add_argument("--paths", type=Path, help="JSON path list for reproducible local selection")
    parser.add_argument("--areas", help="Comma-separated areas for explicit manual verification")
    parser.add_argument("--tests", help="Comma-separated exact Class/testMethod identifiers; diagnostic mode only")
    parser.add_argument("--platforms", help="Comma-separated macOS/iPhone/iPad platforms; diagnostic mode only")
    parser.add_argument("--output", type=Path, default=Path("ci-plan.json"))
    args = parser.parse_args()
    if args.mode == "diagnostic" and os.environ.get("GITHUB_EVENT_NAME", "workflow_dispatch") != "workflow_dispatch":
        raise ValueError("Diagnostic selection is only available through manual dispatch")
    manifest = read_manifest()
    validate_manifest(manifest)
    event_file = os.environ.get("GITHUB_EVENT_PATH")
    event = json.loads(Path(event_file).read_text()) if event_file else {}
    head = git("rev-parse", "HEAD")
    paths = json.loads(args.paths.read_text()) if args.paths else changed_paths(event, head)
    durations = json.loads((CONFIG / "durations.json").read_text())["seconds"]
    split = lambda value: [entry.strip() for entry in value.split(",")] if value else None
    plan = make_plan(manifest, paths, args.mode, durations, split(args.areas), split(args.tests), split(args.platforms))
    plan["sha"] = head
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(plan, indent=2) + "\n")
    if os.environ.get("GITHUB_OUTPUT"):
        matrix = {"include": [{k: w[k] for k in ["id", "platform", "build"]} for w in plan["workers"]]}
        build_matrix = {"include": [{"family": family, "platform": "macOS" if family == "macOS" else "iPhone"}
                                     for family in plan["builds"]]}
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            for key, value in {"app": plan["app"], "contracts": plan["contracts"], "matrix": matrix,
                               "build-matrix": build_matrix}.items():
                output.write(f"{key}={json.dumps(value, separators=(',', ':'))}\n")
    print(f"{plan['reason']}: {plan['testPlatformCount']} test/platform combinations, "
          f"{len(plan['workers'])} UI workers, areas={plan['areas']}")


if __name__ == "__main__":
    main()
