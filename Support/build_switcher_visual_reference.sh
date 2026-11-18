#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/module-cache
stage="$(mktemp -d "$PWD/.build/switcher-visual-build.XXXXXX")"
app="$stage/SwitcherVisualReference.app"
mkdir -p "$app/Contents/MacOS"
swiftc -target arm64-apple-macosx13.0 -module-cache-path .build/module-cache \
  Sources/Utilipilled/Pills/SwitcherHider/*.swift Support/switcher_visual_reference.swift \
  -framework AppKit -framework ApplicationServices -o "$app/Contents/MacOS/SwitcherVisualReference"
python3 - "$app/Contents/Info.plist" "$PWD/.build/switcher-reference" <<'PY'
import plistlib, sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'local.Utilipilled.SwitcherVisualReference',
    'CFBundleName': 'Switcher Visual Comparison',
    'CFBundleExecutable': 'SwitcherVisualReference',
    'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '1',
    'LSMinimumSystemVersion': '13.0',
    'NSHighResolutionCapable': True,
    'ReferenceDirectory': sys.argv[2],
}))
PY
codesign --force --sign - "$app"
codesign --verify --strict "$app"
# Never rewrite the executable inode of a running, signed preview.
destination="$PWD/.build/SwitcherVisualReference.app"
if [[ -d "$destination" ]]; then
  mv "$destination" "$stage/PreviousSwitcherVisualReference.app"
fi
mv "$app" "$destination"
print "Built $destination"
