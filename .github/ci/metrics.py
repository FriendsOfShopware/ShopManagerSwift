"""Collect complete-run timing and test evidence; compare like-for-like cohorts."""

import argparse
from datetime import datetime
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess


def timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def api(path, paginate=False):
    args = ["gh", "api", path]
    if paginate:
        args += ["--paginate", "--slurp"]
    return json.loads(subprocess.check_output(args, text=True))


def collect(run, jobs, artifacts, plan, reports, builds):
    executed = [job for job in jobs if job.get("started_at") and job.get("completed_at")
                and job["conclusion"] != "skipped"]
    end = max([timestamp(job["completed_at"]) for job in executed] or [timestamp(run["created_at"])])
    first_failures, retries, attempts, expected, cases = [], 0, 0, 0, []
    for report in reports:
        expected += len(report["expected"])
        retries += report["retryCount"]
        for attempt in report["attempts"]:
            attempts += len(attempt["cases"])
            for test, case in attempt["cases"].items():
                cases.append({"platform": report["platform"], "test": test, **case})
                if attempt["number"] == 1 and case["result"] != "Passed":
                    first_failures.append({"platform": report["platform"], "test": test, "failures": case["failures"]})
    queue = [max(0, timestamp(j["started_at"]) - timestamp(j["created_at"])) for j in executed if j.get("created_at")]
    return {
        "version": 1, "runId": run["id"], "sha": run["head_sha"], "conclusion": run["conclusion"],
        "url": run["html_url"], "event": run["event"], "mode": plan.get("mode", "unknown"),
        "uiTestPlatformCount": plan.get("testPlatformCount"), "areas": plan.get("areas", []),
        "wallMinutes": (end - timestamp(run["created_at"])) / 60,
        "runnerMinutes": sum(timestamp(j["completed_at"]) - timestamp(j["started_at"]) for j in executed) / 60,
        "queueSeconds": {"median": statistics.median(queue) if queue else None, "max": max(queue) if queue else None},
        "buildCount": len(builds), "buildSeconds": sum(b["buildSeconds"] for b in builds),
        "discoverySeconds": sum(b["discoverySeconds"] for b in builds),
        "discoveryRetryCount": sum(max(0, len(b.get("discoveryAttempts", [])) - 1) for b in builds),
        "discoveryFailures": [a["error"] for b in builds for a in b.get("discoveryAttempts", []) if a.get("error")],
        "expectedTests": expected, "testExecutions": attempts, "retryCount": retries,
        "firstAttemptFailures": first_failures, "cases": cases,
        "executionOverheadSeconds": sum(max(0, a["seconds"] - sum(c["seconds"] for c in a["cases"].values()))
                                         for r in reports for a in r["attempts"]),
        "artifactBytes": sum(a["size_in_bytes"] for a in artifacts),
        "jobs": [{"name": j["name"], "conclusion": j["conclusion"], "labels": j["labels"],
                  "createdAt": j.get("created_at"), "startedAt": j["started_at"], "finishedAt": j["completed_at"],
                  "steps": j["steps"]} for j in jobs],
    }


def comparison(records):
    cohorts = {}
    for record in records:
        key = (record["mode"], record["uiTestPlatformCount"], record["conclusion"])
        cohorts.setdefault(key, []).append(record)
    text = "| Scope / UI pairs / result | Runs | Median wall | P95 wall | Median runner minutes |\n| --- | ---: | ---: | ---: | ---: |\n"
    for key, values in sorted(cohorts.items(), key=lambda item: str(item[0])):
        wall = sorted(r["wallMinutes"] for r in values)
        p95 = wall[math.ceil(len(wall) * .95) - 1]
        text += (f"| {' / '.join(map(str, key))} | {len(wall)} | {statistics.median(wall):.1f} min | "
                 f"{p95:.1f} min | {statistics.median(r['runnerMinutes'] for r in values):.1f} |\n")
    return text + "\nCohorts with fewer than ten runs are provisional. Runner time is not a billing estimate.\n"


def package_count(log):
    matches = re.findall(r"Test run with ([1-9][0-9]*) tests?(?: in .*? suites?)? passed", log)
    return int(matches[-1]) if matches else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--output", type=Path, default=Path("metrics.json"))
    parser.add_argument("--compare", type=Path, help="Directory of previously downloaded metrics JSON files")
    parser.add_argument("--update-durations", type=Path, help="Write a candidate durations.json from measured UI tests")
    args = parser.parse_args()
    if args.compare:
        records = [json.loads(p.read_text()) for p in args.compare.glob("**/metrics.json")]
        print(comparison(records))
        return
    repository = os.environ["GITHUB_REPOSITORY"]
    prefix = f"repos/{repository}/actions/runs/{args.run_id}"
    run = api(prefix)
    jobs = [j for page in api(prefix + "/jobs?filter=all&per_page=100", True) for j in page["jobs"]]
    artifacts = [a for page in api(prefix + "/artifacts?per_page=100", True) for a in page["artifacts"]]
    plans = list(args.evidence.glob("**/ci-plan.json"))
    plan = json.loads(plans[0].read_text()) if len(plans) == 1 else {}
    reports = [json.loads(p.read_text()) for p in args.evidence.glob("**/report-*.json")]
    builds = [json.loads(p.read_text()) for p in args.evidence.glob("**/metadata.json")]
    record = collect(run, jobs, artifacts, plan, reports, builds)
    record["packageTests"] = {str(p.relative_to(args.evidence)): package_count(p.read_text())
                              for p in args.evidence.glob("**/*.log")
                              if p.name in ["api.log", "domain.log", "tests.log"]}
    args.output.write_text(json.dumps(record, indent=2) + "\n")
    if args.update_durations:
        durations = {}
        for case in record["cases"]:
            if case["test"].startswith("shopwareUITests/") and case["result"] == "Passed":
                key = case["platform"] + "/" + case["test"].removeprefix("shopwareUITests/")
                durations.setdefault(key, []).append(case["seconds"])
        args.update_durations.write_text(json.dumps({"sourceRun": run["id"], "seconds": {
            key: round(statistics.median(values), 2) for key, values in sorted(durations.items())}}, indent=2) + "\n")
    text = (f"## CI timing\n\n[{run['id']}]({run['html_url']}): `{run['head_sha']}`\n\n"
            f"{record['wallMinutes']:.1f} min wall; {record['runnerMinutes']:.1f} runner-minutes; "
            f"{record['buildCount']} app builds; {record['artifactBytes'] / 1024**2:.1f} MiB artifacts.\n\n"
            f"{record['expectedTests']} expected app tests, {record['testExecutions']} executions, "
            f"{len(record['firstAttemptFailures'])} first-attempt failures, {record['retryCount']} retries.\n\n"
            "Baseline full run: 68.8 min wall, 282.9 runner-minutes, 24 app builds, 162 UI pairs. "
            "Compare full and affected-area runs separately.\n\n" + comparison([record]))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
            output.write(text)
    print(text)


if __name__ == "__main__":
    main()
