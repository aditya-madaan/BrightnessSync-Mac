#!/bin/bash

# Build script for BrightnessSync Mac
# This creates a proper app bundle and DMG for distribution

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="BrightnessSync Mac"
EXECUTABLE_NAME="BrightnessSyncMac"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="BrightnessSyncMac.dmg"

echo "🔨 Building $APP_NAME..."

# Create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist
cp "$PROJECT_DIR/BrightnessSyncMac/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Generate App Icon (icns) using iconutil (works with Command Line Tools)
echo "🎨 Generating App Icon..."
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Copy icons from xcassets to iconset folder with correct names for iconutil
# iconutil expects names like: icon_16x16.png, icon_16x16@2x.png, etc.
cp "$PROJECT_DIR/BrightnessSyncMac/Assets.xcassets/AppIcon.appiconset/"*.png "$ICONSET_DIR/"

# Convert to icns
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Compile Swift files
echo "📦 Compiling Swift sources..."
swiftc -sdk $(xcrun --show-sdk-path) \
       -target arm64-apple-macosx12.0 \
       -O \
       -o "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME" \
       "$PROJECT_DIR/BrightnessSyncMac/"*.swift \
       -framework AppKit \
       -framework IOKit \
       -framework CoreGraphics \
       -framework Carbon \
       -framework ApplicationServices

echo "✅ App bundle created: $APP_BUNDLE"

# Ad-hoc code signing to help with local execution
echo "✍️  Signing app (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

# Create DMG
echo "💿 Creating DMG..."
rm -f "$BUILD_DIR/$DMG_NAME"

# Create a temporary directory for DMG contents
DMG_TEMP="$BUILD_DIR/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create symbolic link to Applications folder
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$DMG_TEMP" \
               -ov \
               -format UDZO \
               "$BUILD_DIR/$DMG_NAME"

# Clean up
rm -rf "$DMG_TEMP"

echo ""
echo "🎉 Build complete!"
echo "   App: $APP_BUNDLE"
echo "   DMG: $BUILD_DIR/$DMG_NAME"
echo ""
echo "📋 Requirements:"
echo "   - macOS 12.0 (Monterey) or later"
echo "   - Apple Silicon Mac (M1/M2/M3)"
echo "   - m1ddc: brew install m1ddc"
