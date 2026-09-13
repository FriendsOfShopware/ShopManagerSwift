"""Execute a precise test selection from a shared product, with bounded infra retry."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import time

from products import verify_products
from results import command, inventory_ids, result_json, retry_selection, test_cases, verify_execution


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", type=Path, required=True)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--worker", required=True, help="Worker ID or unit-macOS/unit-iOS")
    parser.add_argument("--destination", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--visual", action="store_true")
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text())
    unit = args.worker.startswith("unit-")
    if unit:
        family = args.worker.removeprefix("unit-")
        platform = "macOS" if family == "macOS" else "iPhone"
        target = "shopwareTests"
    else:
        worker = next(w for w in plan["workers"] if w["id"] == args.worker)
        family, platform, target = worker["build"], worker["platform"], "shopwareUITests"
    metadata, inventory = verify_products(args.products, plan["sha"], family)
    available = inventory_ids(inventory)
    selected = sorted(name for name in available if name.startswith(target + "/")) if unit else worker["tests"]
    if not selected or not set(selected) <= available:
        raise ValueError("Selection is empty or contains tests missing from the build")
    directory = args.output.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    attempts = []
    report = {"version": 1, "id": args.worker, "sha": plan["sha"], "platform": platform,
              "expected": selected, "environment": metadata["environment"], "passed": False,
              "startedAt": time.time(), "attempts": attempts}
    pending = selected
    try:
        for number in range(1, 3):
            bundle = directory / f"attempt-{number}.xcresult"
            log = directory / f"attempt-{number}.log"
            code, start, end = command([
                "xcodebuild", "test-without-building", "-testProductsPath", args.products / "Tests.xctestproducts",
                "-destination", args.destination, "-resultBundlePath", bundle,
                "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "300",
                "-maximum-test-execution-time-allowance", "300", "-parallel-testing-enabled", "NO",
                "-collect-test-diagnostics", "never",
                # Swift Testing method filters differ from XCTest filters. Units
                # intentionally run their whole target; discovery still supplies
                # the exact expected IDs for the result check below.
                *["-only-testing:" + test for test in ([target] if unit else pending)]], log)
            cases, summary = {}, {}
            if (bundle / "Info.plist").is_file():
                summary = result_json(bundle, "summary", directory / f"summary-{number}.json")
                tree = result_json(bundle, "tests", directory / f"tests-{number}.json")
                cases = test_cases(tree, target)
            attempt = {"number": number, "selected": pending, "exitCode": code,
                       "startedAt": start, "finishedAt": end, "seconds": end - start,
                       "cases": cases, "summary": summary}
            attempts.append(attempt)
            if args.visual or code:
                if (bundle / "Info.plist").is_file():
                    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                                    "--output-path", str(directory / f"attachments-{number}")], check=False)
            if code == 0:
                break
            pending = retry_selection(cases, selected, log.read_text()) if number == 1 and not unit else []
            if not pending:
                break
            print(f"Retrying infrastructure failure for {len(pending)} selected test(s): {pending}", flush=True)
        final = verify_execution(selected, attempts)
        report["passed"] = True
        report["testSeconds"] = sum(case["seconds"] for case in final.values())
    finally:
        report["finishedAt"] = time.time()
        report["retryCount"] = max(0, len(attempts) - 1)
        report_path = directory / f"report-{args.worker}.json"
        report_path.write_text(json.dumps(report, indent=2) + "\n")
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
                output.write(f"### {args.worker}\n\n"
                             f"{len(selected)} expected tests; {len(attempts)} attempt(s); "
                             f"result: {'passed' if report['passed'] else 'failed'}.\n")
        # Keep result bundles for any retry, failure or deliberate visual run.
        # Successful routine uploads select only JSON and log files in the YAML.
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                output.write(f"diagnostics={str(args.visual or not report['passed'] or len(attempts) > 1).lower()}\n")


if __name__ == "__main__":
    main()
