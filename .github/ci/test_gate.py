import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from gate import evaluate
from planning import make_plan, read_manifest
from products import verify_products


class GateTests(unittest.TestCase):
    def setUp(self):
        self.plan = make_plan(read_manifest(), [], "smoke")
        self.plan["sha"] = "verified-head"
        self.needs = {name: {"result": "success"} for name in ["plan", "fast", "build", "ui"]}
        self.needs["contracts"] = {"result": "skipped"}
        self.reports = []
        selections = {w["id"]: w["tests"] for w in self.plan["workers"]}
        selections.update({"unit-macOS": ["shopwareTests/Suite/one"], "unit-iOS": ["shopwareTests/Suite/one"]})
        for worker, tests in selections.items():
            self.reports.append({"id": worker, "sha": self.plan["sha"], "passed": True, "expected": tests,
                                 "attempts": [{"exitCode": 0, "cases": {test: {"result": "Passed"} for test in tests}}]})

    def test_complete_exact_plan_passes(self):
        evaluate(self.plan, self.needs, self.reports)

    def test_docs_skip_is_explicit_and_cannot_conceal_failed_planning(self):
        plan = make_plan(read_manifest(), ["TESTING.md"])
        needs = {name: {"result": "skipped"} for name in self.needs}
        needs["plan"] = {"result": "success"}
        evaluate(plan, needs, [])
        needs["plan"]["result"] = "failure"
        with self.assertRaises(ValueError):
            evaluate(plan, needs, [])

    def test_cancelled_skipped_or_missing_required_job_fails(self):
        for status in ["cancelled", "failure", "skipped"]:
            needs = copy.deepcopy(self.needs)
            needs["ui"]["result"] = status
            with self.assertRaises(ValueError):
                evaluate(self.plan, needs, self.reports)
        del self.needs["ui"]
        with self.assertRaises(ValueError):
            evaluate(self.plan, self.needs, self.reports)

    def test_missing_duplicate_wrong_commit_or_changed_selection_fails(self):
        bad = [self.reports[:-1], self.reports + self.reports[:1]]
        for key, value in [("sha", "old-head"), ("expected", []), ("passed", False)]:
            changed = copy.deepcopy(self.reports)
            changed[0][key] = value
            bad.append(changed)
        for reports in bad:
            with self.assertRaises(ValueError):
                evaluate(self.plan, self.needs, reports)

    def test_report_pass_flag_cannot_hide_failed_test_tree(self):
        report = self.reports[0]
        case = next(iter(report["attempts"][0]["cases"].values()))
        case["result"] = "Failed"
        with self.assertRaises(ValueError):
            evaluate(self.plan, self.needs, self.reports)

    def test_full_scope_cannot_skip_contracts(self):
        self.plan["contracts"] = True
        with self.assertRaises(ValueError):
            evaluate(self.plan, self.needs, self.reports)


class ProvenanceTests(unittest.TestCase):
    @patch("products.environment", return_value={"xcode": "new-toolchain"})
    def test_wrong_commit_platform_and_toolchain_are_rejected(self, environment):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "metadata.json").write_text(json.dumps({"sha": "head", "family": "iOS",
                                                          "environment": {"xcode": "old-toolchain"}}))
            for sha, family in [("old-head", "iOS"), ("head", "macOS"), ("head", "iOS")]:
                with self.assertRaises(ValueError):
                    verify_products(path, sha, family)


if __name__ == "__main__":
    unittest.main()
