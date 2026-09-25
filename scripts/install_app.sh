#!/usr/bin/env bash
set -euo pipefail

# Builds a release Daymark.app and installs it to /Applications (or $1). This is the
# ad hoc-signed local build ADR-002 allows for daily use, not a notarized release.

cd "$(dirname "$0")/.."
source scripts/toolchain.sh

DEST="${1:-/Applications}/Daymark.app"
VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo dev)"

swift build "${SWIFT_BUILD_FLAGS[@]}" -c release --product Daymark
BIN_DIR="$(swift build "${SWIFT_BUILD_FLAGS[@]}" -c release --show-bin-path)"

STAGE="$(mktemp -d)/Daymark.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN_DIR/Daymark" "$STAGE/Contents/MacOS/Daymark"
cp Daymark/Resources/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
cp -R "$BIN_DIR/Daymark_DaymarkAppShell.bundle" "$STAGE/Contents/Resources/"

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>Daymark</string>
    <key>CFBundleExecutable</key><string>Daymark</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.daymark.app</string>
    <key>CFBundleName</key><string>Daymark</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.7.0</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Daymark development build</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$STAGE"

osascript -e 'quit app id "com.daymark.app"' 2>/dev/null || true
rm -rf "$DEST"
mv "$STAGE" "$DEST"
echo "Installed $DEST ($VERSION)"
