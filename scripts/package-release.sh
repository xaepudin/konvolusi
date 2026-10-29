#!/bin/bash
# Builds the app and produces release artifacts in dist/:
#
#   IRSVerb-<version>-macos.zip
#   IRSVerb-<version>.dmg
#   *.sha256
#
# The app is ad-hoc signed. See docs/building.md for Developer ID signing and
# notarization.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP="dist/IRSVerb.app"
ZIP_NAME="IRSVerb-${VERSION}-macos.zip"
DMG_NAME="IRSVerb-${VERSION}.dmg"
STAGE="dist/dmg-stage"

if [[ -z "$VERSION" ]]; then
    echo "error: could not read CFBundleShortVersionString" >&2
    exit 1
fi

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "error: Resources/AppIcon.icns is missing; run scripts/make-icon.swift" >&2
    exit 1
fi

echo "==> Building IRSVerb $VERSION"
./build.sh release

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Zipping the app bundle"
rm -f "dist/$ZIP_NAME" "dist/$ZIP_NAME.sha256"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "dist/$ZIP_NAME"
(cd dist && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")

echo "==> Building the disk image"
rm -rf "$STAGE" "dist/$DMG_NAME" "dist/$DMG_NAME.sha256"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp README.md LICENSE LICENSE-IRS "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "IRSVerb $VERSION" \
    -srcfolder "$STAGE" -ov -format UDZO "dist/$DMG_NAME"
rm -rf "$STAGE"
(cd dist && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")

echo
echo "Artifacts in dist/:"
ls -lh "dist/$ZIP_NAME" "dist/$ZIP_NAME.sha256" "dist/$DMG_NAME" "dist/$DMG_NAME.sha256"
echo
echo "Note: the app is ad-hoc signed, not notarized. Users must Control-click → Open"
echo "or remove the quarantine attribute. See docs/building.md#signing-and-notarization."
