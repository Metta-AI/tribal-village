version     = "0.1.0"
author      = "Metta Team"
description = "High-performance tribal-village environment for multi-agent RL"
license     = "MIT"

srcDir = "src"

requires "nim >= 2.2.4"
requires "genny >= 0.1.0"
requires "nimpy >= 0.2.0"
requires "pixie >= 5.0.0"
requires "vmath >= 2.0.0"
requires "chroma >= 0.2.7"
requires "boxy >= 0.1.4"
requires "windy >= 0.1.2"

task run, "Run the tribal village game":
  exec "nim c -r tribal_village.nim"

task lib, "Build shared library for PufferLib":
  exec "./build_lib.sh"