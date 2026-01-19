#!/bin/bash

# Build script for BrightnessSync
# This creates a proper app bundle and DMG for distribution

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="BrightnessSync"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"

echo "🔨 Building $APP_NAME..."

# Create build directory
mkdir -p "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Compile Swift files
echo "📦 Compiling Swift sources..."
swiftc -sdk $(xcrun --show-sdk-path) \
       -target arm64-apple-macosx12.0 \
       -O \
       -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
       "$PROJECT_DIR/BrightnessSync/"*.swift \
       -framework AppKit \
       -framework IOKit \
       -framework CoreGraphics \
       -framework Carbon

# Create Info.plist
echo "📝 Creating Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>BrightnessSync</string>
    <key>CFBundleIdentifier</key>
    <string>com.brightness.sync</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>BrightnessSync</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ App bundle created: $APP_BUNDLE"

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
