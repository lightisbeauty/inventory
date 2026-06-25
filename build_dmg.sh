#!/bin/bash
# Builds inventory.app and packages it in a distributable DMG.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/inventory.app"
STAGING="$SCRIPT_DIR/.dmg-staging"
OUTPUT="$SCRIPT_DIR/inventory.dmg"

echo ""
echo "  Building inventory.app..."
echo ""

# Compile Swift binary
swiftc -o "$SCRIPT_DIR/InventoryViewer" \
    "$SCRIPT_DIR/InventoryViewer.swift" \
    -framework Cocoa -framework WebKit

# Build .app bundle
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$SCRIPT_DIR/InventoryViewer"   "$APP/Contents/MacOS/InventoryViewer"
cp "$SCRIPT_DIR/inventory_mac.py"  "$APP/Contents/Resources/inventory_mac.py"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>InventoryViewer</string>
    <key>CFBundleIdentifier</key>
    <string>com.lightisbeauty.inventory</string>
    <key>CFBundleName</key>
    <string>inventory</string>
    <key>CFBundleDisplayName</key>
    <string>inventory</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>26062401</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>by: @lightisbeauty</string>
</dict>
</plist>
PLIST

echo "  inventory.app built"
echo ""
echo "  Packaging DMG..."
echo ""

# Build DMG
rm -rf "$STAGING" "$OUTPUT"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

create-dmg \
    --volname "inventory" \
    --window-size 540 380 \
    --icon-size 100 \
    --icon "inventory.app" 150 170 \
    --icon "Applications" 390 170 \
    --no-internet-enable \
    "$OUTPUT" \
    "$STAGING"

rm -rf "$STAGING"
echo ""
echo "  Done: $OUTPUT"
