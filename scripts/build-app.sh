#!/bin/bash
# Build "Print G2010.app" (single-window SwiftUI app) into build/.
# Choose or drop files, set copies, press Print. It calls scripts/g2010-print,
# so scripts/build-gutenprint.sh must have been run once before.
# The app stores the absolute path of this repo; rebuild it if you move the repo.
# Needs only the Xcode command line tools (swiftc).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Print G2010.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" \
  -o "$APP/Contents/MacOS/PrintG2010" "$ROOT/app/PrintG2010.swift"

cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Print G2010</string>
  <key>CFBundleDisplayName</key><string>Print G2010</string>
  <key>CFBundleIdentifier</key><string>local.canon-pixma-driver.print-g2010</string>
  <key>CFBundleExecutable</key><string>PrintG2010</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>G2010Root</key><string>$ROOT</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Printable files</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.adobe.pdf</string>
        <string>public.image</string>
        <string>public.plain-text</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "built: $APP"
