from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys
import time

from prepare import install_runtime, runtime_images
from results import command, is_infrastructure_failure


class RuntimeTests(unittest.TestCase):
    def test_hung_discovery_commands_are_terminated_and_leave_a_log(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "discovery.log"
            start = time.monotonic()
            code, _, _ = command([sys.executable, "-c", "import time; time.sleep(60)"], log, timeout=.1)
            self.assertEqual(code, 124)
            self.assertLess(time.monotonic() - start, 5)
            self.assertIn("terminated its process group", log.read_text())

    def test_accessibility_startup_error_is_not_confused_with_an_assertion(self):
        self.assertTrue(is_infrastructure_failure(["Timed out while loading Accessibility."]))
        self.assertFalse(is_infrastructure_failure(["XCTAssertEqual failed: Timed out while loading Accessibility."]))

    @patch("prepare.subprocess.run")
    def test_new_download_is_imported_before_using_the_simulator(self, run):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            def download(command, **kwargs):
                if "-downloadPlatform" in command:
                    (path / "iOS 26.dmg").touch()
            run.side_effect = download
            install_runtime(path, "26.0")
            self.assertIn("26.0", run.call_args_list[0].args[0])
            self.assertEqual(run.call_args_list[1].args[0], ["xcodebuild", "-importPlatform", str(path / "iOS 26.dmg")])

    @patch("prepare.subprocess.run")
    def test_cached_asset_bundle_is_imported_without_redownloading(self, run):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            bundle = path / "iOS.exportedBundle"
            bundle.mkdir()
            (bundle / "internal.dmg").touch()
            self.assertEqual(runtime_images(path), [bundle])
            install_runtime(path, "26.0")
            run.assert_called_once_with(["xcodebuild", "-importPlatform", str(bundle)], check=True)

    @patch("prepare.subprocess.run")
    def test_missing_export_does_not_silently_choose_a_newer_os(self, run):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "did not export"):
                install_runtime(Path(directory), "26.0")


if __name__ == "__main__":
    unittest.main()
