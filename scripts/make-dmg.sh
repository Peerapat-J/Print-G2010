#!/bin/bash
# Build dist/PrintG2010-<version>.dmg to share with colleagues: the app, a shortcut to
# /Applications for drag-and-drop installation, and a Read Me.
# Needs scripts/build-gutenprint.sh to have been run once (the app bundles Gutenprint).
#
# For a DMG that opens on other Macs without a warning you need, once:
#   1. a "Developer ID Application" certificate in your keychain (Xcode > Settings > Accounts >
#      Manage Certificates > + ; only the account holder can create it), and
#   2. notarization credentials stored in the keychain:
#        xcrun notarytool store-credentials G2010-notary --apple-id YOU@EXAMPLE.COM --team-id TEAMID
#      (it asks for an app-specific password made at appleid.apple.com).
# Then:  NOTARY_PROFILE=G2010-notary scripts/make-dmg.sh
# Without them the DMG is still built, but other Macs show the "could not verify" warning.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
"$ROOT/scripts/build-app.sh"

APP="build/Print G2010.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
DMG="dist/PrintG2010-$VERSION.dmg"
NOTARY="${NOTARY_PROFILE:-}"

# The identity the app was signed with, when it is a Developer ID one.
DEVID="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' | head -1)"

notarize() {
  local out id
  out="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY" --wait 2>&1)" || true
  echo "$out" | tail -n 5 >&2
  if ! grep -q "status: Accepted" <<<"$out"; then
    id="$(sed -n 's/^ *id: *//p' <<<"$out" | head -1)"
    if [ -n "$id" ]; then xcrun notarytool log "$id" --keychain-profile "$NOTARY" >&2 || true; fi
    echo "error: notarization of $1 failed" >&2
    exit 1
  fi
}

if [ -n "$DEVID" ] && [ -n "$NOTARY" ]; then
  echo "notarizing the app..."
  ZIP="$(mktemp -d)/app.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  xcrun stapler staple "$APP" >/dev/null
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/scripts/dmg/Read Me.txt" "$STAGING/"

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "Print G2010" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

if [ -n "$DEVID" ]; then
  codesign --force --sign "$DEVID" --timestamp "$DMG"
  if [ -n "$NOTARY" ]; then
    echo "notarizing the disk image..."
    notarize "$DMG"
    xcrun stapler staple "$DMG" >/dev/null
    echo "notarized and stapled: other Macs open it without a warning"
  else
    echo "warning: signed with Developer ID but not notarized; set NOTARY_PROFILE (see the top of this script)" >&2
  fi
elif [ -z "$DEVID" ]; then
  echo "warning: no Developer ID signature; other Macs will show the 'could not verify' warning (see Read Me)" >&2
fi
echo "built: $ROOT/$DMG ($(du -h "$DMG" | cut -f1))"
