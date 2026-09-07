#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
ICONSET="$ROOT/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
