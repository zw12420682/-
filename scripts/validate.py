"""Dependency-free repository validation; does not substitute for iOS compilation."""
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parents[1]
required = [
    "Makefile",
    "control",
    "HotspotAutoOff.plist",
    "Sources/Tweak.m",
    "Sources/HAOLog.h",
    "Sources/HAOPreferences.h",
    "Sources/HAOPreferences.m",
    "Sources/HAOHotspot.h",
    "Sources/HAOHotspot.m",
    "Sources/HAOSharing.h",
    "Sources/HAOSharing.m",
    "Sources/HAOController.h",
    "Sources/HAOController.m",
    "Sources/HAODiagnostics.h",
    "Sources/HAODiagnostics.m",
    "Preferences/Makefile",
    "Preferences/HAOPreferences.m",
    "Preferences/Resources/Root.plist",
    "Preferences/Resources/Info.plist",
    "layout/Library/PreferenceLoader/Preferences/HotspotAutoOff.plist",
    ".github/workflows/build.yml",
]
for name in required:
    assert (root / name).is_file(), f"Missing {name}; upload the project CONTENTS to the repository root."

for path in root.rglob("*.plist"):
    if any(part.startswith(".theos") for part in path.parts):
        continue
    with path.open("rb") as stream:
        plistlib.load(stream)

control_bytes = (root / "control").read_bytes()
assert b"\r" not in control_bytes, "control must use Unix LF line endings."
assert control_bytes.endswith(b"\n"), "control must end with a newline."
assert not control_bytes.startswith(b"\xef\xbb\xbf"), "control must be UTF-8 without BOM."
control = dict(line.split(": ", 1) for line in control_bytes.decode("utf-8").splitlines() if ": " in line)
assert control["Architecture"] == "iphoneos-arm64e"

makefile = (root / "Makefile").read_text()
assert "THEOS_PACKAGE_SCHEME = roothide" in makefile, "RootHide packaging scheme is required."
for source in ["Sources/HAOController.m", "Sources/HAODiagnostics.m", "Sources/HAOHotspot.m", "Sources/HAOPreferences.m", "Sources/HAOSharing.m"]:
    assert source in makefile, f"Update the Makefile for {source}."

filters = plistlib.loads((root / "HotspotAutoOff.plist").read_bytes())
assert filters["Filter"]["Bundles"] == ["com.apple.springboard"], "The tweak must only load in SpringBoard."

prefs = plistlib.loads((root / "Preferences/Resources/Root.plist").read_bytes())
keys = {item["key"] for item in prefs["items"] if "key" in item}
assert keys == {"Enabled", "TimeoutMinutes", "DryRun"}, f"Unexpected preference keys: {keys}"

loader = plistlib.loads((root / "layout/Library/PreferenceLoader/Preferences/HotspotAutoOff.plist").read_bytes())
assert loader["entry"]["bundle"] == "HotspotAutoOffPrefs"

print("PASS: required files, property lists, RootHide configuration, preference keys and injection filter")
