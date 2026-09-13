import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from planning import affected_areas, changed_paths, make_plan, read_manifest, validate_manifest
from results import inventory_ids, retry_selection, test_cases, verify_execution, verify_inventory


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.manifest = read_manifest()

    def test_current_sources_have_explicit_ownership(self):
        validate_manifest(self.manifest)

    def test_full_plan_preserves_all_test_platform_pairs_exactly_once(self):
        plan = make_plan(self.manifest, [], "full")
        expected = {(p, "shopwareUITests/" + t["id"]) for t in self.manifest["tests"] for p in t["platforms"]}
        actual = [(w["platform"], t) for w in plan["workers"] for t in w["tests"]]
        self.assertEqual(set(actual), expected)
        self.assertEqual(len(actual), len(expected))
        self.assertLessEqual(len(plan["workers"]), 5)
        self.assertEqual(plan["builds"], ["macOS", "iOS"])

    def test_product_change_adds_area_to_smoke_on_every_platform(self):
        plan = make_plan(self.manifest, ["shopware/UI/Screens/ProductEditorSheet.swift"])
        self.assertEqual(plan["areas"], ["products"])
        for worker in plan["workers"]:
            for name in worker["tests"]:
                entry = next(t for t in self.manifest["tests"] if name == "shopwareUITests/" + t["id"])
                self.assertTrue(entry["smoke"] or entry["area"] == "products")
        self.assertEqual({w["platform"] for w in plan["workers"]}, {"macOS", "iPhone", "iPad"})

    def test_dependency_expansion_is_transitive(self):
        self.manifest["areas"]["products"]["dependents"] = ["media"]
        self.manifest["areas"]["media"]["dependents"] = ["reviews"]
        areas, *_ = affected_areas(["shopware/Data/ProductPriceDraft.swift"], self.manifest)
        self.assertEqual(areas, {"products", "media", "reviews"})

    def test_unknown_files_and_missing_base_expand_coverage(self):
        for paths in [None, ["shopware/UI/NewSharedEditor.swift"], ["shopware.xcodeproj/project.pbxproj"]]:
            with self.subTest(paths=paths):
                plan = make_plan(self.manifest, paths)
                self.assertEqual(set(plan["areas"]), set(self.manifest["areas"]))
                self.assertTrue(plan["app"])

    def test_documentation_has_an_explicit_skip_but_source_wins(self):
        for path in ["TESTING.md", "docs/contributing.md"]:
            self.assertFalse(make_plan(self.manifest, [path])["app"])
        self.assertTrue(make_plan(self.manifest, ["TESTING.md", "shopware/Unknown.swift"])["app"])

    def test_contract_impact_is_independent_of_changed_path_order(self):
        paths = ["shopware/Data/ListingState.swift", "Packages/ShopwareAdminAPI/Sources/Criteria.swift"]
        for values in [paths, paths[::-1]]:
            self.assertTrue(make_plan(self.manifest, values)["contracts"])

    def test_smoke_does_not_become_full_without_a_baseline(self):
        plan = make_plan(self.manifest, None, "smoke")
        self.assertEqual(plan["areas"], [])
        self.assertTrue(plan["app"])
        self.assertTrue(all(next(t for t in self.manifest["tests"] if "shopwareUITests/" + t["id"] == name)["smoke"]
                            for w in plan["workers"] for name in w["tests"]))

    def test_compatibility_contains_smoke_and_compatibility_only(self):
        plan = make_plan(self.manifest, [], "compatibility")
        self.assertTrue(all(next(t for t in self.manifest["tests"] if "shopwareUITests/" + t["id"] == name)["compatibility"]
                            or next(t for t in self.manifest["tests"] if "shopwareUITests/" + t["id"] == name)["smoke"]
                            for w in plan["workers"] for name in w["tests"]))

    def test_manual_selection_rejects_unknown_area(self):
        with self.assertRaises(ValueError):
            make_plan(self.manifest, [], areas=["misspelled-area"])

    def test_large_durations_never_create_unbounded_workers(self):
        costs = {p + "/" + t["id"]: 900 for t in self.manifest["tests"] for p in t["platforms"]}
        plan = make_plan(self.manifest, None, durations=costs)
        self.assertEqual(len(plan["workers"]), 5)
        for platform in ["iPhone", "iPad"]:
            loads = [w["estimatedSeconds"] for w in plan["workers"] if w["platform"] == platform]
            self.assertLessEqual(max(loads) - min(loads), 900)

    def test_unassigned_source_test_is_a_hard_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "shopwareUITests").mkdir()
            (root / "shopwareUITests/NewTests.swift").write_text("final class NewTests: XCTestCase { func testMissing() {} }")
            with self.assertRaisesRegex(ValueError, "Unassigned tests"):
                validate_manifest(self.manifest, root)

    @patch("planning.git", return_value="base")
    @patch("planning.subprocess.check_output", return_value=b"old.swift\0new.swift\0")
    def test_diff_includes_both_sides_of_a_rename(self, output, git):
        self.assertEqual(changed_paths({"pull_request": {"base": {"sha": "base"}}}, "head"), ["old.swift", "new.swift"])
        self.assertIn("--no-renames", output.call_args.args[0])

    @patch("planning.git", side_effect=ValueError("missing history"))
    def test_unavailable_comparison_base_does_not_skip(self, git):
        self.assertIsNone(changed_paths({"pull_request": {"base": {"sha": "missing"}}}, "head"))


class ResultTests(unittest.TestCase):
    def test_empty_or_error_discovery_fails(self):
        for value in [{}, {"errors": ["test runner unavailable"]}, {"values": [{"enabledTests": []}]}]:
            with self.assertRaises(ValueError):
                inventory_ids(value)

    def test_platform_inventory_requires_every_compiled_ui_test(self):
        manifest = read_manifest()
        names = ["shopwareUITests/" + t["id"] + "()" for t in manifest["tests"] if "iPhone" in t["platforms"]]
        names.append("shopwareTests/SomeSuite/someUnit()")
        inventory = {"values": [{"enabledTests": [{"identifier": n} for n in names]}]}
        verify_inventory(inventory, manifest, "iPhone")
        inventory["values"][0]["enabledTests"].pop(0)
        with self.assertRaisesRegex(ValueError, "coverage mismatch"):
            verify_inventory(inventory, manifest, "iPhone")

    def test_only_infrastructure_failures_are_retried(self):
        cases = {"a": {"result": "Passed", "failures": []},
                 "b": {"result": "Failed", "failures": ["Timed out while acquiring background assertion."]}}
        self.assertEqual(retry_selection(cases, ["a", "b"], ""), ["b"])
        cases["b"]["failures"] = ["XCTAssertEqual failed: 1 is not 119"]
        self.assertEqual(retry_selection(cases, ["a", "b"], ""), [])

    def test_mixed_assertion_and_infrastructure_failure_stays_red(self):
        cases = {"a": {"result": "Failed", "failures": ["Failed to boot the simulator"]},
                 "b": {"result": "Failed", "failures": ["Expected retained draft"]}}
        self.assertEqual(retry_selection(cases, ["a", "b"], ""), [])

    def test_runner_boot_failure_without_cases_can_retry_once(self):
        self.assertEqual(retry_selection({}, ["a"], "Failed to boot the simulator"), ["a"])
        self.assertEqual(retry_selection({}, ["a"], "Failed to boot the simulator; XCTAssertFalse failed"), [])

    def test_missing_or_skipped_execution_is_never_a_pass(self):
        for cases in [{}, {"a": {"result": "Skipped"}}, {"b": {"result": "Passed"}}]:
            with self.assertRaises(ValueError):
                verify_execution(["a"], [{"cases": cases, "exitCode": 0}])

    def test_successful_targeted_retry_keeps_first_passes(self):
        attempts = [{"cases": {"a": {"result": "Passed"}, "b": {"result": "Failed"}}, "exitCode": 65},
                    {"cases": {"b": {"result": "Passed"}}, "exitCode": 0}]
        self.assertEqual(set(verify_execution(["a", "b"], attempts)), {"a", "b"})

    def test_passing_cases_cannot_override_nonzero_exit(self):
        with self.assertRaisesRegex(ValueError, "exited"):
            verify_execution(["a"], [{"cases": {"a": {"result": "Passed"}}, "exitCode": 65}])

    def test_result_reader_cannot_confuse_unit_and_ui_targets(self):
        report = {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": "Suite/foo()",
                                  "nodeIdentifierURL": "test://com.apple.xcode/project/shopwareTests/Suite/foo",
                                  "result": "Passed"}]}
        self.assertEqual(test_cases(report, "shopwareUITests"), {})
        self.assertEqual(set(test_cases(report, "shopwareTests")), {"shopwareTests/Suite/foo"})

    def test_suite_named_like_its_target_keeps_both_identifier_components(self):
        report = {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": "shopwareTests/example()",
                                  "result": "Passed"}]}
        self.assertEqual(set(test_cases(report, "shopwareTests")), {"shopwareTests/shopwareTests/example"})


if __name__ == "__main__":
    unittest.main()
