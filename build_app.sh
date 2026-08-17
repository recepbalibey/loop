#!/bin/bash
# Builds Loop.app — a real, launchable macOS app bundle — from the SwiftPM package.
# Run this any time after changing source; it produces Loop.app in this directory.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Loop"
APP_BUNDLE="$APP_NAME.app"

echo "Building release binary..."
swift build -c release

echo "Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Done: $(pwd)/$APP_BUNDLE"
