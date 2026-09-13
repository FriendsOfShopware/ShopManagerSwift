"""Validate Xcode inventories and report exact test execution, including retries."""

import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time


def identifier(value):
    return re.sub(r"\(\)$", "", value)


def inventory_ids(inventory):
    if inventory.get("errors"):
        raise ValueError(f"Xcode discovery errors: {inventory['errors']}")
    found = [identifier(test["identifier"]) for group in inventory.get("values", [])
             for test in group.get("enabledTests", [])]
    if not found or len(found) != len(set(found)):
        raise ValueError("Empty or duplicate Xcode test discovery")
    return set(found)


def verify_inventory(inventory, manifest, platform):
    found = inventory_ids(inventory)
    expected = {"shopwareUITests/" + entry["id"] for entry in manifest["tests"]
                if platform in entry["platforms"]}
    actual = {name for name in found if name.startswith("shopwareUITests/")}
    if actual != expected:
        raise ValueError(f"Compiled UI coverage mismatch: missing={sorted(expected - actual)}, "
                         f"unassigned={sorted(actual - expected)}")
    if not any(name.startswith("shopwareTests/") for name in found):
        raise ValueError("The shared product contains no app unit tests")
    return found


def walk(nodes):
    for node in nodes:
        yield node
        yield from walk(node.get("children", []))


RUNNER_BOOTSTRAP_ERROR = "test runner crashed while preparing to run tests"


def test_cases(report, target):
    cases = {}
    for node in walk(report.get("testNodes", [])):
        if node.get("nodeType") != "Test Case":
            continue
        url = node.get("nodeIdentifierURL", "")
        if url and f"/{target}/" not in url:
            continue
        name = identifier(node["nodeIdentifier"])
        if name.count("/") < 2 or not name.startswith(target + "/"):
            name = target + "/" + name
        if name in cases:
            raise ValueError(f"Unexpected repeated test case: {name}")
        case = {"result": node.get("result"),
                "seconds": node.get("durationInSeconds", 0),
                "failures": [child["name"] for child in walk(node.get("children", []))
                             if child.get("nodeType") == "Failure Message"]}
        # XCTest represents a pre-test runner crash as a synthetic test node.
        # Keep it in the raw tree/summary, but don't confuse it with a test ID.
        if (re.fullmatch(rf"{re.escape(target)}/{re.escape(target)}-Runner \(\d+\) encountered an error", name)
                and case["result"] == "Failed" and is_infrastructure_failure(case["failures"])
                and all(RUNNER_BOOTSTRAP_ERROR in message.lower() for message in case["failures"])):
            continue
        cases[name] = case
    return cases


# Restrict retries to identifiable simulator/runner launch failures. Assertion
# failures and app-idle timeouts can be product defects and must remain failures.
INFRASTRUCTURE_ERRORS = (
    "timed out while acquiring background assertion",
    "failed to establish communication with the test runner",
    "test runner failed to initialize",
    "failed to boot the simulator",
    "timed out while loading accessibility",
    RUNNER_BOOTSTRAP_ERROR,
)

# CoreSimulator can report a successful boot before Xcode's destination service
# sees the device. This is eligible only before any test has executed.
SETUP_ERRORS = INFRASTRUCTURE_ERRORS + (
    "unable to find a device matching the provided destination specifier",
)


def is_infrastructure_failure(messages):
    return bool(messages) and all(
        not re.search(r"XCTAssert|#expect|Expectation failed|Assertion Failure", message)
        and any(pattern in message.lower() for pattern in INFRASTRUCTURE_ERRORS)
        for message in messages)


def retry_selection(cases, expected, log):
    failed = {name: case for name, case in cases.items() if case["result"] != "Passed"}
    if failed and all(case["result"] == "Failed" and is_infrastructure_failure(case["failures"])
                      for case in failed.values()):
        return sorted(failed)
    if not cases and any(pattern in log.lower() for pattern in SETUP_ERRORS):
        # A process that never launched has no per-test identifier. No test has
        # executed, so this is still a single setup retry, not a suite repetition.
        if not re.search(r"XCTAssert|#expect|Expectation failed|Assertion Failure", log):
            return sorted(expected)
    return []


def verify_execution(expected, attempts):
    final = {}
    for attempt in attempts:
        final.update(attempt["cases"])
    actual = set(final)
    if actual != set(expected):
        raise ValueError(f"Executed test mismatch: missing={sorted(set(expected) - actual)}, "
                         f"unexpected={sorted(actual - set(expected))}")
    failed = [name for name, case in final.items() if case["result"] != "Passed"]
    if not actual or failed:
        raise ValueError(f"Tests did not pass: {failed or 'zero tests'}")
    # An infrastructure error outside a test can leave a passing test tree but
    # still make xcodebuild fail. Never reinterpret that exit status as success.
    if attempts[-1]["exitCode"] != 0:
        raise ValueError(f"xcodebuild exited {attempts[-1]['exitCode']} despite its test tree")
    return final


def command(arguments, log_path, timeout=None):
    """Stream to a log without a shell or buffering all compiler output in RAM."""
    start = time.time()
    log_path = Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    print("Running:", " ".join(map(str, arguments)), flush=True)
    with log_path.open("w") as log:
        process = subprocess.Popen(list(map(str, arguments)), stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=timeout is not None)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            log.write(f"\nCommand exceeded {timeout} seconds; terminated its process group.\n")
            code = 124
        except BaseException:
            if timeout is not None and process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise
    print(f"Finished in {time.time() - start:.1f}s (exit {code}); log: {log_path}", flush=True)
    return code, start, time.time()


def result_json(bundle, kind, output):
    data = json.loads(subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(bundle), "--compact"], text=True))
    Path(output).write_text(json.dumps(data, indent=2) + "\n")
    return data
