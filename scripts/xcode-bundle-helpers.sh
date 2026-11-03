#!/bin/bash
# Run by the "Bundle helpers" build phase of the Xcode project. Copies the print script,
# the page-splitting tool, the natively built Gutenprint and its PPD into
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
