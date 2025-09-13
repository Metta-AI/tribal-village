#!/bin/bash
# Build Tribal Village shared library with C interface

set -e

echo "Building Tribal Village shared library..."
echo "Working directory: $(pwd)"

# Build the shared library for the current platform
if [[ "$OSTYPE" == "darwin"* ]]; then
    nim c --app:lib --mm:arc --opt:speed \
        --out:libtribal_village.dylib \
        src/tribal_village_interface.nim
    echo "Built libtribal_village.dylib"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    nim c --app:lib --mm:arc --opt:speed \
        --out:tribal_village.dll \
        src/tribal_village_interface.nim
    echo "Built tribal_village.dll"
else
    nim c --app:lib --mm:arc --opt:speed \
        --out:libtribal_village.so \
        src/tribal_village_interface.nim
    echo "Built libtribal_village.so"
fi

echo "C-compatible shared library is ready!"