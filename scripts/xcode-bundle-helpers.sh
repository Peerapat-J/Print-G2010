#!/bin/bash
# Run by the "Bundle helpers" build phase of the Xcode project. Copies the print script,
# the page-splitting tool, the natively built Gutenprint and its PPD, and the scanner tools into
# Contents/Resources/g2010, laid out like this repo (scripts/, build/...) so that
# scripts/g2010-print works unchanged from inside the app and the app is self-contained.
set -euo pipefail

SRC="${SRCROOT:?run this from the Xcode build}"
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/g2010"
STAGE="$SRC/build/stage"
PPD="$SRC/build/ppd/stp-bjc-G2000-series.5.3.ppd"
FILTER="$STAGE/usr/libexec/cups/filter/rastertogutenprint.5.3"

if [ ! -x "$FILTER" ] || [ ! -f "$PPD" ]; then
  echo "error: Gutenprint is not built yet. Run scripts/build-gutenprint.sh first." >&2
  exit 1
fi

SANE="$SRC/build/sane"
if [ ! -x "$SANE/bin/scanimage" ]; then
  echo "error: the scanner tools are not built yet. Run scripts/build-sane.sh first." >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST/scripts" "$DEST/build/bin" "$DEST/build/ppd"
B="$DEST/build/stage"
mkdir -p "$B/usr/libexec/cups/filter" "$B/usr/local/lib/gutenprint/5.3/modules" "$B/usr/local/share/gutenprint/5.3"

cp "$SRC/scripts/g2010-print" "$DEST/scripts/"
cp "$BUILT_PRODUCTS_DIR/pdf-tool" "$DEST/build/bin/"
cp "$PPD" "$DEST/build/ppd/"
cp "$FILTER" "$B/usr/libexec/cups/filter/"
cp -P "$STAGE"/usr/local/lib/libgutenprint*.dylib "$B/usr/local/lib/"
cp "$STAGE"/usr/local/lib/gutenprint/5.3/modules/*.so "$B/usr/local/lib/gutenprint/5.3/modules/"
cp -R "$STAGE/usr/local/share/gutenprint/5.3/xml" "$B/usr/local/share/gutenprint/5.3/"

# The scanner: scanimage with the pixma backend built in, its libusb and the two config files.
cp -R "$SANE" "$DEST/build/sane"

# The filter was linked against /usr/local/lib/libgutenprint.9.dylib and relied on
# DYLD_LIBRARY_PATH to find the bundled copy. Hardened-runtime binaries ignore that variable,
# so point it at the library next to it instead (usr/libexec/cups/filter -> usr/local/lib).
BUNDLED_FILTER="$B/usr/libexec/cups/filter/rastertogutenprint.5.3"
install_name_tool -change /usr/local/lib/libgutenprint.9.dylib \
  @loader_path/../../../local/lib/libgutenprint.9.dylib "$BUNDLED_FILTER"
install_name_tool -id @loader_path/libgutenprint.9.dylib "$B/usr/local/lib/libgutenprint.9.dylib"

# Xcode seals Resources but does not sign executables inside it, and changing the install
# names invalidated the linker's signatures. Sign every Mach-O file with the build's identity;
# a notarized build needs the hardened runtime and a secure timestamp on each of them.
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
[ -n "$IDENTITY" ] || IDENTITY="-"
FLAGS=(--force --sign "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then FLAGS+=(--timestamp); fi
if [ "${ENABLE_HARDENED_RUNTIME:-NO}" = "YES" ]; then FLAGS+=(--options runtime); fi
find "$DEST" -type f ! -type l | while read -r f; do
  if file -b "$f" | grep -q "Mach-O"; then codesign "${FLAGS[@]}" "$f"; fi
done

# This phase runs on every build, so on an incremental build it changes the bundle after
# Xcode last sealed it. Seal the app again here so its signature always matches its contents.
codesign "${FLAGS[@]}" "$TARGET_BUILD_DIR/$WRAPPER_NAME"
