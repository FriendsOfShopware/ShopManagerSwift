from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from prepare import install_runtime, runtime_images


class RuntimeTests(unittest.TestCase):
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
