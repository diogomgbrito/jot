#!/bin/bash
# Builds an ad-hoc signed universal Jot.app and packages it as a DMG.
# Usage: scripts/release.sh            -> build/Jot-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=build
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="$OUT/Jot-$VERSION.dmg"

UNIVERSAL=1 scripts/bundle.sh >/dev/null
APP="$OUT/Jot.app"
codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/Jot"

STAGING="$OUT/dmg"
rm -rf "$STAGING" "$DMG" && mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Jot" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "Version: $VERSION"
echo "DMG:     $DMG"
echo "SHA256:  $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
