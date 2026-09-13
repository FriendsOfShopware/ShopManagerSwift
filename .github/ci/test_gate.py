import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from gate import evaluate
from planning import make_plan, read_manifest
from products import verify_products
from release_gate import verify_release


class ReleaseTests(unittest.TestCase):
    def test_exact_full_and_minimum_results_allow_signing(self):
        verify_release("head", "head", "full", "head", "compatibility")

    def test_stale_missing_and_partial_verification_cannot_sign(self):
        for full_sha, mode, minimum_sha, minimum_mode in [
            ("old", "full", "head", "compatibility"),
            ("head", "full", "old", "compatibility"),
            (None, "full", "head", "compatibility"),
            ("head", "smoke", "head", "compatibility"),
            ("head", "changed", "head", "compatibility"),
            ("head", "diagnostic", "head", "compatibility"),
            ("head", "full", "head", "smoke"),
            ("head", "full", "head", "diagnostic"),
        ]:
            with self.assertRaises(ValueError):
                verify_release("head", full_sha, mode, minimum_sha, minimum_mode)


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

    def test_diagnostic_gate_requires_only_selected_build_but_every_selected_test(self):
        plan = make_plan(read_manifest(), None, "diagnostic",
                         tests=["ProductUITests/testCreateProductWithTaxAndPrice"], platforms=["iPad"])
        plan["sha"] = self.plan["sha"]
        reports = [copy.deepcopy(r) for r in self.reports if r["id"] in {"iPad-1", "unit-iOS"}]
        ui = next(r for r in reports if r["id"] == "iPad-1")
        ui["expected"] = plan["workers"][0]["tests"]
        ui["attempts"][0]["cases"] = {test: {"result": "Passed"} for test in ui["expected"]}
        evaluate(plan, self.needs, reports)
        with self.assertRaises(ValueError):
            evaluate(plan, self.needs, [ui])

    def test_normal_gate_cannot_drop_a_platform_build(self):
        self.plan["builds"] = ["iOS"]
        with self.assertRaisesRegex(ValueError, "Only diagnostic"):
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
