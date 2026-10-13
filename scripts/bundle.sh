#!/usr/bin/env bash
# Builds Jot.app into ./build. Pass --install to copy it to ~/Applications and launch it.
# UNIVERSAL=1 builds for arm64 + x86_64 (used by scripts/release.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

ARGS=(-c release)
[[ "${UNIVERSAL:-}" == 1 ]] && ARGS+=(--arch arm64 --arch x86_64)
swift build "${ARGS[@]}"
BIN="$(swift build "${ARGS[@]}" --show-bin-path)/Jot"
APP=build/Jot.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Jot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Jot 2>/dev/null && sleep 1 || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Jot.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/Jot.app
    echo "Installed ~/Applications/Jot.app"
fi
