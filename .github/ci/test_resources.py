import json
from pathlib import Path
import tempfile
import unittest

from static_checks import check_localizations, check_package_localizations


class ResourceTests(unittest.TestCase):
    def test_missing_unfinished_and_changed_placeholders_fail_early(self):
        for translation in [None, {"stringUnit": {"state": "new", "value": "Hallo %@"}},
                            {"stringUnit": {"state": "translated", "value": "Hallo %d"}}]:
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "Localizable.xcstrings"
                path.write_text(json.dumps({"strings": {"Hello %@": {"localizations": {"de": translation}}}}))
                with self.assertRaises(ValueError):
                    check_localizations(path)

    def test_missing_package_error_translation_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Packages/API/Sources/API"
            resource = source / "Resources"
            for locale in ["en", "de"]:
                folder = resource / f"{locale}.lproj"
                folder.mkdir(parents=True)
                (folder / "Localizable.strings").write_text('"Known" = "Known";\n')
            (source / "Failure.swift").write_text('let message = apiLocalized("Unknown")')
            with self.assertRaisesRegex(ValueError, "Untranslated package string"):
                check_package_localizations(root)


if __name__ == "__main__":
    unittest.main()
