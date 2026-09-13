import unittest

from metrics import collect, comparison, package_count


class MetricsTests(unittest.TestCase):
    def test_swift_testing_counts_do_not_confuse_xctest_zero_tests_with_success(self):
        self.assertIsNone(package_count("Executed 0 tests, with 0 failures"))
        self.assertIsNone(package_count("Test run with 0 tests passed"))
        self.assertIsNone(package_count("Test run with 3 tests in 1 suite failed"))
        self.assertEqual(package_count("Executed 0 tests\n✔ Test run with 52 tests in 8 suites passed"), 52)
        self.assertEqual(package_count("✔ Test run with 3 tests in 1 suite passed"), 3)

    def test_queue_execution_and_first_attempt_failures_remain_distinct(self):
        run = {"id": 1, "head_sha": "head", "conclusion": "success", "html_url": "https://example.invalid/run",
               "event": "push", "created_at": "2026-09-13T00:00:00Z"}
        job = {"name": "UI", "conclusion": "success", "created_at": "2026-09-13T00:01:00Z",
               "started_at": "2026-09-13T00:03:00Z", "completed_at": "2026-09-13T00:05:00Z",
               "labels": ["xcode-27"], "steps": []}
        report = {"platform": "iPhone", "expected": ["shopwareUITests/Suite/testOne"], "retryCount": 1,
                  "attempts": [
                      {"number": 1, "seconds": 40, "cases": {"shopwareUITests/Suite/testOne": {
                          "result": "Failed", "seconds": 20, "failures": ["Failed to boot the simulator"]}}},
                      {"number": 2, "seconds": 30, "cases": {"shopwareUITests/Suite/testOne": {
                          "result": "Passed", "seconds": 20, "failures": []}}},
                  ]}
        value = collect(run, [job], [{"size_in_bytes": 100}], {"mode": "smoke", "testPlatformCount": 1},
                        [report], [{"buildSeconds": 10, "discoverySeconds": 2,
                                    "environment": {"xcode": "Xcode 27.0\nBuild version 27A5252f"}}])
        self.assertEqual(value["wallMinutes"], 5)
        self.assertEqual(value["runnerMinutes"], 2)
        self.assertEqual(value["queueSeconds"]["max"], 120)
        self.assertEqual(value["executionOverheadSeconds"], 30)
        self.assertEqual(value["expectedTests"], 1)
        self.assertEqual(value["testExecutions"], 2)
        self.assertEqual(len(value["firstAttemptFailures"]), 1)
        self.assertEqual(value["retryCount"], 1)
        self.assertEqual(value["toolchains"], ["Xcode 27.0 / Build version 27A5252f"])

    def test_comparison_keeps_full_and_selective_runs_separate(self):
        values = [{"mode": "full", "uiTestPlatformCount": 162, "conclusion": "success",
                   "wallMinutes": n, "runnerMinutes": n * 2} for n in range(1, 11)]
        values.append({"mode": "changed", "uiTestPlatformCount": 52, "conclusion": "success",
                       "wallMinutes": 2, "runnerMinutes": 4})
        text = comparison(values)
        self.assertIn("full / 162 / success / unknown toolchain / no areas | 10 | 5.5 min | 10.0 min | 11.0", text)
        self.assertIn("changed / 52 / success / unknown toolchain / no areas | 1 | 2.0 min", text)

    def test_comparison_does_not_mix_toolchains_or_different_affected_areas(self):
        base = {"mode": "changed", "uiTestPlatformCount": 52, "conclusion": "success",
                "wallMinutes": 10, "runnerMinutes": 20, "toolchains": ["Xcode 27"], "areas": ["products"]}
        text = comparison([base, {**base, "toolchains": ["Xcode 26"]}, {**base, "areas": ["customers"]}])
        self.assertIn("Xcode 26 / products | 1 |", text)
        self.assertIn("Xcode 27 / products | 1 |", text)
        self.assertIn("Xcode 27 / customers | 1 |", text)


if __name__ == "__main__":
    unittest.main()
