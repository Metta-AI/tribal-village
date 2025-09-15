#!/bin/bash
# Build Tribal Village shared library with maximum performance

set -e

echo "Building Tribal Village shared library (danger mode)..."

# Cross-platform shared library build
case "$OSTYPE" in
  darwin*)  EXT="dylib" ;;
  msys*|cygwin*) EXT="dll" ;;
  *) EXT="so" ;;
esac

nim c --app:lib --mm:arc --opt:speed -d:danger \
    --out:libtribal_village.$EXT \
    src/tribal_village_interface.nim

echo "Built libtribal_village.$EXT with maximum optimization"