#!/bin/zsh

set -euo pipefail

# Build vectorlite from vendored source as a proper SQLite extension.
# We do this instead of shipping the upstream prebuilt artifact because the
# upstream dylib bundled its own SQLite surface, which conflicted with the
# project-owned SQLite runtime that provides FTS5 and extension loading.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Vendor/vectorlite"
BUILD_DIR="$SOURCE_DIR/build/tasktrace-release"
OUTPUT_PATH="$ROOT_DIR/AppResources/SQLiteExtensions/vectorlite.dylib"
SQLITE_INCLUDE_DIR="$ROOT_DIR/Vendor/SQLite"
VCPKG_ROOT="${VCPKG_ROOT:-$SOURCE_DIR/vcpkg}"
TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"

# vectorlite uses a vcpkg-based dependency graph upstream, but we do not keep
# the vcpkg checkout in this repository. Point the build at a local clone via
# VCPKG_ROOT, or place one at Vendor/vectorlite/vcpkg for convenience.
if [ ! -x "$VCPKG_ROOT/bootstrap-vcpkg.sh" ]; then
  echo "Missing vcpkg checkout at $VCPKG_ROOT" >&2
  echo "Set VCPKG_ROOT to a local vcpkg clone or place vcpkg at Vendor/vectorlite/vcpkg" >&2
  exit 1
fi

"$VCPKG_ROOT/bootstrap-vcpkg.sh"

cmake \
  -S "$SOURCE_DIR" \
  -B "$BUILD_DIR" \
  -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
  -DVECTORLITE_BUILD_TESTS=OFF \
  -DVECTORLITE_BUILD_BENCHMARKS=OFF \
  -DVECTORLITE_SQLITE_INCLUDE_DIR="$SQLITE_INCLUDE_DIR"

cmake --build "$BUILD_DIR" --target vectorlite --parallel 8

# The app target copies this dylib into Contents/Resources and then re-signs it
# with the app's code-signing identity so hardened runtime can dlopen it.
cp "$BUILD_DIR/vectorlite/vectorlite.dylib" "$OUTPUT_PATH"
