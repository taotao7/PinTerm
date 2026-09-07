#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
bash "$ROOT/Scripts/build-icon.sh"
swift build --package-path "$ROOT" -c release
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
# SwiftPM assumes a command-line executable with adjacent resource bundles.
# For a signed .app, bundles must live inside Contents/Resources, not the app root.
# Adapt only the generated accessor, leaving the resolved dependency unchanged.
ACCESSOR="$BIN/GhosttyTerminal.build/DerivedSources/resource_bundle_accessor.swift"
if grep -Fq 'Bundle.main.bundleURL.appendingPathComponent(' "$ACCESSOR"; then
    sed 's/Bundle.main.bundleURL.appendingPathComponent(/Bundle.main.resourceURL!.appendingPathComponent(/' "$ACCESSOR" > "$ACCESSOR.pinterm"
    mv "$ACCESSOR.pinterm" "$ACCESSOR"
    swift build --package-path "$ROOT" -c release
fi
grep -Fq 'Bundle.main.resourceURL!.appendingPathComponent(' "$ACCESSOR"
APP="$ROOT/dist/PinTerm.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PinTerm" "$APP/Contents/MacOS/PinTerm"
for bundle in "$BIN/"*.bundle; do
    cp -Rf "$bundle" "$APP/Contents/Resources/"
done
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/License.txt"
cp -Rf "$ROOT/Resources/Licenses" "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
