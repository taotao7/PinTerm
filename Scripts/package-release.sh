#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
test "$(uname -m)" = arm64
bash "$ROOT/Scripts/build-app.sh"
APP="$ROOT/dist/PinTerm.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
codesign --verify --deep --strict "$APP"
test "$(lipo -archs "$APP/Contents/MacOS/PinTerm")" = arm64
"$APP/Contents/MacOS/PinTerm" --verify-resources
ARCHIVE="$ROOT/dist/PinTerm-$VERSION-macos-arm64.zip"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ARCHIVE"
shasum -a 256 "$ARCHIVE"
echo "Release asset: $ARCHIVE (ad-hoc signed, not notarized)"
