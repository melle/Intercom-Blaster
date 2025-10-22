#!/usr/bin/env bash
set -euo pipefail

PRODUCT_NAME="IntercomBlaster"
SCHEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$SCHEME_DIR/.build/release"
APP_DIR="$SCHEME_DIR/.build/${PRODUCT_NAME}.app"
FRAMEWORK_SRC="$SCHEME_DIR/Vendor/VLCKit.xcframework/macos-arm64_x86_64/VLCKit.framework"
INFO_PLIST_SRC="$SCHEME_DIR/Sources/IntercomBlaster/Resources/AppInfo.plist"
ICON_SRC="$SCHEME_DIR/Sources/IntercomBlaster/Resources/AppIcon.icns"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

echo "→ Building release binary…"
swift build -c release

echo "→ Assembling app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"

cp "$BUILD_DIR/$PRODUCT_NAME" "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
cp "$INFO_PLIST_SRC" "$APP_DIR/Contents/Info.plist"
cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R "$FRAMEWORK_SRC" "$APP_DIR/Contents/Frameworks/"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "→ Codesigning with identity: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR"
  echo "✓ Codesign complete"
else
  echo "⚠️  No signing identity provided. Set CODESIGN_IDENTITY to skip this warning."
fi

echo "✅ App bundle ready: $APP_DIR"
