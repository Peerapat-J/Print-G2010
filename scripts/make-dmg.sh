#!/bin/bash
# Build dist/PrintG2010-<version>.dmg to share with colleagues: the app, a shortcut to
# /Applications for drag-and-drop installation, and a Read Me with the first-open steps.
# Needs scripts/build-gutenprint.sh to have been run once (the app bundles Gutenprint).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
"$ROOT/scripts/build-app.sh"

APP="build/Print G2010.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
DMG="dist/PrintG2010-$VERSION.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/scripts/dmg/Read Me.txt" "$STAGING/"

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "Print G2010" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "built: $ROOT/$DMG ($(du -h "$DMG" | cut -f1))"
