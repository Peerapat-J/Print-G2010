#!/bin/bash
# Build the scanner side natively for Apple Silicon: libusb and SANE (only the Canon "pixma"
# backend, which drives the G2010 scanner), then stage a self-contained scanimage. Nothing is
# installed system-wide: everything lands in ./build (ignored by git).
#
# Both are built from source instead of copying Homebrew's files because Homebrew's bottles
# target the newest macOS only and would not start on macOS 14.
set -euo pipefail

SANE_VERSION=1.4.0
SANE_SHA256=f99205c903dfe2fb8990f0c531232c9a00ec9c2c66ac7cb0ce50b4af9f407a72
SANE_URL="https://gitlab.com/-/project/429008/uploads/843c156420e211859e974f78f64c3ea3/sane-backends-${SANE_VERSION}.tar.gz"

USB_VERSION=1.0.30
USB_SHA256=fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf
USB_URL="https://github.com/libusb/libusb/releases/download/v${USB_VERSION}/libusb-${USB_VERSION}.tar.bz2"

JPEG_VERSION=10
JPEG_SHA256=8b9eaa13242690ebd03e1728ab1edf97a81a78ed6e83624d493655f31ac95ab5
JPEG_URL="https://www.ijg.org/files/jpegsrc.v${JPEG_VERSION}.tar.gz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
STAGE="$BUILD/sane-stage"
PREFIX="$BUILD/sane-prefix"   # where libusb is installed for SANE to link against

command -v pkg-config >/dev/null || { echo "pkg-config missing: brew install pkgconf" >&2; exit 1; }
command -v clang >/dev/null || { echo "Xcode command line tools missing: xcode-select --install" >&2; exit 1; }

# The oldest macOS the app runs on (see deploymentTarget in project.yml).
export MACOSX_DEPLOYMENT_TARGET=14.0
export CFLAGS="-arch arm64 -O2"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch arm64"

fetch() { # url sha256 file
  [ -f "$3" ] || curl -fsSL -A "curl/8" -o "$3" "$1"
  echo "$2  $3" | shasum -a 256 -c -
}

mkdir -p "$BUILD"

# --- libusb ---
USB_TAR="$BUILD/libusb-${USB_VERSION}.tar.bz2"
fetch "$USB_URL" "$USB_SHA256" "$USB_TAR"
[ -d "$BUILD/libusb-${USB_VERSION}" ] || tar -xjf "$USB_TAR" -C "$BUILD"
rm -rf "$PREFIX"
( cd "$BUILD/libusb-${USB_VERSION}"
  ./configure --prefix="$PREFIX" --disable-static --disable-udev >"$BUILD/libusb-configure.log" 2>&1
  make -j"$(sysctl -n hw.ncpu)" >"$BUILD/libusb-make.log" 2>&1
  make install >"$BUILD/libusb-install.log" 2>&1 )

# --- JPEG (the pixma backend will not build without it; static, so nothing extra is bundled) ---
JPEG_TAR="$BUILD/jpegsrc.v${JPEG_VERSION}.tar.gz"
fetch "$JPEG_URL" "$JPEG_SHA256" "$JPEG_TAR"
[ -d "$BUILD/jpeg-${JPEG_VERSION}" ] || tar -xzf "$JPEG_TAR" -C "$BUILD"
( cd "$BUILD/jpeg-${JPEG_VERSION}"
  ./configure --prefix="$PREFIX" --disable-shared --enable-static >"$BUILD/jpeg-configure.log" 2>&1
  make -j"$(sysctl -n hw.ncpu)" >"$BUILD/jpeg-make.log" 2>&1
  make install >"$BUILD/jpeg-install.log" 2>&1 )
export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="$LDFLAGS -L$PREFIX/lib"

# --- SANE ---
SANE_TAR="$BUILD/sane-backends-${SANE_VERSION}.tar.gz"
SRC="$BUILD/sane-backends-${SANE_VERSION}"
fetch "$SANE_URL" "$SANE_SHA256" "$SANE_TAR"
rm -rf "$SRC"; tar -xzf "$SANE_TAR" -C "$BUILD"

cd "$SRC"
# Clang 16+ turns SANE's old-style backend function tables into errors, so allow them.
export CFLAGS="$CFLAGS -Wno-incompatible-function-pointer-types"
# Only the pixma backend, linked into libsane itself (--enable-preload, static) so scanimage
# needs no backend files to find at run time. The one runtime dependency is libusb.
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" BACKENDS="pixma" \
  ./configure --prefix=/usr/local --disable-shared --enable-static --enable-preload \
  --disable-latex --disable-locking --disable-avahi --disable-ipv6 --disable-nls \
  --without-snmp --without-gphoto2 --without-v4l --without-poppler-glib \
  --with-usb=yes >"$BUILD/sane-configure.log" 2>&1
make -j"$(sysctl -n hw.ncpu)" >"$BUILD/sane-make.log" 2>&1
rm -rf "$STAGE"
make install DESTDIR="$STAGE" >"$BUILD/sane-install.log" 2>&1

# The files the app bundles. The app copies this folder to Resources/g2010/build/sane, so
# a repo checkout (G2010_ROOT) and the app use the same layout.
OUT="$BUILD/sane"
rm -rf "$OUT"; mkdir -p "$OUT/bin" "$OUT/lib" "$OUT/etc"
cp "$STAGE/usr/local/bin/scanimage" "$OUT/bin/"
cp -P "$PREFIX"/lib/libusb-1.0*.dylib "$OUT/lib/"
# scanimage was linked against libusb's install path; point it at the copy next to it
# (bin -> ../lib) and give the copy a relative name. Hardened-runtime apps ignore DYLD_* variables.
LIB="$(basename "$(readlink -f "$PREFIX/lib/libusb-1.0.0.dylib")")"
install_name_tool -id "@loader_path/$LIB" "$OUT/lib/$LIB"
otool -L "$OUT/bin/scanimage" | awk '/libusb-1.0/ {print $1}' | while read -r old; do
  install_name_tool -change "$old" "@loader_path/../lib/$(basename "$old")" "$OUT/bin/scanimage"
done
# dll.conf lists the backends to load; pixma.conf may stay empty (USB scanners are found by id).
echo pixma > "$OUT/etc/dll.conf"
: > "$OUT/etc/pixma.conf"
codesign --force --sign - "$OUT/lib/$LIB" "$OUT/bin/scanimage"

echo "Built: $OUT/bin/scanimage"
otool -L "$OUT/bin/scanimage"
