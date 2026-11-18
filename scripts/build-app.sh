#!/bin/bash
# Builds "Stay Private.app" into ./build and (with --install) copies it to /Applications.
#
#   ./scripts/build-app.sh            build only
#   ./scripts/build-app.sh --install  build, install to /Applications and launch
#
# Version: "1.0" from the VERSION file, or the exact version in STAYPRIVATE_VERSION
# (the release workflow sets it to 1.0.<commit count>). STAYPRIVATE_BUILD sets the build number.
# STAYPRIVATE_UNIVERSAL=1 builds for both Apple Silicon and Intel Macs.
#
# The app is ad-hoc signed (free, no Apple Developer account). It runs without
# fuss on the Mac that built it; a copy downloaded from the internet needs a
# one-time "Open Anyway" in System Settings (see the README).

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${STAYPRIVATE_VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD="${STAYPRIVATE_BUILD:-1}"
APP="build/Stay Private.app"
INSTALLED="/Applications/Stay Private.app"
# The executable has no space in its name so that pgrep/pkill can match it exactly.
EXE=StayPrivate

ARCH_FLAGS=()
if [ "${STAYPRIVATE_UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi
# ${arr[@]+...} keeps macOS's bash 3.2 happy when the array is empty.
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/StayVPN"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
# The helper and its installer travel inside the app, so the app can set itself up.
mkdir -p "$APP/Contents/Resources"
cp helper/stayvpn-helper scripts/install-helper.sh "$APP/Contents/Resources/"
chmod 755 "$APP/Contents/Resources/stayvpn-helper" "$APP/Contents/Resources/install-helper.sh"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Stay Private</string>
    <key>CFBundleDisplayName</key><string>Stay Private</string>
    <key>CFBundleIdentifier</key><string>local.stayprivate.app</string>
    <key>CFBundleExecutable</key><string>$EXE</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP (version $VERSION)"

if [ "${1:-}" = "--install" ]; then
    # Quit the running copy and wait for it to go; opening too early fails with error -600.
    # (StayVPN is the app's former name; an old copy is replaced by this one.)
    pkill -x "$EXE" 2>/dev/null || true
    pkill -x StayVPN 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$EXE" >/dev/null || pgrep -x StayVPN >/dev/null || break; sleep 0.3; done
    rm -rf "$INSTALLED" /Applications/StayVPN.app
    cp -R "$APP" "$INSTALLED"
    open "$INSTALLED" 2>/dev/null || { sleep 2; open "$INSTALLED"; }
    echo "Installed to $INSTALLED and launched (look for the keyhole icon in the menu bar)."
fi
