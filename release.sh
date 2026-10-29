#!/bin/zsh
# Builds a native-architecture release. This script does not publish or bypass Gatekeeper.
set -euo pipefail
cd "${0:A:h}"
if [[ -n "${JOSHTOOLS_NOTARY_PROFILE:-}" && "${JOSHTOOLS_SIGNING_IDENTITY:--}" == "-" ]]; then
  print -u2 "Notarization requires JOSHTOOLS_SIGNING_IDENTITY (Developer ID Application)."
  exit 1
fi
./build.sh
app="$PWD/dist/Utilipilled.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
architecture=$(lipo -archs "$app/Contents/MacOS/Utilipilled")
case "$architecture" in
  arm64|x86_64) ;;
  *) print -u2 "Unsupported release architecture: $architecture"; exit 1 ;;
esac
archive="$PWD/dist/Utilipilled-${version}-macOS-${architecture}.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
if [[ -n "${JOSHTOOLS_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$archive" --keychain-profile "$JOSHTOOLS_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
fi
(cd dist && shasum -a 256 "${archive:t}" > "${archive:t}.sha256")
print "Packaged $archive"
cat "${archive}.sha256"
