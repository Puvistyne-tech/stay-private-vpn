#!/bin/bash
# Regenerates assets/AppIcon.icns (and assets/AppIcon.png) from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p assets "$WORK/AppIcon.iconset"

swift scripts/make-icon.swift "$WORK/icon.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o assets/AppIcon.icns
cp "$WORK/icon.png" assets/AppIcon.png
echo "Wrote assets/AppIcon.icns and assets/AppIcon.png"
