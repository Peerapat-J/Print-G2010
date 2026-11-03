#!/bin/bash
# Build "Print G2010.app" into build/ with Xcode (xcodebuild). The app bundles everything it
# needs (print script, page tool, Gutenprint, PPD), so scripts/build-gutenprint.sh must have
# been run once before. Regenerates PrintG2010.xcodeproj from project.yml when XcodeGen
# (brew install xcodegen) is installed; otherwise the committed project is used.
# Set CONFIGURATION=Debug for a debug build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIGURATION:-Release}"
cd "$ROOT"
mkdir -p build

if command -v xcodegen >/dev/null; then
  xcodegen generate --quiet
else
  echo "xcodegen not found; using the committed PrintG2010.xcodeproj" >&2
fi

xcodebuild -project PrintG2010.xcodeproj -scheme PrintG2010 -configuration "$CONFIG" \
  -derivedDataPath build/xcode -destination 'platform=macOS,arch=arm64' build \
  >build/xcode-build.log 2>&1 || { grep -E "error:" build/xcode-build.log | head -20 >&2; echo "see build/xcode-build.log" >&2; exit 1; }

rm -rf "build/Print G2010.app"
cp -R "build/xcode/Build/Products/$CONFIG/Print G2010.app" build/
echo "built: $ROOT/build/Print G2010.app"
