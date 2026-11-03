#!/bin/bash
# Build Gutenprint (open source, GPL) natively for Apple Silicon and generate the
# Canon G2000-series PPD that the G2010 uses. Nothing is installed system-wide:
# everything lands in ./build (ignored by git).
set -euo pipefail

VERSION=5.3.5
SHA256=f5a9f47de28530b1ae2069cfbc647a9a641baeeabe809bb0ef2b3ec5b9668d70
URL="https://downloads.sourceforge.net/project/gimp-print/gutenprint-5.3/${VERSION}/gutenprint-${VERSION}.tar.xz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
SRC="$BUILD/gutenprint-${VERSION}"
STAGE="$BUILD/stage"
TARBALL="$BUILD/gutenprint-${VERSION}.tar.xz"

command -v pkg-config >/dev/null || { echo "pkg-config missing: brew install pkgconf" >&2; exit 1; }
command -v clang >/dev/null || { echo "Xcode command line tools missing: xcode-select --install" >&2; exit 1; }

mkdir -p "$BUILD"
if [ ! -f "$TARBALL" ]; then
  curl -fsSL -A "curl/8" -o "$TARBALL" "$URL"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c -

[ -d "$SRC" ] || tar -xJf "$TARBALL" -C "$BUILD"

cd "$SRC"
# _DARWIN_C_SOURCE: macOS headers hide u_int/u_char under strict POSIX mode, which
# breaks src/cups/genppd.c on current SDKs.
CPPFLAGS="-D_DARWIN_C_SOURCE" ./configure --prefix=/usr/local --disable-nls \
  --disable-static --disable-rpath --disable-libgutenprintui2 --disable-samples \
  --disable-escputil --disable-test --disable-testpattern --without-gimp2 --without-doc \
  --enable-cups-ppds --enable-simplified-cups-ppds --disable-static-genppd >"$BUILD/configure.log" 2>&1
make -j"$(sysctl -n hw.ncpu)" >"$BUILD/make.log" 2>&1
rm -rf "$STAGE"
make install DESTDIR="$STAGE" >"$BUILD/install.log" 2>&1

# Generate the PPD. STP_DATA_PATH must point at the xml directory itself.
export STP_DATA_PATH="$STAGE/usr/local/share/gutenprint/${VERSION%.*}/xml"
export STP_MODULE_PATH="$STAGE/usr/local/lib/gutenprint/${VERSION%.*}/modules"
export DYLD_LIBRARY_PATH="$STAGE/usr/local/lib"
rm -rf "$BUILD/ppd"; mkdir -p "$BUILD/ppd"
"$STAGE/usr/local/sbin/cups-genppd.${VERSION%.*}" -p "$BUILD/ppd" -Z bjc-G2000-series >/dev/null

echo "Built: $STAGE/usr/libexec/cups/filter/rastertogutenprint.${VERSION%.*}"
echo "PPD:   $BUILD/ppd/stp-bjc-G2000-series.${VERSION%.*}.ppd"
