version     = "0.1.0"
author      = "Metta Team"
description = "High-performance tribal-village environment for multi-agent RL"
license     = "MIT"

srcDir = "src"

requires "nim >= 2.2.4"
requires "pixie >= 5.0.0"
requires "vmath >= 2.0.0"
requires "chroma >= 0.2.7"
requires "boxy >= 0.1.4"
requires "windy >= 0.1.2"

task buildLib, "Build shared library for PufferLib":
  echo "Building Tribal Village shared library (ultra-fast direct buffers)..."

  let ext = when defined(windows): "dll"
            elif defined(macosx): "dylib"
            else: "so"

  exec "nim c --app:lib --mm:arc --opt:speed -d:danger --out:libtribal_village." & ext & " src/tribal_village_interface.nim"
  echo "Built libtribal_village." & ext & " with ultra-fast direct buffers"

task run, "Run the tribal village game":
  exec "nim c -r tribal_village.nim"

task lib, "Build shared library for PufferLib (alias for buildLib)":
  exec "nimble buildLib"

task wasm, "Build Tribal Village WASM demo":
  exec "bash scripts/build_web.sh"

before install:
  exec "nimble buildLib"

after install:
  echo "Tribal Village installation complete with shared library built!"
