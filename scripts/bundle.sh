#!/usr/bin/env bash
# Builds Jot.app into ./build. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Jot"
APP=build/Jot.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Jot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Jot 2>/dev/null || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Jot.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/Jot.app
    echo "Installed ~/Applications/Jot.app"
fi
