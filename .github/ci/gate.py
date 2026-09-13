"""A stable required check: expected jobs and test selections must all complete."""

import argparse
import json
import os
from pathlib import Path
import subprocess


def evaluate(plan, needs, reports):
    required = {"plan"}
    if plan["app"]:
        required.update(["fast", "build", "ui"])
    if plan["contracts"]:
        required.add("contracts")
    for name, job in needs.items():
        expected = "success" if name in required else "skipped"
        if job["result"] != expected:
            raise ValueError(f"{name}: expected {expected}, got {job['result']}")
    if required - set(needs):
        raise ValueError(f"Missing required jobs: {sorted(required - set(needs))}")
    expected_ids = {worker["id"] for worker in plan["workers"]}
    if plan["app"]:
        builds = set(plan["builds"])
        if not builds or not builds <= {"macOS", "iOS"}:
            raise ValueError("Invalid build selection")
        if plan["mode"] != "diagnostic" and builds != {"macOS", "iOS"}:
            raise ValueError("Only diagnostic mode can narrow platform builds")
        if builds != {worker["build"] for worker in plan["workers"]}:
            raise ValueError("Builds do not match the planned UI platforms")
        expected_ids.update("unit-" + family for family in builds)
    ids = [report["id"] for report in reports]
    if len(ids) != len(set(ids)) or set(ids) != expected_ids:
        raise ValueError(f"Worker reports mismatch: expected={sorted(expected_ids)}, actual={sorted(ids)}")
    for report in reports:
        if report["sha"] != plan["sha"] or not report["passed"] or not report["expected"]:
            raise ValueError(f"Invalid/incomplete worker report: {report['id']}")
        if not report["id"].startswith("unit-"):
            worker = next(w for w in plan["workers"] if w["id"] == report["id"])
            if set(report["expected"]) != set(worker["tests"]):
                raise ValueError(f"Worker changed its planned selection: {report['id']}")
        # Revalidate the test tree rather than trusting a report's passed flag.
        from results import verify_execution
        verify_execution(report["expected"], report["attempts"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--reports", type=Path, required=True)
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text())
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if plan["sha"] != head:
        raise ValueError("The test plan does not belong to the checked-out commit")
    reports = [json.loads(p.read_text()) for p in args.reports.glob("**/report-*.json")]
    needs = json.loads(os.environ["CI_NEEDS"])
    evaluate(plan, needs, reports)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write(f"sha={head}\nmode={plan['mode']}\n")
    text = (f"## CI verification\n\nCommit: `{plan['sha']}`\n\n"
            f"Scope: {plan['reason']}\n\n"
            f"{plan['testPlatformCount']} UI test/platform combinations, "
            f"{len(plan['builds'])} app builds.\n\n"
            "| Worker | Tests | First-attempt failures | Retries | Elapsed |\n"
            "| --- | ---: | ---: | ---: | ---: |\n")
    for report in sorted(reports, key=lambda r: r["id"]):
        first = report["attempts"][0]["cases"]
        failures = sum(case["result"] != "Passed" for case in first.values())
        text += (f"| {report['id']} | {len(report['expected'])} | {failures} | {report['retryCount']} | "
                 f"{(report['finishedAt'] - report['startedAt']) / 60:.1f} min |\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
            output.write(text)
    print(text)


if __name__ == "__main__":
    main()
