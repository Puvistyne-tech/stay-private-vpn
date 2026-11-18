#!/bin/bash
# Builds "build/Stay Private.dmg": open it and drag Stay Private to Applications.
#
#   ./scripts/build-dmg.sh
#
# The app inside is ad-hoc signed (free, no Apple Developer account), so on a
# Mac other than the one that built it, macOS will ask for confirmation the
# first time it is opened.

set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

DMG="build/Stay Private.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "build/Stay Private.app" "$STAGE/Stay Private.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read me first.txt" <<'TXT'
Stay Private

1. Drag Stay Private onto the Applications folder, then open it from Applications.
   A keyhole icon appears in the menu bar.
   If macOS says it could not verify the app (it is not notarized), open
   System Settings > Privacy & Security and click "Open Anyway" (macOS 15+),
   or right-click the app and choose Open (macOS 13-14).
2. Click that icon and choose "Install helper...". macOS asks for your
   password once.
3. Stay Private needs the free WireGuard tools. If the menu says they are missing,
   open Terminal and run:   brew install wireguard-tools
   (Homebrew itself comes from https://brew.sh)
4. Click "Import config..." and pick a WireGuard .conf file from your VPN
   provider, then click Connect.
TXT

rm -f "$DMG"
hdiutil create -volname "Stay Private" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Built $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
