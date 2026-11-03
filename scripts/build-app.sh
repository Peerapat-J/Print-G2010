#!/bin/bash
# Build "Print G2010.app" into build/ with Xcode (xcodebuild). The app bundles everything it
# needs (print script, page tool, Gutenprint, PPD), so scripts/build-gutenprint.sh must have
# been run once before. Regenerates PrintG2010.xcodeproj from project.yml when XcodeGen
# (brew install xcodegen) is installed; otherwise the committed project is used.
# Set CONFIGURATION=Debug for a debug build.
#
# Signing: with a "Developer ID Application" certificate in the keychain the app is signed with
# it (hardened runtime, secure timestamp), which is what a notarized build needs. Choose another
# identity with SIGN_IDENTITY="certificate name" (set DEVELOPMENT_TEAM=TEAMID if it is a hash),
# or SIGN_IDENTITY=- to force ad-hoc signing, which is fine on this Mac only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIGURATION:-Release}"
cd "$ROOT"
mkdir -p build

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
fi
SIGN_ARGS=()
if [ -n "$IDENTITY" ] && [ "$IDENTITY" != "-" ]; then
  # The team ID is the certificate's organizational unit (not the number in its name).
  TEAM="${DEVELOPMENT_TEAM:-$(security find-certificate -c "$IDENTITY" -p 2>/dev/null \
    | openssl x509 -noout -subject -nameopt multiline 2>/dev/null | awk '/organizationalUnitName/ {print $3}')}"
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$IDENTITY" ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp")
  [ -z "$TEAM" ] || SIGN_ARGS+=(DEVELOPMENT_TEAM="$TEAM")
  echo "signing with: $IDENTITY"
else
  echo "ad-hoc signing: fine on this Mac, other Macs will refuse to open it (see make-dmg.sh)" >&2
fi

if command -v xcodegen >/dev/null; then
  xcodegen generate --quiet
else
  echo "xcodegen not found; using the committed PrintG2010.xcodeproj" >&2
fi

xcodebuild -project PrintG2010.xcodeproj -scheme PrintG2010 -configuration "$CONFIG" \
  -derivedDataPath build/xcode -destination 'platform=macOS,arch=arm64' \
  ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} build \
  >build/xcode-build.log 2>&1 || { grep -E "error:" build/xcode-build.log | head -20 >&2; echo "see build/xcode-build.log" >&2; exit 1; }

rm -rf "build/Print G2010.app"
cp -R "build/xcode/Build/Products/$CONFIG/Print G2010.app" build/
echo "built: $ROOT/build/Print G2010.app"
