#!/bin/zsh
# Builds a release binary and wraps it in MythosTable.app (in ./build).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/MythosTable.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MythosTable "$APP/Contents/MacOS/MythosTable"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MythosTable</string>
  <key>CFBundleDisplayName</key><string>MythosTable</string>
  <key>CFBundleIdentifier</key><string>local.mythostable</string>
  <key>CFBundleExecutable</key><string>MythosTable</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
