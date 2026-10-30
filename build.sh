#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if ! xcrun --find actool >/dev/null 2>&1; then
  print -u2 "Building the app icon requires full Xcode 26 or later. Select Xcode as the active developer tools."
  exit 1
fi
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift build -c release --disable-sandbox --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security --product Utilipilled
mkdir -p "$PWD/dist"
# Stage on the destination filesystem; never sign stale contents from a prior build.
staging_root=$(mktemp -d "$PWD/dist/.Utilipilled-build.XXXXXX")
trap 'rm -rf -- "$staging_root"' EXIT
staged_app="$staging_root/Utilipilled.app"
app="$PWD/dist/Utilipilled.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp .build/release/Utilipilled "$staged_app/Contents/MacOS/Utilipilled"
cp Support/Info.plist "$staged_app/Contents/Info.plist"
cp LICENSE "$staged_app/Contents/Resources/LICENSE"
xcrun actool Support/AppIcon.icon \
  --compile "$staged_app/Contents/Resources" \
  --app-icon AppIcon --include-all-app-icons --target-device mac \
  --platform macosx --minimum-deployment-target 13.0 \
  --output-partial-info-plist "$staging_root/icon-info.plist" \
  --output-format human-readable-text --notices --warnings --errors
python3 - "$staged_app/Contents/Info.plist" "$staging_root/icon-info.plist" <<'PY'
from pathlib import Path
import plistlib, sys
path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info.update(plistlib.loads(Path(sys.argv[2]).read_bytes()))
path.write_bytes(plistlib.dumps(info, sort_keys=False))
PY
test -s "$staged_app/Contents/Resources/Assets.car"
test -s "$staged_app/Contents/Resources/AppIcon.icns"
signing_identity="${JOSHTOOLS_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
  codesign --force --sign - "$staged_app"
else
  codesign --force --options runtime --timestamp --sign "$signing_identity" "$staged_app"
fi
codesign --verify --strict "$staged_app"
# Atomic directory exchange keeps the last successful app intact if staging/signing fails.
swift Support/publish_bundle.swift "$staged_app" "$app"
print "Built $app"
