#!/bin/bash
# Builds IRSVerb.app (menu bar app) and the irsconv CLI into dist/.
#
#   ./build.sh            release build (default)
#   ./build.sh debug      debug build
#
# The app bundle is ad-hoc signed, which is enough for Core Audio taps and for
# the system-audio-recording permission prompt. Note that the ad-hoc signature
# changes every time you rebuild, so macOS may ask for permission again.
set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-release}"
APP="dist/IRSVerb.app"

echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product IRSVerb
swift build -c "$CONFIGURATION" --product irsconv

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/IRSVerb" "$APP/Contents/MacOS/IRSVerb"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/irsconv" "$APP/Contents/MacOS/irsconv"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

echo "==> Demo impulse responses"
mkdir -p "Impulse Responses"
"$BIN_DIR/irsconv" make-ir --out "Impulse Responses" >/dev/null

mkdir -p dist
cp -f "$BIN_DIR/irsconv" dist/irsconv

echo
echo "Built:"
echo "  $APP"
echo "  dist/irsconv"
echo
echo "Run:  open $APP"
