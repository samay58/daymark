#!/usr/bin/env bash
set -euo pipefail

# Builds Daymark and wraps the executable in a throwaway .app bundle so macOS gives it
# a real window and activation. This is a dev convenience for the Milestone 0 prototype,
# not the signed app bundle decision deferred in docs/DECISIONS.md (ADR-002).

cd "$(dirname "$0")/.."

swift build
BIN_DIR="$(swift build --show-bin-path)"
APP="$BIN_DIR/Daymark.app"

pkill -x Daymark 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Daymark" "$APP/Contents/MacOS/Daymark"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Daymark</string>
    <key>CFBundleIdentifier</key><string>com.daymark.prototype</string>
    <key>CFBundleName</key><string>Daymark</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

open "$APP"
echo "Launched $APP"
