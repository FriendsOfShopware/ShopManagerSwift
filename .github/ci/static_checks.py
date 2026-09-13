"""Validate CI ownership, native test plans, and app translation completeness."""

import collections
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from planning import ROOT, read_manifest, validate_manifest


def placeholders(value):
    value = value.replace("%%", "")
    return collections.Counter(re.findall(r"%(?:\d+\$)?([-+#0 ]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:ll|l|z|h)?[@diufgse])", value))


def units(value):
    if isinstance(value, dict):
        if "stringUnit" in value:
            yield value["stringUnit"]
        for key, child in value.items():
            if key != "stringUnit":
                yield from units(child)


def check_localizations(path):
    data = json.loads(path.read_text())
    errors = []
    for key, entry in data["strings"].items():
        if not key or not entry.get("shouldTranslate", True) or entry.get("extractionState") == "stale":
            continue
        translation = entry.get("localizations", {}).get("de")
        values = list(units(translation))
        if not values:
            errors.append(f"Missing German translation: {key}")
        for unit in values:
            if unit.get("state") != "translated" or not unit.get("value"):
                errors.append(f"Unfinished German translation: {key}")
            # Plural substitution variables have their own format declarations.
            # Compare simple leaves here; Xcode validates plural resources on build.
            if translation and "stringUnit" in translation and placeholders(key) != placeholders(unit.get("value", "")):
                errors.append(f"Mismatched format placeholders: {key}")
    if errors:
        raise ValueError("\n".join(errors))


def check_plans(manifest):
    ui = "56F0E9142FDD314100A62FEC"
    unit = "56F0E90A2FDD314100A62FEC"
    expected = {
        "UISmoke": {t["id"] + "()" for t in manifest["tests"] if t["smoke"]},
        "UICompatibility": {t["id"] + "()" for t in manifest["tests"] if t["compatibility"]},
        "UIRegression": {t["id"].split("/")[0] for t in manifest["tests"]},
    }
    for name in ["Unit", *expected]:
        data = json.loads((ROOT / "TestPlans" / f"{name}.xctestplan").read_text())
        targets = {t["target"]["identifier"]: t for t in data["testTargets"]}
        wanted = {unit} if name == "Unit" else {unit, ui} if name == "UIRegression" else {ui}
        if set(targets) != wanted:
            raise ValueError(f"Wrong test targets in {name}")
        if name in expected and set(targets[ui]["selectedTests"]) != expected[name]:
            raise ValueError(f"{name} does not match areas.json")
    scheme = ET.parse(ROOT / "shopware.xcodeproj/xcshareddata/xcschemes/CI.xcscheme")
    names = {node.attrib["reference"] for node in scheme.findall("./TestAction/TestPlans/TestPlanReference")}
    if names != {f"container:TestPlans/{name}.xctestplan" for name in ["Unit", *expected]}:
        raise ValueError("CI scheme must expose all explicit test plans")


def check_package_localizations(root=ROOT):
    quoted = r'"(?:\\.|[^"\\])*"'
    pair = re.compile(rf'({quoted})\s*=\s*({quoted})\s*;')
    for resource in (root / "Packages").glob("*/Sources/*/Resources"):
        catalogs = {}
        for locale in ["en", "de"]:
            path = resource / f"{locale}.lproj/Localizable.strings"
            source = path.read_text()
            entries = [(json.loads(key), json.loads(value)) for key, value in pair.findall(source)]
            if pair.sub("", source).strip() or len(entries) != len(dict(entries)) or not entries:
                raise ValueError(f"Invalid or duplicate localization entries: {path}")
            catalogs[locale] = dict(entries)
        if catalogs["en"].keys() != catalogs["de"].keys():
            raise ValueError(f"Package translation keys differ: {resource}")
        for key, value in catalogs["de"].items():
            if not value or placeholders(catalogs["en"][key]) != placeholders(value):
                raise ValueError(f"Invalid package translation: {key}")
        # New literal localized errors must be present in both resource files.
        for source in resource.parent.glob("*.swift"):
            for key in re.findall(rf'(?:apiLocalized\(|localizedString\(forKey:\s*)({quoted})', source.read_text()):
                if json.loads(key) not in catalogs["en"]:
                    raise ValueError(f"Untranslated package string in {source}: {key}")


def main():
    manifest = read_manifest()
    validate_manifest(manifest)
    check_plans(manifest)
    check_localizations(ROOT / "shopware/Localizable.xcstrings")
    check_package_localizations()
    print("Test ownership, native plans, and translations verified")


if __name__ == "__main__":
    main()
