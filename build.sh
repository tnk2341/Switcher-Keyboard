#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/MySwitcher.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SRC_ICON="$ROOT_DIR/Resources/AppIcon.png"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Running unit tests..."
swiftc -O \
  -framework Cocoa \
  "$ROOT_DIR/Sources/Converter.swift" \
  "$ROOT_DIR/Sources/AutoSwitcher.swift" \
  "$ROOT_DIR/Tests/ConverterTests.swift" \
  -o "$BUILD_DIR/ConverterTests"
"$BUILD_DIR/ConverterTests"

echo "Building MySwitcher.app..."
swiftc -O \
  -framework Cocoa \
  -framework Carbon \
  -framework ApplicationServices \
  "$ROOT_DIR/Sources/Converter.swift" \
  "$ROOT_DIR/Sources/AutoSwitcher.swift" \
  "$ROOT_DIR/Sources/InputSourceManager.swift" \
  "$ROOT_DIR/Sources/TextReplacer.swift" \
  "$ROOT_DIR/Sources/EventTapManager.swift" \
  "$ROOT_DIR/Sources/AppDelegate.swift" \
  "$ROOT_DIR/Sources/main.swift" \
  -o "$MACOS_DIR/MySwitcher"

if [[ -f "$SRC_ICON" ]]; then
  echo "Generating AppIcon.icns..."
  ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$SRC_ICON" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$SRC_ICON" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
fi

cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MySwitcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.timur.MySwitcher</string>
    <key>CFBundleName</key>
    <string>MySwitcher</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_DIR"
echo "Built: $APP_DIR"
