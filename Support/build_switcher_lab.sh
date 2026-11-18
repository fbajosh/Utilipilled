#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/module-cache
lab="$PWD/.build/SwitcherHiderLab.app"
mkdir -p "$lab/Contents/MacOS"
swiftc -O -target arm64-apple-macosx13.0 -module-cache-path .build/module-cache \
  Sources/Utilipilled/Pills/SwitcherHider/*.swift Support/switcher_lab.swift \
  -framework AppKit -framework ApplicationServices -o "$lab/Contents/MacOS/SwitcherHiderLab"
python3 - "$lab/Contents/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.Utilipilled.SwitcherLab',
    'CFBundleName': 'Switcher Hider Lab',
    'CFBundleDisplayName': 'Switcher Hider Lab',
    'CFBundleExecutable': 'SwitcherHiderLab',
    'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '1',
    'CFBundleShortVersionString': '0.1',
    'LSMinimumSystemVersion': '13.0',
    'NSHighResolutionCapable': True,
}))
PY
codesign --force --sign - --identifier local.Utilipilled.SwitcherLab "$lab"
codesign --verify --strict "$lab"
print "Built $lab"
