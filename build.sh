#!/bin/bash
# Builds Konvolusi.app (menu bar app) and the irsconv CLI into dist/.
#
#   ./build.sh            native release build (default)
#   ./build.sh universal  arm64 + x86_64 release build
#   ./build.sh debug      native debug build
#
# The app bundle is ad-hoc signed, which is enough for Core Audio taps and for
# the system-audio-recording permission prompt. Note that the ad-hoc signature
# changes every time you rebuild, so macOS may ask for permission again.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-release}"
APP="dist/Konvolusi.app"

if [[ "$MODE" == "universal" ]]; then
    CONFIGURATION=release
    UNIVERSAL=1
else
    CONFIGURATION="$MODE"
    UNIVERSAL=0
fi

if [[ "$UNIVERSAL" == 1 ]]; then
    ARM_TRIPLE="arm64-apple-macosx15.0"
    INTEL_TRIPLE="x86_64-apple-macosx15.0"
    # SwiftPM otherwise reuses one product directory for both triples and the
    # second build silently replaces the first. Separate scratch paths keep a
    # real arm64 product around for lipo.
    ARM_SCRATCH=".build/universal-arm64"
    INTEL_SCRATCH=".build/universal-x86_64"

    echo "==> Building universal ($ARM_TRIPLE + $INTEL_TRIPLE)"
    swift build -c release --scratch-path "$ARM_SCRATCH" --triple "$ARM_TRIPLE" --product Konvolusi
    swift build -c release --scratch-path "$ARM_SCRATCH" --triple "$ARM_TRIPLE" --product irsconv
    swift build -c release --scratch-path "$INTEL_SCRATCH" --triple "$INTEL_TRIPLE" --product Konvolusi
    swift build -c release --scratch-path "$INTEL_SCRATCH" --triple "$INTEL_TRIPLE" --product irsconv

    ARM_BIN="$(swift build -c release --scratch-path "$ARM_SCRATCH" --triple "$ARM_TRIPLE" --show-bin-path)"
    INTEL_BIN="$(swift build -c release --scratch-path "$INTEL_SCRATCH" --triple "$INTEL_TRIPLE" --show-bin-path)"

    BIN_DIR="dist/universal"
    rm -rf "$BIN_DIR"
    mkdir -p "$BIN_DIR"
    lipo -create "$ARM_BIN/Konvolusi" "$INTEL_BIN/Konvolusi" -output "$BIN_DIR/Konvolusi"
    lipo -create "$ARM_BIN/irsconv" "$INTEL_BIN/irsconv" -output "$BIN_DIR/irsconv"
    lipo -info "$BIN_DIR/Konvolusi"
else
    echo "==> Building ($CONFIGURATION)"
    swift build -c "$CONFIGURATION" --product Konvolusi
    swift build -c "$CONFIGURATION" --product irsconv
    BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Konvolusi" "$APP/Contents/MacOS/Konvolusi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN_DIR/irsconv" "$APP/Contents/MacOS/irsconv"

echo "==> Signing (ad-hoc)"
# lipo strips the linker's ad-hoc signature from the universal helper, and
# codesign does not reach into Contents/MacOS on its own. Sign the nested
# executable first, then the bundle that seals it.
codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/irsconv"
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
